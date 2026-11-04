/*
 * ChipDeck core: Amiga TFMX (Chris Huelsbeck; mdat./smpl. file pairs) and
 * Jochen Hippel TFMX / Future Composer via libtfmxaudiodecoder.
 * Copyright (C) 2026 ChipDeck contributors. GPL-2.0-or-later.
 *
 * Internal to chipdeck-core; not part of the public C API.
 */
#ifndef CHIPDECK_TFMX_BACKEND_H
#define CHIPDECK_TFMX_BACKEND_H

#include "chipdeck/chipdeck.h"

#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace chipdeck {

// True if the data looks like an Atari ST TFMX ("TFMX-ST") music file:
// an Amiga-style TFMX mdat whose instrument macros use the ST's YM2149
// commands ($40 and up). Same test as UADE's amifilemagic.
bool isTfmxStData(const uint8_t* data, size_t size);

// True if the file name looks like a TFMX samples file (smpl.*, *.smpl,
// *.sam). Those are only loaded together with their music data file.
bool isTfmxSamplesName(const char* path);

class TfmxTune
{
public:
    // Load `data` (the music data file). `path` is the file it came from
    // (UTF-8); it is used to find the matching samples file (mdat.x ->
    // smpl.x, x.mdat -> x.smpl, x.tfx -> x.sam). May be null for data
    // without a samples file (Hippel TFMX, FC, single-file TFMX).
    // subtune is 1-based, 0 = first. Returns nullptr and sets `error` if
    // the data is not a format the library plays.
    static std::unique_ptr<TfmxTune> load(const uint8_t* data, size_t size, const char* path,
                                          uint32_t sampleRate, int subtune, std::string& error);
    // Read metadata only (for cd_probe_file).
    static bool probe(const uint8_t* data, size_t size, const char* path, cd_info* out);
    ~TfmxTune();

    int subtunes() const { return songs_; }
    bool select(int subtune);
    void fillInfo(cd_info* out) const;
    size_t render(int16_t* out, size_t frames, int16_t* chans = nullptr);
    int channelCount() const { return channels_; }
    const char* channelName(int ch) const;
    uint32_t positionMs() const;

private:
    TfmxTune() = default;
    void* dec_ = nullptr;  // tfmxdec
    uint32_t rate_ = 0;
    int songs_ = 1;
    int current_ = 1;
    int channels_ = 0;
    uint64_t framesPlayed_ = 0;
    std::vector<std::string> names_;
};

} // namespace chipdeck

#endif
