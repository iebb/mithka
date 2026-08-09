import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/bot_api_access_warning.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/app_theme.dart';

void main() {
  test('warning visibility is limited to Bot API group chats', () {
    final model = ChatViewModel(
      chatId: -1001,
      title: 'Group',
      markReadOnOpen: false,
    );
    model
      ..isBotApiAccount = true
      ..isGroup = true
      ..isChannel = false
      ..botApiCanReadAllGroupMessages = false
      ..botApiBotToBotAccessObserved = false;

    expect(model.showBotApiPrivacyWarning, isTrue);
    expect(model.showBotApiBotToBotWarning, isTrue);
    expect(model.showBotApiAccessWarning, isTrue);

    model.botApiCanReadAllGroupMessages = true;
    model.botApiBotToBotAccessObserved = true;
    expect(model.showBotApiAccessWarning, isFalse);

    model
      ..botApiCanReadAllGroupMessages = false
      ..isChannel = true;
    expect(model.showBotApiAccessWarning, isFalse);
    model.dispose();
  });

  testWidgets('renders both notices and exposes a close action', (
    tester,
  ) async {
    var dismissed = false;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
          brightness: Brightness.light,
          extensions: [AppColors.light],
        ),
        home: Scaffold(
          body: BotApiAccessWarning(
            showPrivacyWarning: true,
            showBotToBotWarning: true,
            onDismiss: () => dismissed = true,
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('botApiAccessWarning')), findsOneWidget);
    expect(find.textContaining('Group Privacy is enabled'), findsOneWidget);
    expect(
      find.textContaining('Bot-to-bot access cannot be verified'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('botApiAccessWarningDismiss')));
    expect(dismissed, isTrue);
  });
}
