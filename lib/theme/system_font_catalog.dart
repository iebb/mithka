//
//  system_font_catalog.dart
//
//  Lists platform-installed font families for the text font picker.
//

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
}
