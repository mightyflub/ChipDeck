/*
 * ChipDeck core: TFMX-ST playback.
 * Copyright (C) 2026 ChipDeck contributors. GPL-2.0-or-later.
 *
 * The Replay struct below is a C++ port of Chris Huelsbeck's TFMX-ST
 * replay routine ("TFMX-ROUTINE versionnum $0892, last 18.9.92"), from the
 * commented 68000 source in Wanted Team's TFMX ST EaglePlayer as shipped
 * with UADE (amigasrc/players/wanted_team/TFMX_ST/TFMX ST_v1.asm). Labels
 * and field names follow that source so the two can be compared. Writes
 * to the YM2149 (GISELECT/GIWRITE in the original) go to AtariAudio's
 * YM2149 emulation. The digi-drum player ("digisound") is not in that
 * source; it is approximated here: 4-bit samples from the smpl. file are
 * written to the channel's volume register at the rate set by macro $49
 * (an Amiga period, as in the Wanted Team player), until the next sample,
 * macro $4A or the end of the file.
 *
 * Known quirks of the original are kept on purpose (they are how the
 * music sounded on the ST): pattern command $F9 (return) restores track 1,
 * portamento notes use the Amiga period table, and the YM volume of the
 * noise/envelope pseudo channel goes to the noise period register.
 */
#include "tfmxst_backend.h"

#include <algorithm>
#include <cstdio>
#include <cstring>

#include "ym2149c.h"

namespace chipdeck {

namespace {

constexpr int kTickHz = 50;      // the replay runs from the ST's 50 Hz VBL
constexpr int kMaxSongTicks = kTickHz * 60 * 30;  // stop measuring after 30 min
constexpr uint32_t kAmigaClock = 3546895;

const uint16_t kNotTab[64] = {
    1710,1614,1524,1438,1357,1281,1209,1141,1077,1017, 960, 908,
     856, 810, 764, 720, 680, 642, 606, 571, 539, 509, 480, 454,
     428, 404, 381, 360, 340, 320, 303, 286, 270, 254, 240, 227,
     214, 202, 191, 180, 170, 160, 151, 143, 135, 127, 120, 113,
     214, 202, 191, 180, 170, 160, 151, 143, 135, 127, 120, 113,
     214, 202, 191, 180 };

const uint16_t kPsgNotTab[64] = {
    2703,2551,2407,2273,2145,2025,1911,1804,1703,1607,1517,1432,
    1351,1275,1203,1136,1072,1012, 955, 902, 851, 803, 758, 716,
     675, 637, 601, 568, 536, 506, 477, 451, 425, 401, 379, 358,
     337, 318, 300, 284, 268, 253, 238, 225, 212, 200, 189, 179,
     168, 159, 150, 142, 134, 126, 119, 112, 106, 100,  94,  89,
      84,  79,  75,  71 };

void copyStr(char* dst, size_t cap, const char* src)
{
    std::snprintf(dst, cap, "%s", src ? src : "");
}

} // namespace

// ------------------------------------------------------------------ replay

struct TfmxStTune::Replay
{
    // psgfieldN (synthesizer, one per YM voice plus the noise/envelope one)
    struct Synth
    {
        uint8_t mstatus = 0, modstatus = 0;
        uint8_t noteLo = 0, noteHi = 0;   // basenote+1 (current), basenote (previous)
        uint16_t basevol = 0;
        int16_t detunes = 0;
        uint32_t madress = 0;
        uint16_t mstep = 0, mawait = 0;
        uint8_t volume = 0, mloopcount = 0;
        uint8_t envelope = 0, envcount = 0, envolume = 0, envspeed = 0;
        int8_t vibrate = 0;
        uint8_t vibcount = 0, pospeed = 0, pocount = 0;
        int16_t vibperiod = 0;
        uint8_t vibsize1 = 0, vibsize2 = 0;
        uint16_t baseperiod = 0, potime = 0, poperiod = 0;
        uint8_t keyflag = 0, riffAND = 0;
        uint32_t msubadr = 0;
        uint16_t msubstep = 0;
        uint8_t riffspeed = 0, riffrandm = 0, riffcount = 0;
        int8_t riffstats = 0;
        uint32_t riffadres = 0;
        uint16_t riffsteps = 0;
        uint8_t riffmacro = 0, rifftrigg = 0, mskipflag = 0;
        int8_t psg_peroffs = 0, psg_voloffs = 0;
        uint8_t psg_pulseon = 0, psg_pulsoff = 0, psg_noiseon = 0, psg_noisoff = 0;
        uint8_t psg_ebit = 0, psg_samflag = 0;
    };
    // CHfield2 (sequencer), one per track
    struct Track
    {
        uint16_t muteflags = 0;
        uint32_t padress = 0;   // offset into mdat, or kEmptyPatt
        uint8_t pt = 0xff, transpose = 0, ploopcount = 0;
        uint16_t pstep = 0;
        uint8_t pawait = 0;
        uint32_t psubadr = 0;
        uint16_t psubstep = 0;
    };
    static constexpr uint32_t kEmptyPatt = 0xFFFFFFF0u;  // $f4000000,$f0000000

    std::vector<uint8_t> m;     // mdat (writable: macro cmds $32/$33 modify it)
    const std::vector<uint8_t>* smpl = nullptr;
    Ym2149c* ym = nullptr;      // null during dry runs (length measuring)
    std::unique_ptr<Ym2149c> chip;

    Synth s[4];
    Track tr[8];
    uint32_t trackbase = 0x800, pattnbase = 0x400, macrobase = 0x600;
    uint16_t fstep = 0, lstep = 0, cstep = 0, speed = 5;
    int16_t scount = 0, tloopcount = -1;
    uint8_t newstep = 0, allon = 0, psgmix = 0xff;
    int8_t song = -1;
    uint8_t fadevol = 0x40, fadeend = 0x40, fadecount1 = 0, fadecount2 = 0;
    int8_t fadeadd = 0;
    uint16_t infoFade = 0;
    uint16_t random = 0;
    uint32_t beam = 0x1234567;
    uint8_t help[4] = {0, 0, 0, 0};   // help1: aa bb cd ee
    bool songEnd = false;

    // Digi sample player (approximation of the ST "digisound" routine).
    bool digiOn = false;
    int digiReg = 8;
    uint32_t digiPos = 0;
    uint64_t digiFrac = 0;
    uint16_t digiRate = 0x240;
    bool smpl4bit = true;

    // ---- memory helpers (bounds checked; out of range reads give 0)
    uint8_t rd8(uint32_t o) const { return o < m.size() ? m[o] : 0; }
    uint16_t rd16(uint32_t o) const { return static_cast<uint16_t>((rd8(o) << 8) | rd8(o + 1)); }
    uint32_t rd32(uint32_t o) const { return (uint32_t(rd16(o)) << 16) | rd16(o + 2); }
    void wr16(uint32_t o, uint16_t v)
    {
        if (o + 1 < m.size()) { m[o] = static_cast<uint8_t>(v >> 8); m[o + 1] = static_cast<uint8_t>(v); }
    }
    uint16_t cdee() const { return static_cast<uint16_t>((help[2] << 8) | help[3]); }

    void ymw(int reg, uint8_t v)
    {
        reg &= 15;
        if (ym && reg < 14) { ym->WritePort(0, static_cast<uint8_t>(reg)); ym->WritePort(2, v); }
    }
    void writePeriod(const Synth& f, uint16_t p)
    {
        if (f.psg_peroffs < 0) return;
        ymw(f.psg_peroffs, static_cast<uint8_t>(p));
        ymw(f.psg_peroffs + 1, static_cast<uint8_t>(p >> 8));
    }
    uint32_t macroAddr(unsigned n) const { return rd32(macrobase + (n & 0xff) * 4); }
    uint32_t pattAddr(unsigned n) const { return rd32(pattnbase + (n & 0xff) * 4); }
    Synth& synthFor(uint8_t cd) { return s[(cd & 0xf) & 3]; }  // Synoffsets (16 entries, x4)

    void randomize()
    {
        beam = beam * 1103515245u + 12345u;          // stands in for $dff006
        random ^= static_cast<uint16_t>(beam >> 16);
        random = static_cast<uint16_t>(random + 0x4335);
    }

    // ---- init
    void initdata()
    {
        fadevol = fadeend = 0x40;
        fadecount1 = fadecount2 = 0;
        fadeadd = 0;
        if (rd32(0x1d0) != 0)
        {
            trackbase = rd32(0x1d0);
            pattnbase = rd32(0x1d4);
            macrobase = rd32(0x1d8);
        }
        else
        {
            trackbase = 0x800; pattnbase = 0x400; macrobase = 0x600;
        }
        speed = 5;
        static const int8_t per[4] = { 0, 2, 4, 0x0b };
        static const int8_t vol[4] = { 8, 9, 10, 6 };
        static const uint8_t pon[4] = { 0xfe, 0xfd, 0xfb, 0xff };
        static const uint8_t poff[4] = { 0x01, 0x02, 0x04, 0x00 };
        static const uint8_t non[4] = { 0xf7, 0xef, 0xdf, 0xff };
        static const uint8_t noff[4] = { 0x08, 0x10, 0x20, 0x00 };
        for (int i = 0; i < 4; ++i)
        {
            s[i] = Synth();
            s[i].psg_peroffs = per[i];
            s[i].psg_voloffs = vol[i];
            s[i].psg_pulseon = pon[i];
            s[i].psg_pulsoff = poff[i];
            s[i].psg_noiseon = non[i];
            s[i].psg_noisoff = noff[i];
        }
    }

    void aclear(Synth& f)
    {
        f.mstatus = 0;
        f.mskipflag = 0;
        f.riffstats = 0;
        f.psg_samflag = 0;
    }

    void alloff()
    {
        allon = 0;
        psgmix = 0xff;
        for (auto& f : s) aclear(f);
        digiOn = false;
    }

    void songset(int n)
    {
        alloff();
        n &= 0x1f;
        cstep = fstep = rd16(256 + n * 2);
        lstep = rd16(320 + n * 2);
        speed = rd16(384 + n * 2);
        for (auto& t : tr)
        {
            t.padress = kEmptyPatt;
            t.pt = 0xff;
            t.transpose = 0;
            t.pstep = 0;
            t.pawait = 0;
        }
        newtrack();
        newstep = 0;
        scount = 0;
        tloopcount = -1;
        song = static_cast<int8_t>(n);
        infoFade = 0;
        allon = 1;
    }

    // ---- per VBL
    void irqin()
    {
        if (!allon) return;
        for (auto& f : s) specials(f);   // synthesizer
        if (song >= 0) sequencer();
        // Wanted Team: song end once every track has stopped.
        bool all = true;
        for (auto& t : tr) all = all && t.pt == 0xff;
        if (all) songEnd = true;
    }

    // ---- sequencer
    void sequencer()
    {
        if (--scount >= 0) return;
        scount = static_cast<int16_t>(speed);
        for (int t = 0; t < 8; ++t) tr[t].muteflags = rd16(448 + t * 2);
        for (int guard = 0; guard < 64; ++guard)   // patternplay
        {
            newstep = 0;
            int t = 0;
            for (; t < 8; ++t)
            {
                playTrack(tr[t]);
                if (newstep) break;
            }
            if (!newstep) break;
        }
    }

    uint32_t pattWord(const Track& t, uint16_t step, uint8_t out[4]) const
    {
        if (t.padress == kEmptyPatt)
        {
            static const uint8_t e[8] = { 0xf4, 0, 0, 0, 0xf0, 0, 0, 0 };
            const int i = (step & 1) * 4;
            std::memcpy(out, e + i, 4);
            return 0;
        }
        const uint32_t o = t.padress + uint32_t(step) * 4;
        for (int i = 0; i < 4; ++i) out[i] = rd8(o + i);
        return o;
    }

    void playTrack(Track& t)
    {
        if (t.pt >= 0x90)
        {
            if (t.pt == 0xfe)
            {
                t.pt = 0xff;
                if (t.muteflags == 0) channeloff(t.transpose);
            }
            return;
        }
        if (t.pawait) { --t.pawait; return; }
        for (int guard = 0; guard < 512; ++guard)   // play2
        {
            pattWord(t, t.pstep, help);
            const uint8_t aa = help[0];
            if (aa < 0xf0)
            {
                const uint8_t d7 = aa;
                if (aa < 0xc0 && aa >= 0x7f)
                {
                    t.pawait = help[3];
                    help[3] = 0;
                }
                uint8_t d0 = static_cast<uint8_t>(aa + t.transpose);
                if (d7 < 0xc0) d0 &= 0x3f;
                help[0] = d0;
                if (t.muteflags == 0) noteport(help);
                ++t.pstep;
                if (d7 >= 0xc0 || d7 < 0x7f) continue;  // play4
                return;                                  // play5
            }
            switch (aa & 0xf)
            {
            case 0x0:  // pend
                t.pt = 0xff;
                if (cstep == lstep) { cstep = fstep; songEnd = true; }
                else ++cstep;
                newtrack();
                newstep = 1;
                return;
            case 0x1:  // ploop
                if (t.ploopcount)
                {
                    if (--t.ploopcount == 0) { ++t.pstep; continue; }
                    t.pstep = cdee();
                    continue;
                }
                t.ploopcount = help[1];
                t.pstep = cdee();
                continue;
            case 0x2:  // pcont
                t.pt = help[1];
                t.padress = pattAddr(help[1]);
                t.pstep = cdee();
                continue;
            case 0x3:  // pwait
                t.pawait = help[1];
                ++t.pstep;
                return;
            case 0x4:  // pstop
            case 0xe:  // pstopcus
                t.pt = 0xff;
                return;
            case 0x5:  // pkeyup
                help[1] = static_cast<uint8_t>(help[1] + t.transpose);
                // fall through
            case 0x6: case 0x7: case 0xc:  // pportsp
                if (t.muteflags == 0) noteport(help);
                ++t.pstep;
                continue;
            case 0x8:  // pgosub
                t.psubadr = t.padress;
                t.psubstep = t.pstep;
                t.pt = help[1];
                t.padress = pattAddr(help[1]);
                t.pstep = cdee();
                continue;
            case 0x9:  // preturn (the original restores track 1, see top)
                tr[0].padress = tr[0].psubadr;
                tr[0].pstep = tr[0].psubstep;
                ++t.pstep;
                continue;
            case 0xa:  // pfade
                fadeCmd(help[1], help[3]);
                ++t.pstep;
                continue;
            case 0xb:  // ppseq
            {
                Track& o = tr[help[2] & 7];
                o.pt = help[1];
                o.transpose = help[3];
                o.padress = pattAddr(help[1] & 0x7f);
                o.pstep = 0;
                o.pawait = 0;
                o.ploopcount = 0;
                ++t.pstep;
                continue;
            }
            default:   // $fd psendflag, $ff
                ++t.pstep;
                continue;
            }
        }
        t.pt = 0xff;   // runaway pattern
    }

    void fadeCmd(uint8_t count, uint8_t end)
    {
        if (infoFade) return;
        infoFade = 1;
        fadeend = end;
        fadecount1 = fadecount2 = count;
        if (count == 0)
        {
            fadevol = fadeend;
            fadeadd = 0;
            infoFade = 0;
            return;
        }
        fadeadd = 1;
        if (fadevol == fadeend) { fadeadd = 0; infoFade = 0; return; }
        if (fadevol < fadeend) return;
        fadeadd = -1;
    }

    void newtrack()
    {
        for (int guard = 0; guard < 64; ++guard)
        {
            const uint32_t a = trackbase + uint32_t(cstep & 0x1ff) * 16;
            if (rd16(a) == 0xeffe)
            {
                uint16_t cmd = rd16(a + 2);
                if (cmd > 4) cmd = 0;
                switch (cmd)
                {
                case 0:  // stopsong
                    allon = 0;
                    songEnd = true;
                    return;
                case 1:  // loopsong
                    if (tloopcount == 0)
                    {
                        tloopcount = -1;
                        ++cstep;
                    }
                    else if (tloopcount < 0)
                    {
                        const int16_t d0 = static_cast<int16_t>(rd16(a + 6));
                        if (d0 <= 0) songEnd = true;
                        tloopcount = static_cast<int16_t>(d0 - 1);
                        cstep = rd16(a + 4);
                    }
                    else
                    {
                        --tloopcount;
                        cstep = rd16(a + 4);
                    }
                    continue;
                case 2:  // speedsong
                    speed = rd16(a + 4);
                    scount = static_cast<int16_t>(speed);
                    ++cstep;
                    continue;
                default:  // 3 set7freq, 4 fadesong
                    ++cstep;
                    fadeCmd(rd8(a + 5), rd8(a + 7));
                    continue;
                }
            }
            for (int t = 0; t < 8; ++t)
            {
                Track& k = tr[t];
                k.pt = rd8(a + t * 2);
                k.transpose = rd8(a + t * 2 + 1);
                if (k.pt < 0x80)
                {
                    k.padress = pattAddr(k.pt);
                    k.pstep = 0;
                    k.pawait = 0;
                    k.ploopcount = 0;
                }
            }
            return;
        }
        songEnd = true;  // endless loop of track commands
        allon = 0;
    }

    // ---- notes into the synthesizer
    void noteport(const uint8_t in[4])
    {
        uint8_t saved[4];
        std::memcpy(saved, help, 4);
        uint8_t h[4];
        std::memcpy(h, in, 4);
        Synth& f = synthFor(h[2]);
        const uint8_t aa = h[0];
        if (aa >= 0x80)
        {
            if (aa == 0xf7)
            {
                f.envspeed = h[1];
                f.envcount = f.envelope = static_cast<uint8_t>((h[2] >> 4) + 1);
                f.envolume = h[3];
                std::memcpy(help, saved, 4);
                return;
            }
            if (aa == 0xf6)
            {
                f.vibsize1 = h[1] & 0xfe;
                f.vibsize2 = f.vibsize1 >> 1;
                f.vibrate = static_cast<int8_t>(h[3]);
                f.vibcount = 1;
                f.vibperiod = 0;
                std::memcpy(help, saved, 4);
                return;
            }
            if (aa == 0xf5)
            {
                f.keyflag = 0;
                std::memcpy(help, saved, 4);
                return;
            }
            if (aa >= 0xbf)
            {
                // portnote
                f.pospeed = h[1];
                f.pocount = 1;
                if (f.potime == 0) f.poperiod = f.baseperiod;
                f.potime = h[3];
                f.noteLo = aa & 0x3f;
                f.baseperiod = kNotTab[aa & 0x3f];
                std::memcpy(help, saved, 4);
                return;
            }
        }
        // noteonly
        f.detunes = static_cast<int8_t>(h[3]);
        f.basevol = (h[2] >> 4) & 0xf;
        f.noteHi = f.noteLo;
        f.noteLo = aa;
        const uint32_t ma = macroAddr(h[1]);
        if (ma != f.madress) f.mskipflag = 0;
        f.madress = ma;
        f.mstep = 0;
        f.mawait = 0;
        f.modstatus = 0;
        f.mloopcount = 0;
        f.mstatus = 0xff;
        f.keyflag = 1;
        std::memcpy(help, saved, 4);
    }

    void channeloff(uint8_t ch)
    {
        Synth& f = s[(ch & 0xf) & 3];
        if ((ch & 0xf) * 4 >= 0x18)
        {
            psgmix |= f.psg_pulsoff;
            ymw(7, psgmix);
            psgmix |= f.psg_noisoff;
            ymw(7, psgmix);
            f.psg_ebit = 0;
        }
        f.mstatus = 0;
        f.riffstats = 0;
    }

    // mputnote: d2 = note to add; sets baseperiod (and the YM period).
    void mputnote(Synth& f, uint8_t d2)
    {
        const int n = (help[1] + d2) & 0x3f;
        uint32_t d0 = f.psg_peroffs >= 0 ? kPsgNotTab[n] : kNotTab[n];
        const uint16_t d1 = static_cast<uint16_t>(f.detunes + cdee());
        if (d1 != 0) d0 = ((d0 * uint16_t(d1 + 256)) >> 8) & 0xffff;
        f.baseperiod = static_cast<uint16_t>(d0);
        if (f.potime == 0) writePeriod(f, f.baseperiod);
    }

    void volFe(Synth& f)
    {
        // Volume macros with $FE in byte 3: also set the note.
        if (help[2] != 0xfe) return;
        const uint8_t d3 = help[3];
        help[2] = help[3] = 0;
        mputnote(f, f.noteLo);
        help[3] = d3;
    }

    void startSample(Synth& f)
    {
        const uint32_t ofs = ((help[1] & 0xf) << 16) | (help[2] << 8) | help[3];
        if (f.psg_voloffs < 8 || f.psg_voloffs > 10 || !smpl || ofs >= smpl->size())
        {
            digiOn = false;
            return;
        }
        digiOn = true;
        digiReg = f.psg_voloffs;
        digiPos = ofs;
        digiFrac = 0;
    }

    // ---- macros ("specials")
    void specials(Synth& f)
    {
        if (!f.mstatus) { modulations(f); return; }
        if (f.mawait) { --f.mawait; modulations(f); return; }
        for (int guard = 0; guard < 256; ++guard)   // mac2
        {
            const uint32_t a0 = f.madress + uint32_t(f.mstep) * 4;
            const uint8_t cmd = rd8(a0);
            help[0] = 0;
            help[1] = rd8(a0 + 1);
            help[2] = rd8(a0 + 2);
            help[3] = rd8(a0 + 3);
            if (cmd >= 0x50) { ++f.mstep; modulations(f); return; }  // macadd
            switch (cmd)
            {
            case 0x04:  // mwait
                if (help[1] & 1)
                {
                    if (f.rifftrigg) { modulations(f); return; }
                    f.rifftrigg = 1;
                    ++f.mstep;
                    continue;
                }
                f.mawait = cdee();
                ++f.mstep;
                modulations(f);
                return;
            case 0x10:  // mloopkey
                if (!f.keyflag) { ++f.mstep; continue; }
                // fall through
            case 0x05:  // mloop
                if (f.mloopcount)
                {
                    if (--f.mloopcount == 0) { ++f.mstep; continue; }
                    f.mstep = cdee();
                    continue;
                }
                f.mloopcount = help[1];
                f.mstep = cdee();
                continue;
            case 0x15:  // mgosub
                f.msubadr = f.madress;
                f.msubstep = f.mstep;
                // fall through
            case 0x06:  // mcont
                f.madress = macroAddr(help[1] & 0x7f);
                f.mstep = cdee();
                f.mloopcount = 0;
                f.mskipflag = 0;
                continue;
            case 0x07:  // mstop
                f.mstatus = 0;
                modulations(f);
                return;
            case 0x08:  // maddnote
                mputnote(f, f.noteLo);
                ++f.mstep;
                modulations(f);
                return;
            case 0x09:  // msetnote
                mputnote(f, 0);
                ++f.mstep;
                modulations(f);
                return;
            case 0x1f:  // mlastnote
                mputnote(f, f.noteHi);
                ++f.mstep;
                modulations(f);
                return;
            case 0x0a:  // mclear
                f.riffstats = 0;
                // fall through
            case 0x40:  // mpsgreset
                f.envelope = 0;
                f.vibsize1 = 0;
                f.potime = 0;
                f.psg_ebit = 0;
                ++f.mstep;
                continue;
            case 0x0b:  // mporta
                f.pospeed = help[1];
                f.pocount = 1;
                if (f.potime == 0) f.poperiod = f.baseperiod;
                f.potime = cdee();
                ++f.mstep;
                continue;
            case 0x0c:  // mvibrato
                f.vibsize1 = help[1];
                f.vibsize2 = help[1] >> 1;
                f.vibrate = static_cast<int8_t>(help[3]);
                f.vibcount = 1;
                if (f.potime == 0) f.vibperiod = 0;
                ++f.mstep;
                continue;
            case 0x0d:  // maddvolume
                volFe(f);
                f.volume = static_cast<uint8_t>(f.basevol * 3 + cdee());
                ++f.mstep;
                continue;
            case 0x0e:  // msetvolume
                volFe(f);
                f.volume = help[3];
                ++f.mstep;
                continue;
            case 0x0f:  // menvelope
                f.envelope = help[2];
                f.envspeed = help[1];
                f.envcount = help[2];
                f.envolume = help[3];
                ++f.mstep;
                continue;
            case 0x14:  // mwaitkeyo
                if (!f.keyflag) { ++f.mstep; continue; }
                if (f.mloopcount == 0)
                {
                    f.mloopcount = help[3];
                    modulations(f);
                    return;
                }
                if (--f.mloopcount == 0) { ++f.mstep; continue; }
                modulations(f);
                return;
            case 0x16:  // mreturn
                f.madress = f.msubadr;
                f.mstep = static_cast<uint16_t>(f.msubstep + 1);
                continue;
            case 0x17:  // msetperiod
                f.baseperiod = cdee();
                ++f.mstep;
                continue;
            case 0x1b:  // mriff
                f.riffmacro = help[1];
                f.riffspeed = help[2];
                f.riffrandm = help[3];
                f.riffcount = 1;
                f.riffstats = 1;
                riffplay(f);
                f.rifftrigg = 1;
                ++f.mstep;
                continue;
            case 0x1c:  // msplitk
                if (help[1] >= f.noteLo) { ++f.mstep; continue; }
                f.mstep = cdee();
                continue;
            case 0x1d:  // msplitv
                if (help[1] >= f.volume) { ++f.mstep; continue; }
                f.mstep = cdee();
                continue;
            case 0x1e:  // mriff2
                f.riffAND = help[1];
                ++f.mstep;
                continue;
            case 0x21:  // mplaynote
            {
                uint8_t h[4] = { f.noteLo, help[1],
                                 static_cast<uint8_t>(help[2] | (f.basevol << 4)), help[3] };
                noteport(h);
                ++f.mstep;
                continue;
            }
            case 0x30:  // mskip
                if (!f.mskipflag) { f.mskipflag = 1; ++f.mstep; continue; }
                f.mstep = cdee();
                continue;
            case 0x31:  // mskeyup
            {
                uint8_t h[4] = { 0xf5, help[1], help[2], help[3] };
                noteport(h);
                ++f.mstep;
                continue;
            }
            case 0x32:  // maddword
            case 0x33:  // mandword
            {
                const uint32_t o = a0 + uint32_t(help[1]) * 2;
                const uint16_t v = rd16(o);
                wr16(o, cmd == 0x32 ? static_cast<uint16_t>(v + cdee())
                                    : static_cast<uint16_t>(v & cdee()));
                ++f.mstep;
                continue;
            }
            case 0x41:  // mpsgwave
                if (help[1]) psgmix &= f.psg_pulseon; else psgmix |= f.psg_pulsoff;
                ymw(7, psgmix);
                if (help[3]) psgmix &= f.psg_noiseon; else psgmix |= f.psg_noisoff;
                ymw(7, psgmix);
                ++f.mstep;
                continue;
            case 0x42:  // mpsgcenv
                ymw(11, help[3]);
                ymw(12, help[2]);
                ymw(13, help[1]);
                f.psg_ebit = 0x10;
                ++f.mstep;
                continue;
            case 0x43:  // mpsgcean
            {
                const int n = (help[1] + f.noteLo) & 0x3f;
                uint32_t d0 = kPsgNotTab[n];
                const uint16_t d1 = static_cast<uint16_t>(f.detunes + cdee());
                if (d1 != 0) d0 = ((d0 * uint16_t(d1 + 256)) >> 8) & 0xffff;
                f.baseperiod = static_cast<uint16_t>(d0);
                if (f.potime == 0)
                {
                    ymw(11, static_cast<uint8_t>(d0));
                    ymw(12, static_cast<uint8_t>(d0 >> 8));
                }
                ++f.mstep;
                continue;
            }
            case 0x44:  // mpsgnper
                s[3].volume = help[1];
                ++f.mstep;
                continue;
            case 0x45:  // mpsgsetp
                ymw(f.psg_peroffs, help[3]);
                ymw(f.psg_peroffs + 1, help[2]);
                f.baseperiod = cdee();
                ++f.mstep;
                continue;
            case 0x47:  // mpsgmixa
                psgmix = static_cast<uint8_t>((psgmix & help[1]) | help[3]);
                ymw(7, psgmix);
                ++f.mstep;
                continue;
            case 0x48:  // mpsgsample
                psgmix &= f.psg_pulseon;
                psgmix |= f.psg_noisoff;
                ymw(f.psg_peroffs, 0);
                ymw(f.psg_peroffs + 1, 0);
                ymw(7, psgmix);
                f.baseperiod = 0;
                startSample(f);
                f.psg_samflag = 0xff;
                ++f.mstep;
                continue;
            case 0x49:  // mpsgsrate
                digiRate = cdee();
                ++f.mstep;
                continue;
            case 0x4a:  // mpsgsstop
                f.psg_samflag = 0;
                if (digiReg == f.psg_voloffs) digiOn = false;
                ++f.mstep;
                continue;
            default:    // mac3: commands with no effect on the ST
                ++f.mstep;
                continue;
            }
        }
        f.mstatus = 0;   // runaway macro
        modulations(f);
    }

    // ---- modulations
    void modulations(Synth& f)
    {
        if (f.modstatus & 0x80) { fader(f); return; }
        if (f.modstatus == 0) { f.modstatus = 1; fader(f); return; }
        vibratos(f);
    }

    void vibratos(Synth& f)
    {
        if (f.vibsize1)
        {
            f.vibperiod = static_cast<int16_t>(f.vibperiod + f.vibrate);
            uint16_t d0 = f.baseperiod;
            if (f.vibperiod != 0)
            {
                const uint32_t prod = uint32_t(f.baseperiod) * uint16_t(f.vibperiod + 2048);
                d0 = static_cast<uint16_t>((prod << 5) >> 16);
            }
            if (f.potime == 0) writePeriod(f, d0);
            if (--f.vibsize2 == 0)
            {
                f.vibsize2 = f.vibsize1;
                f.vibrate = static_cast<int8_t>(-f.vibrate);
            }
        }
        glides(f);
    }

    void glides(Synth& f)
    {
        if (f.potime != 0 && --f.pocount == 0)
        {
            f.pocount = f.pospeed;
            const uint16_t d1 = f.baseperiod;
            uint32_t d0 = f.poperiod;
            bool end = false;
            if (d0 == d1) end = true;
            else if (d0 < d1)
            {
                d0 = (d0 * uint16_t(f.potime + 256)) >> 8;
                if ((d0 & 0xffff) >= d1) end = true;
            }
            else
            {
                d0 = (d0 * uint16_t(256 - f.potime)) >> 8;
                if ((d0 & 0xffff) <= d1) end = true;
            }
            if (end)
            {
                f.potime = 0;
                d0 = f.baseperiod;
            }
            d0 &= 0x7ff;
            f.poperiod = static_cast<uint16_t>(d0);
            writePeriod(f, f.poperiod);
        }
        envelopes(f);
    }

    void envelopes(Synth& f)
    {
        if (f.envelope)
        {
            if (f.envcount) --f.envcount;
            else
            {
                f.envcount = f.envelope;
                const int8_t d0 = static_cast<int8_t>(f.envolume);
                if (d0 > static_cast<int8_t>(f.volume))
                {
                    f.volume = static_cast<uint8_t>(f.volume + f.envspeed);
                    if (d0 <= static_cast<int8_t>(f.volume)) { f.volume = f.envolume; f.envelope = 0; }
                }
                else
                {
                    f.volume = static_cast<uint8_t>(f.volume - f.envspeed);
                    if (static_cast<int8_t>(f.volume) < 0 || d0 >= static_cast<int8_t>(f.volume))
                    {
                        f.volume = f.envolume;
                        f.envelope = 0;
                    }
                }
            }
        }
        riffplay(f);
    }

    uint16_t riffDetune(const Synth& f, uint16_t d0) const
    {
        if (f.detunes != 0) d0 = static_cast<uint16_t>((uint32_t(d0) * uint16_t(f.detunes + 256)) >> 8);
        return d0;
    }

    void fchoose(Synth& f)
    {
        randomize();
        f.riffsteps = static_cast<uint16_t>((random & 0xff) & f.riffAND);
        fader(f);
    }

    // Ballblazer riff player; always ends with the fader.
    void riffplay(Synth& f)
    {
        if (f.riffstats == 0) { fader(f); return; }
        if (f.riffstats > 0)
        {
            f.riffadres = macroAddr(f.riffmacro & 0x7f);
            f.riffsteps = 0;
            f.riffstats = -1;
            if (f.riffrandm & 1) fchoose(f);
        }
        if (--f.riffcount != 0)
        {
            // askecho
            if ((f.riffrandm & 2) && static_cast<uint8_t>((f.riffspeed * 3) >> 3) == f.riffcount)
                f.volume = static_cast<uint8_t>((f.volume * 5) >> 3);
            fader(f);
            return;
        }
        f.riffcount = f.riffspeed;
        uint8_t note = 0;
        for (int guard = 0; guard < 2; ++guard)
        {
            note = rd8(f.riffadres + f.riffsteps);
            help[0] = note;
            if (note) break;
            if (f.riffsteps == 0) { fader(f); return; }
            f.riffsteps = 0;
        }
        if (!note) { fader(f); return; }
        const int n = (note + f.noteLo) & 0x3f;
        if (n == 0) { fchoose(f); return; }
        const uint16_t d0 = riffDetune(f, kNotTab[n]);
        if (!(f.riffrandm & 1))
        {
            f.baseperiod = d0;
            if (f.potime) { fader(f); return; }
            writePeriod(f, d0);
            if (help[0] & 0x80) f.rifftrigg = 0;
            ++f.riffsteps;
            fader(f);
            return;
        }
        // ballblazer
        randomize();
        bool play = (f.riffrandm & 4) || (f.riffsteps & 3) != 0 || 16 < (random & 0xff);
        if (play)
        {
            if (help[0] & 0x80) f.rifftrigg = 0;
            f.baseperiod = d0;
            if (f.potime == 0 && f.psg_peroffs != 0) writePeriod(f, d0);
        }
        ++f.riffsteps;
        if (!(help[0] & 0x40)) { fader(f); return; }
        randomize();
        if (6 >= (random >> 8)) { fader(f); return; }
        fchoose(f);
    }

    void fader(Synth& f)
    {
        if (fadeadd)
        {
            if (--fadecount1 == 0)
            {
                fadecount1 = fadecount2;
                fadevol = static_cast<uint8_t>(fadevol + fadeadd);
                if (fadeend == fadevol) { fadeadd = 0; infoFade = 0; }
            }
        }
        uint16_t d0 = f.volume;
        if (!(fadevol & 0x40))
        {
            d0 = static_cast<uint16_t>((d0 * 4 * fadevol) >> 8);
            if (f.psg_voloffs >= 0) f.psg_ebit = 0;
        }
        if (f.psg_voloffs < 0 || f.psg_samflag) return;
        d0 >>= 2;
        if (d0 & 0x10) d0 = 0x0f;
        ymw(f.psg_voloffs, static_cast<uint8_t>(d0 | f.psg_ebit));
    }

    // ---- digi samples: called once per output sample
    void digiStep(uint32_t sampleRate)
    {
        if (!digiOn || !ym || !smpl) return;
        if (digiPos >= smpl->size()) { digiOn = false; return; }
        const uint8_t b = (*smpl)[digiPos];
        const uint8_t v = smpl4bit ? (b & 0x0f) : static_cast<uint8_t>((b ^ 0x80) >> 4);
        ymw(digiReg, v);
        const uint32_t period = digiRate ? digiRate : 1;
        digiFrac += kAmigaClock / period;          // sample steps per second
        while (digiFrac >= sampleRate) { digiFrac -= sampleRate; ++digiPos; }
    }
};

// ------------------------------------------------------------------ tune

namespace {

// Song numbers (0..31) worth offering: valid step ranges, no duplicates.
std::vector<int> findSongs(const std::vector<uint8_t>& m)
{
    auto rd16 = [&](size_t o) -> int { return o + 1 < m.size() ? (m[o] << 8) | m[o + 1] : 0; };
    std::vector<int> songs;
    std::vector<std::pair<int, int>> seen;
    for (int n = 0; n < 32; ++n)
    {
        const int s1 = rd16(256 + n * 2), s2 = rd16(320 + n * 2);
        if (n > 0 && (s1 == 0x1ff || s2 == 0x1ff || s1 > s2 || (s1 == 0 && s2 == 0))) continue;
        if (s1 > 0x1ff || s2 > 0x1ff) continue;
        if (std::find(seen.begin(), seen.end(), std::make_pair(s1, s2)) != seen.end()) continue;
        seen.emplace_back(s1, s2);
        songs.push_back(n);
    }
    return songs;
}

} // namespace

std::unique_ptr<TfmxStTune> TfmxStTune::load(const uint8_t* data, size_t size,
                                             const uint8_t* smpl, size_t smplSize,
                                             const std::string& name, uint32_t sampleRate,
                                             int subtune, std::string& error)
{
    if (!data || size < 0x800 || size > 0x1000000 || std::memcmp(data, "TFMX-SONG ", 10) != 0)
    {
        error = "not a TFMX-ST file";
        return nullptr;
    }
    std::unique_ptr<TfmxStTune> t(new TfmxStTune());
    t->pristine_.assign(data, data + size);
    if (smpl && smplSize) t->smpl_.assign(smpl, smpl + smplSize);
    t->name_ = name;
    t->rate_ = sampleRate ? sampleRate : 44100;
    t->songs_ = findSongs(t->pristine_);
    if (t->songs_.empty()) { error = "TFMX-ST file has no songs"; return nullptr; }

    // Measure each song with a dry run (no sound chip).
    for (int n : t->songs_)
    {
        Replay r;
        r.m = t->pristine_;
        r.initdata();
        r.songset(n);
        int ticks = 0;
        while (!r.songEnd && r.allon && ticks < kMaxSongTicks) { r.irqin(); ++ticks; }
        t->lengths_.push_back(r.songEnd || !r.allon ? ticks * (1000 / kTickHz) : -1);
    }
    if (!t->start(subtune > 0 ? subtune : 1)) { error = "cannot start the song"; return nullptr; }
    return t;
}

TfmxStTune::~TfmxStTune() = default;

bool TfmxStTune::start(int subtune)
{
    if (subtune < 1 || subtune > subtunes()) return false;
    std::unique_ptr<Replay> h(new Replay());
    h->chip.reset(new Ym2149c());
    h->chip->Reset(rate_, 2000000, true);
    h->ym = h->chip.get();
    h->m = pristine_;
    h->smpl = &smpl_;
    // Samples come as one volume nibble per byte; anything with high nibbles
    // set is treated as 8-bit (the Wanted Team player makes the same check).
    h->smpl4bit = true;
    for (size_t i = 4; i < smpl_.size() && i < 8; ++i)
        if (smpl_[i] & 0xf0) h->smpl4bit = false;
    h->initdata();
    // All voices off, as alloff leaves them.
    h->ymw(7, 0xff);
    for (int reg = 8; reg <= 10; ++reg) h->ymw(reg, 0);
    h->songset(songs_[static_cast<size_t>(subtune - 1)]);
    r_ = std::move(h);
    current_ = subtune;
    framesPlayed_ = 0;
    tickAcc_ = 0;
    setMute(mute_);
    return true;
}

void TfmxStTune::setMute(uint32_t mask)
{
    mute_ = mask;
    if (r_ && r_->ym) r_->ym->MuteVoices(mask & 7u);
}

void TfmxStTune::seek(uint32_t ms)
{
    const uint64_t target = uint64_t(ms) * rate_ / 1000u;
    if (target < framesPlayed_) start(current_);
    // Run only the 50 Hz replay ticks; register writes still reach the YM,
    // which makes no sound meanwhile.
    Replay& r = *r_;
    while (framesPlayed_ < target)
    {
        const uint64_t step = std::min<uint64_t>(target - framesPlayed_, rate_);
        tickAcc_ += step * kTickHz;
        while (tickAcc_ >= rate_) { tickAcc_ -= rate_; r.irqin(); }
        framesPlayed_ += step;
    }
}

bool TfmxStTune::select(int subtune) { return start(subtune); }

void TfmxStTune::fillInfo(cd_info* out) const
{
    std::memset(out, 0, sizeof *out);
    out->system = CD_SYSTEM_ATARI_ST;
    copyStr(out->title, sizeof out->title, name_.c_str());
    copyStr(out->format, sizeof out->format, "TFMX-ST (Huelsbeck, Atari ST)");
    out->subtunes = subtunes();
    out->start_subtune = 1;
    out->current_subtune = current_;
    out->length_ms = lengths_.empty() ? -1 : lengths_[static_cast<size_t>(current_ - 1)];
}

const char* TfmxStTune::channelName(int ch) const
{
    static const char* const kNames[3] = { "A", "B", "C" };
    return ch >= 0 && ch < 3 ? kNames[ch] : "";
}

size_t TfmxStTune::render(int16_t* out, size_t frames, int16_t* chans)
{
    Replay& r = *r_;
    for (size_t i = 0; i < frames; ++i)
    {
        // Run the replay at 50 Hz, in step with the output.
        tickAcc_ += kTickHz;
        if (tickAcc_ >= rate_) { tickAcc_ -= rate_; r.irqin(); }
        r.digiStep(rate_);
        const int16_t v = r.ym->ComputeNextSample();
        out[i * 2] = v;
        out[i * 2 + 1] = v;
        if (chans)
        {
            const uint32_t vis = r.ym->ComputeCurrentVisualLevels();
            for (int k = 0; k < 3; ++k)
                chans[i * 3 + k] = static_cast<int16_t>(static_cast<int8_t>(vis >> (k * 8)) * 256);
        }
    }
    framesPlayed_ += frames;
    return frames;
}

uint32_t TfmxStTune::positionMs() const
{
    return rate_ ? static_cast<uint32_t>(framesPlayed_ * 1000u / rate_) : 0;
}

} // namespace chipdeck
