import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/services.dart';

class LiveCommunicationBridge {
  LiveCommunicationBridge._();

  static final instance = LiveCommunicationBridge._();
  static const _channel = MethodChannel('mithka/live_communication');

  void Function(String uuid, bool muted)? onSystemMuted;
  void Function(String uuid)? onSystemEnded;

  void installHandler() {
    _channel.setMethodCallHandler((call) async {
      final arguments = (call.arguments as Map?)?.cast<String, dynamic>();
      final uuid = arguments?['uuid'] as String?;
      if (uuid == null) return;
      switch (call.method) {
        case 'setMuted':
          onSystemMuted?.call(uuid, arguments?['muted'] as bool? ?? false);
        case 'end':
          onSystemEnded?.call(uuid);
      }
    });
  }

  static String newUuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  Future<void> start({
    required String uuid,
    required String title,
    required bool isVideo,
    required List<String> memberHandles,
  }) async {
    if (!Platform.isIOS) return;
    await _channel.invokeMethod<void>('start', {
      'uuid': uuid,
      'title': title,
      'isVideo': isVideo,
      'members': memberHandles,
    });
  }

  Future<void> connected(String uuid) async {
    if (!Platform.isIOS) return;
    await _channel.invokeMethod<void>('connected', {'uuid': uuid});
  }

  Future<void> setMuted(String uuid, bool muted) async {
    if (!Platform.isIOS) return;
    await _channel.invokeMethod<void>('setMuted', {
      'uuid': uuid,
      'muted': muted,
    });
  }

  Future<void> updateMembers(String uuid, List<String> members) async {
    if (!Platform.isIOS) return;
    await _channel.invokeMethod<void>('updateMembers', {
      'uuid': uuid,
      'members': members,
    });
  }

  Future<void> end(String uuid) async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>('end', {'uuid': uuid});
    } on PlatformException catch (error) {
      // CallKit rejects a second end transaction when its UI already ended the
      // conversation. The app has already stopped media and cleared its local
      // call state, so that idempotency race is safe to ignore.
      if (error.code != 'live_communication_failed') rethrow;
    }
  }
}
