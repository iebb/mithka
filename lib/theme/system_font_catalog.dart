//
//  system_font_catalog.dart
//
//  Lists platform-installed font families for the text font picker.
//

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SystemFontEntry {
  const SystemFontEntry({
    required this.family,
    String? displayName,
    this.isMonospace,
  }) : displayName = displayName ?? family;

  final String family;
  final String displayName;

  /// Platform-supplied monospace classification when known (e.g. DirectWrite
  /// `IDWriteFont1::IsMonospacedFont` on Windows), or null on platforms that
  /// return only family names.
  final bool? isMonospace;

  bool matchesQuery(String normalizedLowerQuery) =>
      family.toLowerCase().contains(normalizedLowerQuery) ||
      displayName.toLowerCase().contains(normalizedLowerQuery);
}

class SystemFontCatalog {
  SystemFontCatalog._();

  static const MethodChannel _channel = MethodChannel('mithka/fonts');
  static Set<String>? _knownLocalFamiliesLower;

  static bool get hasLoadedLocalFamilies => _knownLocalFamiliesLower != null;

  static bool isKnownLocalFamily(String family) {
    final trimmed = family.trim();
    if (trimmed.isEmpty || trimmed.startsWith('google:')) return false;
    return _knownLocalFamiliesLower?.contains(trimmed.toLowerCase()) ?? false;
  }

  @visibleForTesting
  static void setKnownLocalFamiliesForTesting(Iterable<String>? families) {
    _knownLocalFamiliesLower = families == null
        ? null
        : {
            for (final family in families)
              if (family.trim().isNotEmpty) family.trim().toLowerCase(),
          };
  }

  static Future<List<SystemFontEntry>> loadFontEntries() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('listFonts');
      final entries = parseRawFontList(result);
      _knownLocalFamiliesLower = {
        for (final entry in entries) entry.family.toLowerCase(),
      };
      return entries;
    } catch (_) {
      return const <SystemFontEntry>[];
    }
  }

  static Future<List<String>> loadFonts() async {
    final entries = await loadFontEntries();
    return [for (final entry in entries) entry.family];
  }

  @visibleForTesting
  static List<SystemFontEntry> parseRawFontList(List<dynamic>? raw) {
    if (raw == null || raw.isEmpty) return const <SystemFontEntry>[];
    final byFamilyLower = <String, SystemFontEntry>{};
    for (final item in raw) {
      SystemFontEntry? parsed;
      if (item is String) {
        final trimmed = item.trim();
        if (trimmed.isNotEmpty) {
          parsed = SystemFontEntry(family: trimmed, displayName: trimmed);
        }
      } else if (item is Map) {
        final family = item['family']?.toString().trim() ?? '';
        if (family.isNotEmpty) {
          final rawDisplay = item['displayName']?.toString().trim();
          final rawMono = item['isMonospace'];
          parsed = SystemFontEntry(
            family: family,
            displayName: (rawDisplay != null && rawDisplay.isNotEmpty)
                ? rawDisplay
                : family,
            isMonospace: rawMono is bool ? rawMono : null,
          );
        }
      }
      if (parsed != null) {
        byFamilyLower.putIfAbsent(parsed.family.toLowerCase(), () => parsed!);
      }
    }
    return byFamilyLower.values.toList()..sort((a, b) {
      final cmp = a.family.toLowerCase().compareTo(b.family.toLowerCase());
      return cmp != 0 ? cmp : a.family.compareTo(b.family);
    });
  }

  // These engine aliases must not be persisted as a native font's private
  // family name (UIKit/AppKit may resolve an Apple alias to such a name).
  static bool _isSystemAlias(String family) =>
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS) &&
      const {
        '.AppleSystemUIFont',
        'CupertinoSystemText',
        'CupertinoSystemDisplay',
      }.contains(family);

  static bool _shouldPreserveVerbatim(String family) {
    final trimmed = family.trim();
    return trimmed.isEmpty ||
        trimmed.startsWith('google:') ||
        _isSystemAlias(trimmed);
  }

  static Future<List<String>> normalizeFamilies(List<String> families) async {
    if (families.every(_shouldPreserveVerbatim)) return families;
    try {
      final result = await _channel.invokeListMethod<String>(
        'normalizeFontFamilies',
        families,
      );
      if (result == null || result.length != families.length) return families;
      return [
        for (var i = 0; i < result.length; i++)
          _shouldPreserveVerbatim(families[i]) || result[i].trim().isEmpty
              ? families[i]
              : result[i].trim(),
      ];
    } catch (_) {
      return families;
    }
  }
}
