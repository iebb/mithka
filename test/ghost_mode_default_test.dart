import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/config/build_flags.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/ghost_mode_controller.dart';
import 'package:mithka/settings/privacy_security_view.dart';
import 'package:mithka/settings/sensitive_content_controller.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Default-build variant (no `I_DONT_FUCKING_CARE_ABOUT_TOS` define): the
/// enabled-build counterpart lives in ghost_mode_enabled_test.dart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (allowTelegramTosViolations) {
    // This file pins the flag-OFF variant; the enabled counterpart lives in
    // ghost_mode_enabled_test.dart / ghost_mode_story_viewer_enabled_test.dart.
    return;
  }


  final updates = StreamController<Map<String, dynamic>>.broadcast();
  final requests = <Map<String, dynamic>>[];

  setUpAll(() {
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (_) async => <String, dynamic>{'@type': 'ok'},
        send: (request) async => requests.add(request),
        updates: updates.stream,
      ),
    );
  });

  setUp(() {
    requests.clear();
    SharedPreferences.setMockInitialValues({});
  });

  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  test('flag is off in this variant', () {
    expect(allowTelegramTosViolations, isFalse);
  });

  test('ghost queries answer "never block" while the flag is off', () async {
    // Stale persisted state from an opted-in build must not leak effects.
    SharedPreferences.setMockInitialValues({
      'ghost_mode.enabled': true,
      'ghost_mode.chat.-10042': 1,
    });
    GhostModeController.shared.initialize(
      await SharedPreferences.getInstance(),
    );
    addTearDown(() {
      return GhostModeController.shared.setChatException(
        -10042,
        GhostChatException.defaultState,
      );
    });
    addTearDown(() {
      return GhostModeController.shared.setGlobalEnabled(false);
    });

    expect(GhostModeController.shared.globalEnabled, isFalse);
    expect(GhostModeController.shared.shouldBlockRead(-10042).isBlock, isFalse);
    expect(
      GhostModeController.shared.shouldBlockTyping(-10042).isBlock,
      isFalse,
    );
    expect(
      GhostModeController.shared.shouldBlockStories(-10042).isBlock,
      isFalse,
    );
    expect(GhostModeController.shared.shouldShareOnline(), isFalse);
  });

  test('toggling the global switch stays off without the flag', () async {
    GhostModeController.shared.initialize(
      await SharedPreferences.getInstance(),
    );
    await GhostModeController.shared.setGlobalEnabled(true);
    expect(GhostModeController.shared.globalEnabled, isFalse);
    await GhostModeController.shared.setGlobalEnabled(false);
  });

  test(
    'visible messages still issue the force_read viewMessages request',
    () async {
      final viewModel = ChatViewModel(
        chatId: -10042,
        title: 'Group',
        markReadOnOpen: false,
      );
      addTearDown(viewModel.dispose);

      viewModel.markVisibleMessagesViewed([
        ChatMessage(id: 101, text: 'visible', date: 1, isOutgoing: false),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(requests, [
        {
          '@type': 'viewMessages',
          'chat_id': -10042,
          'message_ids': [101],
          'force_read': true,
        },
      ]);
    },
  );

  test('typing still issues the sendChatAction request', () async {
    final viewModel = ChatViewModel(
      chatId: -10042,
      title: 'Group',
      markReadOnOpen: false,
    );
    addTearDown(viewModel.dispose);

    viewModel.sendTyping();
    await Future<void>.delayed(Duration.zero);

    expect(requests.single['@type'], 'sendChatAction');
    expect(requests.single['action']['@type'], 'chatActionTyping');
  });

  testWidgets('privacy screen shows no ghost mode row', (tester) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final theme = ThemeController(await SharedPreferences.getInstance());
    addTearDown(theme.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeController>.value(value: theme),
          ChangeNotifierProvider<SensitiveContentController>.value(
            value: SensitiveContentController.shared,
          ),
        ],
        child: const MaterialApp(
          locale: Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: PrivacySecurityView(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('隐身模式'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
