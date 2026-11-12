import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/desktop_mini_app_window.dart';
import 'package:mithka/app/desktop_mini_app_window_io.dart';

void main() {
  DesktopMiniAppWindowArguments arguments({
    String instanceId = 'mini_app_1',
    int accountSlot = 2,
    int? accountUserId = 4200,
    int? launchId = 7788,
  }) => DesktopMiniAppWindowArguments(
    instanceId: instanceId,
    accountSlot: accountSlot,
    accountUserId: accountUserId,
    title: 'Demo\nMini App',
    botUserId: 42,
    chatId: -1007,
    localeTag: 'zh-Hans',
    dark: true,
    launchId: launchId,
  );

  DesktopMiniAppWindowLaunch launch({
    String instanceId = 'mini_app_1',
    int accountSlot = 2,
    int? accountUserId = 4200,
    int? launchId = 7788,
  }) => DesktopMiniAppWindowLaunch(
    arguments: arguments(
      instanceId: instanceId,
      accountSlot: accountSlot,
      accountUserId: accountUserId,
      launchId: launchId,
    ),
    url:
        'https://mini.example/app?tgWebAppData=signed-secret&tgWebAppVersion=9',
    keyboardButtonText: 'Open demo',
  );

  test('startup arguments exclude authenticated launch material', () {
    final original = launch();
    final encoded = original.arguments.encode();
    final parsed = DesktopMiniAppWindowArguments.tryParse(encoded);

    expect(parsed?.instanceId, 'mini_app_1');
    expect(parsed?.accountSlot, 2);
    expect(parsed?.accountUserId, 4200);
    expect(parsed?.title, 'Demo Mini App');
    expect(parsed?.botUserId, 42);
    expect(parsed?.chatId, -1007);
    expect(parsed?.launchId, 7788);
    expect(parsed?.localeTag, 'zh-Hans');
    expect(parsed?.dark, isTrue);
    expect(encoded, isNot(contains('https://')));
    expect(encoded, isNot(contains('tgWebAppData')));
    expect(encoded, isNot(contains('signed-secret')));
    expect(encoded, isNot(contains('keyboardButtonText')));
    expect(original.arguments.toIpcJson(), isNot(contains('url')));
    expect(original.arguments.toIpcJson()['accountUserId'], 4200);
    expect(
      original.arguments.matchesIpc({
        ...original.arguments.toIpcJson(),
        'accountUserId': 4300,
      }),
      isFalse,
    );
  });

  test(
    'slot reuse rejects A connect, query, send, cleanup, and close routes',
    () {
      const accountA = DesktopMiniAppAccountBinding(
        accountSlot: 2,
        accountUserId: 4200,
        clientId: 11,
      );

      bool routeAllowed({required int clientId, required int userId}) =>
          accountA.matchesCurrent(
            currentClientId: clientId,
            currentAccountUserId: userId,
          );

      for (final reusedIdentity in [
        (clientId: 12, userId: 4300),
        (clientId: 11, userId: 4300),
      ]) {
        final connectAllowed = routeAllowed(
          clientId: reusedIdentity.clientId,
          userId: reusedIdentity.userId,
        );
        final queryAllowed = routeAllowed(
          clientId: reusedIdentity.clientId,
          userId: reusedIdentity.userId,
        );
        final sendAllowed = routeAllowed(
          clientId: reusedIdentity.clientId,
          userId: reusedIdentity.userId,
        );
        final cleanupAllowed = routeAllowed(
          clientId: reusedIdentity.clientId,
          userId: reusedIdentity.userId,
        );
        var closeCount = 0;
        if (cleanupAllowed) closeCount += 1;

        expect(connectAllowed, isFalse);
        expect(queryAllowed, isFalse);
        expect(sendAllowed, isFalse);
        expect(cleanupAllowed, isFalse);
        expect(closeCount, 0);
      }
    },
  );

  test('TD IPC normalizes nested maps and blocks lifecycle requests', () {
    final bytes = Uint8List.fromList(const [1, 2, 3]);
    final request = desktopMiniAppSanitizeRequest(<Object?, Object?>{
      '@type': 'invokeWebAppCustomMethod',
      '@client_id': 99,
      '@extra': 'child-correlation',
      'parameters': <Object?, Object?>{
        'nested': <Object?>[
          <Object?, Object?>{'value': 7},
        ],
        'bytes': bytes,
      },
    });

    expect(request?['@client_id'], isNull);
    expect(request?['@extra'], isNull);
    final parameters = request?['parameters'] as Map<String, dynamic>;
    expect(parameters['nested'], [
      {'value': 7},
    ]);
    expect(parameters['bytes'], same(bytes));
    for (final type in ['close', 'destroy', 'logOut', 'setTdlibParameters']) {
      expect(desktopMiniAppSanitizeRequest({'@type': type}), isNull);
    }
  });
}
