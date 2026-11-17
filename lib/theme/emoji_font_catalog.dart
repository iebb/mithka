//
//  emoji_font_catalog.dart
//
//  Runtime emoji font catalog backed by iebb/emojifonts' release manifest.
//  Font binaries are downloaded on demand and loaded with Flutter's FontLoader.
//

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:mithka/l10n/app_localizations.dart';
import 'package:path_provider/path_provider.dart';

class EmojiFontChoice {
  const EmojiFontChoice({
    required this.key,
    required this.label,
    this.license,
    this.fontFamily,
  });

  static const system = EmojiFontChoice(
    key: 'system',
    label: AppStringKeys.emojiFontCatalogSystemDefault,
  );

  /// The runtime family the Apple Color Emoji font registers under. Same
  /// deterministic namespace the downloaded catalog fonts use, so every
  /// consumer (theme chains, previews) treats it like any loaded pack.
  static const bundledAppleFamily = 'MithkaEmoji_apple';

  final String key;
  final String label;
  final String? license;
  final String? fontFamily;

  bool get isSystem => key == system.key;

  List<String> get fontFamilies {
    final family = fontFamily;
    if (family == null || family.isEmpty) return platformEmojiFontFallback();
    return _dedupeFontFamilies([family, ...platformEmojiFontFallback()]);
  }

  static List<String> platformEmojiFontFallback() {
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => const ['Apple Color Emoji'],
      TargetPlatform.android => const ['Noto Color Emoji'],
      _ => const ['Noto Color Emoji', 'Apple Color Emoji'],
    };
  }

  static String runtimeFamilyForKey(String key) {
    final sanitized = key.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
    return 'MithkaEmoji_$sanitized';
  }
}

List<String> _dedupeFontFamilies(Iterable<String> values) {
  final seen = <String>{};
  return [
    for (final value in values)
      if (value.trim().isNotEmpty && seen.add(value.trim())) value.trim(),
  ];
}

class EmojiFontManifestEntry {
  const EmojiFontManifestEntry({
    required this.key,
    required this.label,
    required this.license,
    required this.kind,
    required this.url,
    required this.format,
    required this.coveragePct,
    required this.emojiVersion,
    required this.updated,
  });

  final String key;
  final String label;
  final String license;
  final String kind;
  final String url;
  final String format;
  final int coveragePct;
  final String emojiVersion;
  final String updated;

  String get runtimeFamily => EmojiFontChoice.runtimeFamilyForKey(key);

  String get extension {
    final path = Uri.tryParse(url)?.path ?? '';
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    return dot < 0 ? 'ttf' : name.substring(dot + 1);
  }

  factory EmojiFontManifestEntry.fromJson(Map<String, dynamic> json) {
    final formats = (json['formats'] as Map?)?.cast<String, dynamic>() ?? {};
    final selected = _selectFormat(formats);
    if (selected == null) {
      throw const FormatException('emoji font has no supported format');
    }
    final MapEntry(:key, :value) = selected;
    return EmojiFontManifestEntry(
      key: (json['key'] as String?)?.trim() ?? '',
      label: (json['label'] as String?)?.trim() ?? '',
      license: (json['license'] as String?)?.trim() ?? '',
      kind: (json['kind'] as String?)?.trim() ?? '',
      url: value.toString(),
      format: key,
      coveragePct: (json['coverage_pct'] as num?)?.round() ?? 0,
      emojiVersion: (json['emoji_version'] as String?)?.trim() ?? '',
      updated: (json['updated'] as String?)?.trim() ?? '',
    );
  }

  static MapEntry<String, dynamic>? _selectFormat(
    Map<String, dynamic> formats,
  ) {
    const preferredFormats = ['sbix', 'glyf', 'colrv0', 'svginot'];
    for (final format in preferredFormats) {
      final url = formats[format];
      if (url is String && url.startsWith('https://')) {
        return MapEntry(format, url);
      }
    }
    return null;
  }
}

class EmojiFontCatalog {
  EmojiFontCatalog._();

  @visibleForTesting
  EmojiFontCatalog.forTesting();

  static final shared = EmojiFontCatalog._();

  /// Bump whenever release font binaries change without changing their keys.
  /// A new namespace prevents old glyph data from being loaded and forces the
  /// selected font to be downloaded again.
  static const cacheRevision = 2;
  static const cacheDirectoryName = 'emoji_fonts_v$cacheRevision';

  static const manifestUrl =
      'https://github.com/iebb/emojifonts/releases/download/latest/manifest.json';

  final Set<String> _loadedFamilies = {};
  final Map<String, Future<String>> _inFlightFontLoads = {};

  /// Returns the deterministic runtime family once this process has registered
  /// it with Flutter. New ThemeController instances can therefore retain the
  /// selected emoji face synchronously instead of flashing the platform face
  /// until another asynchronous cache read completes.
  String? loadedFamilyForKey(String key) {
    if (key == EmojiFontChoice.system.key) return null;
    final family = EmojiFontChoice.runtimeFamilyForKey(key);
    return _loadedFamilies.contains(family) ? family : null;
  }

  Future<List<EmojiFontManifestEntry>> loadManifest({
    bool forceRefresh = false,
  }) async {
    final cacheFile = await _manifestCacheFile();
    if (!forceRefresh && await cacheFile.exists()) {
      final cached = await _readManifest(cacheFile);
      if (cached.isNotEmpty) return cached;
    }

    try {
      final response = await http.get(Uri.parse(manifestUrl));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'HTTP ${response.statusCode}',
          uri: response.request?.url,
        );
      }
      await cacheFile.parent.create(recursive: true);
      await cacheFile.writeAsBytes(response.bodyBytes, flush: true);
      return _parseManifest(utf8.decode(response.bodyBytes));
    } catch (_) {
      if (await cacheFile.exists()) return _readManifest(cacheFile);
      rethrow;
    }
  }

  Future<String?> loadCached(String key) async {
    if (key == EmojiFontChoice.system.key) return null;
    // The pinned Apple font has its own loader (cache first, optional
    // download) — it shares the cache directory with the catalog packs.
    if (key == EmojiFontCatalog.appleEntry.key) {
      return loadAppleFont();
    }
    final file = await _cachedFontFileForKey(key);
    if (file == null) return null;
    final family = EmojiFontChoice.runtimeFamilyForKey(key);
    await _loadFontFile(family, file);
    return family;
  }

  Future<String?> loadCachedOrDownload(String key) async {
    final cached = await loadCached(key);
    if (cached != null) return cached;
    if (key == EmojiFontCatalog.appleEntry.key) {
      return loadAppleFont(download: true);
    }
    try {
      final entries = await loadManifest(forceRefresh: true);
      EmojiFontManifestEntry? selected;
      for (final entry in entries) {
        if (entry.key == key) {
          selected = entry;
          break;
        }
      }
      if (selected == null) return null;
      return downloadAndLoad(selected);
    } catch (error) {
      debugPrint(
        '[emoji_font_catalog] redownload failed key=$key '
        'type=${error.runtimeType}',
      );
      return null;
    }
  }

  /// Downloads (if needed) and registers an entry. The pinned Apple row is
  /// routed to its own cache-first loader with optional download.
  Future<String> downloadAndLoad(EmojiFontManifestEntry entry) {
    // The pinned Apple row has its own cache-first loader with optional
    // download — never route it through the manifest flow.
    if (entry.key == appleEntry.key) {
      return loadAppleFont(
        download: true,
      ).then((family) => family ?? EmojiFontChoice.bundledAppleFamily);
    }
    final pending = _inFlightFontLoads[entry.key];
    if (pending != null) return pending;
    final operation = _downloadAndLoad(entry);
    _inFlightFontLoads[entry.key] = operation;
    return operation.whenComplete(() {
      if (identical(_inFlightFontLoads[entry.key], operation)) {
        _inFlightFontLoads.remove(entry.key);
      }
    });
  }

  Future<String> _downloadAndLoad(EmojiFontManifestEntry entry) async {
    await ensureFontDownloaded(entry);
    await _loadFontFile(entry.runtimeFamily, await _fontFile(entry));
    return entry.runtimeFamily;
  }

  /// Brings the entry's cached file to a verified, complete state: downloads
  /// when missing or size-mismatched, records the size either way so later
  /// loads can detect truncation.
  Future<void> ensureFontDownloaded(EmojiFontManifestEntry entry) async {
    final file = await _fontFile(entry);
    if (await _verifyFontFile(entry, file)) return;
    final bytes = await _downloadFontTo(entry, file);
    final sizes = await _readSizeIndex();
    sizes[entry.key] = bytes;
    await _writeSizeIndex(sizes);
  }

  Future<List<EmojiFontManifestEntry>> _readManifest(File file) async {
    return _parseManifest(await file.readAsString());
  }

  List<EmojiFontManifestEntry> _parseManifest(String body) {
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final fonts = decoded['fonts'] as List? ?? const [];
    return [
          // Apple leads the list: the platform set every reference client puts
          // first, and iebb/emojifonts does not build it (its binaries are for
          // macOS Core Text; the upstream AppleColorEmoji CBDT table renders
          // fine through Skia on every platform MithkaX ships).
          EmojiFontCatalog.appleEntry,
          for (final item in fonts)
            if (item is Map) tryParseEntry(item.cast<String, dynamic>()),
        ]
        .whereType<EmojiFontManifestEntry>()
        // The Fluent pack is deliberately absent (its release binary is
        // mis-built and the user removed the set): drop the manifest's
        // own fluent rows, any spelling, instead of shipping broken rows.
        .where((entry) => entry.key != 'fluent')
        .toList()
      // The pinned Apple row owns its slot even if a future manifest ships
      // its own apple key — one row, the fork's.
      ..retainAfterFirstByKey();
  }

  /// Apple Color Emoji, pinned to the community CBDT build of the system
  /// font. The fork's default emoji face: selected out of the box, but its
  /// 45 MB binary is downloaded on first use and cached like any other
  /// pack — the APK stays lean. Not in the iebb/emojifonts manifest — this
  /// fork carries the entry itself so the picker's first row matches the
  /// reference clients.
  static const appleEntry = EmojiFontManifestEntry(
    key: 'apple',
    label: 'Apple Color Emoji',
    license: 'Apple',
    kind: 'color',
    url:
        'https://raw.githubusercontent.com/GORAlexComp/AppleColorEmojiFont'
        '/main/fonts/AppleColorEmoji.ttf',
    format: 'cbdt',
    coveragePct: 100,
    emojiVersion: '18.0',
    updated: '2026-10',
  );

  /// Test seam: run the same parse the manifest loader uses.
  @visibleForTesting
  List<EmojiFontManifestEntry> parseManifestForTesting(String body) =>
      _parseManifest(body);

  /// Cached font bytes are loaded straight into the engine — a truncated
  /// file would register as a broken family or crash the loader, so every
  /// write goes through a temp file + atomic rename and every read checks
  /// the recorded size.
  static const _sizeIndexFileName = 'sizes.json';

  Future<File> _sizeIndexFile() async {
    final dir = await _cacheDir();
    return File('${dir.path}/$_sizeIndexFileName');
  }

  Future<Map<String, int>> _readSizeIndex() async {
    try {
      final file = await _sizeIndexFile();
      if (!await file.exists()) return {};
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return {};
      return decoded.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  Future<File> _writeSizeIndex(Map<String, int> sizes) async {
    final file = await _sizeIndexFile();
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(sizes), flush: true);
    if (await file.exists()) await file.delete();
    return tmp.rename(file.path);
  }

  Future<int> _downloadFontTo(EmojiFontManifestEntry entry, File file) async {
    final response = await http.get(Uri.parse(entry.url));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'HTTP ${response.statusCode}',
        uri: response.request?.url,
      );
    }
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(response.bodyBytes, flush: true);
    if (await file.exists()) await file.delete();
    await tmp.rename(file.path);
    return response.bodyBytes.length;
  }

  EmojiFontManifestEntry? tryParseEntry(Map<String, dynamic> json) {
    try {
      final entry = EmojiFontManifestEntry.fromJson(json);
      return entry.key.isEmpty || entry.label.isEmpty ? null : entry;
    } catch (_) {
      return null;
    }
  }

  Future<File> _manifestCacheFile() async {
    final dir = await _cacheDir();
    return File('${dir.path}/manifest.json');
  }

  Future<File> _fontFile(EmojiFontManifestEntry entry) async {
    final dir = await _cacheDir();
    return File('${dir.path}/${entry.key}.${entry.extension}');
  }

  Future<File?> _cachedFontFileForKey(String key) async {
    final dir = await _cacheDir();
    if (!await dir.exists()) return null;
    await for (final entity in dir.list()) {
      if (entity is File && entity.uri.pathSegments.last.startsWith('$key.')) {
        return entity;
      }
    }
    return null;
  }

  /// The downloaded font files live under the app-support directory in this
  /// revision-tagged cache folder. The Apple font is cached here too — it is
  /// downloaded on demand like every other pack, never shipped in the APK.
  Future<Directory> _cacheDir() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}/$cacheDirectoryName');
  }

  Future<void> _loadFontFile(String family, File file) async {
    if (_loadedFamilies.contains(family)) return;
    final bytes = await file.readAsBytes();
    final loader = FontLoader(family);
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
    _loadedFamilies.add(family);
  }

  /// A font file is valid when its on-disk size matches the size recorded
  /// at download time. Files without an index entry (legacy caches from
  /// before the size index, or the previous bundled-apple release that
  /// never wrote one) are trusted by existence alone.
  Future<bool> _verifyFontFile(EmojiFontManifestEntry entry, File file) async {
    if (!await file.exists()) return false;
    final sizes = await _readSizeIndex();
    final recorded = sizes[entry.key];
    if (recorded == null) return true;
    return await file.length() == recorded;
  }

  /// Loads the pinned Apple font from the cache. With [download], a missing
  /// or broken cache file is fetched first; a failed fetch returns null so
  /// callers keep rendering the platform emoji face (never tofu) until the
  /// next attempt succeeds.
  Future<String?> loadAppleFont({bool download = false}) async {
    final file = await _fontFile(appleEntry);
    if (!await _verifyFontFile(appleEntry, file)) {
      if (!download) return null;
      try {
        await ensureFontDownloaded(appleEntry);
      } catch (error) {
        debugPrint(
          '[emoji_font_catalog] apple font download failed '
          'type=${error.runtimeType}',
        );
        return null;
      }
    }
    await _loadFontFile(appleEntry.runtimeFamily, file);
    return appleEntry.runtimeFamily;
  }
}

extension _EmojiFontEntryDedupe on List<EmojiFontManifestEntry> {
  /// Keep the first entry per key (the pinned Apple row wins its slot).
  void retainAfterFirstByKey() {
    final seen = <String>{};
    removeWhere((entry) => !seen.add(entry.key));
  }
}
