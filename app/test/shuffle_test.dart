// Copyright (C) 2026 ChipDeck contributors. GPL-2.0-or-later.
import 'dart:math';

import 'package:chipdeck/player/shuffle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('plays every tune once, then stops', () {
    final o = ShuffleOrder(Random(1));
    final list = Object();
    final seen = <int>[3];
    int? at = 3;
    while (true) {
      final n = o.next(list, 10, at);
      if (n == null) break;
      seen.add(n);
      at = n;
    }
    expect(seen.toSet().length, 10);
    expect(seen.length, 10);
  });

  test('previous walks back through what was played', () {
    final o = ShuffleOrder(Random(2));
    final list = Object();
    final a = o.next(list, 5, 0)!;
    final b = o.next(list, 5, a)!;
    expect(o.previous(list, 5, b), a);
    expect(o.previous(list, 5, a), 0);
    expect(o.previous(list, 5, 0), isNull);
    // b goes back into the tunes still to play.
    final rest = <int>{};
    int? at = 0;
    for (int? n; (n = o.next(list, 5, at)) != null; at = n) {
      rest.add(n!);
    }
    expect(rest, {1, 2, 3, 4});
  });

  test('a new list or a tune picked by hand starts a fresh order', () {
    final o = ShuffleOrder(Random(3));
    final list = Object();
    final n0 = o.next(list, 4, 0)!;
    final jump = n0 == 1 ? 2 : 1; // the user picks another tune
    expect(o.previous(list, 4, jump), isNull);
    final other = Object();
    final n = o.next(other, 3, null)!;
    expect(n, inInclusiveRange(0, 2));
  });
}
