import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../media/media_metadata.dart';
import 'desktop_window_argument_normalizers.dart';

const desktopImagePreviewWindowType = 'mithka.image-preview';
const _desktopImagePreviewProtocolVersion = 5;
const _maximumEncodedArgumentsLength = 512 * 1024;
const _maximumMiniThumbBytes = 96 * 1024;
const _maximumGalleryItems = 64;
const _maximumMetadataTextLength = 512;

@immutable
class DesktopImagePreviewItemArguments {
  const DesktopImagePreviewItemArguments({
    this.path,
    this.miniThumb,
    this.metadata,
    this.hasMessage = false,
  });

  final String? path;
  final Uint8List? miniThumb;

  /// Media facts for the window's info dialog; null hides the entry.
  final MediaMetadata? metadata;

  /// Whether the opener can jump to this image's message. The message id
  /// itself stays in the opening window, which only accepts an index back.
  final bool hasMessage;

  DesktopImagePreviewItemArguments withPath(String path) =>
      DesktopImagePreviewItemArguments(
        path: path,
        miniThumb: miniThumb,
        metadata: metadata,
        hasMessage: hasMessage,
      );

  Map<String, Object?> toJson() => {
    'path': ?normalizeDesktopImagePath(path),
    if (miniThumb case final bytes?
        when bytes.isNotEmpty && bytes.length <= _maximumMiniThumbBytes)
      'miniThumb': base64Encode(bytes),
    if (metadata case final metadata?) 'metadata': _metadataToJson(metadata),
    if (hasMessage) 'hasMessage': true,
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
    return DesktopImagePreviewItemArguments(
      path: path,
      miniThumb: miniThumb,
      metadata: _metadataFromJson(source['metadata']),
      hasMessage: source['hasMessage'] == true,
    );
  }
}

Map<String, Object?> _metadataToJson(MediaMetadata metadata) => {
  'kind': metadata.kind.name,
  'fileName': ?_boundedText(metadata.fileName),
  'mimeType': ?_boundedText(metadata.mimeType),
  'width': ?metadata.width,
  'height': ?metadata.height,
  'durationSeconds': ?metadata.durationSeconds,
  'sizeBytes': ?metadata.sizeBytes,
  'localPath': ?normalizeDesktopImagePath(metadata.localPath),
};

MediaMetadata? _metadataFromJson(Object? source) {
  if (source is! Map) return null;
  final kind = MediaMetadataKind.values
      .where((kind) => kind.name == source['kind'])
      .firstOrNull;
  if (kind == null) return null;
  int? count(String key) => switch (source[key]) {
    final int value when value >= 0 => value,
    _ => null,
  };
  return MediaMetadata(
    kind: kind,
    fileName: _boundedText(source['fileName']),
    mimeType: _boundedText(source['mimeType']),
    width: count('width'),
    height: count('height'),
    durationSeconds: count('durationSeconds'),
    sizeBytes: count('sizeBytes'),
    localPath: normalizeDesktopImagePath(source['localPath'] as String?),
  );
}

String? _boundedText(Object? source) {
  if (source is! String || source.isEmpty) return null;
  return source.length <= _maximumMetadataTextLength
      ? source
      : source.substring(0, _maximumMetadataTextLength);
}

@immutable
class DesktopImagePreviewWindowArguments {
  const DesktopImagePreviewWindowArguments({
    required this.items,
    required this.title,
    required this.localeTag,
    required this.dark,
    this.startIndex = 0,
    this.canReply = false,
    this.actionSession,
    this.originWindowId,
  });

  final List<DesktopImagePreviewItemArguments> items;
  final String title;
  final String localeTag;
  final bool dark;
  final int startIndex;

  /// Whether items with a message also offer Reply.
  final bool canReply;

  /// Identifies this preview's message actions in [originWindowId], the window
  /// that opened it. Both are null when the preview carries no actions.
  final String? actionSession;
  final int? originWindowId;

  bool get hasMessageActions => actionSession != null && originWindowId != null;

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
      if (canReply) 'canReply': true,
      if (actionSession case final session?
          when isDesktopWindowInstanceId(session) &&
              (originWindowId ?? -1) >= 0) ...{
        'actionSession': session,
        'originWindowId': originWindowId,
      },
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
      final rawSession = decoded['actionSession'];
      final rawOrigin = decoded['originWindowId'];
      final hasActions =
          rawSession is String &&
          isDesktopWindowInstanceId(rawSession) &&
          rawOrigin is int &&
          rawOrigin >= 0;
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
        canReply: decoded['canReply'] == true,
        actionSession: hasActions ? rawSession : null,
        originWindowId: hasActions ? rawOrigin : null,
      );
    } on Object {
      return null;
    }
  }
}

String normalizeDesktopImagePreviewTitle(String? source) =>
    normalizeDesktopWindowTitle(
      source,
      fallback: 'Image preview',
      maxLength: 128,
    );

String normalizeDesktopImagePreviewLocaleTag(String? source) =>
    normalizeDesktopWindowLocaleTag(source?.replaceAll('_', '-'));

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

/// A message action the preview window asks its opener to run.
enum DesktopImagePreviewAction { viewInChat, reply }

/// Runs an action request that arrived from preview window [fromWindowId].
typedef DesktopImagePreviewActionHandler =
    Future<bool> Function(
      int fromWindowId,
      DesktopImagePreviewActionRequest request,
    );

/// What a preview window sends back to its opener: the action, its session and
/// the gallery index. The opener maps the index to a message id it kept.
@immutable
class DesktopImagePreviewActionRequest {
  const DesktopImagePreviewActionRequest({
    required this.session,
    required this.action,
    required this.index,
  });

  final String session;
  final DesktopImagePreviewAction action;
  final int index;

  Map<String, Object?> toJson() => {
    'session': session,
    'action': action.name,
    'index': index,
  };

  static DesktopImagePreviewActionRequest? tryParse(Object? source) {
    if (source is! Map) return null;
    final session = source['session'];
    final index = source['index'];
    final action = DesktopImagePreviewAction.values
        .where((action) => action.name == source['action'])
        .firstOrNull;
    if (session is! String ||
        !isDesktopWindowInstanceId(session) ||
        action == null ||
        index is! int ||
        index < 0 ||
        index >= _maximumGalleryItems) {
      return null;
    }
    return DesktopImagePreviewActionRequest(
      session: session,
      action: action,
      index: index,
    );
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
