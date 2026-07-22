import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_row_view.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('normal users receive their assigned chat-list name color', (
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

    expect(title().style?.color, const Color(0xFF955CDB));

    theme.showNameColors = false;
    await tester.pump();

    expect(title().style?.color, AppColors.light.textPrimary);
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
}
