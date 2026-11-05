// Library refresh: skipping and reporting files and folders it cannot read.
// Needs the native library: build it (cmake --build build --target
// chipdeck-shared) and run with LD_LIBRARY_PATH=../build. Skipped otherwise.
@TestOn('linux')
library;

import 'dart:ffi';
import 'dart:io';

import 'package:chipdeck/library/library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  var haveNative = true;
  try {
    DynamicLibrary.open('libchipdeck.so');
  } catch (_) {
    haveNative = false;
  }

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('chipdeck-scan'));
  tearDown(() => tmp.deleteSync(recursive: true));

  void copyTestTunes(String to) {
    Directory(to).createSync(recursive: true);
    for (final f in Directory('../tests/data').listSync()) {
      if (f is File) f.copySync(p.join(to, p.basename(f.path)));
    }
  }

  test(
    'skips bad and hanging files, reports them, keeps going',
    () async {
      probeTimeout = const Duration(seconds: 3);
      final root = p.join(tmp.path, 'Music');
      copyTestTunes(p.join(root, 'a'));
      copyTestTunes(p.join(root, 'z'));
      File(p.join(root, 'a', 'garbage.mod')).writeAsStringSync('not a module');
      File(p.join(root, 'a', 'empty.sid')).writeAsBytesSync([]);
      // A named pipe blocks the native reader forever: a stand-in for a file
      // that hangs the tune-info code.
      final fifo = p.join(root, 'a', 'hang.xm');
      expect(Process.runSync('mkfifo', [fifo]).exitCode, 0);

      final lib = LibraryController.forIndex(
        File(p.join(tmp.path, 'library.json')),
      );
      await lib.addRoot(root);

      // Both copies of the 7 test tunes, including the folder after the hang.
      expect(lib.tracks.length, 14);
      final byName = {for (final i in lib.scanIssues) p.basename(i.path): i};
      expect(byName['hang.xm']?.kind, ScanIssueKind.timedOut);
      expect(byName['garbage.mod']?.kind, ScanIssueKind.notATune);
      expect(byName['empty.sid']?.kind, ScanIssueKind.notATune);
      expect(lib.message, contains('14 tunes'));
      expect(lib.message, contains('3 files or folders were skipped'));
      expect(lib.messageHasIssues, isTrue);

      // A second refresh does not wait on the hung file again.
      final sw = Stopwatch()..start();
      await lib.rescan();
      expect(sw.elapsed, lessThan(const Duration(seconds: 3)));
      expect(lib.tracks.length, 14);
      expect(
        lib.scanIssues.where((i) => i.kind == ScanIssueKind.timedOut).length,
        1,
      );

      // The report survives a restart.
      final again = LibraryController.forIndex(
        File(p.join(tmp.path, 'library.json')),
      );
      await again.reload();
      expect(again.scanIssues.length, 3);
    },
    skip: haveNative ? false : 'libchipdeck.so not found',
    timeout: const Timeout(Duration(minutes: 1)),
  );

  test('a missing location keeps its tunes', () async {
    final root = p.join(tmp.path, 'Gone');
    copyTestTunes(root);
    final lib = LibraryController.forIndex(
      File(p.join(tmp.path, 'library.json')),
    );
    await lib.addRoot(root);
    expect(lib.tracks.length, 7);
    Directory(root).renameSync(p.join(tmp.path, 'Moved'));
    await lib.rescan();
    expect(lib.tracks.length, 7);
    expect(lib.message, contains('Could not open'));
  }, skip: haveNative ? false : 'libchipdeck.so not found');

  test('a location added during a refresh is refreshed after it', () async {
    final a = p.join(tmp.path, 'A');
    final b = p.join(tmp.path, 'B');
    copyTestTunes(a);
    copyTestTunes(b);
    final lib = LibraryController.forIndex(
      File(p.join(tmp.path, 'library.json')),
    );
    final first = lib.addRoot(a);
    expect(lib.isScanning, isTrue);
    await lib.addRoot(b); // returns at once: queued
    expect(lib.queuedRoots, [b]);
    await first; // runs A, then the queued B
    expect(lib.isScanning, isFalse);
    expect(lib.queuedRoots, isEmpty);
    expect(lib.folder(a)?.totalTracks, 7);
    expect(lib.folder(b)?.totalTracks, 7);
    expect(lib.rootScans.keys, containsAll([a, b]));
  }, skip: haveNative ? false : 'libchipdeck.so not found');
}
