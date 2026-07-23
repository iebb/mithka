import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/communities/community_models.dart';
import 'package:mithka/communities/community_view.dart';
import 'package:mithka/components/photo_avatar.dart';
import 'package:mithka/components/ui_components.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/feature_settings_view.dart';
import 'package:mithka/settings/safety_notice_controller.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Telegram Communities', () {
    test('parses access and administrator chat-list rights', () {
      final community = CommunitySummary.fromTd({
        '@type': 'community',
        'id': '42',
        'have_access': true,
        'name': 'Formula Paddock',
        'status': {
          '@type': 'communityMemberStatusAdministrator',
          'rights': {
            '@type': 'communityAdministratorRights',
            'can_edit_chat_list': true,
          },
        },
        'permissions': {
          '@type': 'communityPermissions',
          'can_edit_chat_list': false,
        },
      });

      expect(community.id, 42);
      expect(community.name, 'Formula Paddock');
      expect(community.haveAccess, isTrue);
      expect(community.isAdministrator, isTrue);
      expect(community.canEditChatList, isTrue);
      expect(community.collapsed, isTrue);
    });

    test('collapses linked chats at the first chat position', () {
      final first = _chat(id: 1, title: 'News', order: 300, unread: 2);
      final unrelated = _chat(id: 2, title: 'Direct', order: 200);
      final second = _chat(
        id: 3,
        title: 'Discussion',
        order: 100,
        markedUnread: true,
      );
      final community = CommunitySummary(
        id: 42,
        name: 'Formula Paddock',
        haveAccess: true,
        isAdministrator: false,
        canEditChatList: true,
      );

      final entries = CommunityChatListProjection.build(
        chats: [first, unrelated, second],
        communityByChat: const {1: 42, 3: 42},
        communities: {42: community},
      );

      expect(entries, hasLength(2));
      final grouped = entries.first as CommunityGroupEntry;
      expect(grouped.chats, [first, second]);
      expect(grouped.latestChat, same(first));
      expect(grouped.unreadCount, 2);
      expect(grouped.showsUnreadIndicator, isTrue);
      expect((entries.last as CommunityChatEntry).chat, same(unrelated));
    });

    test('shows individual chats when one-chat mode is disabled', () {
      final first = _chat(id: 1, title: 'News', order: 200);
      final second = _chat(id: 2, title: 'Discussion', order: 100);
      final community = CommunitySummary(
        id: 42,
        name: 'Formula Paddock',
        haveAccess: true,
        isAdministrator: false,
        canEditChatList: false,
        collapsed: false,
      );

      final entries = CommunityChatListProjection.build(
        chats: [first, second],
        communityByChat: const {1: 42, 2: 42},
        communities: {42: community},
      );

      expect(entries, everyElement(isA<CommunityChatEntry>()));
      expect(entries, hasLength(2));
    });

    test('global disable keeps every community chat as a normal row', () {
      final first = _chat(id: 1, title: 'News', order: 200);
      final second = _chat(id: 2, title: 'Discussion', order: 100);
      final community = CommunitySummary(
        id: 42,
        name: 'Formula Paddock',
        haveAccess: true,
        isAdministrator: false,
        canEditChatList: false,
      );

      final entries = CommunityChatListProjection.build(
        chats: [first, second],
        communityByChat: const {1: 42, 2: 42},
        communities: {42: community},
        communitiesEnabled: false,
      );

      expect(entries, everyElement(isA<CommunityChatEntry>()));
      expect(entries, hasLength(2));
    });

    test('requests the native community peer catalog', () {
      expect(communityFullInfoRequest(42), {
        '@type': 'getCommunityFullInfo',
        'community_id': 42,
      });
    });

    test('global community preference defaults on and persists', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);

      expect(theme.communitiesEnabled, isTrue);
      theme.communitiesEnabled = false;
      expect(theme.communitiesEnabled, isFalse);
      expect(prefs.getBool('communitiesEnabled'), isFalse);

      theme.dispose();
      final restored = ThemeController(prefs);
      addTearDown(restored.dispose);
      expect(restored.communitiesEnabled, isFalse);
    });

    test('recognizes community membership service messages', () {
      final added = {'@type': 'messageChatAddedToCommunity'};
      final removed = {'@type': 'messageChatRemovedFromCommunity'};

      expect(TDParse.isServiceContent(added['@type']), isTrue);
      expect(TDParse.isServiceContent(removed['@type']), isTrue);
      expect(
        TDParse.serviceText(added),
        AppStrings.t(AppStringKeys.communityChatAddedService),
      );
      expect(
        TDParse.serviceText(removed),
        AppStrings.t(AppStringKeys.communityChatRemovedService),
      );
    });

    testWidgets('renders the iOS-style hub and toggles one-chat mode', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);
      addTearDown(theme.dispose);
      final community = CommunitySummary(
        id: 42,
        name: 'Formula Paddock',
        haveAccess: true,
        isAdministrator: false,
        canEditChatList: true,
      );
      bool? collapsed;

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
            home: CommunityView(
              community: community,
              chats: [_chat(id: 1, title: 'Race Chat', order: 100)],
              viewableChats: [
                _chat(id: 2, title: 'Public Announcements', order: 90),
              ],
              onCollapsedChanged: (value) => collapsed = value,
              showBackButton: false,
            ),
          ),
        ),
      );

      expect(find.text('Community'), findsOneWidget);
      expect(find.text('Formula Paddock'), findsOneWidget);
      expect(find.text('Race Chat'), findsOneWidget);
      expect(find.text('CHATS YOU CAN VIEW'), findsOneWidget);
      expect(find.text('Public Announcements'), findsOneWidget);
      expect(find.text('Show as One Chat'), findsOneWidget);

      final header = find.byKey(const ValueKey('community-header'));
      final avatar = find.descendant(
        of: header,
        matching: find.byType(PhotoAvatar),
      );
      final title = find.text('Formula Paddock');
      final count = find.text('2 chats');
      expect(tester.getSize(header).height, 92);
      expect(tester.getSize(avatar), const Size.square(64));
      expect(tester.getTopLeft(title).dx, tester.getTopLeft(count).dx);
      expect(
        tester.getTopLeft(title).dx,
        greaterThan(tester.getTopRight(avatar).dx),
      );

      await tester.tap(find.byType(AppSwitch));
      await tester.pump();

      expect(collapsed, isFalse);
    });

    testWidgets('feature settings exposes the global community switch', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);
      final safety = SafetyNoticeController(prefs);
      addTearDown(theme.dispose);
      addTearDown(safety.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeController>.value(value: theme),
            ChangeNotifierProvider<SafetyNoticeController>.value(value: safety),
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
            home: FeatureSettingsView(),
          ),
        ),
      );

      expect(theme.communitiesEnabled, isTrue);
      await tester.ensureVisible(find.text('Enable Communities'));
      await tester.tap(find.text('Enable Communities'));
      await tester.pump();
      expect(theme.communitiesEnabled, isFalse);
    });
  });
}

ChatSummary _chat({
  required int id,
  required String title,
  required int order,
  int unread = 0,
  bool markedUnread = false,
}) {
  return ChatSummary(
    id: id,
    title: title,
    lastMessage: 'Latest message',
    lastMessageId: id * 10,
    date: order,
    unreadCount: unread,
    order: order,
    isMuted: false,
    isMarkedUnread: markedUnread,
    kind: ChatKind.group,
  );
}
