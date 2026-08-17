import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/video_note_preview_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Used only to install a deterministic fake for the public video_player API.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'video-note review exposes volume and restores its audible level',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });

      final previousPlatform = VideoPlayerPlatform.instance;
      final platform = _FakeVideoNotePlatform();
      VideoPlayerPlatform.instance = platform;
      addTearDown(() => VideoPlayerPlatform.instance = previousPlatform);
      SharedPreferences.setMockInitialValues(const {});
      final theme = ThemeController(await SharedPreferences.getInstance());

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [AppLocalizations.delegate],
            supportedLocales: AppLocalizations.supportedLocales,
            home: VideoNotePreviewView(
              path: File('pubspec.yaml').absolute.path,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final slider = find.byKey(const ValueKey('videoNoteVolumeSlider'));
      expect(slider, findsOneWidget);
      expect(tester.getRect(slider).height, 44);
      final rect = tester.getRect(slider);
      await tester.tapAt(Offset(rect.left + rect.width * 0.25, rect.center.dy));
      await tester.pump();
      expect(platform.volumeValues.last, closeTo(0.25, 0.04));

      await tester.tap(find.byKey(const ValueKey('videoNoteMuteButton')));
      await tester.pump();
      expect(platform.volumeValues.last, 0);
      await tester.tap(find.byKey(const ValueKey('videoNoteMuteButton')));
      await tester.pump();
      expect(platform.volumeValues.last, closeTo(0.25, 0.04));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      theme.dispose();
    },
  );
}

class _FakeVideoNotePlatform extends VideoPlayerPlatform {
  final _events = StreamController<VideoEvent>.broadcast();
  final volumeValues = <double>[];

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async => 1;

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    scheduleMicrotask(() {
      if (!_events.isClosed) {
        _events.add(
          VideoEvent(
            eventType: VideoEventType.initialized,
            duration: const Duration(seconds: 30),
            size: const Size(720, 720),
          ),
        );
      }
    });
    return _events.stream;
  }

  @override
  Future<void> dispose(int playerId) => _events.close();

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {
    volumeValues.add(volume);
  }

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const SizedBox.expand();
}
