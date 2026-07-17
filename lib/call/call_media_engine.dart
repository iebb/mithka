//
//  call_media_engine.dart
//
//  Abstraction over the real-time media transport for a 1:1 call. TDLib handles
//  signaling (call setup, key exchange, emoji verification) and hands us a
//  `callStateReady` payload; the media engine is what actually carries audio /
//  video over the negotiated relay servers using the agreed encryption key.
//
//  TDLib itself does NOT ship a media engine. Android and iOS use
//  `TgcallsMediaEngine` through their native Telegram-call bridges;
//  `NoopCallMediaEngine` remains the fallback on unsupported platforms.
//

import 'package:flutter/foundation.dart';

/// Everything a media engine needs to bring up a call, distilled from TDLib's
/// `callStateReady`. Built by `CallManager` and passed to `engine.start`.
class CallReadyConfig {
  CallReadyConfig({
    required this.callId,
    required this.servers,
    required this.encryptionKey,
    required this.config,
    required this.customParameters,
    required this.libraryVersions,
    required this.maxLayer,
    required this.isOutgoing,
    required this.isVideo,
    required this.allowP2p,
  });

  /// TDLib call id — used as the ntgcalls per-call handle.
  final int callId;
  final List<Map<String, dynamic>> servers;
  final Uint8List encryptionKey;
  final String config;
  final String customParameters;
  final List<String> libraryVersions;
  final int maxLayer;
  final bool isOutgoing;
  final bool isVideo;
  final bool allowP2p;
}

/// The media transport for an active call. A real implementation owns the
/// audio session, the WebRTC peer connection, and the camera/mic capture.
abstract class CallMediaEngine {
  void start(CallReadyConfig config);
  void stop();
  void setMuted(bool muted);
  void setSpeaker(bool speaker);

  /// Enable/disable our outgoing camera. When enabling, [front] selects the
  /// front- or back-facing lens.
  void setVideoEnabled(bool enabled, {bool front = true});

  /// Flip between the front- and back-facing camera during a video call. No-op
  /// for engines without camera control.
  void switchCamera() {}

  /// Inbound TDLib `updateNewCallSignalingData` bytes → fed to the engine so the
  /// WebRTC handshake can complete. No-op for engines that don't signal.
  void receiveSignaling(Uint8List data) {}

  /// Outbound signaling the engine emits, to be relayed via TDLib
  /// `sendCallSignalingData`. `CallManager` sets this before `start`.
  set onSignalingData(void Function(Uint8List data)? callback) {}

  /// The media engine's own supported call protocol ({min, max, versions}),
  /// advertised in createCall so TDLib negotiates a version the engine handles.
  /// Null = engine has no opinion (use defaults).
  Future<Map<String, dynamic>?> queryProtocol() async => null;
}

/// A do-nothing media engine that only logs. Lets the call signaling flow run
/// end to end without any audio transport (used where no native engine exists).
class NoopCallMediaEngine implements CallMediaEngine {
  @override
  void start(CallReadyConfig config) {
    debugPrint(
      '📞 [media] start outgoing=${config.isOutgoing} '
      'video=${config.isVideo} servers=${config.servers.length} '
      'keyBytes=${config.encryptionKey.length} '
      'versions=${config.libraryVersions.join(",")}',
    );
  }

  @override
  void stop() => debugPrint('📞 [media] stop');

  @override
  void setMuted(bool muted) => debugPrint('📞 [media] setMuted $muted');

  @override
  void setSpeaker(bool speaker) => debugPrint('📞 [media] setSpeaker $speaker');

  @override
  void setVideoEnabled(bool enabled, {bool front = true}) =>
      debugPrint('📞 [media] setVideoEnabled $enabled front=$front');

  @override
  void switchCamera() => debugPrint('📞 [media] switchCamera');

  @override
  void receiveSignaling(Uint8List data) {}

  @override
  set onSignalingData(void Function(Uint8List data)? callback) {}

  @override
  Future<Map<String, dynamic>?> queryProtocol() async => null;
}
