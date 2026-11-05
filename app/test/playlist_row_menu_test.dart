// Copyright (C) 2026 ChipDeck contributors. GPL-2.0-or-later.
// 0.11.0-test.102: in a playlist, a tune's "add to another playlist" did
// nothing on Windows, because the row menu disappeared with the hover.
import 'dart:io';

import 'package:chipdeck/player/player_controller.dart';
import 'package:chipdeck/ui/playlist_panel.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('add a tune to another playlist from its row menu', (t) async {
    final dir = Directory.systemTemp.createTempSync('chipdeck_row');
    addTearDown(() => dir.deleteSync(recursive: true));
    final tune = (File('${dir.path}/tune.sid')..writeAsStringSync('x')).path;
    SharedPreferences.setMockInitialValues({});
    late PlayerController c;
    await t.runAsync(() async => c = await PlayerController.create());
    final from = c.createPlaylist('From', [(tune, null)]);
    final to = c.createPlaylist('To');
    c.showList(from);

    t.view.physicalSize = const Size(1200, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaylistPanel(
            controller: c,
            onAddFiles: () {},
            onAddFolder: () {},
          ),
        ),
      ),
    );
    await t.pump();

    // Hover the row so its tools show, open the menu, then move the mouse
    // off the row (onto the menu) as a real pointer does.
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: t.getCenter(find.text('tune')));
    await t.pump();
    await t.tap(find.byTooltip('More'));
    await t.pumpAndSettle();
    await mouse.moveTo(const Offset(5, 880));
    await t.pumpAndSettle();
    await t.tap(find.text('To').last);
    await t.pumpAndSettle();

    expect(c.collections.byId(to)!.paths, [tune]);
  });
}
