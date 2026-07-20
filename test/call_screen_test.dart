import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/call/call_manager.dart';
import 'package:mithka/call/call_media_engine.dart';
import 'package:mithka/call/call_screen.dart';
import 'package:mithka/call/calls_view.dart';
import 'package:mithka/components/photo_avatar.dart';

void main() {
  test('call history uses the pinned dedicated TDLib search method', () {
    expect(callHistorySearchRequest(offset: 'next', limit: 25), {
      '@type': 'searchCallMessages',
      'offset': 'next',
      'limit': 25,
      'only_missed': false,
    });
  });

  test(
    'selects the first locally preferred call version supported by peer',
    () {
      expect(
        selectCallLibraryVersion(
          localVersions: const ['13.0.0', '12.0.0', '11.0.0'],
          remoteVersions: const ['11.0.0', '13.0.0'],
        ),
        '13.0.0',
      );
      expect(
        selectCallLibraryVersion(
          localVersions: const ['13.0.0'],
          remoteVersions: const ['12.0.0'],
        ),
        isNull,
      );
    },
  );

  testWidgets('video call controls use equally spaced centered slots', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final manager = CallManager(engine: NoopCallMediaEngine());
    addTearDown(manager.dispose);
    manager.call = ActiveCall(
      callId: 42,
      peerUserId: 7,
      peerName: 'Video contact',
      isOutgoing: true,
      isVideo: true,
      phase: CallPhase.active,
      startedAt: DateTime.now(),
    );
    manager.isVideoEnabled = true;

    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedBuilder(
          animation: manager,
          builder: (context, child) => CallScreen(manager: manager),
        ),
      ),
    );

    final mute = tester.getCenter(find.byKey(const Key('callControlMute')));
    final camera = tester.getCenter(find.byKey(const Key('callControlCamera')));
    final speaker = tester.getCenter(
      find.byKey(const Key('callControlSpeaker')),
    );

    expect(camera.dx - mute.dx, closeTo(speaker.dx - camera.dx, 0.01));
    expect(camera.dx, closeTo(195, 0.01));
    expect(mute.dy, closeTo(camera.dy, 0.01));
    expect(camera.dy, closeTo(speaker.dy, 0.01));
  });

  testWidgets('active video controls hide and return when surface is tapped', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final manager = CallManager(engine: NoopCallMediaEngine());
    addTearDown(manager.dispose);
    manager.call = ActiveCall(
      callId: 44,
      peerUserId: 9,
      peerName: 'Video contact',
      isOutgoing: true,
      isVideo: true,
      phase: CallPhase.active,
      startedAt: DateTime.now(),
    );
    manager.isVideoEnabled = true;

    await tester.pumpWidget(MaterialApp(home: CallScreen(manager: manager)));

    AnimatedOpacity overlay() => tester.widget<AnimatedOpacity>(
      find.byKey(const Key('callControlsOverlay')),
    );

    expect(overlay().opacity, 1);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 180));
    expect(overlay().opacity, 0);

    await tester.tap(find.byKey(const Key('callSurfaceTap')));
    await tester.pump();
    expect(overlay().opacity, 1);
  });

  testWidgets('outgoing video call shows local preview while ringing', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final manager = CallManager(engine: NoopCallMediaEngine());
    addTearDown(manager.dispose);
    manager.call = ActiveCall(
      callId: 46,
      peerUserId: 11,
      peerName: 'Ringing contact',
      isOutgoing: true,
      isVideo: true,
      phase: CallPhase.ringingOutgoing,
    );
    manager.isVideoEnabled = true;

    await tester.pumpWidget(MaterialApp(home: CallScreen(manager: manager)));

    expect(find.byKey(const Key('callLocalPreview')), findsOneWidget);
    expect(find.byType(PhotoAvatar), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    final overlay = tester.widget<AnimatedOpacity>(
      find.byKey(const Key('callControlsOverlay')),
    );
    expect(overlay.opacity, 1);
  });

  testWidgets('landscape call controls stay horizontal without overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(844, 390));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final manager = CallManager(engine: NoopCallMediaEngine());
    addTearDown(manager.dispose);
    manager.call = ActiveCall(
      callId: 45,
      peerUserId: 10,
      peerName: 'Landscape contact',
      isOutgoing: true,
      isVideo: true,
      phase: CallPhase.active,
      startedAt: DateTime.now(),
      emojis: const ['🚀', '🔴', '🚀', '⚽'],
    );
    manager.isVideoEnabled = true;

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(844, 390),
            padding: EdgeInsets.symmetric(horizontal: 59),
          ),
          child: AnimatedBuilder(
            animation: manager,
            builder: (context, child) => CallScreen(manager: manager),
          ),
        ),
      ),
    );

    final mute = tester.getCenter(find.byKey(const Key('callControlMute')));
    final camera = tester.getCenter(find.byKey(const Key('callControlCamera')));
    final speaker = tester.getCenter(
      find.byKey(const Key('callControlSpeaker')),
    );
    final hangup = tester.getCenter(find.byKey(const Key('callControlHangup')));
    expect(mute.dy, closeTo(camera.dy, 0.01));
    expect(camera.dy, closeTo(speaker.dy, 0.01));
    expect(speaker.dy, closeTo(hangup.dy, 0.01));
    expect(tester.takeException(), isNull);

    manager.disableVideo();
    await tester.pump();

    final identity = tester.getRect(find.byKey(const Key('callIdentityPanel')));
    final controls = tester.getRect(find.byKey(const Key('callControlsPanel')));
    expect(identity.center.dx, lessThan(controls.center.dx));
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('callControlCamera')));
    await tester.pump();
    expect(manager.isVideoEnabled, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('active calls can switch from voice to video and back', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final engine = _RecordingCallMediaEngine();
    final manager = CallManager(engine: engine);
    addTearDown(manager.dispose);
    manager.call = ActiveCall(
      callId: 43,
      peerUserId: 8,
      peerName: 'Voice contact',
      isOutgoing: true,
      isVideo: false,
      phase: CallPhase.active,
      startedAt: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedBuilder(
          animation: manager,
          builder: (context, child) => CallScreen(manager: manager),
        ),
      ),
    );

    expect(find.byKey(const Key('callControlCamera')), findsOneWidget);
    expect(find.byType(PhotoAvatar), findsOneWidget);

    await tester.tap(find.byKey(const Key('callControlCamera')));
    await tester.pump();
    expect(manager.isVideoEnabled, isTrue);
    expect(engine.videoChanges, [true]);
    expect(find.byType(PhotoAvatar), findsNothing);

    await tester.tap(find.byKey(const Key('callControlCamera')));
    await tester.pump();
    expect(manager.isVideoEnabled, isFalse);
    expect(engine.videoChanges, [true, false]);
    expect(find.byType(PhotoAvatar), findsOneWidget);
    expect(find.byKey(const Key('callControlCamera')), findsOneWidget);
  });

  testWidgets('outgoing voice call can enable video before it is answered', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final engine = _RecordingCallMediaEngine();
    final manager = CallManager(engine: engine);
    addTearDown(manager.dispose);
    manager.call = ActiveCall(
      callId: 47,
      peerUserId: 12,
      peerName: 'Ringing voice contact',
      isOutgoing: true,
      isVideo: false,
      phase: CallPhase.ringingOutgoing,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedBuilder(
          animation: manager,
          builder: (context, child) => CallScreen(manager: manager),
        ),
      ),
    );

    expect(find.byKey(const Key('callControlCamera')), findsOneWidget);
    await tester.tap(find.byKey(const Key('callControlCamera')));
    await tester.pump();

    expect(manager.isVideoEnabled, isTrue);
    expect(engine.videoChanges, [true]);
    expect(find.byKey(const Key('callLocalPreview')), findsOneWidget);
  });
}

class _RecordingCallMediaEngine implements CallMediaEngine {
  final List<bool> videoChanges = [];

  @override
  set onSignalingData(void Function(Uint8List data)? callback) {}

  @override
  Future<Map<String, dynamic>?> queryProtocol() async => null;

  @override
  void receiveSignaling(Uint8List data) {}

  @override
  void setMuted(bool muted) {}

  @override
  void setSpeaker(bool speaker) {}

  @override
  void setVideoEnabled(bool enabled, {bool front = true}) {
    videoChanges.add(enabled);
  }

  @override
  void start(CallReadyConfig config) {}

  @override
  void stop() {}

  @override
  void switchCamera() {}
}
