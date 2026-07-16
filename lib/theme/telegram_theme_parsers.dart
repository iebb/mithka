import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

enum TelegramThemePlatform { android, ios, macos, desktop }

/// Fidelity order used when a cloud theme supplies more than one platform
/// document. Telegram's Android palette is the broadest; missing semantic
/// variables then fall back through iOS, macOS, and finally TDesktop.
const telegramThemePlatformFallbackOrder = <TelegramThemePlatform>[
  TelegramThemePlatform.android,
  TelegramThemePlatform.ios,
  TelegramThemePlatform.macos,
  TelegramThemePlatform.desktop,
];

class ParsedTelegramThemeFile {
  const ParsedTelegramThemeFile({
    required this.platform,
    required this.palette,
    this.wallpaperDescriptor,
    this.wallpaperBytes,
    this.wallpaperExtension,
    this.wallpaperIsTiled = false,
  });

  final TelegramThemePlatform platform;
  final Map<String, int> palette;
  final String? wallpaperDescriptor;
  final Uint8List? wallpaperBytes;
  final String? wallpaperExtension;
  final bool wallpaperIsTiled;

  bool get isUseful => palette.isNotEmpty || wallpaperBytes != null;
}

TelegramThemePlatform? telegramThemePlatformForDocument({
  required String fileName,
  required String mimeType,
}) {
  final name = fileName.toLowerCase();
  final mime = mimeType.toLowerCase();
  if (mime.contains('tgtheme-ios') || name.endsWith('.tgios-theme')) {
    return TelegramThemePlatform.ios;
  }
  if (mime.contains('tgtheme-android') || name.endsWith('.attheme')) {
    return TelegramThemePlatform.android;
  }
  if (mime.contains('tgtheme-macos') || name.endsWith('.palette')) {
    return TelegramThemePlatform.macos;
  }
  if (mime.contains('tgtheme-tdesktop') || name.endsWith('.tdesktop-theme')) {
    return TelegramThemePlatform.desktop;
  }
  return null;
}

ParsedTelegramThemeFile? parseTelegramThemeFile(
  TelegramThemePlatform platform,
  Uint8List bytes,
) {
  try {
    return switch (platform) {
      TelegramThemePlatform.android => _parseAndroidFile(bytes),
      TelegramThemePlatform.ios => _parseIosFile(bytes),
      TelegramThemePlatform.macos => _parseMacosFile(bytes),
      TelegramThemePlatform.desktop => _parseDesktopFile(bytes),
    };
  } catch (_) {
    return null;
  }
}

/// Parses Telegram's official iOS `.tgios-theme` indentation format into
/// dotted keys, matching the coding paths used by Telegram-iOS.
Map<String, int> parseTelegramIosTheme(String contents) {
  final result = <String, int>{};
  final parents = <String>[];
  for (final rawLine in const LineSplitter().convert(contents)) {
    final trimmed = rawLine.trim();
    if (trimmed.isEmpty ||
        trimmed.startsWith('//') ||
        trimmed.startsWith('# ')) {
      continue;
    }
    final separator = trimmed.indexOf(':');
    if (separator <= 0) continue;
    final indent = rawLine.length - rawLine.trimLeft().length;
    final depth = indent ~/ 2;
    while (parents.length > depth) {
      parents.removeLast();
    }
    final key = trimmed.substring(0, separator).trim();
    final rawValue = trimmed.substring(separator + 1).trim();
    if (rawValue.isEmpty) {
      while (parents.length < depth) {
        parents.add('');
      }
      if (parents.length == depth) parents.add(key);
      continue;
    }
    final path = [...parents.where((item) => item.isNotEmpty), key].join('.');
    final color = _parseArgbThemeColor(rawValue.split(RegExp(r'\s+')).first);
    if (color != null) result[path] = color;
  }
  return result;
}

Map<String, int> parseTelegramAndroidTheme(String contents) {
  final result = <String, int>{};
  for (final rawLine in const LineSplitter().convert(contents)) {
    final line = rawLine.trim();
    if (line.isEmpty ||
        line.startsWith('//') ||
        line == 'WPS' ||
        line == 'PWS') {
      continue;
    }
    final separator = line.indexOf('=');
    if (separator <= 0) continue;
    final key = line.substring(0, separator).trim();
    final rawValue = line
        .substring(separator + 1)
        .trim()
        .split(RegExp(r'\s+'))
        .first;
    final value = _parseAndroidColor(rawValue);
    if (value != null) result[key] = value;
  }
  return result;
}

/// Parses Telegram macOS `.palette` files. The format is a flat `key=value`
/// list, but unlike Android it also contains metadata and may suffix colors
/// with an alpha component.
Map<String, int> parseTelegramMacosTheme(String contents) {
  final result = <String, int>{};
  for (final rawLine in const LineSplitter().convert(contents)) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('//')) continue;
    final separator = line.indexOf('=');
    if (separator <= 0) continue;
    final key = line.substring(0, separator).trim();
    final rawValue = line.substring(separator + 1).trim();
    if (key == 'isDark') {
      final dark = int.tryParse(rawValue);
      if (dark != null) result['dark'] = dark == 0 ? 0 : 1;
      continue;
    }
    if (key == 'bubbleBackground_outgoing') {
      final colors = rawValue
          .split(',')
          .map(_parseMacosColor)
          .whereType<int>()
          .toList(growable: false);
      if (colors.isNotEmpty) {
        result[key] = colors.first;
        if (colors.length > 1) {
          result['bubbleBackgroundGradient_outgoing'] = colors.last;
        }
      }
      continue;
    }
    final color = _parseMacosColor(rawValue);
    if (color != null) result[key] = color;
  }
  return result;
}

Map<String, int> parseTelegramDesktopTheme(String contents) {
  final rawValues = <String, String>{};
  for (final rawLine in const LineSplitter().convert(contents)) {
    final line = rawLine.split('//').first.trim();
    if (line.isEmpty) continue;
    final separator = line.indexOf(':');
    if (separator <= 0) continue;
    final key = line.substring(0, separator).trim();
    var value = line.substring(separator + 1).trim();
    if (value.endsWith(';')) {
      value = value.substring(0, value.length - 1).trim();
    }
    if (value.isNotEmpty) rawValues[key] = value;
  }

  final result = <String, int>{};
  int? resolve(String key, Set<String> visiting) {
    final cached = result[key];
    if (cached != null) return cached;
    if (!visiting.add(key)) return null;
    final raw = rawValues[key];
    if (raw == null) return null;
    final color = raw.startsWith('#')
        ? _parseDesktopColor(raw)
        : resolve(raw, visiting);
    visiting.remove(key);
    if (color != null) result[key] = color;
    return color;
  }

  for (final key in rawValues.keys) {
    resolve(key, <String>{});
  }
  return result;
}

ParsedTelegramThemeFile _parseIosFile(Uint8List bytes) {
  final contents = utf8.decode(bytes, allowMalformed: true);
  final palette = parseTelegramIosTheme(contents);
  final values = _parseIosStringValues(contents);
  return ParsedTelegramThemeFile(
    platform: TelegramThemePlatform.ios,
    palette: palette,
    wallpaperDescriptor: values['chat.defaultWallpaper'],
  );
}

ParsedTelegramThemeFile _parseAndroidFile(Uint8List bytes) {
  final marker = _findWallpaperMarker(bytes);
  final headerEnd = marker?.$1 ?? bytes.length;
  final header = utf8.decode(bytes.sublist(0, headerEnd), allowMalformed: true);
  final wallpaper = marker == null ? null : _extractImage(bytes, marker.$2);
  return ParsedTelegramThemeFile(
    platform: TelegramThemePlatform.android,
    palette: parseTelegramAndroidTheme(header),
    wallpaperBytes: wallpaper?.$1,
    wallpaperExtension: wallpaper?.$2,
  );
}

ParsedTelegramThemeFile _parseMacosFile(Uint8List bytes) {
  final contents = utf8.decode(bytes, allowMalformed: true);
  return ParsedTelegramThemeFile(
    platform: TelegramThemePlatform.macos,
    palette: parseTelegramMacosTheme(contents),
  );
}

ParsedTelegramThemeFile _parseDesktopFile(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes, verify: true);
  ArchiveFile? colors;
  ArchiveFile? wallpaper;
  var tiled = false;
  for (final file in archive.files) {
    if (!file.isFile) continue;
    final name = file.name.toLowerCase();
    if (name.endsWith('colors.tdesktop-theme')) {
      colors = file;
    } else if (name.endsWith('tiled.jpg') || name.endsWith('tiled.png')) {
      wallpaper = file;
      tiled = true;
    } else if (wallpaper == null &&
        (name.endsWith('background.jpg') || name.endsWith('background.png'))) {
      wallpaper = file;
    }
  }
  if (colors == null) throw const FormatException('Desktop palette is missing');
  final colorBytes = Uint8List.fromList(colors.content as List<int>);
  final wallpaperBytes = wallpaper == null
      ? null
      : Uint8List.fromList(wallpaper.content as List<int>);
  return ParsedTelegramThemeFile(
    platform: TelegramThemePlatform.desktop,
    palette: parseTelegramDesktopTheme(
      utf8.decode(colorBytes, allowMalformed: true),
    ),
    wallpaperBytes: wallpaperBytes,
    wallpaperExtension: wallpaper == null
        ? null
        : (wallpaper.name.toLowerCase().endsWith('.png') ? '.png' : '.jpg'),
    wallpaperIsTiled: tiled,
  );
}

Map<String, String> _parseIosStringValues(String contents) {
  final result = <String, String>{};
  final parents = <String>[];
  for (final rawLine in const LineSplitter().convert(contents)) {
    final trimmed = rawLine.trim();
    if (trimmed.isEmpty || trimmed.startsWith('//')) continue;
    final separator = trimmed.indexOf(':');
    if (separator <= 0) continue;
    final depth = (rawLine.length - rawLine.trimLeft().length) ~/ 2;
    while (parents.length > depth) {
      parents.removeLast();
    }
    final key = trimmed.substring(0, separator).trim();
    final value = trimmed.substring(separator + 1).trim();
    if (value.isEmpty) {
      while (parents.length < depth) {
        parents.add('');
      }
      if (parents.length == depth) parents.add(key);
    } else {
      result[[...parents.where((item) => item.isNotEmpty), key].join('.')] =
          value;
    }
  }
  return result;
}

(int, int)? _findWallpaperMarker(Uint8List bytes) {
  for (final marker in const [
    '\nWPS\n',
    '\r\nWPS\r\n',
    '\nPWS\n',
    '\r\nPWS\r\n',
  ]) {
    final encoded = ascii.encode(marker);
    final index = _indexOf(bytes, encoded);
    if (index >= 0) return (index, index + encoded.length);
  }
  return null;
}

(Uint8List, String)? _extractImage(Uint8List bytes, int start) {
  final jpegStart = _indexOf(bytes, const [0xFF, 0xD8, 0xFF], start);
  if (jpegStart >= 0) {
    final jpegEnd = _lastIndexOf(bytes, const [0xFF, 0xD9]);
    if (jpegEnd > jpegStart) {
      return (
        Uint8List.fromList(bytes.sublist(jpegStart, jpegEnd + 2)),
        '.jpg',
      );
    }
  }
  const pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  final pngStart = _indexOf(bytes, pngSignature, start);
  if (pngStart >= 0) {
    final pngEnd = _lastIndexOf(bytes, const [0x49, 0x45, 0x4E, 0x44]);
    if (pngEnd > pngStart) {
      return (Uint8List.fromList(bytes.sublist(pngStart, pngEnd + 8)), '.png');
    }
  }
  return null;
}

int _indexOf(List<int> bytes, List<int> needle, [int start = 0]) {
  if (needle.isEmpty) return start;
  for (var i = start; i <= bytes.length - needle.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (bytes[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return i;
  }
  return -1;
}

int _lastIndexOf(List<int> bytes, List<int> needle) {
  for (var i = bytes.length - needle.length; i >= 0; i--) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (bytes[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return i;
  }
  return -1;
}

int? _parseAndroidColor(String raw) {
  if (raw.startsWith('#')) return _parseArgbThemeColor(raw);
  final signed = int.tryParse(raw);
  return signed == null ? null : signed & 0xFFFFFFFF;
}

int? _parseMacosColor(String raw) {
  final components = raw.trim().split(':');
  final color = _parseArgbThemeColor(components.first.trim());
  if (color == null) return null;
  if (components.length < 2) return color;
  final alpha = double.tryParse(components[1].trim());
  if (alpha == null) return color;
  final rgb = color & 0x00FFFFFF;
  return ((alpha.clamp(0.0, 1.0) * 255).round() << 24) | rgb;
}

int? _parseArgbThemeColor(String raw) {
  final value = raw.trim();
  if (value == 'true') return 1;
  if (value == 'false') return 0;
  final hex = value.startsWith('#') ? value.substring(1) : value;
  if (hex.length != 6 && hex.length != 8) return null;
  return int.tryParse(hex, radix: 16);
}

int? _parseDesktopColor(String raw) {
  final hex = raw.startsWith('#') ? raw.substring(1) : raw;
  final value = int.tryParse(hex, radix: 16);
  if (value == null || (hex.length != 6 && hex.length != 8)) return null;
  if (hex.length == 6) return value;
  final rgb = value >> 8;
  final alpha = value & 0xFF;
  return (alpha << 24) | rgb;
}
