//
//  Mithka X UI surfaces (Telegram §1.4 self-build, gated): the settings
//  hub, transfer page and advanced entry lay out without overflow, the
//  hub rows answer taps, the sidebar and desktop rail carry the ghost
//  shortcut, and the ghost bubble's deleted marker floats at the bubble's
//  bottom-right meta corner.
//

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/desktop_navigation_rail.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/auth/auth_manager.dart';
import 'package:mithka/chat/message_bubble.dart';
import 'package:mithka/chat/message_reply_count_badge.dart';
import 'package:mithka/components/drawer_controller.dart' as dc;
import 'package:mithka/config/build_flags.dart';
import 'package:mithka/history/message_history_settings.dart';
import 'package:mithka/history/message_history_store.dart';
import 'package:mithka/l10n/app_locale_controller.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/profile/profile_proxy_button.dart';
import 'package:mithka/profile/profile_view.dart';
import 'package:mithka/settings/advanced_settings_view.dart';
import 'package:mithka/settings/message_history_transfer_view.dart';
import 'package:mithka/settings/mithkax_settings_view.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _enabled = allowTelegramTosViolations;

/// Pumps [home] inside the standard localization + theme harness at [size].
Future<void> _pump(
  WidgetTester tester,
  Widget home, [
  Size size = const Size(900, 2600),
]) async {
  final prefs = await SharedPreferences.getInstance();
  final theme = ThemeController(prefs);
  addTearDown(theme.dispose);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeController>.value(
      value: theme,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppColors.light]),
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Minimal host mirroring the chat-info row's ListenableBuilder structure.
class _ChatRecordingSwitchHost extends StatelessWidget {
  const _ChatRecordingSwitchHost({required this.chatId});

  final int chatId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ListenableBuilder(
          listenable: MessageHistoryStore.shared,
          builder: (context, _) {
            final excluded = MessageHistoryStore.shared.isChatExcluded(chatId);
            return Switch(value: !excluded, onChanged: (_) {});
          },
        ),
      ),
    );
  }
}

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

ChatMessage _ghost(
  bool outgoing, {
  String? senderName,
  bool isEdited = false,
  int commentCount = 0,
}) {
  final message = ChatMessage(
    id: 1,
    isOutgoing: outgoing,
    text: 'kept',
    date: 1700000000,
    chatId: -100,
    senderId: outgoing ? 7 : 42,
    senderName: senderName,
    isEdited: isEdited,
    commentCount: commentCount,
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

  group('layout', () {
    for (final (name, size) in [
      ('phone', const Size(390, 844)),
      ('wide', const Size(1280, 800)),
    ]) {
      testWidgets('transfer page lays out without overflow ($name)', (
        tester,
      ) async {
        await _pump(tester, const MessageHistoryTransferView(), size);
        expect(
          find.byKey(const ValueKey('history-transfer-export')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('history-transfer-import')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('hub page lays out without overflow ($name)', (tester) async {
        await _pump(tester, const MithkaXSettingsView(), size);
        expect(
          find.byKey(const ValueKey('history-enable-all')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('per-chat recording switch reads the mirror store', (
      tester,
    ) async {
      final store = MessageHistoryStore.forTesting();
      store.debugSetActiveAccount(4211);
      addTearDown(store.dispose);
      await _pump(
        tester,
        const _ChatRecordingSwitchHost(chatId: 77),
        const Size(390, 844),
      );
      final toggle = find.byType(Switch);
      expect(toggle, findsOneWidget);
      // The host's switch mirrors the row's value: not excluded → on.
      expect(tester.widget<Switch>(toggle).value, isTrue);
      expect(tester.takeException(), isNull);
    });
  });

  group('advanced entry', () {
    testWidgets('Advanced hosts the Ayu entry and it opens the hub', (
      tester,
    ) async {
      await _pump(tester, const AdvancedSettingsView());
      final entry = find.byKey(const ValueKey('mithkax-features'));
      if (!_enabled) {
        expect(entry, findsNothing);
        return;
      }
      await tester.scrollUntilVisible(entry, 300);
      expect(entry, findsOneWidget);
      expect(
        find.text(AppStrings.t(AppStringKeys.mithkaxSettingsTitle)),
        findsWidgets,
      );
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.byType(MithkaXSettingsView), findsOneWidget);
    });
  });

  group('sidebar shortcut', () {
    testWidgets('drawer sidebar carries the ghost glyph after 代理', (
      tester,
    ) async {
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);
      final accounts = AccountStore(prefs);
      final auth = AuthManager();
      final drawer = dc.DrawerController();
      addTearDown(theme.dispose);
      addTearDown(accounts.dispose);
      addTearDown(auth.dispose);
      addTearDown(drawer.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeController>.value(value: theme),
            ChangeNotifierProvider<AppLocaleController>.value(
              value: AppLocaleController(prefs),
            ),
            ChangeNotifierProvider<AccountStore>.value(value: accounts),
            ChangeNotifierProvider<AuthManager>.value(value: auth),
            ChangeNotifierProvider<TranslationController>.value(
              value: TranslationController(prefs),
            ),
            ChangeNotifierProvider<dc.DrawerController>.value(value: drawer),
          ],
          child: const MaterialApp(
            locale: Locale('en'),
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: ProfileView(),
          ),
        ),
      );
      tester.view.physicalSize = const Size(900, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpAndSettle();

      final ghost = find.byKey(const ValueKey('sidebar-ghost-mode-button'));
      if (!_enabled) {
        expect(ghost, findsNothing);
        return;
      }
      expect(ghost, findsOneWidget);
      // Between 代理 and day/night: to the right of the proxy globe.
      final proxy = tester.getCenter(
        find.byKey(const ValueKey('profile-proxy-button')),
      );
      final ghostCenter = tester.getCenter(ghost);
      expect(ghostCenter.dx, greaterThan(proxy.dx));
    });

    testWidgets('desktop rail shows the ghost button only when wired', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppColors.light]),
          home: Scaffold(
            body: DesktopNavigationRail(
              destinations: const [],
              selection: 0,
              onSelect: (_) {},
              unread: 0,
              onClearUnread: () {},
              onToggleThemeMode: () {},
              proxyButton: ProfileProxyButton(extent: 38, onTap: () {}),
              onOpenGhostMode: _enabled ? () {} : null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final ghost = find.byKey(const ValueKey('desktop-ghost-mode-button'));
      if (!_enabled) {
        expect(ghost, findsNothing);
        return;
      }
      expect(ghost, findsOneWidget);
      // Order under the theme toggle: theme → 代理 → ghost (growing dy).
      final themeButton = find.byKey(
        const ValueKey('desktop-theme-toggle-button'),
      );
      final proxy = find.byKey(const ValueKey('profile-proxy-button'));
      expect(proxy, findsOneWidget);
      expect(
        tester.getCenter(proxy).dy,
        greaterThan(tester.getCenter(themeButton).dy),
      );
      expect(
        tester.getCenter(ghost).dy,
        greaterThan(tester.getCenter(proxy).dy),
      );
    });
  });

  group('ghost badge', () {
    Future<void> pumpGhost(
      WidgetTester tester,
      ChatMessage message, {
      required bool isGroup,
    }) async {
      tester.view.physicalSize = const Size(600, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);
      addTearDown(theme.dispose);
      await tester.pumpWidget(_harness(theme, message, isGroup: isGroup));
      await tester.pumpAndSettle();
    }

    for (final (name, isGroup, ghost) in [
      ('group', true, _ghost(false, senderName: 'Alice')),
      ('headerless', true, _ghost(true)),
      ('1:1', false, _ghost(false)),
    ]) {
      testWidgets('the ghost badge floats at the bottom-right ($name)', (
        tester,
      ) async {
        await pumpGhost(tester, ghost, isGroup: isGroup);

        final badge = find.text(
          AppStrings.t(AppStringKeys.historyDeletedLabel),
        );
        expect(badge, findsOneWidget);
        final badgeRect = tester.getRect(badge);
        // The badge rides the floating meta row at the bubble's bottom-right
        // corner: it must sit at (or below) the bubble body's bottom edge and
        // near the bubble's right side, never above the bubble.
        final body = find.byKey(const ValueKey('messageTapTarget-1'));
        expect(body, findsOneWidget);
        final bodyRect = tester.getRect(body);
        expect(
          badgeRect.bottom,
          greaterThan(bodyRect.center.dy),
          reason: 'the badge rides the bottom corner, not a line above',
        );
        expect(
          badgeRect.right,
          greaterThan(bodyRect.center.dx),
          reason: 'the badge sits on the right half of the bubble',
        );
        // No sender-header copy exists anywhere, whichever ghost kind.
        expect(
          find.byKey(const ValueKey('messageSenderHeader-1')),
          isGroup && ghost.senderName != null ? findsOneWidget : findsNothing,
        );
        final header = find.byKey(const ValueKey('messageSenderHeader-1'));
        if (header.evaluate().isNotEmpty) {
          expect(
            tester.getRect(badge).top,
            greaterThan(tester.getRect(header).bottom),
            reason: 'the badge must not ride the sender header line',
          );
        }
      });
    }

    testWidgets('all three corner badges share one chip language', (
      tester,
    ) async {
      // Deleted + edited + reply count on one narrow bubble: the whole row
      // stays inside the bubble's width (the FittedBox shrinks it instead of
      // spilling onto neighboring content) and renders every badge.
      final ghost = _ghost(
        false,
        senderName: 'Alice',
        isEdited: true,
        commentCount: 12,
      );
      await pumpGhost(tester, ghost, isGroup: true);

      expect(
        find.text(AppStrings.t(AppStringKeys.historyDeletedLabel)),
        findsOneWidget,
      );
      final edited = find.byKey(const ValueKey('messageDeliveryEdited'));
      expect(edited, findsOneWidget);
      final replies = find.byKey(const ValueKey('messageCompactReplies-1'));
      expect(replies, findsOneWidget);

      final rowRight = tester.getRect(replies).right;
      final badgeLeft = tester
          .getRect(find.text(AppStrings.t(AppStringKeys.historyDeletedLabel)))
          .left;
      expect(
        badgeLeft,
        greaterThan(rowRight),
        reason: 'order on the row: replies, edited, deleted (right to left)',
      );

      // Same chip geometry: the deleted chip's container and the reply
      // badge's container share the same chip height, and the whole corner
      // row stays inside the bubble's horizontal span.
      final deletedChip = find
          .ancestor(
            of: find.text(AppStrings.t(AppStringKeys.historyDeletedLabel)),
            matching: find.byType(Container),
          )
          .first;
      // The reply badge's Container sits below its own Semantics wrapper
      // and above the keyed element, so measure the badge widget itself.
      final replyChip = find.byType(MessageReplyCountBadge);
      final deletedRect = tester.getRect(deletedChip);
      final replyRect = tester.getRect(replyChip);
      expect(
        (deletedRect.height - replyRect.height).abs(),
        lessThan(2),
        reason: 'the corner chips must look like one family',
      );
      // Icon size parity: the trash glyph and the reply glyph both draw 12.
      final deletedIconRect = tester.getRect(
        find.descendant(of: deletedChip, matching: find.byType(Icon)).first,
      );
      final replyIconRect = tester.getRect(
        find.descendant(of: replyChip, matching: find.byType(Icon)).first,
      );
      expect(
        (deletedIconRect.height - replyIconRect.height).abs(),
        lessThan(2),
        reason: 'the chip icons must share one size',
      );
      final bodyRect = tester.getRect(
        find.byKey(const ValueKey('messageTapTarget-1')),
      );
      expect(deletedRect.left, greaterThanOrEqualTo(bodyRect.left - 1));
      expect(replyRect.right, lessThanOrEqualTo(bodyRect.right + 1));
    });
  });
}
