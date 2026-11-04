// Tests for the HVSC STIL/BUGlist reader.
import 'dart:io';

import 'package:chipdeck/hvsc/stil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _stil = '''
### STIL - SID Tune Information List ###
# Sample written for ChipDeck tests.

### Example_Composer ##################################
/MUSICIANS/E/Example_Composer/
COMMENT: Example Composer wrote music for many games between 1985 and
         1989, mostly for a small UK publisher.

/MUSICIANS/E/Example_Composer/Single.sid
COMMENT: A one-subtune file with a comment that wraps onto a second
         line.

/MUSICIANS/E/Example_Composer/Multi.sid
COMMENT: Shared comment for every subtune.
(#1)
   TITLE: Original Song (0:00-0:45)
  ARTIST: Some Band
 COMMENT: Cover of a pop song.
   TITLE: Another Song (0:45)
  ARTIST: Other Band
(#3)
  AUTHOR: Guest Musician
 COMMENT: Lyrics follow:
            First line
            Second line
''';

const _bugs = '''
### BUGlist ###
/MUSICIANS/E/Example_Composer/Multi.sid
(#3)
     BUG: Plays too fast on emulators without a cycle exact CIA.
''';

void main() {
  late Directory tmp;
  late StilDatabase db;
  late String root;

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('stil');
    root = p.join(tmp.path, 'C64Music');
    Directory(p.join(root, 'DOCUMENTS')).createSync(recursive: true);
    File(p.join(root, 'DOCUMENTS', 'STIL.txt')).writeAsStringSync(_stil);
    File(p.join(root, 'DOCUMENTS', 'BUGlist.txt')).writeAsStringSync(_bugs);
    db = StilDatabase.loadSync(StilDatabase.find(tmp.path)!)!;
  });

  tearDownAll(() => tmp.deleteSync(recursive: true));

  String tune(String name) =>
      p.join(root, 'MUSICIANS', 'E', 'Example_Composer', name);

  test('finds STIL.txt and the HVSC root', () {
    expect(p.equals(db.root, root), isTrue);
    expect(db.entryCount, 3);
    expect(StilDatabase.find(root), isNotNull);
  });

  test('single-subtune entry with folder comment', () {
    final s = db.lookup(tune('Single.sid'));
    expect(s.tune!.global.single.key, 'COMMENT');
    expect(
      s.tune!.global.single.value,
      'A one-subtune file with a comment that wraps onto a second line.',
    );
    expect(s.folders.single.path, '/MUSICIANS/E/Example_Composer/');
    expect(
      s.folders.single.global.single.value,
      startsWith('Example Composer'),
    );
    expect(s.bugs, isNull);
  });

  test('per-subtune fields, covers and bugs', () {
    final s = db.lookup(tune('Multi.sid'));
    final e = s.tune!;
    expect(e.global.single.value, 'Shared comment for every subtune.');
    expect(e.subtunes, [1, 3]);
    expect(e.subtune(1).map((f) => f.key).toList(), [
      'TITLE',
      'ARTIST',
      'COMMENT',
      'TITLE',
      'ARTIST',
    ]);
    expect(s.titleFor(1), 'Original Song (0:00-0:45)');
    expect(s.titleFor(2), isNull);
    expect(
      e.subtune(3).last.value,
      'Lyrics follow:\n   First line\n   Second line',
    );
    expect(s.bugs!.subtune(3).single.key, 'BUG');
  });

  test('case-insensitive and outside the root', () {
    final other = p.join(
      tmp.path,
      'copy',
      'musicians',
      'e',
      'example_composer',
      'single.sid',
    );
    expect(db.hvscPath(other), '/musicians/e/example_composer/single.sid');
    expect(db.lookup(other).tune, isNotNull);
    expect(db.lookup(p.join(tmp.path, 'x.sid')).isEmpty, isTrue);
  });
}
