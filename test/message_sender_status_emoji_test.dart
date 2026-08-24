import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/custom_emoji.dart';
import 'package:mithka/chat/message_bubble.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sender status emoji scales with the chat text scaler', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    addTearDown(theme.dispose);

    final message = ChatMessage(
      id: 702,
      isOutgoing: false,
      text: 'hello',
      date: 1,
      contentType: 'messageText',
      senderName: 'Alice',
      senderEmojiStatusId: 42,
    );

    Widget bubble(double scale) => ChangeNotifierProvider<ThemeController>.value(
      value: theme,
      child: MaterialApp(
        theme: ThemeData(extensions: [AppColors.light]),
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: TickerMode(
              enabled: false,
              child: MessageBubble(
                message: message,
                peerTitle: 'Test Group',
                isGroup: true,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(bubble(1));
    // CustomEmojiCenter debounces its load request on a 40 ms timer.
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      tester.widget<StatusEmojiView>(find.byType(StatusEmojiView)).size,
      14,
    );

    await tester.pumpWidget(bubble(2));
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      tester.widget<StatusEmojiView>(find.byType(StatusEmojiView)).size,
      28,
    );
  });
}
