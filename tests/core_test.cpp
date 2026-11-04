/*
 * Core tests: load the bundled test tune, render audio, check it is sane.
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

static const std::string kTune = std::string(CHIPDECK_TEST_DATA) + "/chipdeck-test.sid";

struct Stats { double rms; int zeroCrossings; };

static Stats render(cd_player* p, double seconds)
{
    const size_t frames = static_cast<size_t>(seconds * 48000);
    std::vector<int16_t> pcm(frames * 2);
    size_t got = cd_render(p, pcm.data(), frames);
    CHECK(got == frames);
    double sum = 0; int zc = 0;
    for (size_t i = 0; i < got; ++i)
    {
        int16_t l = pcm[i * 2];
        sum += double(l) * l;
        if (i > 0 && ((pcm[(i - 1) * 2] < 0) != (l < 0))) ++zc;
    }
    return { got ? std::sqrt(sum / got) : 0.0, zc };
}

int main()
{
    std::printf("chipdeck %s\n", cd_version());

    cd_player* p = cd_create(48000);
    CHECK(p != nullptr);

    // Missing file gives an error, not a crash.
    CHECK(cd_load_file(p, "does-not-exist.sid", 0) != 0);
    CHECK(std::strlen(cd_last_error(p)) > 0);
    int16_t dummy[8];
    CHECK(cd_render(p, dummy, 4) == 0);

    // Load and inspect.
    CHECK(cd_load_file(p, kTune.c_str(), 0) == 0);
    cd_info info;
    CHECK(cd_get_info(p, &info) == 0);
    CHECK(std::strcmp(info.title, "ChipDeck Test Tune") == 0);
    CHECK(info.subtunes == 2);
    CHECK(info.start_subtune == 1);
    CHECK(info.current_subtune == 1);
    CHECK(info.sid_chips == 1);
    CHECK(info.length_ms == -1);

    // Subtune 1 produces sound.
    render(p, 0.2); // skip attack
    Stats s1 = render(p, 1.0);
    std::printf("subtune 1: rms %.0f, zero crossings/s %d\n", s1.rms, s1.zeroCrossings);
    CHECK(s1.rms > 1000);
    CHECK(cd_position_ms(p) >= 1100);

    // Subtune 2 is about an octave higher.
    CHECK(cd_select_subtune(p, 2) == 0);
    CHECK(cd_get_info(p, &info) == 0 && info.current_subtune == 2);
    CHECK(cd_position_ms(p) < 100);
    render(p, 0.2);
    Stats s2 = render(p, 1.0);
    std::printf("subtune 2: rms %.0f, zero crossings/s %d\n", s2.rms, s2.zeroCrossings);
    CHECK(s2.rms > 1000);
    CHECK(s2.zeroCrossings > s1.zeroCrossings * 1.5);

    CHECK(cd_select_subtune(p, 3) != 0);  // out of range

    // Loading from memory works too.
    std::ifstream f(kTune, std::ios::binary);
    std::vector<char> bytes((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
    CHECK(cd_load_memory(p, bytes.data(), bytes.size(), 2) == 0);
    CHECK(cd_get_info(p, &info) == 0 && info.current_subtune == 2);
    CHECK(render(p, 0.5).rms > 1000);

    // Garbage data is rejected.
    const char junk[] = "this is not a sid file at all";
    CHECK(cd_load_memory(p, junk, sizeof junk, 0) != 0);

    cd_destroy(p);
    if (failures) { std::printf("%d check(s) failed\n", failures); return 1; }
    std::printf("all tests passed\n");
    return 0;
}
