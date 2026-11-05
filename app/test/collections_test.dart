// Copyright (C) 2026 ChipDeck contributors. GPL-2.0-or-later.
import 'dart:io';

import 'package:chipdeck/player/collections.dart';
import 'package:chipdeck/player/player_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Collections', () {
    test('favourites toggle, keep order and skip duplicates', () {
      final c = Collections();
      expect(c.toggleFavourite('/a.sid'), isTrue);
      expect(c.toggleFavourite('/b.sid'), isTrue);
      expect(c.addTo(favouritesId, ['/a.sid', '/c.sid']), 1);
      expect(c.favourites, ['/a.sid', '/b.sid', '/c.sid']);
      expect(c.toggleFavourite('/a.sid'), isFalse);
      expect(c.isFavourite('/a.sid'), isFalse);
      expect(c.favourites, ['/b.sid', '/c.sid']);
    });

    test('playlists: create, add, move, remove, rename, delete', () {
      final c = Collections();
      final pl = c.create('Hubbard', paths: ['/1', '/2', '/2']);
      expect(pl.paths, ['/1', '/2']);
      expect(c.addTo(pl.id, ['/2', '/3']), 1);
      expect(c.move(pl.id, 0, 2), isTrue);
      expect(pl.paths, ['/2', '/3', '/1']);
      expect(c.move(pl.id, 2, 0), isTrue);
      expect(pl.paths, ['/1', '/2', '/3']);
      expect(c.removeAt(pl.id, 1), isTrue);
      expect(pl.paths, ['/1', '/3']);
      expect(c.rename(pl.id, '  Rob  '), isTrue);
      expect(pl.name, 'Rob');
      expect(c.rename(pl.id, ' '), isFalse);
      expect(c.delete(pl.id), isTrue);
      expect(c.byId(pl.id), isNull);
    });

    test('unique names', () {
      final c = Collections();
      c.create('Mix');
      c.create('mix 2');
      expect(c.uniqueName('Mix'), 'Mix 3');
      expect(c.uniqueName('Other'), 'Other');
      expect(c.create('').name, 'New playlist');
    });

    test('round trip through preferences, ignoring junk', () {
      final c = Collections();
      c.toggleFavourite('/f.ym');
      c.create('A', paths: ['/x.mod']);
      final d = Collections()
        ..load(
          favourites: c.favouritesToPrefs(),
          playlists: c.playlistsToPrefs(),
        );
      expect(d.favourites, ['/f.ym']);
      expect(d.isFavourite('/f.ym'), isTrue);
      expect(d.playlists.single.name, 'A');
      expect(d.playlists.single.paths, ['/x.mod']);
      final e = Collections()..load(playlists: 'not json');
      expect(e.playlists, isEmpty);
      final g = Collections()..load(playlists: '[1, {"id": "x"}]');
      expect(g.playlists, isEmpty);
    });
  });

  group('PlayerController lists', () {
    late Directory dir;
    late List<String> tunes;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('chipdeck_lists');
      tunes = [
        for (final n in ['one', 'two', 'three'])
          (File('${dir.path}/$n.sid')..writeAsStringSync('x')).path,
      ];
    });
    tearDown(() => dir.deleteSync(recursive: true));

    Future<PlayerController> make([Map<String, Object> prefs = const {}]) {
      SharedPreferences.setMockInitialValues(prefs);
      return PlayerController.create();
    }

    test(
      'adding to favourites and playlists leaves the playlist alone',
      () async {
        final c = await make();
        c.toggleFavourite(tunes[0]);
        final id = c.createPlaylist('Mine', [(tunes[1], null)]);
        c.addToList(id, [(tunes[2], null)]);
        expect(c.playlist, isEmpty);
        expect(c.collections.favourites, [tunes[0]]);
        expect(c.collections.byId(id)!.paths, [tunes[1], tunes[2]]);
        expect(c.listName(id), 'Mine');
        expect(c.listName(favouritesId), 'Favourites');
      },
    );

    test('collections survive a restart', () async {
      final c = await make();
      c.toggleFavourite(tunes[0]);
      final id = c.createPlaylist('Mine', [(tunes[1], null)]);
      c.showList(id);
      final prefs = await SharedPreferences.getInstance();
      final saved = {for (final k in prefs.getKeys()) k: prefs.get(k)!};
      final d = await make(saved);
      expect(d.collections.favourites, [tunes[0]]);
      expect(d.collections.byId(id)!.paths, [tunes[1]]);
      expect(d.shownList, id);
    });

    test(
      'deleting the shown playlist goes back to the main playlist',
      () async {
        final c = await make();
        final id = c.createPlaylist('Gone');
        c.showList(id);
        c.deletePlaylist(id);
        expect(c.shownList, mainListId);
        expect(c.collections.playlists, isEmpty);
      },
    );

    test('save the playlist as a named playlist', () async {
      final c = await make();
      c.addFiles(tunes);
      final id = c.savePlaylistAs('Copy');
      expect(c.collections.byId(id)!.paths, tunes);
      c.clearPlaylist();
      expect(c.addListToPlaylist(id), 3);
      expect(c.playlist.map((e) => e.path), tunes);
    });
  });
}
