import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/message_bubble.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ThemeController> pumpBubble(
    WidgetTester tester,
    ChatMessage message,
  ) async {
    SharedPreferences.setMockInitialValues({'groupImageMessages': true});
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    addTearDown(theme.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MessageBubble(
              message: message,
              peerTitle: 'Test',
              isGroup: false,
            ),
          ),
        ),
      ),
    );
    return theme;
  }

  testWidgets('grouped photo captions render their translation', (
    tester,
  ) async {
    final message = ChatMessage(
      id: 1,
      isOutgoing: false,
      text: 'Original caption',
      date: 1,
      contentType: 'messagePhoto',
      image: TdFileRef(
        id: 101,
        miniThumb: base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
      ),
      imageWidth: 600,
      imageHeight: 400,
      translationText: 'Translated caption',
      translationLanguageCode: 'en',
    );

    await pumpBubble(tester, message);

    expect(find.text('Original caption', findRichText: true), findsOneWidget);
    expect(find.text('Translated caption', findRichText: true), findsOneWidget);
    expect(
      find.byKey(const ValueKey('messageTranslationBlock')),
      findsOneWidget,
    );

    // Expire the mocked TDLib image lookup timeout before test teardown.
    await tester.pump(const Duration(minutes: 3, seconds: 1));
  });

  testWidgets('document captions render their translation', (tester) async {
    final message = ChatMessage(
      id: 2,
      isOutgoing: false,
      text: 'Document caption',
      date: 1,
      contentType: 'messageDocument',
      document: MessageDocument(
        fileName: 'report.pdf',
        size: 1024,
        ext: 'PDF',
        file: null,
      ),
      translationText: 'Translated document caption',
      translationLanguageCode: 'en',
    );

    await pumpBubble(tester, message);

    expect(find.text('Document caption', findRichText: true), findsOneWidget);
    expect(
      find.text('Translated document caption', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('messageTranslationBlock')),
      findsOneWidget,
    );
  });
}
