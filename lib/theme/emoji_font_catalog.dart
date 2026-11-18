//
//  emoji_font_catalog.dart
//
//  Runtime emoji font catalog backed by the MithkaX emoji font source
//  (dl.mintabyss.eu.org/emojifonts). Font binaries are downloaded on demand,
//  integrity-checked against the manifest's sha256, and loaded with Flutter's
//  FontLoader.
//

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/json_helpers.dart';
import 'package:path_provider/path_provider.dart';

import 'emoji_channel_source.dart';

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
    this.sha256,
    this.sizeBytes,
    this.chatId,
    this.channelMessageId,
  });

  /// A pack served as a document in the @mithka_metadata channel. The url
  /// stays empty — this entry downloads through TDLib, never HTTP.
  const EmojiFontManifestEntry.channel({
    required String key,
    required String label,
    required String license,
    required int chatId,
    required int messageId,
    int? sizeBytes,
  }) : this(
         key: key,
         label: label,
         license: license,
         kind: 'color',
         url: '',
         format: 'ttf',
         coveragePct: 0,
         emojiVersion: '',
         updated: '',
         sizeBytes: sizeBytes,
         chatId: chatId,
         channelMessageId: messageId,
       );

  final String key;
  final String label;
  final String license;
  final String kind;
  final String url;
  final String format;
  final int coveragePct;
  final String emojiVersion;
  final String updated;

  /// Content hash from the manifest. When present, a cached file is only
  /// trusted when its sha256 matches — stronger than the legacy size check.
  final String? sha256;

  /// Byte size from the manifest, used to show the download size in the
  /// picker before the pack is fetched.
  final int? sizeBytes;

  /// @mithka_metadata chat id when this pack is served from the channel.
  final int? chatId;

  /// Message id of this pack's font document inside the channel.
  final int? channelMessageId;

  bool get isChannelServed => channelMessageId != null && channelMessageId! > 0;

  String get runtimeFamily => EmojiFontChoice.runtimeFamilyForKey(key);

  String get extension {
    // Channel documents always arrive as .ttf binaries.
    if (isChannelServed) return 'ttf';
    final path = Uri.tryParse(url)?.path ?? '';
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    return dot < 0 ? 'ttf' : name.substring(dot + 1);
  }

  factory EmojiFontManifestEntry.fromJson(Map<String, dynamic> json) {
    // Both manifest generations are accepted: the MithkaX source lists a
    // flat `url` + `format` (preferred), while the legacy shapes —
    // iebb/emojifonts' `formats: {sbix|colrv0|svginot|glyf: url}` map and
    // a top-level `ttc` url — still resolve.
    var url = (json['url'] as String?)?.trim() ?? '';
    var format = (json['format'] as String?)?.trim() ?? '';
    if (url.isEmpty) {
      final formats = (json['formats'] as Map?)?.cast<String, dynamic>() ?? {};
      const preferredFormats = ['sbix', 'glyf', 'colrv0', 'svginot', 'ttc'];
      for (final candidate in preferredFormats) {
        final value = formats[candidate];
        if (value is String && value.startsWith('https://')) {
          url = value;
          format = candidate;
          break;
        }
      }
    }
    if (url.isEmpty || !url.startsWith('https://')) {
      throw const FormatException('emoji font has no supported format');
    }
    return EmojiFontManifestEntry(
      key: (json['key'] as String?)?.trim() ?? '',
      label: (json['label'] as String?)?.trim() ?? '',
      license: (json['license'] as String?)?.trim() ?? '',
      kind: (json['kind'] as String?)?.trim() ?? '',
      url: url,
      format: format,
      coveragePct: (json['coverage_pct'] as num?)?.round() ?? 0,
      emojiVersion: (json['emoji_version'] as String?)?.trim() ?? '',
      updated: (json['updated'] as String?)?.trim() ?? '',
      sha256: (json['sha256'] as String?)?.trim(),
      sizeBytes: (json['bytes'] as num?)?.toInt(),
    );
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

  /// The MithkaX emoji font source. The manifest carries sha256 hashes for
  /// every font binary, so cached files are verified by content, not size.
  /// Primary source is the @mithka_metadata Telegram channel (no external
  /// host once signed in); this URL is the HTTP fallback for TDLib-less
  /// environments (widget tests, demo builds).
  static const manifestUrl =
      'https://dl.mintabyss.eu.org/emojifonts/manifest.json';

  /// Pluggable channel source; production shares one instance so the
  /// channel chat id resolves once per process. Tests inject a fake.
  @visibleForTesting
  EmojiChannelSource? debugChannelSource;

  final EmojiChannelSource _channelSource = EmojiChannelSource();

  /// Last chat id the channel source resolved, for cache-rehydrated entries
  /// whose serialized chat_id predates a process restart.
  int? _channelLastChatId;

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

    // Primary: the @mithka_metadata channel catalog via TDLib.
    try {
      final source = debugChannelSource ?? _channelSource;
      final entries = await source.fetchCatalog();
      if (entries != null && entries.isNotEmpty) {
        _channelLastChatId = entries.first.chatId;
        await cacheFile.parent.create(recursive: true);
        await cacheFile.writeAsString(
          jsonEncode({
            'generated': DateTime.now().toIso8601String(),
            'source': 'channel',
            'fonts': [
              for (final e in entries)
                {
                  'key': e.key,
                  'label': e.label,
                  'license': e.license,
                  'kind': e.kind,
                  'chat_id': e.chatId,
                  'message_id': e.channelMessageId,
                  'bytes': e.sizeBytes,
                },
            ],
          }),
          flush: true,
        );
        return entries;
      }
    } catch (_) {}

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

  /// Downloads (if needed) and registers an entry.
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
    await ensureFontDownloaded(entry);
    await _loadFontFile(entry.runtimeFamily, await _fontFile(entry));
    return entry.runtimeFamily;
  }

  /// Brings the entry's cached file to a verified, complete state: downloads
  /// when missing, hash-mismatched (manifest sha256) or size-mismatched
  /// (legacy installs whose manifest carried no hash).
  Future<void> ensureFontDownloaded(EmojiFontManifestEntry entry) async {
    final file = await _fontFile(entry);
    if (await _verifyFontFile(entry, file)) return;
    final bytes = await _downloadFontTo(entry, file);
    final sizes = await _readSizeIndex();
    sizes[entry.key] = bytes;
    await _writeSizeIndex(sizes);
  }

  /// Deletes a pack's cached font file (the picker's swipe-to-delete). Safe
  /// for any key: missing files are a no-op, the running family registration
  /// is only in-memory and dies with the process. Returns whether a file was
  /// removed.
  Future<bool> deleteCachedFont(String key) async {
    if (key == EmojiFontChoice.system.key) return false;
    final file = await _cachedFontFileForKey(key);
    if (file == null) return false;
    try {
      await file.delete();
    } catch (_) {
      return false;
    }
    final sizes = await _readSizeIndex();
    if (sizes.containsKey(key)) {
      sizes.remove(key);
      await _writeSizeIndex(sizes);
    }
    return true;
  }

  /// On-disk size of a cached pack, or null when it is not downloaded.
  Future<int?> cachedFontSize(String key) async {
    if (key == EmojiFontChoice.system.key) return null;
    final file = await _cachedFontFileForKey(key);
    if (file == null) return null;
    try {
      return await file.length();
    } catch (_) {
      return null;
    }
  }

  Future<List<EmojiFontManifestEntry>> _readManifest(File file) async {
    return _parseManifest(await file.readAsString());
  }

  List<EmojiFontManifestEntry> _parseManifest(String body) {
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    // The channel-source cache: entries carry the channel message id instead
    // of an HTTP url.
    if (decoded['source'] == 'channel') {
      final fonts = decoded['fonts'] as List? ?? const [];
      return [
            for (final item in fonts)
              if (item is Map) _tryParseChannelEntry(item),
          ]
          .whereType<EmojiFontManifestEntry>()
          .where((entry) => entry.key != 'fluent')
          .toList()
        ..retainAfterFirstByKey();
    }
    final fonts = decoded['fonts'] as List? ?? const [];
    return [
          for (final item in fonts)
            if (item is Map) tryParseEntry(Map<String, dynamic>.from(item)),
        ]
        .whereType<EmojiFontManifestEntry>()
        // The Fluent pack is deliberately absent (its release binary is
        // mis-built and the user removed the set): drop any manifest's
        // fluent rows, any spelling, instead of shipping broken rows.
        .where((entry) => entry.key != 'fluent')
        .toList()
      ..retainAfterFirstByKey();
  }

  EmojiFontManifestEntry? _tryParseChannelEntry(Map<dynamic, dynamic> json) {
    final key = (json['key'] as String?)?.trim() ?? '';
    final label = (json['label'] as String?)?.trim() ?? '';
    final chatId = jsonInt(json['chat_id']);
    final messageId = jsonInt(json['message_id']);
    if (key.isEmpty || label.isEmpty || messageId == null || messageId <= 0) {
      return null;
    }
    return EmojiFontManifestEntry.channel(
      key: key,
      label: label,
      license: (json['license'] as String?)?.trim() ?? '',
      chatId: chatId ?? 0,
      messageId: messageId,
      sizeBytes: jsonInt(json['bytes']),
    );
  }

  /// Test seam: run the same parse the manifest loader uses.
  @visibleForTesting
  List<EmojiFontManifestEntry> parseManifestForTesting(String body) =>
      _parseManifest(body);

  /// Cached font bytes are loaded straight into the engine — a truncated
  /// file would register as a broken family or crash the loader, so every
  /// write goes through a temp file + atomic rename and every read verifies
  /// the recorded size (and the manifest's sha256 when it has one).
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
    // Channel-served packs come through TDLib, not HTTP.
    if (entry.isChannelServed) {
      final chatId = entry.chatId ?? _channelLastChatId;
      final messageId = entry.channelMessageId!;
      if (chatId != null && chatId > 0) {
        final bytes = await (debugChannelSource ?? _channelSource)
            .downloadFont(
              chatId: chatId,
              messageId: messageId,
              destPath: '${file.path}.tmp',
            );
        if (bytes != null && bytes > 0) {
          if (await file.exists()) await file.delete();
          await File('${file.path}.tmp').rename(file.path);
          return bytes;
        }
      }
      throw const FileSystemException('channel emoji font unavailable');
    }
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
  /// revision-tagged cache folder. Every pack is downloaded on demand — none
  /// ships in the APK.
  Future<Directory> _cacheDir() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}/$cacheDirectoryName');
  }

  /// FontLoader.load() blocks forever on the widget-test engine (the
  /// platform channel never answers). Tests set this to register the family
  /// without the engine call.
  @visibleForTesting
  static bool debugSkipEngineFontLoad = false;

  Future<void> _loadFontFile(String family, File file) async {
    if (_loadedFamilies.contains(family)) return;
    final bytes = await file.readAsBytes();
    if (!debugSkipEngineFontLoad) {
      final loader = FontLoader(family);
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
    }
    _loadedFamilies.add(family);
  }

  /// A font file is valid when its content matches what the manifest says it
  /// should be: the sha256 when the manifest carries one, otherwise the size
  /// recorded at download time. Files without any recorded expectation
  /// (legacy caches from before the size index) are trusted by existence
  /// alone.
  Future<bool> _verifyFontFile(EmojiFontManifestEntry entry, File file) async {
    if (!await file.exists()) return false;
    final hash = entry.sha256;
    if (hash != null && hash.isNotEmpty) {
      try {
        return _sha256Of(await file.readAsBytes()) == hash.toLowerCase();
      } catch (_) {
        return false;
      }
    }
    final sizes = await _readSizeIndex();
    final recorded = sizes[entry.key];
    if (recorded == null) return true;
    return await file.length() == recorded;
  }

  static String _sha256Of(List<int> bytes) =>
      crypto.sha256.convert(bytes).toString();
}

extension _EmojiFontEntryDedupe on List<EmojiFontManifestEntry> {
  /// Keep the first entry per key.
  void retainAfterFirstByKey() {
    final seen = <String>{};
    removeWhere((entry) => !seen.add(entry.key));
  }
}
