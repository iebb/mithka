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
    final file = await _cachedFontFileForKey(key);
    if (file == null) return null;
    final family = EmojiFontChoice.runtimeFamilyForKey(key);
    await _loadFontFile(family, file);
    return family;
  }

  Future<String?> loadCachedOrDownload(String key) async {
    final cached = await loadCached(key);
    if (cached != null) return cached;
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

  Future<String> downloadAndLoad(EmojiFontManifestEntry entry) {
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
    final file = await _fontFile(entry);
    if (!await file.exists()) {
      await file.parent.create(recursive: true);
      final response = await http.get(Uri.parse(entry.url));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'HTTP ${response.statusCode}',
          uri: response.request?.url,
        );
      }
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsBytes(response.bodyBytes, flush: true);
      if (await file.exists()) await file.delete();
      await tmp.rename(file.path);
    }
    await _loadFontFile(entry.runtimeFamily, file);
    return entry.runtimeFamily;
  }

  Future<List<EmojiFontManifestEntry>> _readManifest(File file) async {
    return _parseManifest(await file.readAsString());
  }

  List<EmojiFontManifestEntry> _parseManifest(String body) {
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final fonts = decoded['fonts'] as List? ?? const [];
    return [
      for (final item in fonts)
        if (item is Map) tryParseEntry(item.cast<String, dynamic>()),
    ].whereType<EmojiFontManifestEntry>().toList();
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
}
