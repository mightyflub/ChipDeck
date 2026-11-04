/*
 * ChipDeck core: Amiga TFMX and Hippel TFMX / Future Composer playback via
 * libtfmxaudiodecoder.
 * Copyright (C) 2026 ChipDeck contributors. GPL-2.0-or-later.
 */
#include "tfmx_backend.h"

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cstring>

#include "tfmxaudiodecoder.h"

namespace chipdeck {

namespace {

// Stereo width: 100 is the Amiga's hard left/right split, which sounds
// odd on headphones. 75 is the library's default.
constexpr int kPanning = 75;

uint32_t be32(const uint8_t* p)
{
    return (uint32_t(p[0]) << 24) | (uint32_t(p[1]) << 16) | (uint32_t(p[2]) << 8) | p[3];
}

uint16_t be16(const uint8_t* p) { return static_cast<uint16_t>((p[0] << 8) | p[1]); }

void copyStr(char* dst, size_t cap, const char* src)
{
    std::snprintf(dst, cap, "%s", src ? src : "");
}

std::string lowerName(const char* path)
{
    std::string s(path ? path : "");
    const size_t slash = s.find_last_of("/\\");
    if (slash != std::string::npos) s = s.substr(slash + 1);
    for (char& c : s) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    return s;
}

bool endsWith(const std::string& s, const char* suffix)
{
    const size_t n = std::strlen(suffix);
    return s.size() >= n && s.compare(s.size() - n, n, suffix) == 0;
}

} // namespace

bool isTfmxStData(const uint8_t* b, size_t size)
{
    // Same test as Wanted Team's TFMX ST EaglePlayer (Check2) and UADE.
    if (size < 0x800 || std::memcmp(b, "TFMX-SONG ", 10) != 0) return false;
    uint32_t first, end;
    if (be32(b + 468) != 0)
    {
        // Packed layout: offsets of the pattern and macro tables.
        end = be32(b + 468);
        const uint32_t table = be32(b + 472);
        if (table > size - 4) return false;
        first = be32(b + table);
    }
    else
    {
        if (be32(b + 464) == 0 && be16(b + 12) != 0) return false;
        first = be32(b + 1536);   // first macro
        end = be32(b + 2044);     // last macro
    }
    if (first == 0 || end == 0 || (first & 1) || (end & 1) || first >= end ||
        first >= 0x80000000u || end >= 0x80000000u)
        return false;
    end = std::min<uint32_t>(end, static_cast<uint32_t>(size));
    // Amiga macro commands are $00..$3F; the ST player adds YM2149 ones.
    for (uint32_t o = first; o < end; o += 4)
        if (b[o] > 63) return true;
    return false;
}

bool isTfmxSamplesName(const char* path)
{
    const std::string n = lowerName(path);
    return n.rfind("smpl.", 0) == 0 || n.rfind("smp.", 0) == 0 ||
           endsWith(n, ".smpl") || endsWith(n, ".sam") || endsWith(n, ".smp");
}

std::unique_ptr<TfmxTune> TfmxTune::load(const uint8_t* data, size_t size, const char* path,
                                         uint32_t sampleRate, int subtune, std::string& error)
{
    if (!data || size == 0 || size > 0x7FFFFFFF) { error = "not a TFMX file"; return nullptr; }
    std::unique_ptr<TfmxTune> t(new TfmxTune());
    t->dec_ = tfmxdec_new();
    if (!t->dec_) { error = "out of memory"; return nullptr; }
    t->rate_ = sampleRate;
    tfmxdec_mixer_init(t->dec_, static_cast<int>(sampleRate), 16, 2, 0, kPanning);
    if (path && *path) tfmxdec_set_path(t->dec_, path);
    const int song = subtune > 0 ? subtune - 1 : 0;
    // init copies the data, and with a path also loads the samples file.
    if (!tfmxdec_init(t->dec_, const_cast<uint8_t*>(data), static_cast<uint32_t>(size), song))
    {
        error = "not a TFMX file ChipDeck can play (for mdat. files, the matching smpl. file must be next to it)";
        return nullptr;
    }
    tfmxdec_set_loop_mode(t->dec_, 0);
    t->songs_ = std::max(1, tfmxdec_songs(t->dec_));
    t->current_ = song + 1;
    t->channels_ = std::min(std::max(0, tfmxdec_voices(t->dec_)), CD_MAX_CHANNELS);
    for (int c = 0; c < t->channels_; ++c) t->names_.push_back(std::to_string(c + 1));
    return t;
}

bool TfmxTune::probe(const uint8_t* data, size_t size, const char* path, cd_info* out)
{
    std::string err;
    auto t = load(data, size, path, 44100, 0, err);
    if (!t) return false;
    t->fillInfo(out);
    return true;
}

TfmxTune::~TfmxTune()
{
    if (dec_) tfmxdec_delete(dec_);
}

bool TfmxTune::select(int subtune)
{
    if (subtune < 1 || subtune > songs_) return false;
    if (!tfmxdec_reinit(dec_, subtune - 1)) return false;
    current_ = subtune;
    framesPlayed_ = 0;
    // 7V songs and 4V songs can share a file.
    const int v = std::min(std::max(0, tfmxdec_voices(dec_)), CD_MAX_CHANNELS);
    if (v != channels_)
    {
        channels_ = v;
        names_.clear();
        for (int c = 0; c < channels_; ++c) names_.push_back(std::to_string(c + 1));
    }
    return true;
}

void TfmxTune::fillInfo(cd_info* out) const
{
    std::memset(out, 0, sizeof *out);
    out->system = CD_SYSTEM_AMIGA;
    const char* title = tfmxdec_get_title(dec_);
    if (!title || !*title) title = tfmxdec_get_name(dec_);
    copyStr(out->title, sizeof out->title, title);
    copyStr(out->author, sizeof out->author, tfmxdec_get_artist(dec_));
    copyStr(out->released, sizeof out->released, tfmxdec_get_game(dec_));
    copyStr(out->format, sizeof out->format, tfmxdec_format_name(dec_));
    out->subtunes = songs_;
    out->start_subtune = 1;
    out->current_subtune = current_;
    const uint32_t ms = tfmxdec_duration(dec_);
    out->length_ms = ms > 0 && ms < 0x7FFFFFFF ? static_cast<int32_t>(ms) : -1;
}

const char* TfmxTune::channelName(int ch) const
{
    if (ch < 0 || ch >= channels_) return "";
    return names_[static_cast<size_t>(ch)].c_str();
}

size_t TfmxTune::render(int16_t* out, size_t frames, int16_t* chans)
{
    // The mixer writes one value per Paula voice and frame into the tap,
    // in the same layout cd_render wants. Its voice count can be larger
    // than CD_MAX_CHANNELS only in theory (8 at most).
    const int voices = std::max(0, tfmxdec_voices(dec_));
    std::vector<int16_t> tmp;
    int16_t* tap = nullptr;
    if (chans && channels_ > 0)
    {
        if (voices == channels_) tap = chans;
        else { tmp.assign(frames * static_cast<size_t>(voices), 0); tap = tmp.data(); }
    }
    tfmxdec_chipdeck_set_tap(dec_, tap);
    tfmxdec_buffer_fill(dec_, out, static_cast<uint32_t>(frames * 4));
    tfmxdec_chipdeck_set_tap(dec_, nullptr);
    if (tap && tap != chans)
    {
        const size_t nc = static_cast<size_t>(channels_);
        std::memset(chans, 0, frames * nc * sizeof(int16_t));
        for (size_t i = 0; i < frames; ++i)
            for (size_t k = 0; k < nc && k < static_cast<size_t>(voices); ++k)
                chans[i * nc + k] = tmp[i * voices + k];
    }
    framesPlayed_ += frames;
    return frames;
}

uint32_t TfmxTune::positionMs() const
{
    return rate_ ? static_cast<uint32_t>(framesPlayed_ * 1000u / rate_) : 0;
}

} // namespace chipdeck
