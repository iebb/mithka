import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_list_view.dart';
import 'package:mithka/chats/chat_row_view.dart';
import 'package:mithka/communities/community_view.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/components/photo_avatar.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final updates = StreamController<Map<String, dynamic>>.broadcast();

  setUpAll(() {
    // Drive the real chat list without touching a Telegram account.
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        send: (_) async {},
        updates: updates.stream,
        query: (request) async => switch (request['@type']) {
          'getMe' => {'@type': 'user', 'id': 1, 'first_name': 'Test'},
          'getChats' => {'@type': 'chats', 'chat_ids': <int>[]},
          'getSupergroup' => {
            '@type': 'supergroup',
            'id': 9,
            'status': {'@type': 'chatMemberStatusMember'},
          },
          'getSupergroupFullInfo' => {
            '@type': 'supergroupFullInfo',
            'community_id': 7,
          },
          'getCommunityFullInfo' => {'@type': 'communityFullInfo'},
          _ => {'@type': 'ok'},
        },
      ),
    );
  });

  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
    testWidgets(
      'the corner badge keeps the row tap for the chat on $platform',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final theme = ThemeController(await SharedPreferences.getInstance());
        addTearDown(theme.dispose);
        var hubTaps = 0;
        var rowTaps = 0;

        await tester.pumpWidget(
          ChangeNotifierProvider<ThemeController>.value(
            value: theme,
            child: MaterialApp(
              theme: ThemeData(
                brightness: Brightness.light,
                extensions: [AppColors.light],
              ),
              home: Scaffold(
                body: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => rowTaps++,
                  child: ChatRowView(
                    chat: _chat(id: 42, title: 'Race Chat'),
                    avatarBadge: CommunityAvatarBadge(onTap: () => hubTaps++),
                  ),
                ),
              ),
            ),
          ),
        );

        final badge = find.byKey(const ValueKey('community-avatar-badge'));
        final plate = find.byKey(
          const ValueKey('community-avatar-badge-plate'),
        );
        expect(badge, findsOneWidget);
        final avatar = tester.getRect(find.byType(PhotoAvatar));
        final plateRect = tester.getRect(plate);
        expect(plateRect.width, AppMetric.communityBadgeSize());
        expect(plateRect.bottomRight, avatar.bottomRight);
        // The extra tap room grows towards the avatar's centre: slop hanging off
        // the avatar would fall outside its stack and hit the row instead.
        final hitRect = tester.getRect(badge);
        expect(hitRect.bottomRight, avatar.bottomRight);
        expect(
          hitRect.width,
          AppMetric.communityBadgeSize() + CommunityAvatarBadge.hitSlop,
        );
        expect(
          tester
              .widget<AppIcon>(
                find.descendant(of: plate, matching: find.byType(AppIcon)),
              )
              .icon,
          HeroAppIcons.objectGroup,
        );

        await tester.tap(badge);
        await tester.pump();
        expect(hubTaps, 1);
        expect(rowTaps, 0);

        await tester.tap(find.text('Race Chat'));
        await tester.pump();
        expect(rowTaps, 1);
        expect(hubTaps, 1);
      },
      variant: TargetPlatformVariant({platform}),
    );
  }

  testWidgets('community badge respects a light accent foreground', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final theme = ThemeController(await SharedPreferences.getInstance());
    addTearDown(theme.dispose);
    final oldBrand = AppTheme.brand;
    final oldForeground = AppTheme.onBrand;
    AppTheme.applyBrand(
      const Color(0xFFFDFDFD),
      onAccent: const Color(0xFF1A1A1A),
    );
    addTearDown(() => AppTheme.applyBrand(oldBrand, onAccent: oldForeground));

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          theme: ThemeData(extensions: [AppColors.light]),
          home: Center(child: CommunityAvatarBadge(onTap: () {})),
        ),
      ),
    );

    final icon = tester.widget<AppIcon>(find.byType(AppIcon));
    expect(icon.color, AppTheme.onBrand);
    final plate = tester.widget<Container>(
      find.byKey(const ValueKey('community-avatar-badge-plate')),
    );
    final background = (plate.decoration! as BoxDecoration).color!;
    final contrast =
        (background.computeLuminance() + 0.05) /
        (icon.color!.computeLuminance() + 0.05);
    expect(contrast, greaterThanOrEqualTo(3));
  });

  for (final folded in [false, true]) {
    testWidgets('member chat rows reach the hub (folded: $folded)', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(
        folded ? {'mithka.community.0.7.collapsed': true} : <String, Object>{},
      );
      final theme = ThemeController(await SharedPreferences.getInstance());
      addTearDown(theme.dispose);
      final hubOpens = <int>[];
      final chatOpens = <int>[];

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [AppLocalizations.delegate],
            supportedLocales: AppLocalizations.supportedLocales,
            theme: ThemeData(extensions: [AppColors.light]),
            home: Scaffold(
              body: ChatListView(
                onChatSelected: (selection) => chatOpens.add(selection.chatId),
                onCommunitySelected: (selection) =>
                    hubOpens.add(selection.community.id),
              ),
            ),
          ),
        ),
      );

      updates.add({
        '@type': 'updateCommunity',
        'community': {
          '@type': 'community',
          'id': 7,
          'name': 'Formula Paddock',
          'have_access': true,
          'status': {'@type': 'communityMemberStatusMember'},
          'permissions': {
            '@type': 'communityPermissions',
            'can_edit_chat_list': false,
          },
        },
      });
      updates.add({'@type': 'updateNewChat', 'chat': _communityChat()});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump();

      final badge = find.byKey(const ValueKey('community-avatar-badge'));
      if (folded) {
        // The community owns the row, so its members are not rendered and the
        // row itself is the entry point.
        expect(find.text('Race Chat'), findsNothing);
        expect(badge, findsNothing);
        await tester.tap(find.text('Formula Paddock'));
      } else {
        expect(find.text('Race Chat'), findsOneWidget);
        expect(find.text('Formula Paddock'), findsNothing);
        expect(badge, findsOneWidget);
        await tester.tap(badge);
      }
      await tester.pump();
      expect(hubOpens, [7]);
      expect(chatOpens, isEmpty);

      if (!folded) {
        // The badge only takes its own corner; the rest of the row still opens
        // the conversation.
        await tester.tap(find.text('Race Chat'));
        await tester.pump();
        expect(chatOpens, [42]);
        expect(hubOpens, [7]);
      }
      // The model warms its caches on deferred timers the binding still
      // accounts for once the tree is gone.
      await tester.pump(const Duration(seconds: 6));
    });
  }
}

Map<String, dynamic> _communityChat() => {
  '@type': 'chat',
  'id': 42,
  'title': 'Race Chat',
  'type': {
    '@type': 'chatTypeSupergroup',
    'supergroup_id': 9,
    'is_channel': false,
  },
  'positions': [
    {
      '@type': 'chatPosition',
      'list': {'@type': 'chatListMain'},
      'order': 100,
      'is_pinned': false,
    },
  ],
  'unread_count': 0,
};

ChatSummary _chat({required int id, required String title}) {
  return ChatSummary(
    id: id,
    title: title,
    lastMessage: 'Latest message',
    lastMessageId: id * 10,
    date: 100,
    unreadCount: 0,
    order: 100,
    isMuted: false,
    kind: ChatKind.group,
  );
}
