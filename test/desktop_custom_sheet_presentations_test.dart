import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_view.dart';
import 'package:mithka/chat/music_player_controller.dart';
import 'package:mithka/chat/music_playlist_service.dart';
import 'package:mithka/chat/rich_text_composer_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/app_motion.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('reaction users use centered chrome on desktop', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    _setTestSize(tester, const Size(1280, 800));

    await tester.pumpWidget(
      _testApp(
        onOpen: (context) => showReactionUsersModal<void>(
          context,
          builder: (_) => const ReactionUsersSheetFrame(
            child: Center(child: Text('Reaction users')),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();

    expect(find.byKey(appCenteredModalSurfaceKey), findsOneWidget);
    expect(find.byKey(reactionUsersCenteredFrameKey), findsOneWidget);
    expect(find.byKey(reactionUsersTouchFrameKey), findsNothing);
    expect(find.byKey(reactionUsersDragHandleKey), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('reaction users preserve the portrait touch sheet', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    _setTestSize(tester, const Size(820, 1180));

    await tester.pumpWidget(
      _testApp(
        onOpen: (context) => showReactionUsersModal<void>(
          context,
          builder: (_) => const ReactionUsersSheetFrame(
            child: Center(child: Text('Reaction users')),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();

    expect(find.byKey(appCenteredModalSurfaceKey), findsNothing);
    expect(find.byKey(reactionUsersCenteredFrameKey), findsNothing);
    expect(find.byKey(reactionUsersTouchFrameKey), findsOneWidget);
    expect(find.byKey(reactionUsersDragHandleKey), findsOneWidget);
    expect(find.byType(SlideTransition), findsWidgets);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('rich composer uses the bounded desktop modal', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    _setTestSize(tester, const Size(1280, 800));

    await tester.pumpWidget(
      _testApp(
        onOpen: (context) => showRichTextComposerSheet(
          context,
          initialText: 'Draft',
          allowMedia: false,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();

    expect(find.byKey(appCenteredModalSurfaceKey), findsOneWidget);
    expect(find.byType(RichTextComposerView), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('music tracks hide the drag handle in a desktop modal', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    _setTestSize(tester, const Size(1280, 800));
    final controller = MusicPlayerController.shared;
    final previous = controller.playlists;
    controller.playlists = const [
      MusicPlaylist(chatId: 42, title: 'Desktop playlist'),
    ];
    addTearDown(() => controller.playlists = previous);

    await tester.pumpWidget(
      _testApp(
        onOpen: (context) => showMusicPlaylistTracks(
          context,
          const MusicPlaylist(chatId: 42, title: 'Desktop playlist'),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();

    expect(find.byKey(appCenteredModalSurfaceKey), findsOneWidget);
    expect(find.byKey(musicSheetGrabberKey), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('music tracks keep their drag handle on portrait touch', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    _setTestSize(tester, const Size(820, 1180));
    final controller = MusicPlayerController.shared;
    final previous = controller.playlists;
    controller.playlists = const [
      MusicPlaylist(chatId: 42, title: 'Touch playlist'),
    ];
    addTearDown(() => controller.playlists = previous);

    await tester.pumpWidget(
      _testApp(
        onOpen: (context) => showMusicPlaylistTracks(
          context,
          const MusicPlaylist(chatId: 42, title: 'Touch playlist'),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();

    expect(find.byKey(appCenteredModalSurfaceKey), findsNothing);
    expect(find.byKey(musicSheetGrabberKey), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}

Widget _testApp({
  required Future<dynamic> Function(BuildContext context) onOpen,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [AppLocalizations.delegate],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) => GestureDetector(
        key: const ValueKey('open'),
        behavior: HitTestBehavior.opaque,
        onTap: () => unawaited(onOpen(context).then<void>((_) {})),
        child: const SizedBox.expand(),
      ),
    ),
  );
}

void _setTestSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
