import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screen_capturer/screen_capturer.dart';

import '../chat/outgoing_attachment.dart';

class DesktopClipboardImageReadResult {
  const DesktopClipboardImageReadResult({
    this.attachments = const [],
    this.availableImageCount = 0,
    this.failedImageCount = 0,
  });

  final List<OutgoingAttachment> attachments;
  final int availableImageCount;
  final int failedImageCount;
}

typedef DesktopClipboardAttachmentReader =
    Future<DesktopClipboardImageReadResult> Function(int limit);

class DesktopClipboardImageData {
  const DesktopClipboardImageData({required this.data, required this.mimeType});

  final Uint8List data;
  final String mimeType;
}

/// Reads desktop clipboard images into owned temporary files for the composer.
///
/// Mithka's owned channel exposes every image item when the platform can do so.
/// The existing screen-capturer plugin is the cross-platform fallback for
/// screenshot/image clipboards that expose only one bitmap.
class DesktopClipboardImageService {
  const DesktopClipboardImageService._();

  static const _channel = MethodChannel('mithka/clipboard');

  static Future<DesktopClipboardImageReadResult> readAttachments(
    int limit,
  ) async {
    if (limit <= 0) return const DesktopClipboardImageReadResult();
    var payloads = await _readOwnedChannelImages();
    if (payloads.isEmpty) {
      final fallback = await _readScreenCapturerImage();
      if (fallback != null) payloads = [fallback];
    }
    if (payloads.isEmpty) return const DesktopClipboardImageReadResult();

    return storeImages(payloads, limit: limit);
  }

  static Future<DesktopClipboardImageReadResult> storeImages(
    List<DesktopClipboardImageData> payloads, {
    required int limit,
  }) async {
    if (limit <= 0 || payloads.isEmpty) {
      return const DesktopClipboardImageReadResult();
    }
    final directory = await getTemporaryDirectory();
    await directory.create(recursive: true);
    final selected = payloads.take(limit).toList(growable: false);
    final attachments = <OutgoingAttachment>[];
    var failures = 0;
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    for (var index = 0; index < selected.length; index++) {
      final payload = selected[index];
      final extension = _extensionForMime(payload.mimeType);
      final path =
          '${directory.path}${Platform.pathSeparator}'
          'mithka-clipboard-$timestamp-$index.$extension';
      try {
        final file = File(path);
        await file.writeAsBytes(payload.data, flush: true);
        attachments.add(
          OutgoingAttachment(
            path: path,
            kind: extension == 'gif'
                ? OutgoingAttachmentKind.animation
                : OutgoingAttachmentKind.photo,
            fileName: Uri.file(path).pathSegments.last,
          ),
        );
      } on FileSystemException {
        failures++;
      }
    }

    final resolved = await resolveAttachmentListDimensions(attachments);
    return DesktopClipboardImageReadResult(
      attachments: List.unmodifiable(resolved),
      availableImageCount: payloads.length,
      failedImageCount: failures,
    );
  }

  static Future<List<DesktopClipboardImageData>>
  _readOwnedChannelImages() async {
    try {
      final value = await _channel.invokeMethod<Object?>('readImages');
      if (value is! List) return const [];
      return [
        for (final item in value)
          if (item is Map)
            if (item['data'] case final Uint8List data when data.isNotEmpty)
              DesktopClipboardImageData(
                data: data,
                mimeType: item['mimeType'] is String
                    ? item['mimeType'] as String
                    : 'image/png',
              ),
      ];
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  static Future<DesktopClipboardImageData?> _readScreenCapturerImage() async {
    try {
      final data = await screenCapturer.readImageFromClipboard();
      if (data == null || data.isEmpty) return null;
      return DesktopClipboardImageData(data: data, mimeType: 'image/png');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  static String _extensionForMime(String mimeType) =>
      switch (mimeType.toLowerCase()) {
        'image/jpeg' || 'image/jpg' => 'jpg',
        'image/gif' => 'gif',
        'image/webp' => 'webp',
        'image/heic' => 'heic',
        'image/heif' => 'heif',
        _ => 'png',
      };
}
