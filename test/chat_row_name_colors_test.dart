import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/group_remark_controller.dart';
import 'package:mithka/chats/chat_row_view.dart';
import 'package:mithka/components/photo_avatar.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/date_text.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('chat rows show the active account local group remark', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    final remarks = GroupRemarkController(
      preferences,
      initialAccountUserId: 101,
    );
    addTearDown(theme.dispose);
    addTearDown(remarks.dispose);
    final chat = ChatSummary(
      id: -1001,
      title: 'Telegram group name',
      lastMessage: 'Hello',
      lastMessageId: 1,
      date: 0,
      unreadCount: 0,
      order: 1,
      isMuted: false,
      kind: ChatKind.group,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeController>.value(value: theme),
          ChangeNotifierProvider<GroupRemarkController>.value(value: remarks),
        ],
        child: MaterialApp(
          theme: ThemeData(
            brightness: Brightness.light,
            extensions: [AppColors.light],
          ),
          home: Scaffold(body: ChatRowView(chat: chat)),
        ),
      ),
    );

    expect(find.text('Telegram group name'), findsOneWidget);
    expect(
      tester.widget<PhotoAvatar>(find.byType(PhotoAvatar)).title,
      'Telegram group name',
    );

    await remarks.setRemark(-1001, 'Local group name');
    await tester.pump();

    expect(find.text('Local group name'), findsOneWidget);
    expect(find.text('Telegram group name'), findsNothing);
    expect(
      tester.widget<PhotoAvatar>(find.byType(PhotoAvatar)).title,
      'Local group name',
    );
    expect(chat.title, 'Telegram group name');

    remarks.setActiveAccountUserId(202);
    await tester.pump();

    expect(find.text('Telegram group name'), findsOneWidget);
    expect(
      tester.widget<PhotoAvatar>(find.byType(PhotoAvatar)).title,
      'Telegram group name',
    );
  });

  testWidgets('chat-list name colors follow the selected audience', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    addTearDown(theme.dispose);
    final chat = ChatSummary(
      id: 1,
      title: 'Normal user',
      lastMessage: 'Hello',
      lastMessageId: 1,
      date: 0,
      unreadCount: 0,
      order: 1,
      isMuted: false,
      peerAccentColorId: 2,
    );
    expect(chat.peerIsPremium, isFalse);

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          theme: ThemeData(
            brightness: Brightness.light,
            extensions: [AppColors.light],
          ),
          home: Scaffold(body: ChatRowView(chat: chat)),
        ),
      ),
    );

    Text title() => tester.widget<Text>(find.text('Normal user'));

    expect(
      tester.widget<PhotoAvatar>(find.byType(PhotoAvatar)).allowAnimation,
      isFalse,
    );

    expect(theme.chatListNameColorAudience, NameColorAudience.premium);
    expect(title().style?.color, AppColors.light.textPrimary);

    theme.chatListNameColorAudience = NameColorAudience.allUsers;
    await tester.pump();

    expect(title().style?.color, const Color(0xFF955CDB));

    theme.chatListNameColorAudience = NameColorAudience.nobody;
    await tester.pump();

    expect(title().style?.color, AppColors.light.textPrimary);
  });

  testWidgets('desktop rows keep time separated and show pin plus mute', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    addTearDown(theme.dispose);
    final chat = ChatSummary(
      id: 8,
      title: 'Pinned muted chat',
      lastMessage: 'Latest message',
      lastMessageId: 1,
      date: 1700000000,
      unreadCount: 0,
      order: 1,
      isMuted: true,
      isPinned: true,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          theme: ThemeData(
            brightness: Brightness.light,
            extensions: [AppColors.light],
          ),
          home: Scaffold(
            body: SizedBox(width: 390, child: ChatRowView(chat: chat)),
          ),
        ),
      ),
    );
    debugDefaultTargetPlatformOverride = null;

    final timestamp = find.text(DateText.listLabel(chat.date));
    final pin = find.byKey(const ValueKey('chat-row-pinned'));
    final muted = find.byKey(const ValueKey('chat-row-muted'));
    expect(timestamp, findsOneWidget);
    expect(pin, findsOneWidget);
    expect(muted, findsOneWidget);
    expect(
      tester.getTopLeft(muted).dy - tester.getBottomLeft(timestamp).dy,
      greaterThanOrEqualTo(AppSpacing.sm),
    );
    expect(tester.getTopLeft(pin).dx, lessThan(tester.getTopLeft(muted).dx));
  });

  test('legacy preference names remain readable', () async {
    SharedPreferences.setMockInitialValues({
      'showPremiumNameColors': false,
      'showChatPremiumNameColors': false,
    });
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    addTearDown(theme.dispose);

    expect(theme.showNameColors, isFalse);
    expect(theme.showChatNameColors, isFalse);
  });

  test('chat and chat-list defaults persist independently', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    addTearDown(theme.dispose);

    expect(theme.chatListNameColorAudience, NameColorAudience.premium);
    expect(theme.chatListStatusEmojiMode, StatusEmojiDisplayMode.static);
    expect(theme.chatNameColorAudience, NameColorAudience.allUsers);
    expect(theme.chatStatusEmojiMode, StatusEmojiDisplayMode.static);

    theme.chatListNameColorAudience = NameColorAudience.nobody;
    theme.chatListStatusEmojiMode = StatusEmojiDisplayMode.animated;
    theme.chatNameColorAudience = NameColorAudience.premium;
    theme.chatStatusEmojiMode = StatusEmojiDisplayMode.none;

    final restored = ThemeController(preferences);
    addTearDown(restored.dispose);
    expect(restored.chatListNameColorAudience, NameColorAudience.nobody);
    expect(restored.chatListStatusEmojiMode, StatusEmojiDisplayMode.animated);
    expect(restored.chatNameColorAudience, NameColorAudience.premium);
    expect(restored.chatStatusEmojiMode, StatusEmojiDisplayMode.none);
  });
}
