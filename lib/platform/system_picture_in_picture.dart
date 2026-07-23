import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

enum _PictureInPictureBackend { activeFvpPlayer, nativePlatform }

class SystemPictureInPicture {
  SystemPictureInPicture._();

  static const MethodChannel _channel = MethodChannel(
    'mithka/system_picture_in_picture',
  );
  static const MethodChannel _activePlayerChannel = MethodChannel(
    'mithka/fvp_picture_in_picture',
  );
  static final Map<String, Future<void> Function()> _cleanupById = {};
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
    Future<void> Function()? onStop,
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
    Future<void> Function()? onStop,
  }) async {
    if (!isSupportedPlatform) return false;
    _attachHandler();
    if (onStop != null) _cleanupById[id] = onStop;
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
        _cleanupById.remove(id);
      }
      return prepared;
    } catch (_) {
      _cleanupById.remove(id);
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
    _cleanupById.remove(id);
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
    _channel.setMethodCallHandler(_handleNativeCallback);
    _activePlayerChannel.setMethodCallHandler(_handleNativeCallback);
  }

  static Future<void> _handleNativeCallback(MethodCall call) async {
    if (call.method != 'didStop') return;
    final args = call.arguments as Map?;
    final id = args?['id'] as String?;
    if (id == null) return;
    final cleanup = _cleanupById.remove(id);
    if (cleanup != null) await cleanup();
    _backendById.remove(id);
  }
}
