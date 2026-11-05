/*
 * Mute and seek tests (0.12.0), for every format ChipDeck plays.
 * Copyright (C) 2026 ChipDeck contributors. GPL-2.0-or-later.
 */
#include "chipdeck/chipdeck.h"

#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

static int failures = 0;
#define CHECK(cond) do { if (!(cond)) { std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); ++failures; } } while (0)

static const std::string kDir = std::string(CHIPDECK_TEST_DATA) + "/";
static const uint32_t kRate = 48000;

// Loudness of the left channel without its DC part (a muted SID still
// holds a constant level).
static double acRms(cd_player* p, double seconds)
{
    const size_t frames = static_cast<size_t>(seconds * kRate);
    std::vector<int16_t> pcm(frames * 2);
    CHECK(cd_render(p, pcm.data(), frames) == frames);
    double mean = 0;
    for (size_t i = 0; i < frames; ++i) mean += pcm[i * 2];
    mean /= frames;
    double sum = 0;
    for (size_t i = 0; i < frames; ++i)
    {
        const double v = pcm[i * 2] - mean;
        sum += v * v;
    }
    return std::sqrt(sum / frames);
}

static void testTune(const char* file)
{
    std::printf("%s\n", file);
    cd_player* p = cd_create(kRate);
    CHECK(cd_load_file(p, (kDir + file).c_str(), 0) == 0);
    const int nc = cd_channel_count(p);
    CHECK(nc > 0);
    CHECK(cd_mute_mask(p) == 0);

    // Muting every channel makes it (almost) silent; unmuting brings it back.
    acRms(p, 0.5);
    const double loud = acRms(p, 1.0);
    const uint32_t all = nc >= 32 ? 0xFFFFFFFFu : (1u << nc) - 1u;
    cd_set_mute_mask(p, all);
    CHECK(cd_mute_mask(p) == all);
    acRms(p, 0.3);  // let releases and filters settle
    const double quiet = acRms(p, 1.0);
    std::printf("  loud %.0f, all muted %.0f\n", loud, quiet);
    CHECK(loud > 100);
    CHECK(quiet < loud * 0.1);
    cd_set_mute_mask(p, 0);
    acRms(p, 0.3);
    CHECK(acRms(p, 1.0) > loud * 0.3);

    // Bits above the channel count are dropped; the mask survives a
    // subtune change and is cleared by loading.
    cd_set_mute_mask(p, 0xFFFFFFFFu);
    CHECK(cd_mute_mask(p) == all);
    cd_set_mute_mask(p, 1);
    cd_info info;
    CHECK(cd_get_info(p, &info) == 0);
    CHECK(cd_select_subtune(p, info.current_subtune) == 0);
    CHECK(cd_mute_mask(p) == 1);
    CHECK(cd_load_file(p, (kDir + file).c_str(), 0) == 0);
    CHECK(cd_mute_mask(p) == 0);

    // Seek forwards, backwards and back to the start.
    for (uint32_t target : { 7000u, 2500u, 9000u, 0u })
    {
        const auto t0 = std::chrono::steady_clock::now();
        CHECK(cd_seek_ms(p, target) == 0);
        const double secs = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
        const uint32_t pos = cd_position_ms(p);
        std::printf("  seek %u -> %u ms in %.3f s\n", target, pos, secs);
        CHECK(pos + 30 >= target && pos <= target + 30);
        acRms(p, 0.2);  // still renders afterwards
    }
    cd_destroy(p);
}

int main()
{
    for (const char* f : { "chipdeck-test.sid", "chipdeck-test.sndh", "chipdeck-test.ym",
                           "chipdeck-test.mod", "chipdeck-test.xm", "mdat.chipdeck-test",
                           "mdat.chipdeck-st-test" })
        testTune(f);

    // A long SID seek must stay fast (the chips are not clocked).
    cd_player* p = cd_create(kRate);
    CHECK(cd_load_file(p, (kDir + "chipdeck-test.sid").c_str(), 0) == 0);
    const auto t0 = std::chrono::steady_clock::now();
    CHECK(cd_seek_ms(p, 180000) == 0);
    const double secs = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
    std::printf("SID 3-minute seek: %.3f s\n", secs);
    CHECK(cd_position_ms(p) >= 180000);
    CHECK(secs < 5.0);
    CHECK(acRms(p, 1.0) > 100);  // the voices sound after the jump
    cd_destroy(p);

    if (failures) { std::printf("%d check(s) failed\n", failures); return 1; }
    std::printf("all mute/seek tests passed\n");
    return 0;
}
