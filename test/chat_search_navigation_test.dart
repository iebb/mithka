import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_info_view.dart';
import 'package:mithka/chat/chat_search_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('chat info relays a selected search message to the open chat', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    addTearDown(theme.dispose);

    int? selectedMessageId;
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
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    selectedMessageId = await Navigator.of(context).push<int>(
                      MaterialPageRoute<int>(
                        builder: (_) =>
                            const ChatInfoView(chatId: 42, title: 'Test chat'),
                      ),
                    );
                  },
                  child: const Text('Open chat info'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open chat info'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatInfoView), findsOneWidget);

    await tester.tap(
      find.text(AppStrings.t(AppStringKeys.chatInfoSearchHistory)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ChatSearchView), findsOneWidget);

    Navigator.of(tester.element(find.byType(ChatSearchView))).pop<int>(8675309);
    await tester.pumpAndSettle();

    expect(selectedMessageId, 8675309);
    expect(find.byType(ChatInfoView), findsNothing);
  });
}
