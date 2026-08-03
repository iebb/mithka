import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart' show Size, TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/chat_deep_link_controller.dart';
import 'package:mithka/app/desktop_mini_app_window.dart';
import 'package:mithka/app/desktop_mini_app_window_io.dart';
import 'package:mithka/chat/telegram_mini_app_view.dart';

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

  test('authenticated launch data transfers only after account pinning', () {
    final forwarded = launch(accountSlot: 91).toPrimaryOpenJson();
    final accepted = DesktopMiniAppWindowLaunch.tryParsePrimaryOpenJson(
      forwarded,
      accountSlot: 4,
      accountUserId: 4400,
    );

    expect(accepted?.arguments.accountSlot, 4);
    expect(accepted?.arguments.accountUserId, 4400);
    expect(accepted?.url, contains('tgWebAppData=signed-secret'));
    expect(accepted?.keyboardButtonText, 'Open demo');
    expect(
      accepted?.arguments.matchesIpc({
        ...accepted.arguments.toIpcJson(),
        'accountSlot': 91,
        'accountUserId': 9100,
      }),
      isFalse,
    );
  });

  test('cleanup identity is URL-free and pinned to the registered account', () {
    final original = launch(accountSlot: 91, accountUserId: 9100);
    final cleanup = original.arguments.toPrimaryCleanupJson();
    final encodedCleanup = jsonEncode(cleanup);
    final accepted = DesktopMiniAppWindowArguments.tryParsePrimaryCleanupJson(
      cleanup,
      accountSlot: 4,
      accountUserId: 4400,
    );

    expect(encodedCleanup, isNot(contains('https://')));
    expect(encodedCleanup, isNot(contains('tgWebAppData')));
    expect(encodedCleanup, isNot(contains('signed-secret')));
    expect(encodedCleanup, isNot(contains('keyboardButtonText')));
    expect(accepted?.accountSlot, 4);
    expect(accepted?.accountUserId, 4400);
    expect(accepted?.instanceId, original.arguments.instanceId);
    expect(accepted?.launchId, original.arguments.launchId);
  });

  test('primary-chat IPC is presentation-only and account-bound', () {
    const request = ChatDeepLinkRequest(
      chatId: -10042,
      title: 'Linked chat',
      messageId: 77,
      accountSlot: 91,
      accountUserId: 9100,
    );
    final payload = request.toDesktopIpcJson();
    const binding = DesktopMiniAppAccountBinding(
      accountSlot: 2,
      accountUserId: 4200,
      clientId: 11,
    );

    expect(payload, {
      'chatId': -10042,
      'title': 'Linked chat',
      'messageId': 77,
    });
    expect(payload, isNot(contains('accountSlot')));
    expect(payload, isNot(contains('accountUserId')));
    expect(arguments().matchesIpc(arguments().toIpcJson()), isTrue);
    expect(
      arguments().matchesIpc({
        ...arguments().toIpcJson(),
        'accountUserId': 4300,
      }),
      isFalse,
    );
    expect(
      binding.matchesCurrent(currentClientId: 11, currentAccountUserId: 4200),
      isTrue,
    );
    expect(
      binding.matchesCurrent(currentClientId: 11, currentAccountUserId: 4300),
      isFalse,
    );
  });

  test('primary rejection cleanup claims close exactly once', () {
    final lifecycle = DesktopMiniAppLaunchLifecycle();
    final rejected = arguments();

    expect(lifecycle.cancel(rejected), isTrue);
    expect(lifecycle.isCancelled(rejected), isTrue);
    expect(lifecycle.cancel(rejected), isFalse);
    expect(lifecycle.claimClose(rejected), isFalse);
  });

  test('timeout cleanup prevents a late open from closing twice', () {
    final lifecycle = DesktopMiniAppLaunchLifecycle();
    final timedOut = arguments(instanceId: 'timed_out_launch');

    expect(lifecycle.cancel(timedOut), isTrue);
    expect(lifecycle.isCancelled(timedOut), isTrue);
    expect(lifecycle.isClosed(timedOut), isTrue);
    expect(lifecycle.claimClose(timedOut), isFalse);
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

  test('startup parser rejects malformed and secret-bearing payloads', () {
    expect(DesktopMiniAppWindowArguments.tryParse(''), isNull);
    expect(DesktopMiniAppWindowArguments.tryParse('not json'), isNull);
    expect(
      DesktopMiniAppWindowArguments.tryParse(
        '{"version":1,"type":"mithka.mini-app",'
        '"instanceId":"bad id","accountSlot":0}',
      ),
      isNull,
    );

    final secretBearing = jsonDecode(arguments().encode()) as Map;
    secretBearing['url'] = 'https://mini.example/?tgWebAppData=secret';
    expect(
      DesktopMiniAppWindowArguments.tryParse(jsonEncode(secretBearing)),
      isNull,
    );
  });

  test('registry keeps repeated same-bot launches independent', () {
    final registry = DesktopMiniAppWindowRegistry();
    final first = launch();
    final second = launch(instanceId: 'mini_app_2');

    registry.register(10, first);
    registry.register(11, second);

    expect(registry.launchFor(10), same(first));
    expect(registry.launchFor(11), same(second));
    expect(registry.remove(10), same(first));
    expect(registry.remove(10), isNull);
    expect(registry.launchFor(11), same(second));
  });

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

  test('native window uses fixed macOS dimensions and system chrome', () {
    final options = desktopMiniAppWindowOptions(arguments());

    expect(options.size, const Size(460, 720));
    expect(options.minimumSize, const Size(360, 500));
    expect(options.title, 'Demo Mini App');
  });

  test('transparent WebView background is skipped only on macOS', () {
    expect(
      telegramMiniAppShouldSetWebViewBackgroundColor(TargetPlatform.macOS),
      isFalse,
    );
    for (final platform in [
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.linux,
      TargetPlatform.windows,
    ]) {
      expect(
        telegramMiniAppShouldSetWebViewBackgroundColor(platform),
        isTrue,
        reason: platform.name,
      );
    }
  });

  test('macOS launch path is native, account-pinned, and non-persistent', () {
    final io = File(
      'lib/app/desktop_mini_app_window_io.dart',
    ).readAsStringSync();
    final app = File(
      'lib/app/desktop_mini_app_window_app.dart',
    ).readAsStringSync();
    final miniApp = File(
      'lib/chat/telegram_mini_app_view.dart',
    ).readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();
    final launcher = File(
      'lib/app/primary_chat_launcher.dart',
    ).readAsStringSync();

    expect(io, contains('MultiWindowManager.createWindow(['));
    expect(io, isNot(contains('createWindowOrReuse')));
    expect(io, contains('arguments.encode()'));
    expect(io, contains("invokeMethodToWindow(0, _openMethod"));
    expect(io, contains("invokeMethodToWindow(0, _cleanupMethod"));
    expect(io, contains("invokeMethodToWindow(0, _openPrimaryChatMethod"));
    expect(io, contains('ChatDeepLinkRequest.tryParseDesktopIpc'));
    expect(io, contains('ChatDeepLinkController.shared.openChat'));
    expect(io, contains('_requestPrimaryCleanup'));
    expect(io, contains('DesktopMiniAppLaunchLifecycle'));
    expect(io, isNot(contains('_closeUnhandedChildLaunch')));
    expect(io, contains('registeredDesktopChatWindowAccountIdentity'));
    expect(io, contains('registeredDesktopUtilityWindowAccountIdentity'));
    expect(io, contains('_pinArgumentsToCurrentAccount'));
    expect(io, contains('if (pinnedLaunch == null) return false;'));
    expect(
      io,
      contains('return account?.accountUserId == null ? null : account'),
    );
    expect(io, contains('final binding = _bindingFor(arguments);'));
    expect(
      io,
      contains('case _connectMethod:\n        final binding = _bindingFor('),
    );
    expect(io, contains('_closeStaleWindow(fromWindowId)'));
    expect(io, contains('closeStaleAccountWindows'));
    expect(
      RegExp(r'_verifyAccountBinding\(binding\)').allMatches(io).length,
      greaterThanOrEqualTo(3),
    );
    expect(io, contains(".queryTo(request, binding.clientId)"));
    expect(io, contains('sendTo(request, binding.clientId)'));
    expect(io, contains('arguments.accountUserId != binding.accountUserId'));
    expect(io, contains('accountSlot: account.accountSlot'));
    expect(io, contains('accountUserId: arguments.accountUserId'));
    expect(io, contains('TdClient.shared.queryTo(request, binding.clientId)'));
    expect(io, isNot(contains('debugPrint(launch')));
    expect(io, isNot(contains('debugPrint(arguments')));
    expect(
      launcher,
      contains('DesktopMiniAppWindowService.instance.openChatInPrimaryWindow'),
    );
    expect(app, contains('closeTdLaunchOnDispose: false'));
    expect(
      app,
      contains('initialAccountUserId: widget.launch.arguments.accountUserId'),
    );
    expect(
      app,
      contains(
        'onClose: DesktopMiniAppWindowService.instance.closeCurrentWindow',
      ),
    );
    expect(main, contains('tryParseLaunchArguments(arguments)'));
    expect(main, contains('configureChildProxy(miniAppArguments)'));
    expect(
      main,
      contains(
        'DesktopMiniAppWindowService.instance.notifyAccountIdentityChanged()',
      ),
    );
    expect(miniApp, contains('if (Platform.isMacOS)'));
    expect(miniApp, contains('showGeneralDialog<void>('));
    expect(
      miniApp.indexOf('if (Platform.isMacOS)'),
      lessThan(miniApp.indexOf('showGeneralDialog<void>(')),
    );
  });
}
