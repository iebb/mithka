import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/web_proxy_carrier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('mithka/web_proxy');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final nativeCalls = <MethodCall>[];
  final requests = <(int, Map<String, dynamic>)>[];
  late WebProxyCarriers carriers;

  Future<void> settle() => Future<void>.delayed(Duration.zero);
  Map<String, dynamic> open(int client, int id, {bool temporary = false}) => {
    '@type': 'updateWebProxyCarrierOpened',
    '@client_id': client,
    'carrier': {
      'id': id,
      'url': 'https://relay.example/relay/#private-capability',
      'origin': 'https://relay.example',
      'path_prefix': '/relay/',
      'bridge_object_name': 'TelegramWebProxy',
      'is_temporary': temporary,
    },
  };
  Future<void> native(String method, String key, [Object? message]) async {
    final completed = Completer<void>();
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall(method, {'key': key, 'message': message}),
      ),
      (_) => completed.complete(),
    );
    await completed.future;
  }

  setUp(() {
    nativeCalls.clear();
    requests.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      nativeCalls.add(call);
      return null;
    });
    carriers = WebProxyCarriers(
      (request, client) => requests.add((client, request)),
      channel: channel,
    );
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'temporary and active carriers preserve account identity and message order',
    () async {
      carriers.handle(open(10, 1));
      carriers.handle(open(20, 1, temporary: true));
      await settle();
      await native('message', '10:1', '{"type":"text","data":"hello"}');
      await native('message', '10:1', '{"type":"binary","data":"AAH/"}');
      await native('message', '20:1', '{"type":"text","data":"other"}');
      expect(requests.map((r) => r.$1), [10, 10, 20]);
      expect(requests[0].$2['message'], {
        '@type': 'webProxyCarrierMessageText',
        'text': 'hello',
      });
      expect(requests[1].$2['message'], {
        '@type': 'webProxyCarrierMessageBinary',
        'data': 'AAH/',
      });
      carriers.handle({
        '@type': 'updateWebProxyCarrierData',
        '@client_id': 20,
        'carrier_id': 1,
        'data': 'AQID',
      });
      carriers.handle({
        '@type': 'updateWebProxyCarrierClosed',
        '@client_id': 20,
        'carrier_id': 1,
      });
      await native('message', '20:1', '{"type":"text","data":"too late"}');
      await settle();
      expect(requests, hasLength(3));
      expect(nativeCalls.map((c) => c.method), [
        'open',
        'open',
        'deliver',
        'close',
      ]);
      expect(nativeCalls[2].arguments['key'], '20:1');
      expect(nativeCalls[3].arguments['delay'], 200);
      carriers.closeClient(10);
      await settle();
    },
  );

  test(
    'close waits for creation and destroys silent views immediately',
    () async {
      final opened = Completer<void>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        nativeCalls.add(call);
        if (call.method == 'open') await opened.future;
        return null;
      });
      carriers.handle(open(10, 1));
      carriers.handle({
        '@type': 'updateWebProxyCarrierClosed',
        '@client_id': 10,
        'carrier_id': 1,
      });
      await settle();
      expect(nativeCalls.map((c) => c.method), ['open']);
      opened.complete();
      await settle();
      expect(nativeCalls.map((c) => c.method), ['open', 'close']);
      expect(nativeCalls.last.arguments['delay'], 0);
    },
  );

  test(
    'missing native hosts report unsupported without exposing capabilities',
    () async {
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw MissingPluginException();
      });
      carriers.handle(open(10, 1));
      await settle();
      expect(requests.single.$1, 10);
      expect(requests.single.$2, {
        '@type': 'reportWebProxyCarrierError',
        'carrier_id': 1,
        'error': {'@type': 'webProxyCarrierErrorUnsupported'},
      });
      expect(
        jsonEncode(requests.single.$2),
        isNot(contains('private-capability')),
      );
    },
  );

  test('native errors and invalid messages are reported only once', () async {
    carriers.handle(open(10, 1));
    await settle();
    await native('message', '10:1', '{"type":"invalid","data":"ignored"}');
    await native('error', '10:1');
    expect(requests.single.$2['error'], {
      '@type': 'webProxyCarrierErrorTerminated',
    });
    carriers.closeClient(10);
    await settle();
  });

  test(
    'TDLib consumes carrier updates before UI and desktop broadcasts',
    () async {
      final client = TdClient.forTesting();
      final events = <Map<String, dynamic>>[];
      final sub = client.subscribeAll().listen(events.add);
      client.routeUpdateForTesting(open(10, 1));
      await settle();
      expect(nativeCalls.single.method, 'open');
      expect(events, isEmpty);
      client.routeUpdateForTesting({
        '@type': 'updateWebProxyCarrierClosed',
        '@client_id': 10,
        'carrier_id': 1,
      });
      await settle();
      await sub.cancel();
    },
  );

  test('JavaScript bridge preserves buffers and typed-array slices', () async {
    final result = await Process.run('node', [
      '-e',
      '''
const assert = require('node:assert/strict');
const vm = require('node:vm');
const script = ${jsonEncode(webProxyBridgeScript('https://relay.example', 'TelegramWebProxy'))};
for (const [top, origin] of [[false, "https://relay.example"], [true, "https://other.example"]]) {
  const window = {mithkaWebProxy: {postMessage() { throw new Error("Forbidden bridge"); }}};
  window.top = top ? window : {};
  vm.runInNewContext(script, {window, location: {origin}});
  assert.equal(window.TelegramWebProxy, undefined);
}
global.window = global;
window.top = window;
global.location = {origin: "https://relay.example"};
const messages = [];
global.mithkaWebProxy = {postMessage: v => messages.push(JSON.parse(v))};
${webProxyBridgeScript('https://relay.example', 'TelegramWebProxy')}
const descriptor = Object.getOwnPropertyDescriptor(window, "TelegramWebProxy");
assert.equal(descriptor.writable, false);
assert.equal(descriptor.configurable, false);
assert.equal(Object.getOwnPropertyDescriptor(TelegramWebProxy, "postMessage").writable, false);
TelegramWebProxy.postMessage("hello");
TelegramWebProxy.postMessage(new Uint8Array([99, 0, 1, 255, 99]).subarray(1, 4));
TelegramWebProxy.postMessage(new Uint8Array([3, 4]).buffer);
assert.deepEqual(messages, [
  {type: "text", data: "hello"},
  {type: "binary", data: "AAH/"},
  {type: "binary", data: "AwQ="}
]);
assert.throws(() => TelegramWebProxy.postMessage({}), TypeError);
let received;
TelegramWebProxy.onmessage = event => received = new Uint8Array(event.data);
${webProxyDeliverScript('AAH/')}
assert.deepEqual([...received], [0, 1, 255]);
''',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });
}
