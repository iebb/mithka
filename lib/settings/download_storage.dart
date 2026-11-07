import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Database paths stay private. Only TDLib media and explicitly retained
/// downloads move, before any client opens its file database.
class DownloadStorage {
  static const channel = MethodChannel('mithka/download_storage');
  static const activeKey = 'downloads.activeRoot.v1';
  static const selectedKey = 'downloads.selectedRoot.v1';
  static const cleanupKey = 'downloads.cleanup.v1';
  static String? currentRoot;
  static bool migrationFailed = false;

  static String filesDirectory(String root, int slot) =>
      slot == 0 ? '$root/tdlib/files' : '$root/tdlib/account-$slot/files';

  static Future<List<String>> locations() async {
    final internal = await getApplicationSupportDirectory();
    final external = await getExternalStorageDirectories() ?? [];
    return [
      for (final directory in external) '${directory.path}/mithka-downloads-v1',
      '${internal.path}/downloads-v1',
    ];
  }

  static Future<void> select(String root) async {
    if (!(await locations()).contains(root)) {
      throw ArgumentError('Not an app-specific storage directory');
    }
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(selectedKey, root)) {
      throw StateError('Could not save the download location');
    }
  }

  static Future<String> retainedRoot() async {
    final support = await getApplicationSupportDirectory();
    return Platform.isAndroid
        ? currentRoot ??
              (await SharedPreferences.getInstance()).getString(activeKey) ??
              support.path
        : support.path;
  }

  static Future<String> prepare({
    required Directory support,
    required SharedPreferences prefs,
    required List<String> availableRoots,
    Future<void> Function(String source, String destination)? copyDirectory,
  }) async {
    final previous = prefs.getString(activeKey) ?? support.path;
    final requested =
        prefs.getString(selectedKey) ?? availableRoots.firstOrNull ?? previous;
    migrationFailed = false;
    await _finishCleanup(prefs);
    // An unavailable volume must not make TDLib forget its existing files.
    if (!await Directory(previous).exists()) {
      throw FileSystemException('Download storage is unavailable', previous);
    }
    if (requested == previous) return currentRoot = previous;
    if (!availableRoots.contains(requested)) {
      migrationFailed = true;
      return currentRoot = previous;
    }
    final sources = <String>[];
    try {
      final destination = await Directory(requested).create(recursive: true);
      final probe = File('${destination.path}/.write-probe');
      await probe.writeAsBytes([1], flush: true);
      await probe.delete();
      final slots = <int>{0};
      final tdlib = Directory('$previous/tdlib');
      if (await tdlib.exists()) {
        await for (final entry in tdlib.list(followLinks: false)) {
          if (entry is! Directory) continue;
          final name = entry.uri.pathSegments.where((p) => p.isNotEmpty).last;
          final match = RegExp(r'^account-(\d+)$').firstMatch(name);
          if (match != null) slots.add(int.parse(match.group(1)!));
        }
      }
      final botSlots = <int>{};
      final bots = Directory('$previous/bot-api');
      if (await bots.exists()) {
        await for (final entry in bots.list(followLinks: false)) {
          if (entry is! Directory) continue;
          final name = entry.uri.pathSegments.where((p) => p.isNotEmpty).last;
          final match = RegExp(r'^account-(\d+)$').firstMatch(name);
          if (match != null) botSlots.add(int.parse(match.group(1)!));
        }
      }
      final copy = copyDirectory ?? _copyDirectory;
      for (final relative in [
        for (final slot in slots)
          slot == 0 ? 'tdlib/files' : 'tdlib/account-$slot/files',
        for (final slot in botSlots) 'bot-api/account-$slot/files',
        'retained-downloads-v1',
      ]) {
        final source = '$previous/$relative';
        if (!await Directory(source).exists()) continue;
        await copy(source, '$requested/$relative');
        sources.add(source);
      }
      // Commit the root only after every copy succeeded. The cleanup journal
      // also covers process death between committing and removing old bytes.
      if (!await prefs.setString(
        cleanupKey,
        jsonEncode({'target': requested, 'sources': sources}),
      )) {
        throw StateError('Could not journal the migration');
      }
      if (!await prefs.setString(activeKey, requested)) {
        throw StateError('Could not commit the migration');
      }
    } catch (_) {
      migrationFailed = true;
      return currentRoot = previous;
    }
    currentRoot = requested;
    await _finishCleanup(prefs);
    return requested;
  }

  static Future<void> _copyDirectory(String source, String destination) async {
    await channel.invokeMethod<void>('copyDirectory', {
      'source': source,
      'destination': destination,
    });
  }

  static Future<void> _finishCleanup(SharedPreferences prefs) async {
    final journal = prefs.getString(cleanupKey);
    if (journal == null) return;
    final data = jsonDecode(journal) as Map<String, dynamic>;
    if (data['target'] != prefs.getString(activeKey)) return;
    try {
      for (final source in (data['sources'] as List).cast<String>()) {
        final directory = Directory(source);
        if (await directory.exists()) await directory.delete(recursive: true);
      }
      await prefs.remove(cleanupKey);
    } on FileSystemException {
      // Retry at next startup; the committed destination owns all the bytes.
    }
  }

  static Future<String?> pickSaveFolder() =>
      channel.invokeMethod<String>('pickSaveFolder');

  static Future<String?> saveFolder() =>
      channel.invokeMethod<String>('saveFolder');

  static Future<void> resetSaveFolder() =>
      channel.invokeMethod<void>('resetSaveFolder');

  static Future<String?> exportFile(
    String source, {
    required String name,
    required String mimeType,
  }) => channel.invokeMethod<String>('exportFile', {
    'source': source,
    'name': name,
    'mimeType': mimeType,
  });
}
