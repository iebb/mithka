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
  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    test('$platform retains compact chat typography and geometry', () {
      expect(AppMetric.chatListRowHeight(platform), 58);
      expect(AppMetric.chatListAvatarSize(platform), 44);
      expect(AppTextSize.chatListTitle(platform), 14);
      expect(AppTextSize.chatListPreview(platform), 12);
      expect(AppTextSize.chatListTimestamp(platform), 12);
      expect(AppTextSize.chatListFolderTag(platform), 10);
      expect(AppTextSize.messageBody(platform), 14);
    });
  }

  for (final platform in [
    TargetPlatform.iOS,
    TargetPlatform.android,
    TargetPlatform.fuchsia,
  ]) {
    test(
      '$platform uses larger touch chat roles without changing geometry',
      () {
        expect(AppMetric.chatListRowHeight(platform), 64);
        expect(AppMetric.chatListAvatarSize(platform), 48);
        expect(AppTextSize.chatListTitle(platform), 16);
        expect(AppTextSize.chatListPreview(platform), 14);
        expect(AppTextSize.chatListTimestamp(platform), 13);
        expect(AppTextSize.chatListFolderTag(platform), 12);
        expect(AppTextSize.messageBody(platform), 17);
      },
    );
  }

  test('shared settings and navigation text tokens are unchanged', () {
    expect(
      [
        AppTextSize.tiny,
        AppTextSize.caption,
        AppTextSize.footnote,
        AppTextSize.callout,
        AppTextSize.body,
        AppTextSize.bodyLarge,
        AppTextSize.title,
        AppTextSize.display,
        AppTextSize.largeDisplay,
      ],
      [10, 12, 13, 14, 15, 16, 17, 22, 24],
    );
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
