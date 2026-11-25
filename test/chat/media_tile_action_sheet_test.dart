//
//  media_tile_action_sheet_test.dart
//
//  The composer's sticker/GIF long-press sheet renders exactly the rows its
//  callback set and tile descriptor ask for: null callbacks hide rows, GIF
//  tiles never offer view-set or copy, copy stays a desktop-only WebP
//  affordance, and tapping a row pops the sheet and invokes the caller's
//  callback. The sheet itself performs no store or TDLib work.
//

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/media_tile_action_sheet.dart';
import 'package:mithka/chat/stickers/gif_item.dart';
import 'package:mithka/chat/stickers/sticker_item.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// A video_player platform whose players never present frames, so the GIF
/// header preview stays on its still thumbnail instead of spinning a decoder.
class _FramelessVideoPlatform extends VideoPlayerPlatform {
  final Map<int, StreamController<void>> _events = {};

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async => 0;

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    // The map owns this controller and dispose() closes it.
    // ignore: close_sinks
    final controller = _events[playerId] ??= StreamController.broadcast();
    return controller.stream.map(
      (_) => VideoEvent(eventType: VideoEventType.initialized),
    );
  }

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<void> dispose(int playerId) async {
    await _events.remove(playerId)?.close();
  }

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const SizedBox.shrink();
}

GifItem _gif() => GifItem(
  id: 4242,
  duration: 2,
  width: 320,
  height: 240,
  mimeType: 'video/mp4',
  // Real worktree files keep TdFileCenter on its local-source path instead of
  // opening TDLib download waiters: the animation file feeds the (frameless)
  // video controller, the thumbnail is what the header actually paints.
  file: TdFileRef(id: 4201, localPath: 'pubspec.yaml'),
  thumbnail: TdFileRef(id: 9201, localPath: 'assets/penguin.png'),
);

StickerItem _sticker({bool animated = false, bool video = false}) =>
    StickerItem(
      id: 7,
      width: 512,
      height: 512,
      emoji: '🙂',
      isAnimated: animated,
      isVideo: video,
    );

Future<void> _pumpHome(WidgetTester tester) async {
  // Seven 48px rows plus the 64px header overflow the default 600px test
  // surface, which would leave bottom rows unbuilt in the lazy list.
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(extensions: [AppColors.light]),
      home: const Scaffold(body: SizedBox.shrink()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openSheet(
  WidgetTester tester, {
  required MediaTileDescriptor descriptor,
  required MediaTileActions actions,
}) async {
  await _pumpHome(tester);
  final ctx = tester.element(find.byType(Scaffold));
  unawaited(showMediaTileActionSheet(ctx, descriptor, actions).then((_) {}));
  await tester.pumpAndSettle();
}

Future<void> _installVideoPlatform() async {
  final platform = _FramelessVideoPlatform();
  final previous = VideoPlayerPlatform.instance;
  VideoPlayerPlatform.instance = platform;
  addTearDown(() => VideoPlayerPlatform.instance = previous);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(const {});
  });

  tearDown(() {});

  testWidgets('sticker sheet shows all wired rows', (tester) async {
    await _openSheet(
      tester,
      descriptor: MediaTileDescriptor.sticker(
        _sticker(),
        false, // inFavorites
        true, // isRecentTile
      ),
      actions: MediaTileActions(
        send: () {},
        sendWithoutSound: () {},
        schedule: () {},
        toggleFavorite: () {},
        viewSet: () {},
        save: () {},
        removeFromRecent: () {},
      ),
    );
    expect(find.byKey(const ValueKey('mediaTileAction-send')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mediaTileAction-sendWithoutSound')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mediaTileAction-schedule')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mediaTileAction-toggleFavorite')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mediaTileAction-viewSet')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('mediaTileAction-save')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mediaTileAction-removeFromRecent')),
      findsOneWidget,
    );
    // Not desktop and not webp-copy-eligible: no copy row.
    expect(find.byKey(const ValueKey('mediaTileAction-copy')), findsNothing);
  });

  testWidgets('gif sheet hides view-set and copy rows', (tester) async {
    await _installVideoPlatform();
    await _openSheet(
      tester,
      descriptor: MediaTileDescriptor.gif(_gif(), false),
      actions: MediaTileActions(
        send: () {},
        sendWithoutSound: () {},
        schedule: () {},
        save: () {},
        viewSet: () {},
        copy: () {},
      ),
    );
    expect(find.byKey(const ValueKey('mediaTileAction-send')), findsOneWidget);
    expect(find.byKey(const ValueKey('mediaTileAction-save')), findsOneWidget);
    expect(find.byKey(const ValueKey('mediaTileAction-viewSet')), findsNothing);
    expect(find.byKey(const ValueKey('mediaTileAction-copy')), findsNothing);
  });

  testWidgets('webp sticker on desktop offers copy', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await _openSheet(
        tester,
        descriptor: MediaTileDescriptor.sticker(_sticker(), false, false),
        actions: MediaTileActions(send: () {}, copy: () {}),
      );
      expect(
        find.byKey(const ValueKey('mediaTileAction-copy')),
        findsOneWidget,
      );
      // Desktop save uses the "Save to File" label; the gallery wording must
      // not appear.
      expect(
        find.text(AppStrings.t(AppStringKeys.mediaTileSaveToGallery)),
        findsNothing,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('tapping send pops the sheet and fires the callback', (
    tester,
  ) async {
    var sent = false;
    await _openSheet(
      tester,
      descriptor: MediaTileDescriptor.sticker(_sticker(), false, false),
      actions: MediaTileActions(send: () => sent = true),
    );
    await tester.tap(find.byKey(const ValueKey('mediaTileAction-send')));
    await tester.pumpAndSettle();
    expect(sent, isTrue);
    expect(find.byKey(const ValueKey('mediaTileAction-send')), findsNothing);
  });
}
