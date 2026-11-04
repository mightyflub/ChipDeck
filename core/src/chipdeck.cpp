/*
 * ChipDeck core implementation.
 * SID via libsidplayfp + reSIDfp; Atari ST .sndh/.ym via AtariAudio
 * (see atari_backend.cpp); Amiga .mod and other tracker modules via libxmp
 * (see mod_backend.cpp). A cd_player holds one tune of any kind.
 * Copyright (C) 2026 ChipDeck contributors. GPL-2.0-or-later.
 */
#define CHIPDECK_BUILDING
#include "chipdeck/chipdeck.h"
#include "atari_backend.h"
#include "mod_backend.h"

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "sidplayfp/sidplayfp.h"
#include "sidplayfp/SidConfig.h"
#include "sidplayfp/SidInfo.h"
#include "sidplayfp/SidTune.h"
#include "sidplayfp/SidTuneInfo.h"
#include "builders/residfp-builder/residfp.h"
#include "SidDatabase.h"

#ifdef _WIN32
#  include <windows.h>
#endif

#ifndef CHIPDECK_VERSION
#  define CHIPDECK_VERSION "0.0.0"
#endif

namespace {

// Emulate this many C64 cycles per engine call (~5 ms of audio on PAL).
const unsigned int kCyclesPerChunk = 5000;

// Per-channel history kept for cd_channel_scope().
const size_t kChanRing = 4096;

// Open a file for reading, accepting UTF-8 paths on every platform.
FILE* openFile(const char* path)
{
#ifdef _WIN32
    int n = MultiByteToWideChar(CP_UTF8, 0, path, -1, nullptr, 0);
    if (n <= 0) return nullptr;
    std::wstring w(static_cast<size_t>(n), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, path, -1, &w[0], n);
    return _wfopen(w.c_str(), L"rb");
#else
    return std::fopen(path, "rb");
#endif
}

// Read a whole file, accepting UTF-8 paths on every platform.
bool readFile(const char* path, std::vector<uint8_t>& out)
{
    FILE* f = openFile(path);
    if (!f) return false;
    out.clear();
    uint8_t buf[65536];
    size_t got;
    while ((got = std::fread(buf, 1, sizeof buf, f)) > 0)
        out.insert(out.end(), buf, buf + got);
    std::fclose(f);
    return true;
}

// SidTune loader hook so libsidplayfp also uses UTF-8 aware file access.
void tuneLoader(const char* fileName, std::vector<uint8_t>& buffer)
{
    if (!readFile(fileName, buffer))
        buffer.clear();
}

bool openDb(SidDatabase& db, const char* path)
{
#ifdef _WIN32
    int n = MultiByteToWideChar(CP_UTF8, 0, path, -1, nullptr, 0);
    if (n <= 0) return false;
    std::wstring w(static_cast<size_t>(n), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, path, -1, &w[0], n);
    return db.open(w.c_str());
#else
    return db.open(path);
#endif
}

// Songlengths database shared by cd_probe_file() calls, reopened only when
// the path changes (the file is several MB, too slow to parse per probe).
std::mutex probeDbLock;
std::string probeDbPath;
std::unique_ptr<SidDatabase> probeDb;

void copyStr(char* dst, size_t cap, const char* src)
{
    if (!src) src = "";
    std::snprintf(dst, cap, "%s", src);
}

// PSID/RSID files are recognised by their magic bytes.
bool isSidFile(const std::vector<uint8_t>& b)
{
    return b.size() >= 4 && (std::memcmp(b.data(), "PSID", 4) == 0 ||
                             std::memcmp(b.data(), "RSID", 4) == 0);
}

// C64 formats without magic bytes that libsidplayfp loads by extension.
// They are never handed to libxmp, whose old Soundtracker loader guesses
// from the data and could claim one.
bool isC64Extension(const char* path)
{
    std::string s(path ? path : "");
    const size_t slash = s.find_last_of("/\\");
    if (slash != std::string::npos) s = s.substr(slash + 1);
    const size_t dot = s.find_last_of('.');
    if (dot == std::string::npos) return false;
    std::string ext = s.substr(dot + 1);
    for (char& c : ext) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    if (ext.size() == 3 && ext[0] == 'p' && std::isdigit(static_cast<unsigned char>(ext[1])) &&
        std::isdigit(static_cast<unsigned char>(ext[2])))
        return true;  // .p00 .. .p99
    return ext == "prg" || ext == "c64" || ext == "mus" || ext == "str";
}

// Open `path` and let libxmp try it (it also unpacks packed modules).
std::unique_ptr<chipdeck::ModTune> tryModFile(const char* path, size_t size, uint32_t rate,
                                              int subtune, std::string& err)
{
    FILE* f = openFile(path);
    if (!f) { err = "cannot open file"; return nullptr; }
    auto t = chipdeck::ModTune::loadFile(f, static_cast<long>(size), rate, subtune, err);
    std::fclose(f);
    return t;
}

} // namespace

struct cd_player
{
    std::mutex lock;
    uint32_t sampleRate;
    std::string error;
    std::string errorOut;   // copy handed back to callers

    sidplayfp engine;
    ReSIDfpBuilder builder{"ChipDeck reSIDfp"};
    std::unique_ptr<SidTune> tune;
    std::unique_ptr<SidDatabase> songlengths;
    cd_sid_model model = CD_SID_AUTO;

    std::vector<uint8_t> kernal, basic, chargen;

    // Set when the loaded tune is an Atari ST tune; then the SID members
    // above are unused (tune is null, ready is false).
    std::unique_ptr<chipdeck::AtariTune> atari;
    // Set when the loaded tune is a tracker module (Amiga .mod etc.).
    std::unique_ptr<chipdeck::ModTune> mod;

    std::vector<short> chunk;  // engine output, interleaved stereo
    size_t chunkPos = 0;       // next unread int16 in chunk
    bool ready = false;

    // Per-channel output for visualisers (cd_channel_*).
    int channels = 0;
    std::vector<std::string> channelNames;
    std::vector<int16_t> chanChunk;  // SID: `channels` values per chunk frame
    std::vector<int16_t> chanTmp;    // Atari/MOD: `channels` values per frame
    std::vector<int16_t> chanRing;   // kChanRing values per channel
    size_t chanPos = 0;              // next write index in each ring
    std::vector<float> dcIn, dcOut;  // DC blocker state per channel

    void setChannels(std::vector<std::string> names)
    {
        channelNames = std::move(names);
        channels = static_cast<int>(channelNames.size());
        chanRing.assign(static_cast<size_t>(channels) * kChanRing, 0);
        chanPos = 0;
        dcIn.assign(static_cast<size_t>(channels), 0.f);
        dcOut.assign(static_cast<size_t>(channels), 0.f);
        chanChunk.clear();
    }

    // Append `frames` frames (`channels` values each) to the rings.
    void pushChannels(const int16_t* src, size_t frames)
    {
        const size_t nc = static_cast<size_t>(channels);
        if (nc == 0) return;
        for (size_t i = 0; i < frames; ++i)
        {
            for (size_t k = 0; k < nc; ++k)
            {
                // One-pole DC blocker (~4 Hz at 48 kHz): silent channels and
                // the constant volume of non-digi tunes settle at 0.
                const float x = src[i * nc + k];
                float y = x - dcIn[k] + 0.9995f * dcOut[k];
                dcIn[k] = x;
                dcOut[k] = y;
                y = std::max(-32768.f, std::min(32767.f, y));
                chanRing[k * kChanRing + chanPos] = static_cast<int16_t>(y);
            }
            chanPos = (chanPos + 1) % kChanRing;
        }
    }

    void sidChannels()
    {
        int chips = tune ? static_cast<int>(tune->getInfo()->sidChips()) : 1;
        chips = std::max(1, std::min(3, chips));
        std::vector<std::string> names;
        for (int c = 0; c < chips; ++c)
        {
            const std::string pre = chips > 1 ? std::to_string(c + 1) + ":" : "";
            for (const char* n : { "V1", "V2", "V3", "Digi" })
                names.push_back(pre + n);
        }
        setChannels(std::move(names));
    }

    explicit cd_player(uint32_t rate) : sampleRate(rate) {}

    int fail(const std::string& msg)
    {
        error = msg;
        ready = false;
        return 1;
    }

    int configure()
    {
        SidConfig cfg = engine.config();
        cfg.frequency = sampleRate;
        cfg.samplingMethod = SidConfig::RESAMPLE_INTERPOLATE;
        cfg.sidEmulation = &builder;
        cfg.defaultC64Model = SidConfig::PAL;
        cfg.forceC64Model = false;
        switch (model)
        {
        case CD_SID_6581:
            cfg.defaultSidModel = SidConfig::MOS6581;
            cfg.forceSidModel = true;
            break;
        case CD_SID_8580:
            cfg.defaultSidModel = SidConfig::MOS8580;
            cfg.forceSidModel = true;
            break;
        default:
            cfg.defaultSidModel = SidConfig::MOS6581;
            cfg.forceSidModel = false;
            break;
        }
        if (!engine.config(cfg))
            return fail(std::string("engine config failed: ") + engine.error());
        return 0;
    }

    // (Re)start the current tune at the given 1-based subtune (0 = default).
    int start(int subtune)
    {
        ready = false;
        if (!tune) return fail("no tune loaded");
        tune->selectSong(subtune < 0 ? 0u : static_cast<unsigned>(subtune));
        if (configure() != 0) return 1;
        if (!engine.load(tune.get()))
            return fail(std::string("engine load failed: ") + engine.error());
        engine.initMixer(true);
        chunk.clear();
        chunkPos = 0;
        sidChannels();
        error.clear();
        ready = true;
        return 0;
    }

    // Clear whatever was loaded before (SID, Atari or module).
    void unload()
    {
        tune.reset();
        atari.reset();
        mod.reset();
        ready = false;
    }

    int loadAtari(const uint8_t* data, size_t size, int subtune)
    {
        unload();
        std::string err;
        atari = chipdeck::AtariTune::load(data, size, sampleRate, subtune, err);
        if (!atari) { setChannels({}); return fail(err); }
        std::vector<std::string> names;
        for (int c = 0; c < atari->channelCount(); ++c)
            names.push_back(atari->channelName(c));
        setChannels(std::move(names));
        error.clear();
        return 0;
    }

    int useMod(std::unique_ptr<chipdeck::ModTune> t, const std::string& err)
    {
        if (!t) { setChannels({}); return fail(err); }
        mod = std::move(t);
        std::vector<std::string> names;
        for (int c = 0; c < mod->channelCount(); ++c)
            names.push_back(mod->channelName(c));
        setChannels(std::move(names));
        error.clear();
        return 0;
    }

    int finishLoad(int subtune)
    {
        if (!tune->getStatus())
        {
            std::string msg = tune->statusString();
            tune.reset();
            return fail(msg);
        }
        return start(subtune);
    }
};

extern "C" {

const char* cd_version(void)
{
    return CHIPDECK_VERSION " (libsidplayfp 3.1.2, libresidfp 1.2.3, AtariAudio 1.27, libxmp 4.6.3)";
}

cd_player* cd_create(uint32_t sample_rate)
{
    if (sample_rate < 8000 || sample_rate > 192000) return nullptr;
    try { return new cd_player(sample_rate); }
    catch (...) { return nullptr; }
}

void cd_destroy(cd_player* p)
{
    delete p;
}

const char* cd_last_error(cd_player* p)
{
    if (!p) return "null player";
    std::lock_guard<std::mutex> g(p->lock);
    p->errorOut = p->error;
    return p->errorOut.c_str();
}

int cd_load_songlengths(cd_player* p, const char* path)
{
    if (!p || !path) return 1;
    std::lock_guard<std::mutex> g(p->lock);
    std::unique_ptr<SidDatabase> db(new SidDatabase());
    bool ok = openDb(*db, path);
    if (!ok)
    {
        p->error = std::string("cannot open songlengths: ") + db->error();
        return 1;
    }
    p->songlengths = std::move(db);
    return 0;
}

int cd_set_roms(cd_player* p, const char* kernal, const char* basic,
                const char* chargen)
{
    if (!p) return 1;
    std::lock_guard<std::mutex> g(p->lock);
    struct { const char* path; std::vector<uint8_t>* dst; size_t size; const char* name; } roms[] = {
        { kernal,  &p->kernal,  8192, "KERNAL" },
        { basic,   &p->basic,   8192, "BASIC" },
        { chargen, &p->chargen, 4096, "chargen" },
    };
    for (auto& r : roms)
    {
        r.dst->clear();
        if (!r.path) continue;
        if (!readFile(r.path, *r.dst) || r.dst->size() != r.size)
        {
            r.dst->clear();
            p->error = std::string("bad ") + r.name + " ROM: " + r.path;
            return 1;
        }
    }
    p->engine.setRoms(p->kernal.empty() ? nullptr : p->kernal.data(),
                      p->basic.empty() ? nullptr : p->basic.data(),
                      p->chargen.empty() ? nullptr : p->chargen.data());
    return 0;
}

void cd_set_sid_model(cd_player* p, cd_sid_model model)
{
    if (!p) return;
    std::lock_guard<std::mutex> g(p->lock);
    p->model = model;
}

int cd_load_file(cd_player* p, const char* path, int subtune)
{
    if (!p || !path) return 1;
    std::lock_guard<std::mutex> g(p->lock);
    try
    {
        std::vector<uint8_t> bytes;
        const bool read = readFile(path, bytes);
        if (read && chipdeck::isAtariTune(bytes.data(), bytes.size()))
            return p->loadAtari(bytes.data(), bytes.size(), subtune);
        p->unload();
        if (read && !isSidFile(bytes) && !isC64Extension(path))
        {
            std::string err;
            auto m = tryModFile(path, bytes.size(), p->sampleRate, subtune, err);
            if (m) return p->useMod(std::move(m), err);
        }
        p->tune.reset(new SidTune(tuneLoader, path, nullptr, true));
        return p->finishLoad(subtune);
    }
    catch (const std::exception& e) { return p->fail(e.what()); }
}

int cd_load_memory(cd_player* p, const void* data, size_t size, int subtune)
{
    if (!p || !data || size == 0 || size > 0xFFFFFFFFu) return 1;
    std::lock_guard<std::mutex> g(p->lock);
    try
    {
        const uint8_t* bytes = static_cast<const uint8_t*>(data);
        if (chipdeck::isAtariTune(bytes, size))
            return p->loadAtari(bytes, size, subtune);
        p->unload();
        if (!(size >= 4 && (std::memcmp(bytes, "PSID", 4) == 0 || std::memcmp(bytes, "RSID", 4) == 0)))
        {
            std::string err;
            auto m = chipdeck::ModTune::loadMemory(bytes, size, p->sampleRate, subtune, err);
            if (m) return p->useMod(std::move(m), err);
        }
        p->tune.reset(new SidTune(static_cast<const uint_least8_t*>(data),
                                  static_cast<uint_least32_t>(size)));
        return p->finishLoad(subtune);
    }
    catch (const std::exception& e) { return p->fail(e.what()); }
}

int cd_select_subtune(cd_player* p, int subtune)
{
    if (!p) return 1;
    std::lock_guard<std::mutex> g(p->lock);
    if (p->atari)
    {
        if (p->atari->select(subtune)) { p->setChannels(p->channelNames); return 0; }
        p->error = "subtune out of range";
        return 1;
    }
    if (p->mod)
    {
        if (p->mod->select(subtune)) { p->setChannels(p->channelNames); return 0; }
        p->error = "subtune out of range";
        return 1;
    }
    if (!p->tune) return p->fail("no tune loaded");
    const int songs = static_cast<int>(p->tune->getInfo()->songs());
    if (subtune < 1 || subtune > songs)
    {
        p->error = "subtune out of range";
        return 1;
    }
    return p->start(subtune);
}

int cd_get_info(cd_player* p, cd_info* out)
{
    if (!p || !out) return 1;
    std::lock_guard<std::mutex> g(p->lock);
    std::memset(out, 0, sizeof *out);
    out->length_ms = -1;
    if (p->atari) { p->atari->fillInfo(out); return 0; }
    if (p->mod) { p->mod->fillInfo(out); return 0; }
    if (!p->tune) return 1;
    const SidTuneInfo* ti = p->tune->getInfo();
    const unsigned nInfo = ti->numberOfInfoStrings();
    copyStr(out->title,    sizeof out->title,    nInfo > 0 ? ti->infoString(0) : "");
    copyStr(out->author,   sizeof out->author,   nInfo > 1 ? ti->infoString(1) : "");
    copyStr(out->released, sizeof out->released, nInfo > 2 ? ti->infoString(2) : "");
    copyStr(out->format,   sizeof out->format,   ti->formatString());
    out->subtunes = static_cast<int>(ti->songs());
    out->start_subtune = static_cast<int>(ti->startSong());
    out->current_subtune = static_cast<int>(ti->currentSong());
    out->sid_chips = ti->sidChips();
    out->is_ntsc = ti->clockSpeed() == SidTuneInfo::CLOCK_NTSC ? 1 : 0;
    if (p->ready && p->engine.info().numberOfSIDs() > 0)
        out->sid_model = p->engine.info().sidModel(0) == SidTuneInfo::SIDMODEL_8580
                       ? CD_SID_8580 : CD_SID_6581;
    if (p->songlengths)
    {
        int_least32_t ms = p->songlengths->lengthMs(*p->tune);
        out->length_ms = ms > 0 ? ms : -1;
    }
    return 0;
}

size_t cd_render(cd_player* p, int16_t* out, size_t frames)
{
    if (!p || !out) return 0;
    std::lock_guard<std::mutex> g(p->lock);
    if (p->atari)
    {
        p->chanTmp.resize(frames * static_cast<size_t>(p->channels));
        size_t n = p->atari->render(out, frames, p->channels ? p->chanTmp.data() : nullptr);
        p->pushChannels(p->chanTmp.data(), n);
        return n;
    }
    if (p->mod)
    {
        p->chanTmp.resize(frames * static_cast<size_t>(p->channels));
        size_t n = p->mod->render(out, frames, p->channels ? p->chanTmp.data() : nullptr);
        p->pushChannels(p->chanTmp.data(), n);
        return n;
    }
    if (!p->ready) return 0;

    size_t want = frames * 2;  // int16 values
    size_t done = 0;
    int emptyChunks = 0;  // guard against an engine that stops producing audio
    while (done < want)
    {
        if (p->chunkPos >= p->chunk.size())
        {
            int samples = p->engine.play(kCyclesPerChunk);
            if (samples < 0) { p->fail(std::string("emulation error: ") + p->engine.error()); break; }
            // mix() writes `samples` frames of interleaved stereo.
            p->chunk.resize(static_cast<size_t>(samples) * 2);
            unsigned int n = samples > 0
                ? p->engine.mix(p->chunk.data(), static_cast<unsigned>(samples)) : 0u;
            p->chunk.resize(n);
            p->chunkPos = 0;
            // Per-voice samples, aligned with the chunk's frames.
            const size_t nc = static_cast<size_t>(p->channels);
            const size_t fr = n / 2;
            p->chanChunk.assign(fr * nc, 0);
            short* vb[3] = { nullptr, nullptr, nullptr };
            if (nc > 0 && p->engine.info().numberOfSIDs() <= 3)
            {
                p->engine.voiceBuffers(vb);
                for (size_t chip = 0; chip * 4 < nc; ++chip)
                {
                    if (!vb[chip]) continue;
                    for (size_t i = 0; i < fr; ++i)
                        for (size_t k = 0; k < 4; ++k)
                            p->chanChunk[i * nc + chip * 4 + k] = vb[chip][i * 4 + k];
                }
            }
            if (n == 0 && ++emptyChunks > 1000) { p->fail("emulation produced no audio"); break; }
            continue;
        }
        size_t take = std::min(want - done, p->chunk.size() - p->chunkPos);
        std::memcpy(out + done, p->chunk.data() + p->chunkPos, take * sizeof(int16_t));
        if (p->channels > 0 && p->chanChunk.size() >= (p->chunkPos + take) / 2 * p->channels)
            p->pushChannels(p->chanChunk.data() + p->chunkPos / 2 * p->channels, take / 2);
        p->chunkPos += take;
        done += take;
    }
    return done / 2;
}

uint32_t cd_position_ms(cd_player* p)
{
    if (!p) return 0;
    std::lock_guard<std::mutex> g(p->lock);
    if (p->atari) return p->atari->positionMs();
    if (p->mod) return p->mod->positionMs();
    return p->ready ? p->engine.timeMs() : 0;
}

int cd_get_sid_registers(cd_player* p, int chip, uint8_t regs[32])
{
    if (!p || !regs || chip < 0) return 1;
    std::lock_guard<std::mutex> g(p->lock);
    if (!p->ready) return 1;
    return p->engine.getSidStatus(static_cast<unsigned>(chip), regs) ? 0 : 1;
}

int cd_channel_count(cd_player* p)
{
    if (!p) return 0;
    std::lock_guard<std::mutex> g(p->lock);
    return (p->atari || p->mod || p->ready) ? p->channels : 0;
}

int cd_channel_name(cd_player* p, int ch, char* out, size_t cap)
{
    if (!p || !out || cap == 0) return 1;
    std::lock_guard<std::mutex> g(p->lock);
    if (ch < 0 || ch >= p->channels) { out[0] = 0; return 1; }
    copyStr(out, cap, p->channelNames[static_cast<size_t>(ch)].c_str());
    return 0;
}

size_t cd_channel_scope(cd_player* p, int16_t* out, size_t frames)
{
    if (!p || !out) return 0;
    std::lock_guard<std::mutex> g(p->lock);
    if (frames > kChanRing) frames = kChanRing;
    const size_t start = (p->chanPos + kChanRing - frames) % kChanRing;
    for (size_t k = 0; k < static_cast<size_t>(p->channels); ++k)
    {
        const int16_t* ring = p->chanRing.data() + k * kChanRing;
        int16_t* o = out + k * frames;
        for (size_t i = 0; i < frames; ++i)
            o[i] = ring[(start + i) % kChanRing];
    }
    return frames;
}

int cd_probe_file(const char* path, const char* songlengths_path, cd_info* out)
{
    if (!path || !out) return 1;
    std::memset(out, 0, sizeof *out);
    out->length_ms = -1;
    try
    {
        std::vector<uint8_t> bytes;
        const bool read = readFile(path, bytes);
        if (read && chipdeck::isAtariTune(bytes.data(), bytes.size()))
            return chipdeck::AtariTune::probe(bytes.data(), bytes.size(), out) ? 0 : 1;
        if (read && !isSidFile(bytes) && !isC64Extension(path))
        {
            FILE* f = openFile(path);
            if (f)
            {
                const bool ok = chipdeck::ModTune::probeFile(f, static_cast<long>(bytes.size()), out);
                std::fclose(f);
                if (ok) return 0;
                std::memset(out, 0, sizeof *out);
                out->length_ms = -1;
            }
        }
        SidTune tune(tuneLoader, path, nullptr, true);
        if (!tune.getStatus()) return 1;
        tune.selectSong(0);
        const SidTuneInfo* ti = tune.getInfo();
        const unsigned nInfo = ti->numberOfInfoStrings();
        copyStr(out->title,    sizeof out->title,    nInfo > 0 ? ti->infoString(0) : "");
        copyStr(out->author,   sizeof out->author,   nInfo > 1 ? ti->infoString(1) : "");
        copyStr(out->released, sizeof out->released, nInfo > 2 ? ti->infoString(2) : "");
        copyStr(out->format,   sizeof out->format,   ti->formatString());
        out->subtunes = static_cast<int>(ti->songs());
        out->start_subtune = static_cast<int>(ti->startSong());
        out->current_subtune = static_cast<int>(ti->currentSong());
        out->sid_chips = ti->sidChips();
        out->sid_model = ti->sidModel(0) == SidTuneInfo::SIDMODEL_8580 ? CD_SID_8580
                       : ti->sidModel(0) == SidTuneInfo::SIDMODEL_6581 ? CD_SID_6581
                       : CD_SID_AUTO;
        out->is_ntsc = ti->clockSpeed() == SidTuneInfo::CLOCK_NTSC ? 1 : 0;
        if (songlengths_path && *songlengths_path)
        {
            std::lock_guard<std::mutex> g(probeDbLock);
            if (probeDbPath != songlengths_path)
            {
                probeDb.reset(new SidDatabase());
                if (!openDb(*probeDb, songlengths_path)) probeDb.reset();
                probeDbPath = songlengths_path;
            }
            if (probeDb)
            {
                int_least32_t ms = probeDb->lengthMs(tune);
                out->length_ms = ms > 0 ? ms : -1;
            }
        }
        return 0;
    }
    catch (...) { return 1; }
}

} // extern "C"
