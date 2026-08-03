import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_row_view.dart';
import 'package:mithka/components/photo_avatar.dart';
import 'package:mithka/components/ui_components.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('native desktop uses compact chat typography and row geometry', () {
    expect(AppMetric.chatListRowHeight(TargetPlatform.macOS), 58);
    expect(AppMetric.chatListAvatarSize(TargetPlatform.macOS), 44);
    expect(AppTextSize.chatListTitle(TargetPlatform.macOS), 14);
    expect(AppTextSize.chatListPreview(TargetPlatform.macOS), 12);
    expect(AppTextSize.chatListTimestamp(TargetPlatform.macOS), 12);
    expect(AppTextSize.messageBody(TargetPlatform.macOS), 14);
  });

  test('touch platforms preserve the existing chat metrics', () {
    expect(AppMetric.chatListRowHeight(TargetPlatform.iOS), 64);
    expect(AppMetric.chatListAvatarSize(TargetPlatform.iOS), 48);
    expect(AppTextSize.chatListTitle(TargetPlatform.iOS), 15);
    expect(AppTextSize.chatListPreview(TargetPlatform.iOS), 13);
    expect(AppTextSize.chatListTimestamp(TargetPlatform.iOS), 12);
    expect(AppTextSize.messageBody(TargetPlatform.iOS), 15);
  });

  testWidgets('chat row consumes compact desktop metrics', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final theme = ThemeController(preferences);
      addTearDown(theme.dispose);
      final chat = ChatSummary(
        id: 1,
        title: 'Desktop chat',
        lastMessage: 'Compact preview',
        lastMessageId: 1,
        date: 1,
        unreadCount: 0,
        order: 1,
        isMuted: false,
      );

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

      expect(tester.getSize(find.byType(ChatRowView)).height, 58);
      expect(tester.widget<PhotoAvatar>(find.byType(PhotoAvatar)).size, 44);
      expect(
        tester.widget<Text>(find.text('Desktop chat')).style?.fontSize,
        14,
      );
      expect(
        tester.widget<ChatPreviewText>(find.byType(ChatPreviewText)).fontSize,
        12,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
