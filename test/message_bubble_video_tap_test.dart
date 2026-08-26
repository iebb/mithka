import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/message_bubble.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('an inline video without a thumbnail still opens on tap', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    addTearDown(theme.dispose);

    final message = ChatMessage(
      id: 701,
      isOutgoing: false,
      text: '',
      date: 1,
      contentType: 'messageVideo',
      imageWidth: 320,
      imageHeight: 180,
      video: TdFileRef(id: 1701),
      videoDuration: 5,
      videoFileSize: 1024 * 1024,
    );
    ChatMessage? opened;

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          theme: ThemeData(extensions: [AppColors.light]),
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: TickerMode(
              enabled: false,
              child: MessageBubble(
                message: message,
                peerTitle: 'Test',
                isGroup: false,
                onPlayVideo: (value) => opened = value,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final video = find.byKey(const ValueKey('message-inline-video-701'));
    await tester.tapAt(tester.getCenter(video));
    await tester.pump();

    expect(opened, same(message));
  });
}
