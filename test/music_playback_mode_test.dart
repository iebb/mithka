import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/app_navigator.dart';
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

  test('the prefetched track follows the playback order', () {
    final player = MusicPlayerController.shared;
    ChatMessage track(int id) => ChatMessage(
      id: id,
      isOutgoing: false,
      text: '',
      date: 1,
      music: MessageMusic(
        title: 'Track $id',
        file: TdFileRef(id: id),
      ),
    );
    final tracks = [track(1), track(2), track(3)];
    player
      ..queue = tracks
      ..current = tracks[1];
    addTearDown(() {
      player
        ..mode = MusicPlaybackMode.sequence
        ..queue = const []
        ..current = null;
    });

    player.mode = MusicPlaybackMode.sequence;
    expect(player.upcomingTrack()?.id, 3);
    player.mode = MusicPlaybackMode.reverseSequence;
    expect(player.upcomingTrack()?.id, 1);
    player.mode = MusicPlaybackMode.repeatOne;
    expect(player.upcomingTrack(), isNull);
    player.mode = MusicPlaybackMode.shuffle;
    final shuffled = player.upcomingTrack();
    expect(shuffled, isNotNull);
    expect(shuffled!.id, isNot(2));
    expect(player.upcomingTrack()?.id, shuffled.id);

    player
      ..mode = MusicPlaybackMode.sequence
      ..current = tracks[2];
    expect(player.upcomingTrack(), isNull);
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

  testWidgets('player bar places previous before play and next', (
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
      ..hidden = false
      ..collapsed = false;
    addTearDown(() {
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

    Finder control(String label) => find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == label,
    );
    final previous = control('Previous');
    final play = control('Play');
    final next = control('Next');
    expect(previous, findsOneWidget);
    expect(play, findsOneWidget);
    expect(next, findsOneWidget);
    expect(tester.getCenter(previous).dx, lessThan(tester.getCenter(play).dx));
    expect(tester.getCenter(play).dx, lessThan(tester.getCenter(next).dx));
  });
  test('display queue follows the reverse sequence traversal order', () {
    final player = MusicPlayerController.shared;
    final tracks = [
      for (var i = 1; i <= 3; i++)
        ChatMessage(
          id: i,
          isOutgoing: false,
          text: '',
          date: i,
          chatId: 2,
          music: MessageMusic(
            title: 'Track $i',
            duration: 120,
            file: TdFileRef(id: 10 + i),
          ),
        ),
    ];
    player
      ..queue = tracks
      ..mode = MusicPlaybackMode.sequence;
    addTearDown(() {
      player
        ..queue = const []
        ..mode = MusicPlaybackMode.sequence;
    });

    expect(player.displayQueue.map((item) => item.id), [1, 2, 3]);
    player.mode = MusicPlaybackMode.reverseSequence;
    expect(player.displayQueue.map((item) => item.id), [3, 2, 1]);
    expect(player.queue.map((item) => item.id), [1, 2, 3]);
    player.mode = MusicPlaybackMode.shuffle;
    expect(player.displayQueue.map((item) => item.id), [1, 2, 3]);
  });

  testWidgets('queue sheet reorders rows when reverse sequence is toggled', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    final player = MusicPlayerController.shared;
    final tracks = [
      for (var i = 1; i <= 3; i++)
        ChatMessage(
          id: i,
          isOutgoing: false,
          text: '',
          date: i,
          chatId: 2,
          music: MessageMusic(
            title: 'Track $i',
            duration: 120,
            file: TdFileRef(id: 20 + i),
          ),
        ),
    ];
    player
      ..current = tracks.first
      ..queue = tracks
      ..mode = MusicPlaybackMode.sequence
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
          navigatorKey: appNavigatorKey,
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: Column(children: [Spacer(), GlobalMusicPlayerBar()]),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == 'Playlist',
      ),
    );
    await tester.pumpAndSettle();

    List<double> rowOffsets() => [
      for (var i = 1; i <= 3; i++)
        tester.getTopLeft(find.text('Track $i').last).dy,
    ];

    final forward = rowOffsets();
    expect(forward[0], lessThan(forward[1]));
    expect(forward[1], lessThan(forward[2]));

    await tester.tap(find.text('Play in order').last);
    await tester.pumpAndSettle();
    expect(player.mode, MusicPlaybackMode.reverseSequence);

    final reversed = rowOffsets();
    expect(reversed[2], lessThan(reversed[1]));
    expect(reversed[1], lessThan(reversed[0]));
  });

  group('shuffle', () {
    ChatMessage track(int id) => ChatMessage(
      id: id,
      isOutgoing: false,
      text: '',
      date: id,
      music: MessageMusic(
        title: 'Track $id',
        file: TdFileRef(id: id),
      ),
    );

    tearDown(() {
      MusicPlayerController.shared
        ..mode = MusicPlaybackMode.sequence
        ..queue = const []
        ..current = null;
    });

    test('a pass starts with the given track and covers every track once', () {
      final order = MusicPlayerController.shuffledOrder(
        [1, 2, 3, 4, 5, 6],
        4,
        Random(7),
      );
      expect(order.first, 4);
      expect(order.toSet(), {1, 2, 3, 4, 5, 6});
      expect(order, hasLength(6));
    });

    test('next walks the pass and previous walks back through it', () {
      final player = MusicPlayerController.shared;
      final tracks = [for (var i = 1; i <= 5; i++) track(i)];
      player
        ..queue = tracks
        ..current = tracks[2]
        ..mode = MusicPlaybackMode.shuffle;

      final played = <int>[3];
      for (var i = 0; i < 4; i++) {
        final next = player.adjacentTrack(1, manual: false)!;
        played.add(next.id);
        player.current = next;
      }
      expect(played.toSet(), {1, 2, 3, 4, 5});
      // Automatic advance at the end of a pass starts a new one with a
      // different track instead of repeating the last.
      final wrapped = player.adjacentTrack(1, manual: false);
      expect(wrapped, isNotNull);
      expect(wrapped!.id, isNot(played.last));

      for (var i = played.length - 2; i >= 0; i--) {
        final previous = player.adjacentTrack(-1, manual: true)!;
        expect(previous.id, played[i]);
        player.current = previous;
      }
      expect(player.adjacentTrack(-1, manual: false), isNull);
    });

    test('changing mode starts a new pass', () {
      final player = MusicPlayerController.shared;
      final tracks = [for (var i = 1; i <= 8; i++) track(i)];
      player
        ..queue = tracks
        ..current = tracks.first
        ..mode = MusicPlaybackMode.repeatOne;
      player.cycleMode();
      expect(player.mode, MusicPlaybackMode.shuffle);
      final next = player.adjacentTrack(1, manual: true);
      expect(next, isNotNull);
      expect(next!.id, isNot(1));
    });
  });

  test('playback mode survives a restart', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final player = MusicPlayerController.shared;
    addTearDown(() => player.mode = MusicPlaybackMode.sequence);
    player.initialize(prefs);
    player.mode = MusicPlaybackMode.repeatOne;
    player.cycleMode();
    expect(prefs.getString('mithka.musicPlaybackMode.v1'), 'shuffle');

    player.mode = MusicPlaybackMode.sequence;
    player.initialize(prefs);
    expect(player.mode, MusicPlaybackMode.shuffle);
  });
}
