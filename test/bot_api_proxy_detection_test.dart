import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/tdlib/td_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamController<Map<String, dynamic>> updates;
  late Map<String, dynamic> response;
  late Map<String, dynamic> request;

  setUpAll(() {
    updates = StreamController<Map<String, dynamic>>.broadcast();
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 7,
        query: (value) async {
          request = value;
          return response;
        },
        send: (_) async {},
        updates: updates.stream,
      ),
    );
  });

  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  test('detached desktop window detects a Bot API account', () async {
    response = const {'@type': 'botApiAccountInfo'};

    expect(await TdClient.shared.activeAccountUsesBotApi(), isTrue);
  });

  test(
    'detached desktop window treats TDLib error as a user account',
    () async {
      response = const {
        '@type': 'error',
        'code': 400,
        'message': 'Unknown function',
      };

      expect(await TdClient.shared.activeAccountUsesBotApi(), isFalse);
    },
  );

  test('detached settings read the global Bot API endpoint', () async {
    response = const {
      '@type': 'botApiEndpointConfiguration',
      'endpoint': 'https://bots.example.test/telegram',
    };

    expect(
      await TdClient.shared.configuredBotApiEndpoint(),
      Uri.parse('https://bots.example.test/telegram'),
    );
    expect(request['@type'], 'getBotApiEndpointConfiguration');
  });

  test(
    'detached settings normalize the global endpoint before saving',
    () async {
      response = const {
        '@type': 'botApiEndpointConfiguration',
        'endpoint': 'https://bots.example.test/telegram',
      };

      expect(
        await TdClient.shared.setBotApiEndpoint(
          'https://bots.example.test/telegram/',
        ),
        Uri.parse('https://bots.example.test/telegram'),
      );
      expect(request, {
        '@type': 'setBotApiEndpointConfiguration',
        'endpoint': 'https://bots.example.test/telegram',
      });
    },
  );
}
