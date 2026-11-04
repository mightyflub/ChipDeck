// File and folder pickers that work the same on Windows, Linux and Android.
// Copyright (C) 2026 ChipDeck contributors. GPL-2.0-or-later.
//
// The core and the library index work on plain file paths. On desktop the
// file_selector plugin gives us those directly. On Android the system picker
// (Storage Access Framework) returns content:// URIs, so MainActivity.kt turns
// them back into paths under /storage/... (which ChipDeck can read once the
// user grants "All files access"); files from providers without a path
// (Google Drive, some download providers) are copied into the app's storage.
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../player/player_controller.dart' show supportedExtensions;

const _channel = MethodChannel('chipdeck/android');

/// Asks for storage access on Android when it is missing. Returns true when
/// ChipDeck can read the user's folders (always true on desktop).
Future<bool> ensureStorageAccess(BuildContext context) async {
  if (!Platform.isAndroid) return true;
  if (await hasStorageAccess()) return true;
  if (!context.mounted) return false;
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Allow access to your music'),
      content: const Text(
        'ChipDeck plays tunes straight from your folders and indexes whole '
        'archives like HVSC and the SNDH collection. Android calls the '
        'permission for this "All files access". ChipDeck only reads files; '
        'it never changes or uploads them.\n\n'
        'On the next screen, switch on "Allow access to manage all files".',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Continue'),
        ),
      ],
    ),
  );
  if (go != true) return false;
  return await _channel.invokeMethod<bool>('requestStorageAccess') ?? false;
}

Future<bool> hasStorageAccess() async {
  if (!Platform.isAndroid) return true;
  return await _channel.invokeMethod<bool>('hasStorageAccess') ?? false;
}

/// Lets the user choose tune files. Returns their paths.
Future<List<String>> pickTuneFiles(BuildContext context) async {
  if (Platform.isAndroid) {
    if (!await ensureStorageAccess(context)) return const [];
    final paths = await _channel.invokeListMethod<String>('pickFiles', {
      'multiple': true,
    });
    // The Android picker cannot filter by extension, so filter here.
    return [
      for (final f in paths ?? const <String>[])
        if (supportedExtensions.contains(_ext(f))) f,
    ];
  }
  const group = XTypeGroup(
    label: 'Chiptunes',
    extensions: ['sid', 'psid', 'rsid', 'mus', 'prg', 'sndh', 'snd', 'ym'],
  );
  final files = await openFiles(acceptedTypeGroups: [group]);
  return [for (final f in files) f.path];
}

/// Lets the user choose one file (e.g. Songlengths.md5).
Future<String?> pickSingleFile(
  BuildContext context, {
  required String label,
  required List<String> extensions,
}) async {
  if (Platform.isAndroid) {
    if (!await ensureStorageAccess(context)) return null;
    final paths = await _channel.invokeListMethod<String>('pickFiles', {
      'multiple': false,
    });
    return (paths == null || paths.isEmpty) ? null : paths.first;
  }
  final f = await openFile(
    acceptedTypeGroups: [XTypeGroup(label: label, extensions: extensions)],
  );
  return f?.path;
}

/// Lets the user choose a folder. Returns its path.
Future<String?> pickFolder(
  BuildContext context, {
  String? confirmButtonText,
}) async {
  if (Platform.isAndroid) {
    if (!await ensureStorageAccess(context)) return null;
    try {
      return await _channel.invokeMethod<String>('pickFolder');
    } on PlatformException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.message ??
                  'That folder cannot be used. Pick one on the phone '
                      'storage or SD card.',
            ),
          ),
        );
      }
      return null;
    }
  }
  return getDirectoryPath(confirmButtonText: confirmButtonText);
}

String _ext(String path) {
  final dot = path.lastIndexOf('.');
  return dot < 0 ? '' : path.substring(dot).toLowerCase();
}
