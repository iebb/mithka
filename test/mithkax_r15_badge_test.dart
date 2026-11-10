//
//  r15: the deleted marker of a ghost bubble rides the meta line.
//  A group ghost's badge sits in the sender header between the name and
//  the time — the badge's vertical center matches the timestamp slot's
//  center. A ghost without a sender header (outgoing / 1:1) carries the
//  badge on its own line ABOVE the bubble.
//

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/message_bubble.dart';
import 'package:mithka/config/build_flags.dart';
import 'package:mithka/history/message_history_models.dart';
import 'package:mithka/history/message_history_settings.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _enabled = allowTelegramTosViolations;

Widget _harness(
  ThemeController theme,
  ChatMessage message, {
  required bool isGroup,
}) => ChangeNotifierProvider<ThemeController>.value(
  value: theme,
  child: MaterialApp(
    theme: ThemeData(extensions: [AppColors.light]),
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: TickerMode(
        enabled: false,
        child: MessageBubble(
          message: message,
          peerTitle: 'Test Group',
          isGroup: isGroup,
        ),
      ),
    ),
  ),
);

ChatMessage _ghost({required bool outgoing, String? senderName}) {
  final message = ChatMessage(
    id: 1,
    isOutgoing: outgoing,
    text: 'kept',
    date: 1700000000,
    chatId: -100,
    senderId: outgoing ? 7 : 42,
    senderName: senderName,
  );
  message.mirrorEntry = MessageHistoryEntry(
    accountUserId: 7,
    chatId: -100,
    messageId: 1,
    senderId: outgoing ? 7 : 42,
    date: 1,
    text: 'kept',
    kindKey: '',
    state: MessageHistoryState.deleted,
    deletedAt: 2,
    events: const [],
  );
  return message;
}

void main() {
  if (!_enabled) return;
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    MessageHistorySettings.shared.initialize(prefs);
    MessageHistorySettings.shared.setBadgeStyle(GhostBadgeStyle.both);
  });

  tearDown(() {
    MessageHistorySettings.shared.setBadgeStyle(GhostBadgeStyle.icon);
  });

  testWidgets('a group ghost badge rides the sender header line', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      _harness(
        theme,
        _ghost(outgoing: false, senderName: 'Alice'),
        isGroup: true,
      ),
    );
    await tester.pumpAndSettle();

    final badge = find.text(AppStrings.t(AppStringKeys.historyDeletedLabel));
    expect(badge, findsOneWidget);
    final badgeRect = tester.getRect(badge);
    final header = find.byKey(const ValueKey('messageSenderHeader-1'));
    expect(header, findsOneWidget);
    final headerRect = tester.getRect(header);
    // The badge sits INSIDE the header's vertical span, on the same line
    // as the name and the time slot.
    expect(badgeRect.center.dy, greaterThanOrEqualTo(headerRect.top));
    expect(badgeRect.center.dy, lessThanOrEqualTo(headerRect.bottom));
  });

  testWidgets('a headerless ghost badge renders above the bubble', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      _harness(theme, _ghost(outgoing: true), isGroup: true),
    );
    await tester.pumpAndSettle();

    final badge = find.text(AppStrings.t(AppStringKeys.historyDeletedLabel));
    expect(badge, findsOneWidget);
    // No sender header on an outgoing message: the badge is its own line,
    // above the translucent bubble (the badge's bottom stays above the
    // message text's top).
    final badgeRect = tester.getRect(badge);
    final body = find.byKey(const ValueKey('messageTapTarget-1'));
    expect(body, findsOneWidget);
    final bodyRect = tester.getRect(body);
    expect(badgeRect.bottom, lessThanOrEqualTo(bodyRect.top + 1));
  });
}
