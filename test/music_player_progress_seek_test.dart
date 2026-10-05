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
  late ThemeController theme;
  final player = MusicPlayerController.shared;
  final deepLinks = ChatDeepLinkController.shared;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    theme = ThemeController(await SharedPreferences.getInstance());
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
        duration: 200,
        file: TdFileRef(id: 303),
      ),
    );
    player
      ..current = track
      ..queue = [track]
      ..hidden = false
      ..collapsed = false;
    player.seekFraction(0);
  });

  tearDown(() {
    deepLinks.consumePending();
    player
      ..current = null
      ..queue = const []
      ..hidden = true
      ..collapsed = false;
    theme.dispose();
  });

  Future<void> pumpBar(WidgetTester tester) {
    return tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
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
  }

  testWidgets('dragging the scrubber seeks relative to the grab point', (
    tester,
  ) async {
    await pumpBar(tester);
    final rect = tester.getRect(find.byKey(musicPlayerProgressKey));
    final gesture = await tester.startGesture(
      Offset(rect.center.dx, rect.center.dy),
    );
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump(const Duration(milliseconds: 300));
    // The drag previews locally and only seeks on release.
    expect(player.position, Duration.zero);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));

    // Playback was at 0, so grabbing mid-line must not jump to the middle.
    // The first move only wins the drag arena; the second one scrubs.
    final trackWidth = rect.width - 2 * (44 + 8);
    expect(
      player.position.inMilliseconds / 1000,
      closeTo(200 * 80 / trackWidth, 1),
    );
    expect(player.collapsed, isFalse);
    expect(player.current, isNotNull);
    expect(deepLinks.consumePending(), isNull);
  });

  testWidgets('tapping the scrubber seeks to that point', (tester) async {
    await pumpBar(tester);
    final rect = tester.getRect(find.byKey(musicPlayerProgressKey));
    const label = 44 + 8;
    final trackWidth = rect.width - 2 * label;

    await tester.tapAt(
      Offset(rect.left + label + trackWidth * 0.25, rect.center.dy),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(player.position.inSeconds, closeTo(50, 1));
    expect(find.text('0:50'), findsOneWidget);
    expect(find.text('-2:30'), findsOneWidget);
    expect(deepLinks.consumePending(), isNull);
  });

  testWidgets('a const bar follows controller updates', (tester) async {
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
    expect(find.text('0:00'), findsOneWidget);

    player.seekFraction(0.5);
    await tester.pump();

    expect(find.text('1:40'), findsOneWidget);
    expect(find.text('-1:40'), findsOneWidget);
  });

  testWidgets('shell scope tells panes not to add their own bar', (
    tester,
  ) async {
    late bool inside;
    late bool outside;
    await tester.pumpWidget(
      Column(
        children: [
          Builder(
            builder: (context) {
              outside = MusicPlayerShellScope.providesPlayer(context);
              return const SizedBox();
            },
          ),
          MusicPlayerShellScope(
            child: Builder(
              builder: (context) {
                inside = MusicPlayerShellScope.providesPlayer(context);
                return const SizedBox();
              },
            ),
          ),
        ],
      ),
    );
    expect(outside, isFalse);
    expect(inside, isTrue);
  });
}
