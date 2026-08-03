import 'dart:convert';

import 'package:flutter/foundation.dart';

const desktopImagePreviewWindowType = 'mithka.image-preview';
const _desktopImagePreviewProtocolVersion = 4;
const _maximumEncodedArgumentsLength = 512 * 1024;
const _maximumMiniThumbBytes = 96 * 1024;
const _maximumGalleryItems = 64;

@immutable
class DesktopImagePreviewItemArguments {
  const DesktopImagePreviewItemArguments({this.path, this.miniThumb});

  final String? path;
  final Uint8List? miniThumb;

  Map<String, Object?> toJson() => {
    'path': ?normalizeDesktopImagePath(path),
    if (miniThumb case final bytes?
        when bytes.isNotEmpty && bytes.length <= _maximumMiniThumbBytes)
      'miniThumb': base64Encode(bytes),
  };

  static DesktopImagePreviewItemArguments? tryParse(Object? source) {
    if (source is! Map) return null;
    final path = normalizeDesktopImagePath(source['path'] as String?);
    Uint8List? miniThumb;
    final encodedThumb = source['miniThumb'];
    if (encodedThumb is String && encodedThumb.isNotEmpty) {
      final bytes = base64Decode(encodedThumb);
      if (bytes.length > _maximumMiniThumbBytes) return null;
      miniThumb = Uint8List.fromList(bytes);
    }
    return DesktopImagePreviewItemArguments(path: path, miniThumb: miniThumb);
  }
}

@immutable
class DesktopImagePreviewWindowArguments {
  const DesktopImagePreviewWindowArguments({
    required this.items,
    required this.title,
    required this.localeTag,
    required this.dark,
    this.startIndex = 0,
  });

  final List<DesktopImagePreviewItemArguments> items;
  final String title;
  final String localeTag;
  final bool dark;
  final int startIndex;

  String encode() {
    final safeItems = items.take(_maximumGalleryItems).toList(growable: false);
    final source = jsonEncode({
      'type': desktopImagePreviewWindowType,
      'version': _desktopImagePreviewProtocolVersion,
      'title': normalizeDesktopImagePreviewTitle(title),
      'localeTag': normalizeDesktopImagePreviewLocaleTag(localeTag),
      'dark': dark,
      'startIndex': safeItems.isEmpty
          ? 0
          : startIndex.clamp(0, safeItems.length - 1),
      'items': [for (final item in safeItems) item.toJson()],
    });
    if (source.length > _maximumEncodedArgumentsLength) {
      throw StateError('Image preview arguments exceed the safe IPC limit');
    }
    return source;
  }

  static DesktopImagePreviewWindowArguments? tryParseLaunchArguments(
    List<String> arguments,
  ) => arguments.length < 2 ? null : tryParse(arguments[1]);

  static DesktopImagePreviewWindowArguments? tryParse(String source) {
    if (source.isEmpty || source.length > _maximumEncodedArgumentsLength) {
      return null;
    }
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map ||
          decoded['type'] != desktopImagePreviewWindowType ||
          decoded['version'] != _desktopImagePreviewProtocolVersion) {
        return null;
      }
      final rawItems = decoded['items'];
      if (rawItems is! List ||
          rawItems.isEmpty ||
          rawItems.length > _maximumGalleryItems) {
        return null;
      }
      final items = <DesktopImagePreviewItemArguments>[];
      for (final rawItem in rawItems) {
        final item = DesktopImagePreviewItemArguments.tryParse(rawItem);
        if (item == null) return null;
        items.add(item);
      }
      final rawStartIndex = decoded['startIndex'];
      final startIndex = rawStartIndex is int
          ? rawStartIndex.clamp(0, items.length - 1)
          : 0;
      return DesktopImagePreviewWindowArguments(
        items: items,
        title: normalizeDesktopImagePreviewTitle(decoded['title'] as String?),
        localeTag: normalizeDesktopImagePreviewLocaleTag(
          decoded['localeTag'] as String?,
        ),
        dark: decoded['dark'] is bool ? decoded['dark']! as bool : true,
        startIndex: startIndex,
      );
    } on Object {
      return null;
    }
  }
}

String normalizeDesktopImagePreviewTitle(String? source) {
  final value = source?.replaceAll(RegExp(r'[\r\n]+'), ' ').trim() ?? '';
  if (value.isEmpty) return 'Image preview';
  return value.length <= 128 ? value : value.substring(0, 128);
}

String normalizeDesktopImagePreviewLocaleTag(String? source) {
  final value = source?.trim().replaceAll('_', '-') ?? '';
  if (value.isEmpty || value.length > 32) return 'en';
  return RegExp(r'^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$').hasMatch(value)
      ? value
      : 'en';
}

@immutable
class DesktopImagePreviewPathUpdate {
  const DesktopImagePreviewPathUpdate({
    required this.index,
    required this.path,
  });

  final int index;
  final String path;

  Map<String, Object?> toJson() => {'index': index, 'path': path};

  static DesktopImagePreviewPathUpdate? tryParse(Object? source) {
    if (source is! Map) return null;
    final index = source['index'];
    final path = normalizeDesktopImagePath(source['path'] as String?);
    if (index is! int ||
        index < 0 ||
        index >= _maximumGalleryItems ||
        path == null) {
      return null;
    }
    return DesktopImagePreviewPathUpdate(index: index, path: path);
  }
}

/// Accepts local absolute filesystem paths only, never URLs or relative paths.
String? normalizeDesktopImagePath(String? source) {
  final value = source?.trim();
  if (value == null ||
      value.isEmpty ||
      value.length > 4096 ||
      value.contains('\u0000') ||
      value.contains('://')) {
    return null;
  }
  final unixAbsolute = value.startsWith('/') && !value.startsWith('//');
  final windowsAbsolute = RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value);
  return unixAbsolute || windowsAbsolute ? value : null;
}
