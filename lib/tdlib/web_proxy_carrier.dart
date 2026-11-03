import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import 'json_helpers.dart';

typedef WebProxySend =
    void Function(Map<String, dynamic> request, int clientId);

/// Owns transport WebViews for every TDLib account, including login clients.
/// Carrier updates are consumed before public UI/desktop IPC broadcasts because
/// the relay URL contains a capability and must never escape this transport.
final class WebProxyCarriers {
  WebProxyCarriers(this.send, {MethodChannel? channel})
    : channel = channel ?? const MethodChannel('mithka/web_proxy') {
    this.channel.setMethodCallHandler(_onNativeCall);
  }

  final WebProxySend send;
  final MethodChannel channel;
  final Map<String, _Carrier> _carriers = {};

  bool handle(Map<String, dynamic> update) {
    final type = update.type;
    if (type != 'updateWebProxyCarrierOpened' &&
        type != 'updateWebProxyCarrierData' &&
        type != 'updateWebProxyCarrierClosed') {
      return false;
    }
    final client = update.integer('@client_id') ?? 0;
    final details = update.obj('carrier');
    final id = details?.integer('id') ?? update.integer('carrier_id') ?? 0;
    final key = '$client:$id';
    if (type == 'updateWebProxyCarrierOpened' && details != null) {
      final carrier = _Carrier(client, id);
      _carriers[key] = carrier;
      _enqueue(key, carrier, () async {
        await channel.invokeMethod<void>('open', {
          'key': key,
          'url': details.str('url'),
          'origin': details.str('origin'),
          'pathPrefix': details.str('path_prefix'),
          'script': webProxyBridgeScript(
            details.str('origin') ?? '',
            details.str('bridge_object_name') ?? '',
          ),
        });
      });
    } else {
      final carrier = _carriers[key];
      if (carrier == null) return true;
      if (type == 'updateWebProxyCarrierData') {
        _enqueue(key, carrier, () async {
          await channel.invokeMethod<void>('deliver', {
            'key': key,
            'script': webProxyDeliverScript(update.str('data') ?? ''),
          });
        });
      } else {
        _carriers.remove(key);
        unawaited(_close(key, carrier));
      }
    }
    return true;
  }

  void closeClient(int clientId) {
    for (final entry in _carriers.entries.toList()) {
      if (entry.value.clientId != clientId) continue;
      _carriers.remove(entry.key);
      unawaited(_close(entry.key, entry.value));
    }
  }

  void _enqueue(
    String key,
    _Carrier carrier,
    Future<void> Function() operation,
  ) {
    carrier.pending = carrier.pending
        .then((_) async {
          if (!carrier.failed) await operation();
        })
        .catchError((Object error) {
          _fail(
            key,
            carrier,
            error is MissingPluginException ||
                    (error is PlatformException &&
                        error.code == 'unsupported_carrier')
                ? 'Unsupported'
                : 'Terminated',
          );
        });
  }

  void _fail(String key, _Carrier carrier, String kind) {
    if (!identical(_carriers[key], carrier) || carrier.failed) return;
    carrier.failed = true;
    send({
      '@type': 'reportWebProxyCarrierError',
      'carrier_id': carrier.id,
      'error': {
        '@type': 'webProxyCarrierError$kind',
        if (kind == 'LoadFailed') 'message': 'Web proxy relay failed to load',
      },
    }, carrier.clientId);
  }

  Future<void> _onNativeCall(MethodCall call) async {
    final args = Map<String, dynamic>.from(call.arguments as Map);
    final key = args['key'] as String;
    final carrier = _carriers[key];
    if (carrier == null || carrier.failed) return;
    if (call.method == 'error') {
      _fail(
        key,
        carrier,
        args['terminated'] == true ? 'Terminated' : 'LoadFailed',
      );
      return;
    }
    if (call.method != 'message') return;
    try {
      final message = jsonDecode(args['message'] as String) as Map;
      if (message['type'] != 'binary' && message['type'] != 'text') {
        throw const FormatException('Invalid relay message');
      }
      final binary = message['type'] == 'binary';
      final data = message['data'] as String;
      if (binary) base64Decode(data);
      carrier.sentMessage = true;
      send({
        '@type': 'processWebProxyCarrierMessage',
        'carrier_id': carrier.id,
        'message': {
          '@type': binary
              ? 'webProxyCarrierMessageBinary'
              : 'webProxyCarrierMessageText',
          binary ? 'data' : 'text': data,
        },
      }, carrier.clientId);
    } catch (_) {
      _fail(key, carrier, 'Terminated');
    }
  }

  Future<void> _close(String key, _Carrier carrier) async {
    await carrier.pending;
    try {
      await channel.invokeMethod<void>('close', {
        'key': key,
        'script': carrier.sentMessage
            ? 'window.TelegramWebProxy?.onmessage?.({data:\'{"t":"close"}\'});'
            : '',
        'delay': carrier.sentMessage ? 200 : 0,
      });
    } catch (_) {
      // Closing a missing/terminated platform view is already complete.
    }
  }
}

final class _Carrier {
  _Carrier(this.clientId, this.id);
  final int clientId;
  final int id;
  Future<void> pending = Future<void>.value();
  bool sentMessage = false;
  bool failed = false;
}

/// Native hosts expose only a private string channel. This adapter preserves
/// typed-array offsets and supplies TDLib's read-only, top-frame-only bridge.
String webProxyBridgeScript(String origin, String name) =>
    '''
(() => {
  if (window !== window.top || location.origin !== ${jsonEncode(origin)} ||
      ${jsonEncode(name)} !== "TelegramWebProxy") return;
  const native = window.webkit?.messageHandlers?.mithkaWebProxy
    || window.mithkaWebProxy;
  const post = native.postMessage.bind(native);
  const bridge = {onmessage: null};
  Object.defineProperty(bridge, "postMessage", {value(value) {
    if (typeof value === "string") {
      post(JSON.stringify({type: "text", data: value}));
      return;
    }
    let bytes;
    if (value instanceof ArrayBuffer) bytes = new Uint8Array(value);
    else if (ArrayBuffer.isView(value))
      bytes = new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
    else throw new TypeError("Expected a string or binary buffer");
    let binary = "";
    for (let i = 0; i < bytes.length; i += 8192)
      binary += String.fromCharCode(...bytes.subarray(i, i + 8192));
    post(JSON.stringify({type: "binary", data: btoa(binary)}));
  }});
  Object.defineProperty(window, "TelegramWebProxy", {value: bridge});
})();
''';

String webProxyDeliverScript(String data) =>
    '''
(() => {
  const bytes = Uint8Array.from(atob(${jsonEncode(data)}), c => c.charCodeAt(0));
  const bridge = window.TelegramWebProxy;
  if (typeof bridge?.onmessage !== "function") throw new Error("No relay receiver");
  bridge.onmessage({data: bytes.buffer});
})();
''';
