/*
 * Amiga MOD and Fasttracker 2 XM tests: load chipdeck-test.mod/.xm through the same C API
 * as SID and Atari tunes, render audio, check metadata, subtunes (libxmp
 * sequences) and the per-channel scopes.
 * Copyright (C) 2026 ChipDeck contributors. GPL-2.0-or-later.
 */
#include "chipdeck/chipdeck.h"

#include <cmath>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

static int failures = 0;
#define CHECK(cond) do { if (!(cond)) { std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); ++failures; } } while (0)

static const std::string kMod = std::string(CHIPDECK_TEST_DATA) + "/chipdeck-test.mod";
static const std::string kSid = std::string(CHIPDECK_TEST_DATA) + "/chipdeck-test.sid";
static const std::string kXm = std::string(CHIPDECK_TEST_DATA) + "/chipdeck-test.xm";
static const std::string kSndh = std::string(CHIPDECK_TEST_DATA) + "/chipdeck-test.sndh";

static double rmsOf(const int16_t* s, size_t n, size_t stride)
{
    double sum = 0;
    for (size_t i = 0; i < n; ++i) sum += double(s[i * stride]) * s[i * stride];
    return n ? std::sqrt(sum / n) : 0;
}

// Energy of each channel's scope over the last `frames` frames.
static std::vector<double> channelRms(cd_player* p, size_t frames)
{
    const int n = cd_channel_count(p);
    std::vector<int16_t> buf(static_cast<size_t>(n) * frames);
    CHECK(cd_channel_scope(p, buf.data(), frames) == frames);
    std::vector<double> out;
    for (int c = 0; c < n; ++c) out.push_back(rmsOf(buf.data() + c * frames, frames, 1));
    return out;
}

int main()
{
    std::printf("chipdeck %s\n", cd_version());
    CHECK(std::strstr(cd_version(), "libxmp") != nullptr);

    // Probe (library index).
    cd_info info;
    CHECK(cd_probe_file(kMod.c_str(), nullptr, &info) == 0);
    CHECK(std::strcmp(info.title, "ChipDeck test") == 0);
    CHECK(info.system == CD_SYSTEM_AMIGA);
    CHECK(info.sid_chips == 0);
    CHECK(info.subtunes == 2);
    CHECK(info.length_ms > 14000 && info.length_ms < 17000);  // 128 rows x 120 ms
    std::printf("probe: '%s' format '%s' subtunes %d length %d ms\n", info.title,
                info.format, info.subtunes, info.length_ms);
    // Other kinds keep their system.
    CHECK(cd_probe_file(kSid.c_str(), nullptr, &info) == 0 && info.system == CD_SYSTEM_C64);
    CHECK(cd_probe_file(kSndh.c_str(), nullptr, &info) == 0 && info.system == CD_SYSTEM_ATARI_ST);

    cd_player* p = cd_create(48000);
    CHECK(p != nullptr);
    CHECK(cd_load_file(p, kMod.c_str(), 0) == 0);
    CHECK(cd_get_info(p, &info) == 0);
    CHECK(info.system == CD_SYSTEM_AMIGA && info.current_subtune == 1);
    CHECK(std::strstr(info.format, "M.K.") != nullptr);

    // Four channels named 1-4.
    CHECK(cd_channel_count(p) == 4);
    for (int c = 0; c < 4; ++c)
    {
        char name[16];
        CHECK(cd_channel_name(p, c, name, sizeof name) == 0 && name[0] == '1' + c);
    }

    // First 2 s (pattern 0): channels 1-3 play, channel 4 is silent.
    std::vector<int16_t> pcm(96000 * 2);
    CHECK(cd_render(p, pcm.data(), 96000) == 96000);
    const double l = rmsOf(pcm.data(), 96000, 2), r = rmsOf(pcm.data() + 1, 96000, 2);
    std::printf("mix rms L %.0f R %.0f\n", l, r);
    CHECK(l > 300 && r > 300);
    CHECK(cd_position_ms(p) == 2000);
    auto e = channelRms(p, 4096);
    std::printf("pattern 0 channels: %.0f %.0f %.0f %.0f\n", e[0], e[1], e[2], e[3]);
    CHECK(e[0] > 200 && e[1] > 200 && e[2] > 50);
    CHECK(e[3] < 1);

    // Pattern 1 starts at 7.68 s; render into it, channel 4 joins.
    std::vector<int16_t> more(48000 * 7 * 2);
    CHECK(cd_render(p, more.data(), 48000 * 7) == 48000 * 7);
    e = channelRms(p, 4096);
    std::printf("pattern 1 channels: %.0f %.0f %.0f %.0f\n", e[0], e[1], e[2], e[3]);
    CHECK(e[3] > 200);

    // Subtune 2 (hidden sequence at order 2): only channel 1.
    CHECK(cd_select_subtune(p, 2) == 0);
    CHECK(cd_get_info(p, &info) == 0 && info.current_subtune == 2);
    CHECK(cd_position_ms(p) == 0);
    CHECK(cd_render(p, pcm.data(), 48000) == 48000);
    e = channelRms(p, 4096);
    std::printf("subtune 2 channels: %.0f %.0f %.0f %.0f\n", e[0], e[1], e[2], e[3]);
    CHECK(e[0] > 200 && e[1] < 1 && e[2] < 1 && e[3] < 1);
    CHECK(cd_select_subtune(p, 3) != 0);

    // From memory (no unpacking there, plain modules work).
    std::ifstream f(kMod, std::ios::binary);
    std::vector<char> bytes((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
    CHECK(cd_load_memory(p, bytes.data(), bytes.size(), 0) == 0);
    CHECK(cd_get_info(p, &info) == 0 && info.system == CD_SYSTEM_AMIGA);
    CHECK(cd_render(p, pcm.data(), 4800) == 4800);

    // ------------------------------------------------------- Fasttracker 2
    CHECK(cd_probe_file(kXm.c_str(), nullptr, &info) == 0);
    CHECK(info.system == CD_SYSTEM_PC && info.sid_chips == 0 && info.subtunes == 1);
    CHECK(std::strcmp(info.title, "ChipDeck XM test") == 0);
    CHECK(info.length_ms > 3500 && info.length_ms < 4200);  // 32 rows x 120 ms
    CHECK(cd_load_file(p, kXm.c_str(), 0) == 0);
    CHECK(cd_get_info(p, &info) == 0 && info.system == CD_SYSTEM_PC);
    std::printf("xm: '%s' format '%s' length %d ms\n", info.title, info.format, info.length_ms);
    CHECK(cd_channel_count(p) == 6);
    CHECK(cd_render(p, pcm.data(), 72000) == 72000);  // 1.5 s: channel 6 not started
    e = channelRms(p, 4096);
    std::printf("xm at 1.5 s: %.0f %.0f %.0f %.0f %.0f %.0f\n", e[0], e[1], e[2], e[3], e[4], e[5]);
    for (int c = 0; c < 5; ++c) CHECK(e[c] > 200);
    CHECK(e[5] < 1);
    CHECK(cd_render(p, pcm.data(), 48000) == 48000);  // 2.5 s: channel 6 plays
    e = channelRms(p, 4096);
    CHECK(e[5] > 200);

    // Switching back to a SID tune still works, and garbage is rejected.
    CHECK(cd_load_file(p, kSid.c_str(), 0) == 0);
    CHECK(cd_get_info(p, &info) == 0 && info.system == CD_SYSTEM_C64 && info.sid_chips == 1);
    CHECK(cd_channel_count(p) == 4);  // V1-V3 + Digi
    std::vector<char> junk(4000, 'x');
    CHECK(cd_load_memory(p, junk.data(), junk.size(), 0) != 0);
    CHECK(cd_channel_count(p) == 0);

    cd_destroy(p);
    if (failures) { std::printf("%d failure(s)\n", failures); return 1; }
    std::printf("all MOD tests passed\n");
    return 0;
}
