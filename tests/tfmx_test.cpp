/*
 * TFMX tests: Amiga TFMX (libtfmxaudiodecoder) and Atari ST TFMX-ST (our
 * replay port), both as mdat./smpl. file pairs made by
 * tools/make_test_tfmx.py and tools/make_test_tfmxst.py. Loads them through
 * the C API, renders audio, checks metadata, subtunes and channel scopes.
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

static const std::string kDir = std::string(CHIPDECK_TEST_DATA) + "/";
static const std::string kMdat = kDir + "mdat.chipdeck-test";
static const std::string kSmpl = kDir + "smpl.chipdeck-test";
static const std::string kStMdat = kDir + "mdat.chipdeck-st-test";
static const std::string kMod = kDir + "chipdeck-test.mod";
static const std::string kSid = kDir + "chipdeck-test.sid";

static double rmsOf(const int16_t* s, size_t n, size_t stride)
{
    double sum = 0;
    for (size_t i = 0; i < n; ++i) sum += double(s[i * stride]) * s[i * stride];
    return n ? std::sqrt(sum / n) : 0;
}

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
    CHECK(std::strstr(cd_version(), "libtfmxaudiodecoder") != nullptr);

    // ------------------------------------------------------- Amiga TFMX
    cd_info info;
    CHECK(cd_probe_file(kMdat.c_str(), nullptr, &info) == 0);
    std::printf("tfmx probe: '%s' format '%s' subtunes %d length %d ms\n", info.title,
                info.format, info.subtunes, info.length_ms);
    CHECK(std::strcmp(info.title, "chipdeck-test") == 0);
    CHECK(info.system == CD_SYSTEM_AMIGA && info.sid_chips == 0);
    CHECK(std::strstr(info.format, "TFMX") != nullptr);
    CHECK(info.subtunes == 2);
    CHECK(info.length_ms > 7000 && info.length_ms < 8500);
    // The samples file alone is not a tune.
    CHECK(cd_probe_file(kSmpl.c_str(), nullptr, &info) != 0);
    // Other formats are not taken for TFMX.
    CHECK(cd_probe_file(kMod.c_str(), nullptr, &info) == 0 && std::strstr(info.format, "TFMX") == nullptr);
    CHECK(cd_probe_file(kSid.c_str(), nullptr, &info) == 0 && info.system == CD_SYSTEM_C64);

    cd_player* p = cd_create(48000);
    CHECK(cd_load_file(p, kMdat.c_str(), 0) == 0);
    CHECK(cd_get_info(p, &info) == 0 && info.current_subtune == 1 && info.system == CD_SYSTEM_AMIGA);
    CHECK(cd_channel_count(p) == 4);
    std::vector<int16_t> pcm(48000 * 2);
    CHECK(cd_render(p, pcm.data(), 48000) == 48000);
    CHECK(rmsOf(pcm.data(), 48000, 2) > 500);
    CHECK(cd_position_ms(p) == 1000);
    auto e = channelRms(p, 4096);
    std::printf("tfmx channels: %.0f %.0f %.0f %.0f\n", e[0], e[1], e[2], e[3]);
    CHECK(e[0] > 500 && e[1] > 500 && e[2] < 1 && e[3] < 1);
    // Subtune 2: bass only.
    CHECK(cd_select_subtune(p, 2) == 0);
    CHECK(cd_get_info(p, &info) == 0 && info.current_subtune == 2);
    CHECK(cd_render(p, pcm.data(), 48000) == 48000);
    e = channelRms(p, 4096);
    CHECK(e[0] < 1 && e[1] > 500);
    CHECK(cd_select_subtune(p, 3) != 0);
    // From memory there is no samples file, so the pair cannot load.
    {
        std::ifstream f(kMdat, std::ios::binary);
        std::vector<char> b((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
        CHECK(cd_load_memory(p, b.data(), b.size(), 0) != 0);
    }

    // ----------------------------------------------------------- TFMX-ST
    CHECK(cd_probe_file(kStMdat.c_str(), nullptr, &info) == 0);
    std::printf("tfmx-st probe: '%s' format '%s' subtunes %d length %d ms\n", info.title,
                info.format, info.subtunes, info.length_ms);
    CHECK(std::strcmp(info.title, "chipdeck-st-test") == 0);
    CHECK(info.system == CD_SYSTEM_ATARI_ST);
    CHECK(std::strstr(info.format, "TFMX-ST") != nullptr);
    CHECK(info.subtunes == 2);
    CHECK(info.length_ms > 7000 && info.length_ms < 8500);

    CHECK(cd_load_file(p, kStMdat.c_str(), 0) == 0);
    CHECK(cd_channel_count(p) == 3);
    char name[8];
    CHECK(cd_channel_name(p, 2, name, sizeof name) == 0 && std::strcmp(name, "C") == 0);
    CHECK(cd_render(p, pcm.data(), 48000) == 48000);
    CHECK(rmsOf(pcm.data(), 48000, 2) > 500);
    e = channelRms(p, 4096);
    std::printf("tfmx-st channels: %.0f %.0f %.0f\n", e[0], e[1], e[2]);
    CHECK(e[0] > 300 && e[1] > 300 && e[2] > 100);
    // Subtune 2: digi drum on voice C right at the start, A and B silent.
    CHECK(cd_select_subtune(p, 2) == 0);
    CHECK(cd_render(p, pcm.data(), 2400) == 2400);
    CHECK(rmsOf(pcm.data(), 2400, 2) > 100);
    // (Scopes are DC-blocked; give silent voices time to settle.)
    CHECK(cd_render(p, pcm.data(), 30000) == 30000);
    e = channelRms(p, 4096);
    std::printf("tfmx-st subtune 2: %.0f %.0f %.0f\n", e[0], e[1], e[2]);
    CHECK(e[0] < 1 && e[1] < 1);
    // From memory TFMX-ST still plays (digi drums are silent then).
    {
        std::ifstream f(kStMdat, std::ios::binary);
        std::vector<char> b((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
        CHECK(cd_load_memory(p, b.data(), b.size(), 0) == 0);
        CHECK(cd_get_info(p, &info) == 0 && info.system == CD_SYSTEM_ATARI_ST);
        CHECK(cd_render(p, pcm.data(), 48000) == 48000);
    }

    cd_destroy(p);
    if (failures) { std::printf("%d failure(s)\n", failures); return 1; }
    std::printf("all TFMX tests passed\n");
    return 0;
}
