// TEMPORARY: switches read from environment variables to find what makes
// 0.9.0-test.79 crash on Windows. Remove once found.
import 'dart:io';

bool _on(String k) => Platform.environment[k] == '1';
final dbgNo3Col = _on('CD_NO3COL');
final dbgNoFilterButton = _on('CD_NOFILTER');
final dbgNoDesktopNowPlaying = _on('CD_NODESKTOP');
final dbgNoRescan = _on('CD_NORESCAN');
final dbgNoSemantics = _on('CD_NOSEMANTICS');
final dbgX1 = _on('CD_X1');
final dbgX2 = _on('CD_X2');
final dbgX3 = _on('CD_X3');
final dbgX4 = _on('CD_X4');
