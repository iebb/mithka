import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../chat/outgoing_attachment.dart';

/// The data Android provides for an ACTION_SEND or ACTION_SEND_MULTIPLE
/// launch. Provider URIs stay native; Dart receives private cache paths only
/// after [copyFiles] has completed.
@immutable
class AndroidShareIntentPayload {
  const AndroidShareIntentPayload({
    required this.id,
    required this.text,
    required this.mimeType,
    required this.uris,
  });

  factory AndroidShareIntentPayload.fromMap(Map<dynamic, dynamic> value) {
    final uris = [
      for (final item
          in value['uris'] is List ? value['uris'] as List : const [])
        if (item is String && item.trim().isNotEmpty) item,
    ];
    final text = value['text'] is String ? value['text'] as String : '';
    final mimeType = value['mimeType'] is String
        ? (value['mimeType'] as String).trim()
        : '';
    final fallbackId = '$mimeType\n$text\n${uris.join('\n')}';
    return AndroidShareIntentPayload(
      id: value['id'] is String && (value['id'] as String).isNotEmpty
          ? value['id'] as String
          : fallbackId,
      text: text,
      mimeType: mimeType,
      uris: List.unmodifiable(uris),
    );
  }

  final String id;
  final String text;
  final String mimeType;
  final List<String> uris;

  bool get hasContent => text.trim().isNotEmpty || uris.isNotEmpty;
}

@immutable
class AndroidSharedFile {
  const AndroidSharedFile({
    required this.path,
    required this.fileName,
    required this.mimeType,
  });

  factory AndroidSharedFile.fromMap(Map<dynamic, dynamic> value) {
    return AndroidSharedFile(
      path: value['path'] is String ? value['path'] as String : '',
      fileName: value['fileName'] is String ? value['fileName'] as String : '',
      mimeType: value['mimeType'] is String
          ? (value['mimeType'] as String).trim()
          : 'application/octet-stream',
    );
  }

  final String path;
  final String fileName;
  final String mimeType;

  bool get isUsable => path.isNotEmpty;

  OutgoingAttachmentKind get attachmentKind {
    final mime = mimeType.toLowerCase();
    if (mime == 'image/gif') return OutgoingAttachmentKind.animation;
    if (mime.startsWith('image/')) return OutgoingAttachmentKind.photo;
    if (mime.startsWith('video/')) return OutgoingAttachmentKind.video;
    if (mime.startsWith('audio/')) return OutgoingAttachmentKind.audio;
    return OutgoingAttachmentKind.document;
  }
}

/// Android's share target bridge. It deliberately owns only intent parsing and
/// temporary-file lifecycle; the UI remains the same chat picker and media
/// preview used for content shared from inside Mithka.
class AndroidShareIntentController extends ChangeNotifier {
  AndroidShareIntentController._();

  static final shared = AndroidShareIntentController._();

  static const _channel = MethodChannel('mithka/share_intent');
  bool _started = false;
  AndroidShareIntentPayload? _pending;
  final List<AndroidShareIntentPayload> _queued = <AndroidShareIntentPayload>[];
  final Set<String> _seenIds = <String>{};

  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get hasPending => _pending != null;

  Future<void> start() async {
    if (!supported || _started) return;
    _started = true;
    _channel.setMethodCallHandler(_handleNativeCall);
    try {
      final initial = await _channel.invokeMethod<dynamic>('initial');
      if (initial is Map) _enqueue(AndroidShareIntentPayload.fromMap(initial));
    } on PlatformException {
      // A share target can be started while Flutter is still attaching its
      // engine. The native side keeps the payload for the next initial call.
    }
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method != 'share' || call.arguments is! Map) return;
    _enqueue(AndroidShareIntentPayload.fromMap(call.arguments as Map));
  }

  void _enqueue(AndroidShareIntentPayload payload) {
    if (!payload.hasContent || !_seenIds.add(payload.id)) return;
    if (_seenIds.length > 32) _seenIds.remove(_seenIds.first);
    if (_pending == null) {
      _pending = payload;
    } else {
      _queued.add(payload);
    }
    notifyListeners();
  }

  AndroidShareIntentPayload? takePending() {
    final payload = _pending;
    if (payload == null) return null;
    _pending = _queued.isEmpty ? null : _queued.removeAt(0);
    notifyListeners();
    return payload;
  }

  Future<List<AndroidSharedFile>> copyFiles(Iterable<String> uris) async {
    if (!supported) return const [];
    try {
      final raw = await _channel.invokeMethod<dynamic>(
        'copyFiles',
        uris.toList(growable: false),
      );
      if (raw is! List) return const [];
      return [
        for (final value in raw)
          if (value is Map)
            AndroidSharedFile.fromMap(value)
          else
            const AndroidSharedFile(
              path: '',
              fileName: '',
              mimeType: 'application/octet-stream',
            ),
      ].where((file) => file.isUsable).toList(growable: false);
    } on PlatformException {
      return const [];
    }
  }

  Future<void> deleteFiles(Iterable<String> paths) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('deleteFiles', paths.toList());
    } on PlatformException {
      // Cache cleanup is best effort; native code rejects paths outside its
      // own cache directory even if a caller supplies one accidentally.
    }
  }
}
