import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
