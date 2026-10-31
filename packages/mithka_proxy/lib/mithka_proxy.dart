import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

const _asset = 'package:mithka_proxy/mithka_proxy';

@Native<Int64 Function(Pointer<Utf8>)>(
  symbol: 'mithka_proxy_start',
  assetId: _asset,
)
external int _start(Pointer<Utf8> json);

@Native<Void Function(Uint16)>(symbol: 'mithka_proxy_stop', assetId: _asset)
external void _stop(int id);

@Native<Bool Function(Uint16)>(
  symbol: 'mithka_proxy_is_running',
  assetId: _asset,
  isLeaf: true,
)
external bool _isRunning(int id);

@Native<Void Function(Uint16)>(
  symbol: 'mithka_proxy_set_app_http_port',
  assetId: _asset,
  isLeaf: true,
)
external void _setAppHttpPort(int port);

@Native<Uint16 Function()>(
  symbol: 'mithka_proxy_app_http_port',
  assetId: _asset,
  isLeaf: true,
)
external int _appHttpPort();

/// Error codes returned by the native engine.
enum LeafStartError { invalidConfig, bindFailed, internal, timeout }

final class LeafEngineException implements Exception {
  const LeafEngineException(this.error);
  final LeafStartError error;
  @override
  String toString() => 'LeafEngineException(${error.name})';
}

final class LeafEngine {
  LeafEngine._(this.id, this.socksPort, this.httpPort);

  /// The platforms the build hook produces the engine for.
  static bool get isSupported =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  final int id;
  final int socksPort;
  final int httpPort;
  bool _stopped = false;

  static Future<LeafEngine> start(String outboundsJson) async {
    if (!isSupported) {
      throw UnsupportedError(
        'Encrypted proxies are not built for this platform',
      );
    }
    final code = await Isolate.run(() {
      final input = outboundsJson.toNativeUtf8();
      try {
        return _start(input);
      } finally {
        malloc.free(input);
      }
    });
    if (code < 0) {
      throw LeafEngineException(switch (code) {
        -1 => LeafStartError.invalidConfig,
        -2 => LeafStartError.bindFailed,
        -4 => LeafStartError.timeout,
        _ => LeafStartError.internal,
      });
    }
    return LeafEngine._(code >> 32, (code >> 16) & 65535, code & 65535);
  }

  /// False once the runtime ended, for example after the OS reclaimed its
  /// listening sockets while the app was suspended.
  bool get isRunning => !_stopped && _isRunning(id);

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    final runtimeId = id;
    await Isolate.run(() => _stop(runtimeId));
  }

  /// The HTTP proxy port app traffic uses, shared by every Flutter engine in
  /// this process (desktop windows run their own isolates). Null is direct.
  static int? get appHttpPort {
    if (!isSupported) return null;
    final port = _appHttpPort();
    return port == 0 ? null : port;
  }

  static set appHttpPort(int? port) {
    if (!isSupported) return;
    _setAppHttpPort(port ?? 0);
  }
}

/// Applies to the application's WebViews only. False permits a visible direct
/// browser fallback on old OS/WebView versions; it never changes device routing.
abstract final class LeafWebViewProxy {
  static const _channel = MethodChannel('ad.neko.mithka/proxy');

  /// A child engine can inspect capability without changing the shared store.
  static Future<bool> isSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> configure(int? httpPort) async {
    try {
      return await _channel.invokeMethod<bool>('configure', {
            'port': httpPort,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      // Not proxied: the caller reports the direct fallback.
      return false;
    }
  }
}
