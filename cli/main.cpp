/*
 * chipdeck-cli: command-line player for testing the ChipDeck core.
 * Plays C64 .sid and Atari ST .sndh / .ym files.
 * Copyright (C) 2026 ChipDeck contributors. GPL-2.0-or-later.
 */
#include "chipdeck/chipdeck.h"
#include "miniaudio.h"

#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <thread>
#include <vector>

#ifdef _WIN32
#  include <windows.h>
#  include <conio.h>
#else
#  include <termios.h>
#  include <unistd.h>
#  include <sys/select.h>
#endif

namespace {

const uint32_t kRate = 48000;

void usage()
{
    std::fprintf(stderr,
        "ChipDeck CLI %s\n\n"
        "Usage: chipdeck-cli [options] <file.sid|file.sndh|file.ym>\n\n"
        "Options:\n"
        "  -s, --subtune N       start at subtune N (default: tune's default)\n"
        "  -t, --time SECONDS    stop after SECONDS (default: tune length if known,\n"
        "                        else forever)\n"
        "  -m, --model 6581|8580 force SID model (SID only)\n"
        "  -l, --songlengths F   HVSC Songlengths.md5 file\n"
        "      --kernal F        KERNAL ROM (8 KB), improves RSID compatibility\n"
        "      --basic F         BASIC ROM (8 KB)\n"
        "      --chargen F       character ROM (4 KB)\n"
        "  -w, --wav OUT.wav     render to a WAV file instead of the speakers\n"
        "  -i, --info            print tune info and exit\n\n"
        "Keys while playing: n/p next/previous subtune, space pause, q quit\n",
        cd_version());
}

// ------------------------------------------------------------ console keys
#ifdef _WIN32
int pollKey() { return _kbhit() ? _getch() : -1; }
struct RawConsole { RawConsole() {} ~RawConsole() {} };
#else
struct RawConsole
{
    termios old{};
    bool active = false;
    RawConsole()
    {
        if (!isatty(STDIN_FILENO)) return;
        tcgetattr(STDIN_FILENO, &old);
        termios raw = old;
        raw.c_lflag &= ~(ICANON | ECHO);
        tcsetattr(STDIN_FILENO, TCSANOW, &raw);
        active = true;
    }
    ~RawConsole() { if (active) tcsetattr(STDIN_FILENO, TCSANOW, &old); }
};
int pollKey()
{
    if (!isatty(STDIN_FILENO)) return -1;
    fd_set fds; FD_ZERO(&fds); FD_SET(STDIN_FILENO, &fds);
    timeval tv{0, 0};
    if (select(STDIN_FILENO + 1, &fds, nullptr, nullptr, &tv) <= 0) return -1;
    unsigned char c;
    return read(STDIN_FILENO, &c, 1) == 1 ? c : -1;
}
#endif

// --------------------------------------------------------------- WAV out
void put16(FILE* f, uint16_t v) { std::fputc(v & 0xFF, f); std::fputc(v >> 8, f); }
void put32(FILE* f, uint32_t v) { put16(f, v & 0xFFFF); put16(f, v >> 16); }

bool writeWav(const char* path, const std::vector<int16_t>& pcm)
{
    FILE* f = std::fopen(path, "wb");
    if (!f) return false;
    const uint32_t dataBytes = static_cast<uint32_t>(pcm.size() * 2);
    std::fwrite("RIFF", 1, 4, f); put32(f, 36 + dataBytes);
    std::fwrite("WAVEfmt ", 1, 8, f); put32(f, 16);
    put16(f, 1); put16(f, 2); put32(f, kRate); put32(f, kRate * 4);
    put16(f, 4); put16(f, 16);
    std::fwrite("data", 1, 4, f); put32(f, dataBytes);
    for (int16_t s : pcm) put16(f, static_cast<uint16_t>(s));
    std::fclose(f);
    return true;
}

// ------------------------------------------------------------ playback
struct State
{
    cd_player* player;
    std::atomic<bool> paused{false};
};

void audioCallback(ma_device* dev, void* out, const void*, ma_uint32 frames)
{
    State* st = static_cast<State*>(dev->pUserData);
    int16_t* o = static_cast<int16_t*>(out);
    if (st->paused) { std::memset(o, 0, frames * 4); return; }
    size_t got = cd_render(st->player, o, frames);
    if (got < frames) std::memset(o + got * 2, 0, (frames - got) * 4);
}

void printInfo(cd_player* p)
{
    cd_info i;
    if (cd_get_info(p, &i) != 0) return;
    std::printf("Title   : %s\nAuthor  : %s\nReleased: %s\nFormat  : %s\n",
                i.title, i.author, i.released, i.format);
    std::printf("Subtune : %d of %d (default %d)\n", i.current_subtune, i.subtunes, i.start_subtune);
    if (i.sid_chips > 0)  // 0 for Atari ST tunes
        std::printf("SID     : %d chip(s), %s, %s\n", i.sid_chips,
                    i.sid_model == CD_SID_8580 ? "8580" : "6581", i.is_ntsc ? "NTSC" : "PAL");
    if (i.length_ms > 0)
        std::printf("Length  : %d:%02d\n", i.length_ms / 60000, (i.length_ms / 1000) % 60);
}

double limitFor(cd_player* p, double userSeconds)
{
    if (userSeconds > 0) return userSeconds;
    cd_info i;
    if (cd_get_info(p, &i) == 0 && i.length_ms > 0) return i.length_ms / 1000.0;
    return 0; // forever
}

} // namespace

int main(int argc, char** argv)
{
#ifdef _WIN32
    SetConsoleOutputCP(CP_UTF8);
#endif
    const char* file = nullptr;
    const char* wav = nullptr;
    const char* songlengths = nullptr;
    const char *kernal = nullptr, *basic = nullptr, *chargen = nullptr;
    int subtune = 0;
    double seconds = 0;
    bool infoOnly = false;
    cd_sid_model model = CD_SID_AUTO;

    for (int a = 1; a < argc; ++a)
    {
        std::string s = argv[a];
        auto next = [&]() -> const char* {
            if (a + 1 >= argc) { usage(); std::exit(2); }
            return argv[++a];
        };
        if (s == "-s" || s == "--subtune") subtune = std::atoi(next());
        else if (s == "-t" || s == "--time") seconds = std::atof(next());
        else if (s == "-w" || s == "--wav") wav = next();
        else if (s == "-l" || s == "--songlengths") songlengths = next();
        else if (s == "--kernal") kernal = next();
        else if (s == "--basic") basic = next();
        else if (s == "--chargen") chargen = next();
        else if (s == "-i" || s == "--info") infoOnly = true;
        else if (s == "-m" || s == "--model")
        {
            std::string m = next();
            model = m == "8580" ? CD_SID_8580 : m == "6581" ? CD_SID_6581 : CD_SID_AUTO;
        }
        else if (s == "-h" || s == "--help") { usage(); return 0; }
        else if (!s.empty() && s[0] == '-') { usage(); return 2; }
        else file = argv[a];
    }
    if (!file) { usage(); return 2; }

    cd_player* p = cd_create(kRate);
    if (!p) { std::fprintf(stderr, "cannot create player\n"); return 1; }
    cd_set_sid_model(p, model);
    if (songlengths && cd_load_songlengths(p, songlengths) != 0)
        std::fprintf(stderr, "warning: %s\n", cd_last_error(p));
    if ((kernal || basic || chargen) && cd_set_roms(p, kernal, basic, chargen) != 0)
        std::fprintf(stderr, "warning: %s\n", cd_last_error(p));
    if (cd_load_file(p, file, subtune) != 0)
    {
        std::fprintf(stderr, "error loading %s: %s\n", file, cd_last_error(p));
        cd_destroy(p);
        return 1;
    }
    printInfo(p);
    if (infoOnly) { cd_destroy(p); return 0; }

    // ---------------------------------------------------- render to WAV
    if (wav)
    {
        double limit = limitFor(p, seconds);
        if (limit <= 0) limit = 180;
        const size_t total = static_cast<size_t>(limit * kRate);
        std::vector<int16_t> pcm(total * 2);
        size_t got = cd_render(p, pcm.data(), total);
        pcm.resize(got * 2);
        double sum = 0; int peak = 0;
        for (int16_t v : pcm) { sum += double(v) * v; peak = std::max(peak, std::abs(int(v))); }
        double rms = pcm.empty() ? 0 : std::sqrt(sum / pcm.size());
        if (!writeWav(wav, pcm)) { std::fprintf(stderr, "cannot write %s\n", wav); cd_destroy(p); return 1; }
        std::printf("Wrote %s: %.1f s, RMS %.0f, peak %d\n", wav, got / double(kRate), rms, peak);
        cd_destroy(p);
        return got == total ? 0 : 1;
    }

    // --------------------------------------------------- live playback
    State st; st.player = p;
    ma_device_config cfg = ma_device_config_init(ma_device_type_playback);
    cfg.playback.format = ma_format_s16;
    cfg.playback.channels = 2;
    cfg.sampleRate = kRate;
    cfg.dataCallback = audioCallback;
    cfg.pUserData = &st;
    ma_device dev;
    if (ma_device_init(nullptr, &cfg, &dev) != MA_SUCCESS || ma_device_start(&dev) != MA_SUCCESS)
    {
        std::fprintf(stderr, "cannot open audio device (try --wav out.wav)\n");
        cd_destroy(p);
        return 1;
    }
    std::printf("Output  : %s\n\n[n] next  [p] prev  [space] pause  [q] quit\n", dev.playback.name);

    RawConsole raw;
    double limit = limitFor(p, seconds);
    bool quit = false;
    while (!quit)
    {
        int k = pollKey();
        cd_info i; cd_get_info(p, &i);
        int target = 0;
        if (k == 'q' || k == 'Q' || k == 27) quit = true;
        else if (k == ' ') st.paused = !st.paused;
        else if ((k == 'n' || k == 'N' || k == '+') && i.current_subtune < i.subtunes) target = i.current_subtune + 1;
        else if ((k == 'p' || k == 'P' || k == '-') && i.current_subtune > 1) target = i.current_subtune - 1;
        if (target)
        {
            cd_select_subtune(p, target);
            limit = limitFor(p, seconds);
            std::printf("\n");
            printInfo(p);
        }
        uint32_t ms = cd_position_ms(p);
        std::printf("\r  %d:%02d %s   ", ms / 60000, (ms / 1000) % 60, st.paused ? "(paused)" : "        ");
        std::fflush(stdout);
        if (limit > 0 && ms / 1000.0 >= limit) quit = true;
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }
    std::printf("\n");
    ma_device_uninit(&dev);
    cd_destroy(p);
    return 0;
}
