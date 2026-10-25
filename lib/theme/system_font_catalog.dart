//
//  system_font_catalog.dart
//
//  Lists platform-installed font families for the text font picker.
//

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SystemFontCatalog {
  SystemFontCatalog._();

  static const MethodChannel _channel = MethodChannel('mithka/fonts');

  static Future<List<String>> loadFonts() async {
    try {
      final result = await _channel.invokeListMethod<String>('listFonts');
      final fonts =
          (result ?? const <String>[])
              .map((font) => font.trim())
              .where((font) => font.isNotEmpty)
              .toSet()
              .toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      return fonts;
    } catch (_) {
      return const <String>[];
    }
  }

  // These engine aliases must not be persisted as a native font's private
  // family name (UIKit may resolve the old Apple alias to such a name).
  static bool _isSystemAlias(String family) =>
      defaultTargetPlatform == TargetPlatform.iOS &&
      const {
        '.AppleSystemUIFont',
        'CupertinoSystemText',
        'CupertinoSystemDisplay',
      }.contains(family);

  static Future<List<String>> normalizeFamilies(List<String> families) async {
    try {
      final result = await _channel.invokeListMethod<String>(
        'normalizeFontFamilies',
        families,
      );
      if (result == null || result.length != families.length) return families;
      return [
        for (var i = 0; i < result.length; i++)
          _isSystemAlias(families[i]) || result[i].trim().isEmpty
              ? families[i]
              : result[i].trim(),
      ];
    } catch (_) {
      return families;
    }
  }
}
