//
//  tgcalls_media_engine.dart
//
//  Native Telegram media engine backed by ntgcalls on Android and
//  TgVoipWebrtc on iOS. It marshals the TDLib `callStateReady` payload over a
//  MethodChannel and runs the signaling loop over an EventChannel:
//    • outbound: ntgcalls emits signaling bytes → 'signaling' event → onSignalingData
//      → CallManager relays via TDLib sendCallSignalingData;
//    • inbound: TDLib updateNewCallSignalingData → receiveSignaling() → ntgcalls.
//

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'call_media_engine.dart';

class TgcallsMediaEngine implements CallMediaEngine {
  TgcallsMediaEngine() {
    _events.receiveBroadcastStream().listen(_onEvent, onError: (_) {});
  }

  static const _methods = MethodChannel('mithka/call_media');
  static const _events = EventChannel('mithka/call_media/events');

  void Function(Uint8List data)? _onSignalingData;

  @override
  set onSignalingData(void Function(Uint8List data)? callback) =>
      _onSignalingData = callback;

  void _onEvent(dynamic event) {
    if (event is! Map) return;
    switch (event['type']) {
      case 'signaling':
        final data = event['data'];
        if (data is Uint8List) _onSignalingData?.call(data);
      case 'state':
        debugPrint('📞 [ntgcalls] state=${event['state']}');
    }
  }

  @override
  void start(CallReadyConfig config) {
    _methods
        .invokeMethod('start', {
          'config': {
            'callId': config.callId,
            'isOutgoing': config.isOutgoing,
            'isVideo': config.isVideo,
            'p2pAllowed': config.allowP2p,
            'encryptionKey': config.encryptionKey,
            'libraryVersions': config.libraryVersions,
            'maxLayer': config.maxLayer,
            'serverConfig': config.config,
            'customParameters': config.customParameters,
            'servers': config.servers
                .map(_normalizeServer)
                .whereType<Map<String, dynamic>>()
                .toList(),
          },
        })
        .catchError((Object e) => debugPrint('📞 [ntgcalls] start failed: $e'));
  }

  @override
  void stop() {
    _methods.invokeMethod('stop').catchError((Object _) {});
  }

  @override
  void setMuted(bool muted) {
    _methods.invokeMethod('setMuted', muted).catchError((Object _) {});
  }

  @override
  void setSpeaker(bool speaker) {
    _methods.invokeMethod('setSpeaker', speaker).catchError((Object _) {});
  }

  @override
  void setVideoEnabled(bool enabled, {bool front = true}) {
    _methods
        .invokeMethod('setVideoEnabled', {'enabled': enabled, 'front': front})
        .catchError((Object _) {});
  }

  @override
  void switchCamera() {
    _methods.invokeMethod('switchCamera').catchError((Object _) {});
  }

  @override
  void receiveSignaling(Uint8List data) {
    _methods.invokeMethod('receiveSignaling', data).catchError((Object _) {});
  }

  @override
  Future<Map<String, dynamic>?> queryProtocol() async {
    try {
      final r = await _methods.invokeMethod('getProtocol');
      return (r as Map?)?.cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  /// TDLib `callServer` → the flat shape the native bridges turn into relays.
  /// TDLib JSON encodes int64 (`id`) as a string and bytes (`peer_tag`) as base64.
  static Map<String, dynamic>? _normalizeServer(Map<String, dynamic> s) {
    final rawId = s['id'];
    final id = rawId is String ? int.tryParse(rawId) : (rawId as num?)?.toInt();
    if (id == null) return null;
    final type = (s['type'] as Map?)?.cast<String, dynamic>();
    final base = <String, dynamic>{
      'id': id,
      'ipv4': s['ip_address'] ?? '',
      'ipv6': s['ipv6_address'] ?? '',
      'port': (s['port'] as num?)?.toInt() ?? 0,
    };
    if (type?['@type'] == 'callServerTypeWebrtc') {
      return {
        ...base,
        'username': type?['username'] ?? '',
        'password': type?['password'] ?? '',
        'turn': type?['supports_turn'] ?? false,
        'stun': type?['supports_stun'] ?? false,
        'tcp': false,
        'peerTag': null,
      };
    }
    // callServerTypeTelegramReflector
    Uint8List? peerTag;
    final pt = type?['peer_tag'];
    if (pt is String && pt.isNotEmpty) {
      try {
        peerTag = base64.decode(pt);
      } catch (_) {}
    }
    return {
      ...base,
      'username': '',
      'password': '',
      'turn': true,
      'stun': false,
      'tcp': type?['is_tcp'] ?? false,
      'peerTag': peerTag,
    };
  }
}
