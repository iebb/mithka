import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

const mithkaDesktopVideoWindowType = 'mithka.video';
const _windowProtocolVersion = 1;

/// Serializable startup data passed to an independent video window.
@immutable
class MithkaDesktopVideoWindowArguments {
  const MithkaDesktopVideoWindowArguments({
    required this.uri,
    required this.title,
    required this.width,
    required this.height,
    required this.muted,
    this.windowType = mithkaDesktopVideoWindowType,
  });

  final Uri uri;
  final String title;
  final int? width;
  final int? height;
  final bool muted;

  /// Application-specific discriminator used to distinguish child windows.
  final String windowType;

  String encode() => jsonEncode({
    'version': _windowProtocolVersion,
    'type': windowType,
    'uri': uri.toString(),
    'title': normalizeTitle(title),
    'width': _normalizedDimension(width),
    'height': _normalizedDimension(height),
    'muted': muted,
  });

  static MithkaDesktopVideoWindowArguments? tryParse(
    String source, {
    String windowType = mithkaDesktopVideoWindowType,
  }) {
    if (source.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map) return null;
      final value = Map<String, Object?>.from(decoded);
      if (value['type'] != windowType) return null;

      // Missing versions are accepted for compatibility with 0.1.0 windows.
      final version = value['version'];
      if (version != null && version != _windowProtocolVersion) return null;

      final uriSource = value['uri'];
      if (uriSource is! String || uriSource.trim().isEmpty) return null;
      final uri = Uri.tryParse(uriSource.trim());
      if (uri == null || !uri.hasScheme) return null;

      return MithkaDesktopVideoWindowArguments(
        uri: uri,
        title: normalizeTitle(value['title'] as String?),
        width: _decodeDimension(value['width']),
        height: _decodeDimension(value['height']),
        muted: value['muted'] is bool ? value['muted']! as bool : false,
        windowType: windowType,
      );
    } on Object {
      return null;
    }
  }

  @internal
  static String normalizeTitle(String? title) {
    final normalized = title?.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    if (normalized == null || normalized.isEmpty) return 'Video';
    return normalized;
  }

  static int? _normalizedDimension(int? value) =>
      value != null && value > 0 ? value : null;

  static int? _decodeDimension(Object? value) {
    if (value is! num || !value.isFinite || value <= 0) return null;
    final rounded = value.round();
    return rounded.toDouble() == value.toDouble() ? rounded : null;
  }
}

typedef MithkaDesktopWindowClosed = FutureOr<void> Function();
typedef MithkaDesktopWindowErrorHandler =
    void Function(MithkaDesktopWindowException error, StackTrace stackTrace);

/// A non-fatal error raised by the native desktop-window integration.
@immutable
class MithkaDesktopWindowException implements Exception {
  const MithkaDesktopWindowException(this.operation, this.cause);

  final String operation;
  final Object cause;

  @override
  String toString() => 'MithkaDesktopWindowException($operation): $cause';
}
