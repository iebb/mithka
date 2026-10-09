import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/app_navigator.dart';
import 'package:mithka/chat/music_player_controller.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/l10n_fixtures.dart';

/// The queue sheet follows the playing row while it is open. Auto-advance and
/// manual skips were already covered by the row changing; these are the order
/// changes that move the same row to another index.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final player = MusicPlayerController.shared;
  late ThemeController theme;

  setUpAll(() => L10nFixtures.load().install());

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

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    theme = ThemeController(await SharedPreferences.getInstance());
    player
      ..mode = MusicPlaybackMode.sequence
      ..queue = [for (var id = 1; id <= 24; id += 1) track(id)]
      ..hidden = false
      ..collapsed = false;
  });

  tearDown(() {
    player
      ..current = null
      ..queue = const []
      ..mode = MusicPlaybackMode.sequence
      ..hidden = true
      ..collapsed = false;
    theme.dispose();
  });

  Finder row(int fileId) => find.byKey(ValueKey('music-queue-$fileId'));

  /// Opens the sheet on a phone-sized surface with [currentId] playing, after
  /// the opening jump has landed.
  Future<void> openQueueSheet(
    WidgetTester tester, {
    required int currentId,
    ValueNotifier<double>? textScale,
  }) async {
    // 390x844 logical: the sheet header's mode label needs the width a phone
    // gives it, and the test font renders every glyph as a full-em box.
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    player.current = player.queue.firstWhere(
      (message) => message.music?.file?.id == currentId,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          navigatorKey: appNavigatorKey,
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          builder: textScale == null
              ? null
              : (context, child) => ValueListenableBuilder<double>(
                  valueListenable: textScale,
                  builder: (context, scale, _) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
                ),
          home: Scaffold(
            body: Column(
              children: [
                const Spacer(),
                AnimatedBuilder(
                  animation: player,
                  builder: (context, _) => const GlobalMusicPlayerBar(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.bySemanticsLabel(
        AppStrings.t(AppStringKeys.musicPlayerShowPlaylist),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('flipping the queue order keeps the playing row in view', (
    tester,
  ) async {
    await openQueueSheet(tester, currentId: 2);
    expect(row(2), findsOneWidget);

    // Reverse sequence shows the same queue backwards, so the playing row
    // moves from the top of the list to its bottom without the track
    // changing — the sheet used to stay where it was until it was reopened.
    player.cycleMode();
    await tester.pumpAndSettle();

    expect(row(2), findsOneWidget);
    expect(row(24), findsNothing);

    // Repeat one plays the source order again, and the row comes back with it.
    player.cycleMode();
    await tester.pumpAndSettle();

    expect(row(2), findsOneWidget);
    expect(row(1), findsOneWidget);
    expect(row(24), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a reorder recenters after the first row has scrolled away', (
    tester,
  ) async {
    // Opening on a track near the end scrolls the sheet there, which unmounts
    // the first row — the one the row height used to be read from.
    await openQueueSheet(tester, currentId: 21);
    expect(row(21), findsOneWidget);

    player.cycleMode();
    await tester.pumpAndSettle();

    expect(row(21), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a reorder uses the current scaled row extent', (tester) async {
    final scale = ValueNotifier(1.0);
    addTearDown(scale.dispose);
    await openQueueSheet(tester, currentId: 13, textScale: scale);
    expect(row(1), findsNothing);

    // Keep the header within the 390px test-font layout while changing the
    // list's prototype extent; this assertion isolates scroll geometry.
    scale.value = 1.05;
    await tester.pumpAndSettle();
    player.cycleMode();
    await tester.pumpAndSettle();

    expect(row(13), findsOneWidget);
    final viewport = tester.getRect(find.byType(ListView).last);
    final playing = tester.getRect(row(13));
    expect(playing.center.dy, closeTo(viewport.center.dy, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing before the queued reveal cancels the UI work', (
    tester,
  ) async {
    await openQueueSheet(tester, currentId: 21);
    player.cycleMode();
    appNavigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(row(21), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
