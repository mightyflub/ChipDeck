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

// RMS of each channel over the last `frames` samples (cd_channel_scope).
static std::vector<double> channelRms(cd_player* p, size_t frames)
{
    const int n = cd_channel_count(p);
    std::vector<int16_t> buf(static_cast<size_t>(n) * frames);
    CHECK(cd_channel_scope(p, buf.data(), frames) == frames);
    std::vector<double> rms;
    for (int c = 0; c < n; ++c)
    {
        double sum = 0;
        for (size_t i = 0; i < frames; ++i)
        {
            double v = buf[static_cast<size_t>(c) * frames + i];
            sum += v * v;
        }
        rms.push_back(std::sqrt(sum / frames));
    }
    return rms;
}

// A tiny PSID whose play routine flips the $D418 volume between 7 and 15
// every frame, like a (very slow) volume-register digi. No voices play.
static std::vector<uint8_t> digiTune()
{
    std::vector<uint8_t> d(0x7C, 0);
    auto be16 = [&](size_t at, unsigned v) { d[at] = uint8_t(v >> 8); d[at + 1] = uint8_t(v); };
    std::memcpy(d.data(), "PSID", 4);
    be16(4, 2); be16(6, 0x7C); be16(8, 0); be16(10, 0x1000); be16(12, 0x1006);
    be16(14, 1); be16(16, 1);
    std::memcpy(d.data() + 0x16, "Digi Test", 9);
    const uint8_t code[] = {
        0x00, 0x10,                    // load address $1000
        0xA9, 0x0F, 0x8D, 0x18, 0xD4,  // init: LDA #$0F, STA $D418
        0x60,                          // RTS
        0xE6, 0xFB, 0xA5, 0xFB,        // play: INC $FB, LDA $FB
        0x29, 0x01, 0x0A, 0x0A, 0x0A,  // AND #1, ASL x3 -> 0 or 8
        0x09, 0x07, 0x8D, 0x18, 0xD4,  // ORA #7, STA $D418
        0x60,                          // RTS
    };
    d.insert(d.end(), code, code + sizeof code);
    return d;
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

    // Per-channel scopes: the test tune plays a pulse on voice 1 only.
    {
        CHECK(cd_channel_count(p) == 4);
        char name[16];
        const char* expect[] = { "V1", "V2", "V3", "Digi" };
        for (int c = 0; c < 4; ++c)
            CHECK(cd_channel_name(p, c, name, sizeof name) == 0 && std::strcmp(name, expect[c]) == 0);
        CHECK(cd_channel_name(p, 4, name, sizeof name) != 0);
        std::vector<double> r = channelRms(p, 4096);
        std::printf("channels: V1 %.0f, V2 %.0f, V3 %.0f, Digi %.0f\n", r[0], r[1], r[2], r[3]);
        CHECK(r[0] > 2000);
        CHECK(r[1] < 50 && r[2] < 50 && r[3] < 50);
    }

    // Loading from memory works too.
    std::ifstream f(kTune, std::ios::binary);
    std::vector<char> bytes((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
    CHECK(cd_load_memory(p, bytes.data(), bytes.size(), 2) == 0);
    CHECK(cd_get_info(p, &info) == 0 && info.current_subtune == 2);
    CHECK(render(p, 0.5).rms > 1000);

    // Volume-register digis show up on the Digi channel.
    {
        std::vector<uint8_t> digi = digiTune();
        CHECK(cd_load_memory(p, digi.data(), digi.size(), 0) == 0);
        render(p, 0.5);
        std::vector<double> r = channelRms(p, 4096);
        CHECK(r.size() == 4);
        if (r.size() == 4)
        {
            std::printf("digi tune: V1 %.0f, Digi %.0f\n", r[0], r[3]);
            CHECK(r[3] > 2000);
            CHECK(r[0] < 50);
        }
    }

    // Garbage data is rejected.
    const char junk[] = "this is not a sid file at all";
    CHECK(cd_load_memory(p, junk, sizeof junk, 0) != 0);

    cd_destroy(p);
    if (failures) { std::printf("%d check(s) failed\n", failures); return 1; }
    std::printf("all tests passed\n");
    return 0;
}
