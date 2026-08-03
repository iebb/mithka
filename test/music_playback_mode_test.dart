import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/music_player_controller.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('playback mode cycle includes reverse sequence', () {
    final player = MusicPlayerController.shared;
    player.mode = MusicPlaybackMode.sequence;
    addTearDown(() => player.mode = MusicPlaybackMode.sequence);

    player.cycleMode();
    expect(player.mode, MusicPlaybackMode.reverseSequence);
    player.cycleMode();
    expect(player.mode, MusicPlaybackMode.repeatOne);
    player.cycleMode();
    expect(player.mode, MusicPlaybackMode.shuffle);
    player.cycleMode();
    expect(player.mode, MusicPlaybackMode.sequence);
  });

  test('reverse sequence next and finished traversal move backward', () {
    expect(
      MusicPlayerController.resolveAdjacentIndex(
        currentIndex: 2,
        itemCount: 4,
        delta: 1,
        wrap: false,
        mode: MusicPlaybackMode.reverseSequence,
      ),
      1,
    );
    expect(
      MusicPlayerController.resolveAdjacentIndex(
        currentIndex: 0,
        itemCount: 4,
        delta: 1,
        wrap: false,
        mode: MusicPlaybackMode.reverseSequence,
      ),
      isNull,
    );
    expect(
      MusicPlayerController.resolveAdjacentIndex(
        currentIndex: 0,
        itemCount: 4,
        delta: 1,
        wrap: true,
        mode: MusicPlaybackMode.reverseSequence,
      ),
      3,
    );
  });

  test('reverse sequence previous traversal moves forward', () {
    expect(
      MusicPlayerController.resolveAdjacentIndex(
        currentIndex: 1,
        itemCount: 4,
        delta: -1,
        wrap: false,
        mode: MusicPlaybackMode.reverseSequence,
      ),
      2,
    );
    expect(
      MusicPlayerController.resolveAdjacentIndex(
        currentIndex: 3,
        itemCount: 4,
        delta: -1,
        wrap: true,
        mode: MusicPlaybackMode.reverseSequence,
      ),
      0,
    );
  });

  test('ordinary sequence traversal remains unchanged', () {
    expect(
      MusicPlayerController.resolveAdjacentIndex(
        currentIndex: 1,
        itemCount: 4,
        delta: 1,
        wrap: false,
        mode: MusicPlaybackMode.sequence,
      ),
      2,
    );
    expect(
      MusicPlayerController.resolveAdjacentIndex(
        currentIndex: 3,
        itemCount: 4,
        delta: 1,
        wrap: true,
        mode: MusicPlaybackMode.repeatOne,
      ),
      0,
    );
  });

  test('reverse sequence label is localized in every supported table', () {
    const expected = <String, String>{
      'zhHans': '倒序播放',
      'zhHant': '倒序播放',
      'ja': '逆順で再生',
      'ko': '역순 재생',
      'en': 'Play in reverse order',
      'fr': 'Lecture en ordre inverse',
      'es': 'Reproducir en orden inverso',
      'de': 'In umgekehrter Reihenfolge abspielen',
    };

    for (final entry in expected.entries) {
      expect(
        AppStrings.tForLocale(
          entry.key,
          AppStringKeys.musicPlayerModeReverseSequence,
        ),
        entry.value,
      );
    }
  });

  testWidgets('player exposes reverse mode with an owned painted glyph', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    final player = MusicPlayerController.shared;
    final track = ChatMessage(
      id: 1,
      isOutgoing: false,
      text: '',
      date: 1,
      chatId: 2,
      music: MessageMusic(
        title: 'Track',
        duration: 120,
        file: TdFileRef(id: 3),
      ),
    );
    player
      ..current = track
      ..queue = [track]
      ..mode = MusicPlaybackMode.reverseSequence
      ..hidden = false
      ..collapsed = false;
    addTearDown(() {
      player
        ..current = null
        ..queue = const []
        ..mode = MusicPlaybackMode.sequence
        ..hidden = true
        ..collapsed = false;
      theme.dispose();
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: AnimatedBuilder(
              animation: player,
              builder: (context, _) =>
                  const Column(children: [Spacer(), GlobalMusicPlayerBar()]),
            ),
          ),
        ),
      ),
    );

    final reverseControl = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.label == 'Play in reverse order',
    );
    expect(reverseControl, findsOneWidget);
    expect(
      find.descendant(of: reverseControl, matching: find.byType(CustomPaint)),
      findsOneWidget,
    );

    await tester.tap(reverseControl);
    await tester.pump();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == 'Repeat one',
      ),
      findsOneWidget,
    );
  });
}
