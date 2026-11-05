// Random play order: every tune of a list once, in a random order, with
// "previous" stepping back through the tunes already played.
// Copyright (C) 2026 ChipDeck contributors. GPL-2.0-or-later.
import 'dart:math';

class ShuffleOrder {
  ShuffleOrder([Random? random]) : _random = random ?? Random();

  final Random _random;
  Object? _list; // the list the order is for (compared by identity)
  int _length = -1;
  int? _expected; // index we last moved to
  List<int> _left = const []; // not played yet, next one at the end
  final List<int> _played = [];

  bool _matches(Object list, int length, int? at) =>
      identical(list, _list) && length == _length && at == _expected;

  /// A fresh order for [list]: every index except [at] (the tune playing
  /// now, if any), shuffled. Called when the list, its length or the tune
  /// picked by the user changes.
  void _start(Object list, int length, int? at) {
    _list = list;
    _length = length;
    _expected = at;
    _played.clear();
    _left = [
      for (var i = 0; i < length; i++)
        if (i != at) i,
    ]..shuffle(_random);
  }

  /// The index to play after [at] in [list] (of [length] tunes), or null
  /// when every tune has been played.
  int? next(Object list, int length, int? at) {
    if (!_matches(list, length, at)) _start(list, length, at);
    if (_left.isEmpty) return null;
    if (at != null) _played.add(at);
    final n = _left.removeLast();
    _expected = n;
    return n;
  }

  /// The tune played before [at], or null when there is none (or the list
  /// changed since).
  int? previous(Object list, int length, int? at) {
    if (!_matches(list, length, at) || _played.isEmpty) return null;
    final p = _played.removeLast();
    if (at != null) _left.add(at);
    _expected = p;
    return p;
  }

  /// Forgets the order (shuffle turned off or on again).
  void reset() => _list = null;
}
