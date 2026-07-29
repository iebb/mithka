import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/chat_deep_link_controller.dart';
import 'package:mithka/chat/music_player_controller.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('repeated music title taps keep one source-chat request', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    final player = MusicPlayerController.shared;
    final deepLinks = ChatDeepLinkController.shared;
    deepLinks.consumePending();
    final track = ChatMessage(
      id: 101,
      isOutgoing: false,
      text: '',
      date: 1,
      chatId: 202,
      senderName: 'Chat source',
      music: MessageMusic(
        title: 'Chat track',
        performer: 'Artist',
        duration: 180,
        file: TdFileRef(id: 303),
      ),
    );
    player
      ..current = track
      ..queue = [track]
      ..hidden = false
      ..collapsed = false;
    addTearDown(() {
      deepLinks.consumePending();
      player
        ..current = null
        ..queue = const []
        ..hidden = true
        ..collapsed = false;
      theme.dispose();
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Column(children: [Spacer(), GlobalMusicPlayerBar()]),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Chat track'));
    await tester.pump();
    await tester.tap(find.text('Chat track'));
    await tester.pump();

    final request = deepLinks.consumePending();
    expect(request?.chatId, 202);
    expect(request?.title, 'Chat source');
    expect(request?.messageId, 101);
    expect(deepLinks.consumePending(), isNull);
  });
}
