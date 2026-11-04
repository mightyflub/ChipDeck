/*
 * Atari ST tests: load the bundled .sndh and .ym test tunes through the
 * same C API as SID tunes, render audio, check pitch and metadata.
 * Copyright (C) 2026 ChipDeck contributors. GPL-2.0-or-later.
 */
#include "chipdeck/chipdeck.h"

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

static int failures = 0;
#define CHECK(cond) do { if (!(cond)) { std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); ++failures; } } while (0)

static const std::string kSndh = std::string(CHIPDECK_TEST_DATA) + "/chipdeck-test.sndh";
static const std::string kYm = std::string(CHIPDECK_TEST_DATA) + "/chipdeck-test.ym";
static const std::string kSid = std::string(CHIPDECK_TEST_DATA) + "/chipdeck-test.sid";

struct Stats { double rms; double hz; bool stereoEqual; };

// Render `seconds` and estimate the fundamental from zero crossings.
static Stats render(cd_player* p, double seconds)
{
    const size_t frames = static_cast<size_t>(seconds * 48000);
    std::vector<int16_t> pcm(frames * 2);
    size_t got = cd_render(p, pcm.data(), frames);
    CHECK(got == frames);
    double mean = 0;
    for (size_t i = 0; i < got; ++i) mean += pcm[i * 2];
    mean = got ? mean / got : 0;
    double sum = 0; int zc = 0; bool eq = true;
    for (size_t i = 0; i < got; ++i)
    {
        double l = pcm[i * 2] - mean;
        sum += l * l;
        if (i > 0 && ((pcm[(i - 1) * 2] - mean < 0) != (l < 0))) ++zc;
        if (pcm[i * 2] != pcm[i * 2 + 1]) eq = false;
    }
    return { got ? std::sqrt(sum / got) : 0.0, zc / 2.0 / seconds, eq };
}

static bool near(double v, double want, double tol) { return std::fabs(v - want) <= tol; }

int main()
{
    std::printf("chipdeck %s\n", cd_version());
    CHECK(std::strstr(cd_version(), "AtariAudio") != nullptr);

    cd_player* p = cd_create(48000);
    CHECK(p != nullptr);

    // ---------------------------------------------------------------- SNDH
    CHECK(cd_load_file(p, kSndh.c_str(), 0) == 0);
    cd_info info;
    CHECK(cd_get_info(p, &info) == 0);
    CHECK(std::strcmp(info.title, "ChipDeck Test SNDH") == 0);
    CHECK(std::strcmp(info.author, "ChipDeck") == 0);
    CHECK(std::strcmp(info.released, "2026") == 0);
    CHECK(std::strcmp(info.format, "SNDH") == 0);
    CHECK(info.subtunes == 2);
    CHECK(info.start_subtune == 1);
    CHECK(info.current_subtune == 1);
    CHECK(info.sid_chips == 0);
    // FRMS says 1000 ticks; an Atari "50 Hz" tick is really ~50.05 Hz.
    CHECK(near(info.length_ms, 20000, 100));
    std::printf("sndh subtune 1 length %d ms\n", info.length_ms);

    Stats s1 = render(p, 1.0);
    std::printf("sndh subtune 1: rms %.0f, %.1f Hz\n", s1.rms, s1.hz);
    CHECK(s1.rms > 1000);
    CHECK(near(s1.hz, 2000000.0 / (16 * 254), 5));  // ~492 Hz
    CHECK(s1.stereoEqual);
    CHECK(near(cd_position_ms(p), 1000, 2));

    CHECK(cd_select_subtune(p, 2) == 0);
    CHECK(cd_get_info(p, &info) == 0 && info.current_subtune == 2);
    CHECK(near(info.length_ms, 30000, 100));
    CHECK(cd_position_ms(p) == 0);
    Stats s2 = render(p, 1.0);
    std::printf("sndh subtune 2: rms %.0f, %.1f Hz\n", s2.rms, s2.hz);
    CHECK(near(s2.hz, 2000000.0 / (16 * 127), 5));  // ~984 Hz

    CHECK(cd_select_subtune(p, 3) != 0);
    CHECK(cd_select_subtune(p, 0) != 0);

    // Per-channel scopes: YM A, B, C and the STE DAC; the tune uses A.
    {
        CHECK(cd_channel_count(p) == 4);
        char name[16];
        const char* expect[] = { "A", "B", "C", "DAC" };
        for (int c = 0; c < 4; ++c)
            CHECK(cd_channel_name(p, c, name, sizeof name) == 0 && std::strcmp(name, expect[c]) == 0);
        std::vector<int16_t> buf(4 * 2048);
        CHECK(cd_channel_scope(p, buf.data(), 2048) == 2048);
        double e[4] = { 0, 0, 0, 0 };
        for (int c = 0; c < 4; ++c)
            for (int i = 0; i < 2048; ++i) e[c] += std::abs(double(buf[c * 2048 + i]));
        std::printf("sndh channels: A %.0f B %.0f C %.0f DAC %.0f\n", e[0] / 2048, e[1] / 2048, e[2] / 2048, e[3] / 2048);
        CHECK(e[0] / 2048 > 1000);
        CHECK(e[1] / 2048 < 100 && e[2] / 2048 < 100 && e[3] / 2048 < 100);
    }

    // SID register access is SID-only.
    uint8_t regs[32];
    CHECK(cd_get_sid_registers(p, 0, regs) != 0);

    // Loading from memory works too, with an explicit subtune.
    {
        std::ifstream f(kSndh, std::ios::binary);
        std::vector<char> bytes((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
        CHECK(cd_load_memory(p, bytes.data(), bytes.size(), 2) == 0);
        CHECK(cd_get_info(p, &info) == 0 && info.current_subtune == 2);
        CHECK(near(render(p, 0.5).hz, 984, 6));
    }

    // ------------------------------------------------------------------ YM
    CHECK(cd_load_file(p, kYm.c_str(), 0) == 0);
    CHECK(cd_get_info(p, &info) == 0);
    CHECK(std::strcmp(info.title, "ChipDeck Test YM") == 0);
    CHECK(std::strcmp(info.format, "YM 5") == 0);
    CHECK(info.subtunes == 1);
    CHECK(near(info.length_ms, 10000, 100));
    // Notes alternate every 16 ticks (~0.32 s); 0.3 s windows see one note.
    Stats y1 = render(p, 0.3);
    Stats y2 = render(p, 0.32);
    std::printf("ym: %.1f Hz then %.1f Hz\n", y1.hz, y2.hz);
    CHECK(y1.rms > 1000);
    CHECK(near(y1.hz, 2000000.0 / (16 * 254), 6));
    CHECK(near(y2.hz, 2000000.0 / (16 * 190), 15));
    CHECK(cd_channel_count(p) == 3);  // YM: A, B, C, no DAC

    // ------------------------------------------- switching back to SID works
    CHECK(cd_load_file(p, kSid.c_str(), 0) == 0);
    CHECK(cd_get_info(p, &info) == 0 && info.sid_chips == 1);
    CHECK(std::strcmp(info.title, "ChipDeck Test Tune") == 0);
    CHECK(render(p, 0.5).rms > 1000);

    // Broken Atari data is rejected, not crashed on.
    {
        std::ifstream f(kSndh, std::ios::binary);
        std::vector<char> bytes((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
        // Keep the SNDH magic but wipe every tag (and the HDNS end marker).
        for (size_t i = 16; i < 100 && i < bytes.size(); ++i) bytes[i] = 'X';
        CHECK(cd_load_memory(p, bytes.data(), bytes.size(), 0) != 0);
        CHECK(std::strlen(cd_last_error(p)) > 0);
        int16_t dummy[8];
        CHECK(cd_render(p, dummy, 4) == 0);
    }
    cd_destroy(p);

    // ------------------------------------------------------- cd_probe_file
    CHECK(cd_probe_file(kSndh.c_str(), nullptr, &info) == 0);
    CHECK(std::strcmp(info.format, "SNDH") == 0 && info.subtunes == 2);
    CHECK(near(info.length_ms, 20000, 100));
    CHECK(cd_probe_file(kYm.c_str(), nullptr, &info) == 0);
    CHECK(std::strcmp(info.format, "YM 5") == 0);

    if (failures) { std::printf("%d check(s) failed\n", failures); return 1; }
    std::printf("all tests passed\n");
    return 0;
}
