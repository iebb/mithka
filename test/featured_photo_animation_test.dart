import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/full_image_viewer.dart';
import 'package:mithka/chat/looping_video_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/profile/profile_detail_view.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/l10n_fixtures.dart';

// Telegram delivers an animated profile photo as a `chatPhoto` whose still
// `sizes` and silent-MP4 `animation` are separate files. The featured strip
// must advertise that motion without decoding a dozen videos, and the full
// viewer must actually play it while keeping the still for the poster and the
// photo-library save.

Map<String, dynamic> _fileJson(int id, String path) => {
  '@type': 'file',
  'id': id,
  'local': {
    '@type': 'localFile',
    'path': path,
    'is_downloading_completed': true,
  },
};

Map<String, dynamic> _chatPhoto({
  required int id,
  required int stillFileId,
  required String stillPath,
  int? animationFileId,
  String? animationPath,
  bool smallAnimationOnly = false,
}) {
  Map<String, dynamic> animation(int fileId) => {
    '@type': 'animatedChatPhoto',
    'length': 3,
    'main_frame_timestamp': 0.0,
    'file': _fileJson(fileId, animationPath!),
  };

  return {
    '@type': 'chatPhoto',
    'id': id,
    'added_date': 0,
    'sizes': [
      {
        '@type': 'photoSize',
        'type': 'y',
        'width': 320,
        'height': 320,
        'photo': _fileJson(stillFileId, stillPath),
      },
    ],
    if (animationFileId != null && !smallAnimationOnly)
      'animation': animation(animationFileId),
    if (animationFileId != null && smallAnimationOnly)
      'small_animation': animation(animationFileId),
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  L10nFixtures.load().install();

  late Directory directory;
  late String stillPath;
  late String otherStillPath;
  late String animationPath;
  late List<Map<String, dynamic>> profilePhotos;

  setUpAll(() {
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async => switch (request['@type']) {
          'getMe' => {
            '@type': 'user',
            'id': 1,
            'type': {'@type': 'userTypeRegular'},
          },
          'getUser' => {
            '@type': 'user',
            'id': 1,
            'first_name': 'Me',
            'profile_photo': {
              '@type': 'chatPhotoInfo',
              'small': _fileJson(101, stillPath),
            },
            'type': {'@type': 'userTypeRegular'},
          },
          'getUserProfilePhotos' => {
            '@type': 'photos',
            'total_count': profilePhotos.length,
            'photos': profilePhotos,
          },
          _ => {'@type': 'ok'},
        },
        send: (_) async {},
        updates: const Stream<Map<String, dynamic>>.empty(),
      ),
    );
  });
  tearDownAll(TdClient.shared.closeProxy);

  setUp(() {
    directory = Directory.systemTemp.createTempSync(
      'mithka-featured-photo-animation-',
    );
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
      'AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    // Both stills and the animation need real paths: TdFileCenter
    // short-circuits on an existing file instead of arming a download waiter,
    // and the player is constructed from the animation path. Its bytes never
    // decode under `flutter test` — the platform channel is absent — so the
    // tests assert on the widget's file/fallback refs, not on frames.
    stillPath = '${directory.path}/still.png';
    otherStillPath = '${directory.path}/other.png';
    animationPath = '${directory.path}/animation.mp4';
    File(stillPath).writeAsBytesSync(png);
    File(otherStillPath).writeAsBytesSync(png);
    File(animationPath).writeAsBytesSync(const [0, 0, 0, 0]);
    profilePhotos = [];
  });
  tearDown(() => directory.deleteSync(recursive: true));

  Future<void> pumpOwnProfile(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final theme = ThemeController(await SharedPreferences.getInstance());
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          theme: ThemeData(
            extensions: [AppColors.light],
            // Keeps the featured-photo flow on the in-app viewer: profile
            // actions suppress the desktop preview window.
            platform: TargetPlatform.android,
          ),
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ProfileDetailView(userId: 1, name: 'Me'),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> openFirstTile(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('featured-photo-tile-0')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(FullImageViewer), findsOneWidget);
  }

  // The animation file resolves through real IO. Let that window run so the
  // player's (unsupported) initialization is attempted, fails, and disposes
  // before the test ends instead of leaving platform-channel work pending.
  Future<void> settlePlayer(WidgetTester tester) async {
    for (var round = 0; round < 3; round++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
  }

  testWidgets(
    'animated featured photo badges its tile and plays in the viewer',
    (tester) async {
      profilePhotos = [
        _chatPhoto(
          id: 5,
          stillFileId: 10,
          stillPath: stillPath,
          animationFileId: 12,
          animationPath: animationPath,
        ),
        _chatPhoto(id: 6, stillFileId: 11, stillPath: otherStillPath),
      ];
      await pumpOwnProfile(tester);

      expect(
        find.byKey(const ValueKey('featured-photo-animation-badge')),
        findsOneWidget,
        reason: 'only the animated photo gets the play badge',
      );
      expect(
        find.byType(LoopingVideoView),
        findsNothing,
        reason: 'the strip keeps still frames instead of mounting decoders',
      );

      await openFirstTile(tester);

      final player = tester.widget<LoopingVideoView>(
        find.byType(LoopingVideoView),
      );
      expect(player.file.id, 12, reason: 'the silent MP4 is what plays');
      expect(
        player.fallback?.id,
        10,
        reason: 'the still remains the poster under the animation',
      );

      final viewer = tester.widget<FullImageViewer>(
        find.byType(FullImageViewer),
      );
      expect(
        viewer.items.map((item) => item.id),
        [10, 11],
        reason: 'the gallery keeps still refs; saving reads these, not the MP4',
      );
      expect(
        viewer.animations.map((item) => item?.id),
        [12, null],
        reason: 'only the animated photo carries a motion variant',
      );

      await settlePlayer(tester);

      // Paging to the still-only photo must not leave a player mounted for it.
      // The still's file resolution needs real IO, so its placeholder keeps
      // animating: pump explicit frames rather than waiting for settle.
      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('2 / 2'), findsOneWidget);
      expect(find.byType(LoopingVideoView), findsNothing);
    },
  );

  testWidgets('a still-only featured photo mounts no player', (tester) async {
    profilePhotos = [
      _chatPhoto(id: 6, stillFileId: 11, stillPath: otherStillPath),
    ];
    await pumpOwnProfile(tester);

    expect(
      find.byKey(const ValueKey('featured-photo-animation-badge')),
      findsNothing,
    );

    await openFirstTile(tester);

    expect(find.byType(LoopingVideoView), findsNothing);
    final viewer = tester.widget<FullImageViewer>(find.byType(FullImageViewer));
    expect(viewer.items.single.id, 11);
    expect(viewer.animations.single, isNull);
  });

  testWidgets('falls back to small_animation when no full animation exists', (
    tester,
  ) async {
    profilePhotos = [
      _chatPhoto(
        id: 7,
        stillFileId: 14,
        stillPath: stillPath,
        animationFileId: 13,
        animationPath: animationPath,
        smallAnimationOnly: true,
      ),
    ];
    await pumpOwnProfile(tester);

    expect(
      find.byKey(const ValueKey('featured-photo-animation-badge')),
      findsOneWidget,
    );

    await openFirstTile(tester);

    final player = tester.widget<LoopingVideoView>(
      find.byType(LoopingVideoView),
    );
    expect(player.file.id, 13);
    expect(player.fallback?.id, 14);
    await settlePlayer(tester);
  });
}
