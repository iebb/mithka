import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef SystemPictureInPictureStopped =
    FutureOr<void> Function(Duration? finalPosition);
typedef SystemPictureInPictureRestoreRequested =
    FutureOr<bool> Function(SystemPictureInPictureSnapshot snapshot);

@immutable
final class SystemPictureInPictureSnapshot {
  const SystemPictureInPictureSnapshot({
    required this.position,
    required this.playing,
    required this.speed,
    required this.muted,
  });

  final Duration position;
  final bool playing;
  final double speed;
  final bool muted;
}

final class _SystemPictureInPictureSession {
  _SystemPictureInPictureSession({this.onStop, this.onRestoreRequested});

  final SystemPictureInPictureStopped? onStop;
  final SystemPictureInPictureRestoreRequested? onRestoreRequested;
  bool restoreAttempted = false;
  bool stopping = false;
}

enum _PictureInPictureBackend { activeFvpPlayer, nativePlatform }

class SystemPictureInPicture {
  SystemPictureInPicture._();

  static const MethodChannel _channel = MethodChannel(
    'mithka/system_picture_in_picture',
  );
  static const MethodChannel _activePlayerChannel = MethodChannel(
    'mithka/fvp_picture_in_picture',
  );
  static final Map<String, _SystemPictureInPictureSession> _sessionsById = {};
  static final Map<String, _PictureInPictureBackend> _backendById = {};
  static bool _handlerAttached = false;

  static bool get isSupportedPlatform => Platform.isIOS || Platform.isAndroid;

  /// Android PiP hosts the existing Activity, including its Flutter texture.
  /// iOS instead transfers playback to AVPictureInPictureController.
  static bool get keepsFlutterPlayerInActivity => Platform.isAndroid;

  static Future<bool> isSupported() async {
    if (!isSupportedPlatform) return false;
    _attachHandler();
    try {
      final supported =
          await _activePlayerChannel.invokeMethod<bool>('isSupported') ?? false;
      if (supported) return true;
    } catch (_) {}
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> start({
    required String id,
    required Uri uri,
    required Duration position,
    required double speed,
    required bool muted,
    required bool playing,
    required Size videoSize,
    int? playerId,
    SystemPictureInPictureStopped? onStop,
    SystemPictureInPictureRestoreRequested? onRestoreRequested,
  }) async {
    if (!isSupportedPlatform) return false;
    final prepared = await prepare(
      id: id,
      uri: uri,
      position: position,
      speed: speed,
      muted: muted,
      playing: playing,
      videoSize: videoSize,
      playerId: playerId,
      onStop: onStop,
      onRestoreRequested: onRestoreRequested,
    );
    if (!prepared) return false;
    final started = await startPrepared(
      id: id,
      position: position,
      speed: speed,
      muted: muted,
      playing: playing,
      videoSize: videoSize,
    );
    if (!started) {
      await cancelPrepared(id);
      return false;
    }
    return true;
  }

  static Future<bool> prepare({
    required String id,
    required Uri uri,
    required Duration position,
    required double speed,
    required bool muted,
    required bool playing,
    required Size videoSize,
    int? playerId,
    SystemPictureInPictureStopped? onStop,
    SystemPictureInPictureRestoreRequested? onRestoreRequested,
  }) async {
    if (!isSupportedPlatform) return false;
    _attachHandler();
    _sessionsById[id] = _SystemPictureInPictureSession(
      onStop: onStop,
      onRestoreRequested: onRestoreRequested,
    );
    if (playerId != null) {
      try {
        final prepared =
            await _activePlayerChannel.invokeMethod<bool>('prepare', {
              'id': id,
              'playerId': playerId,
              'positionMs': position.inMilliseconds,
              'speed': speed,
              'muted': muted,
              'playing': playing,
              'width': videoSize.width,
              'height': videoSize.height,
            }) ??
            false;
        if (prepared) {
          _backendById[id] = _PictureInPictureBackend.activeFvpPlayer;
          return true;
        }
      } catch (_) {}
    }
    try {
      final prepared =
          await _channel.invokeMethod<bool>('prepare', {
            'id': id,
            'url': uri.toString(),
            'positionMs': position.inMilliseconds,
            'speed': speed,
            'muted': muted,
            'playing': playing,
            'width': videoSize.width,
            'height': videoSize.height,
          }) ??
          false;
      if (prepared) {
        _backendById[id] = _PictureInPictureBackend.nativePlatform;
      } else {
        _sessionsById.remove(id);
      }
      return prepared;
    } catch (_) {
      _sessionsById.remove(id);
      return false;
    }
  }

  static Future<bool> startPrepared({
    required String id,
    required Duration position,
    required double speed,
    required bool muted,
    required bool playing,
    required Size videoSize,
  }) async {
    if (!isSupportedPlatform) return false;
    _attachHandler();
    final channel = _backendById[id] == _PictureInPictureBackend.activeFvpPlayer
        ? _activePlayerChannel
        : _channel;
    try {
      return await channel.invokeMethod<bool>('startPrepared', {
            'id': id,
            'positionMs': position.inMilliseconds,
            'speed': speed,
            'muted': muted,
            'playing': playing,
            'width': videoSize.width,
            'height': videoSize.height,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> updatePrepared({
    required String id,
    required Duration position,
    required double speed,
    required bool muted,
    required bool playing,
    required Size videoSize,
  }) async {
    if (!isSupportedPlatform) return;
    _attachHandler();
    final channel = _backendById[id] == _PictureInPictureBackend.activeFvpPlayer
        ? _activePlayerChannel
        : _channel;
    try {
      await channel.invokeMethod<void>('update', {
        'id': id,
        'positionMs': position.inMilliseconds,
        'speed': speed,
        'muted': muted,
        'playing': playing,
        'width': videoSize.width,
        'height': videoSize.height,
      });
    } catch (_) {}
  }

  static Future<void> cancelPrepared(String id) async {
    if (!isSupportedPlatform) return;
    final backend = _backendById.remove(id);
    _sessionsById.remove(id);
    _attachHandler();
    final channel = backend == _PictureInPictureBackend.activeFvpPlayer
        ? _activePlayerChannel
        : _channel;
    try {
      await channel.invokeMethod<void>('cancel', {'id': id});
    } catch (_) {}
  }

  static Future<void> stop() async {
    if (!isSupportedPlatform) return;
    _attachHandler();
    try {
      await _activePlayerChannel.invokeMethod<void>('stop');
    } catch (_) {}
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
  }

  static bool usesActivePlayer(String id) =>
      _backendById[id] == _PictureInPictureBackend.activeFvpPlayer;

  static void _attachHandler() {
    if (_handlerAttached) return;
    _handlerAttached = true;
    _channel.setMethodCallHandler(
      (call) => _handleNativeCallback(
        call,
        sourceBackend: _PictureInPictureBackend.nativePlatform,
      ),
    );
    _activePlayerChannel.setMethodCallHandler(
      (call) => _handleNativeCallback(
        call,
        sourceBackend: _PictureInPictureBackend.activeFvpPlayer,
      ),
    );
  }

  static Future<Object?> _handleNativeCallback(
    MethodCall call, {
    _PictureInPictureBackend? sourceBackend,
  }) async {
    final args = call.arguments as Map?;
    final id = args?['id'] as String?;
    if (id == null) {
      return call.method == 'restoreRequested' ? false : null;
    }
    final registeredBackend = _backendById[id];
    if (sourceBackend != null &&
        registeredBackend != null &&
        registeredBackend != sourceBackend) {
      return call.method == 'restoreRequested' ? false : null;
    }
    final position = _positionFromArguments(args);
    switch (call.method) {
      case 'restoreRequested':
        final session = _sessionsById[id];
        final callback = session?.onRestoreRequested;
        if (session == null ||
            callback == null ||
            session.restoreAttempted ||
            session.stopping) {
          return false;
        }
        session.restoreAttempted = true;
        try {
          return await Future<bool>.value(
            callback(_snapshotFromArguments(args)),
          );
        } catch (_) {
          return false;
        }
      case 'didStop':
        final session = _sessionsById[id];
        if (session == null || session.stopping) return null;
        session.stopping = true;
        try {
          await Future<void>.value(session.onStop?.call(position));
        } catch (_) {}
        if (identical(_sessionsById[id], session)) {
          _sessionsById.remove(id);
          _backendById.remove(id);
        }
      default:
        return null;
    }
    return null;
  }

  static Duration? _positionFromArguments(Map<dynamic, dynamic>? arguments) {
    final value = arguments?['positionMs'];
    if (value is! num || !value.isFinite || value < 0) return null;
    return Duration(milliseconds: value.round());
  }

  static SystemPictureInPictureSnapshot _snapshotFromArguments(
    Map<dynamic, dynamic>? arguments,
  ) {
    final rawSpeed = arguments?['speed'];
    final speed = rawSpeed is num && rawSpeed.isFinite && rawSpeed > 0
        ? rawSpeed.toDouble()
        : 1.0;
    return SystemPictureInPictureSnapshot(
      position: _positionFromArguments(arguments) ?? Duration.zero,
      playing: arguments?['playing'] is bool
          ? arguments!['playing'] as bool
          : true,
      speed: speed,
      muted: arguments?['muted'] is bool ? arguments!['muted'] as bool : false,
    );
  }

  @visibleForTesting
  static void debugRegisterSession({
    required String id,
    bool? usesActivePlayer,
    SystemPictureInPictureStopped? onStop,
    SystemPictureInPictureRestoreRequested? onRestoreRequested,
  }) {
    _sessionsById[id] = _SystemPictureInPictureSession(
      onStop: onStop,
      onRestoreRequested: onRestoreRequested,
    );
    if (usesActivePlayer != null) {
      _backendById[id] = usesActivePlayer
          ? _PictureInPictureBackend.activeFvpPlayer
          : _PictureInPictureBackend.nativePlatform;
    }
  }

  @visibleForTesting
  static Future<Object?> debugHandleNativeCallback(
    MethodCall call, {
    bool? fromActivePlayer,
  }) => _handleNativeCallback(
    call,
    sourceBackend: fromActivePlayer == null
        ? null
        : fromActivePlayer
        ? _PictureInPictureBackend.activeFvpPlayer
        : _PictureInPictureBackend.nativePlatform,
  );

  @visibleForTesting
  static void debugClearSessions() {
    _sessionsById.clear();
    _backendById.clear();
  }
}
