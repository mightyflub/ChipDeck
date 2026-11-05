// Copyright (C) 2026 ChipDeck contributors. GPL-2.0-or-later.
import 'package:chipdeck/library/library.dart';
import 'package:chipdeck/native/chipdeck_ffi.dart';
import 'package:flutter_test/flutter_test.dart';

LibraryTrack track(TuneSystem system, String format, String path) =>
    LibraryTrack(
      path: path,
      title: 't',
      author: 'a',
      released: '',
      format: format,
      subtunes: 1,
      lengthMs: -1,
      size: 1,
      mtime: 0,
      sidChips: system == TuneSystem.c64 ? 1 : 0,
      system: system,
    );

void main() {
  final sid = track(TuneSystem.c64, 'PSID v2', '/x/a.sid');
  final sndh = track(TuneSystem.atariSt, 'SNDH', '/x/a.sndh');
  final tfmxSt = track(TuneSystem.atariSt, 'TFMX-ST', '/x/mdat.a');
  final tfmx = track(TuneSystem.amiga, 'TFMX Pro (AMIGA)', '/x/mdat.b');
  final xm = track(TuneSystem.pc, 'Fasttracker II XM', '/x/a.xm');

  test('empty filter accepts everything', () {
    for (final t in [sid, sndh, tfmxSt, tfmx, xm]) {
      expect(FormatFilter.all.accepts(t), isTrue);
    }
  });

  test('TFMX on the ST and on the Amiga are separate formats', () {
    final f = FormatFilter.all.toggle(tfmx.formatKey);
    expect(f.accepts(tfmx), isTrue);
    expect(f.accepts(tfmxSt), isFalse);
  });

  test('system toggle selects all its formats, tristate summary', () {
    var f = FormatFilter.all.toggleSystem(TuneSystem.atariSt);
    expect(f.hasSystem(TuneSystem.atariSt), isTrue);
    expect(f.accepts(sndh) && f.accepts(tfmxSt), isTrue);
    expect(f.accepts(sid), isFalse);
    expect(f.summary, 'Atari ST');
    f = f.toggle(xm.formatKey);
    expect(f.summary, 'Atari ST, XM');
    f = f.toggleSystem(TuneSystem.atariSt);
    expect(f.summary, 'XM');
  });

  test('every format selected is the same as no filter', () {
    var f = FormatFilter.all;
    for (final g in formatGroups) {
      f = f.toggleSystem(g.$1);
    }
    expect(f.isAll, isTrue);
  });

  test('saved filter round-trips', () {
    final f = FormatFilter.all.toggle(sid.formatKey).toggle(xm.formatKey);
    expect(FormatFilter.fromJson(f.toJson()), f);
  });
}
