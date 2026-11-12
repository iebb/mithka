import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/media/video_playback_reporting.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:video_player/video_player.dart';

void main() {
  late List<SentryEvent> events;
  late VideoFailureReporter reporter;
  late DateTime now;

  setUp(() {
    now = DateTime.utc(2026, 9, 22);
    events = [];
    reporter = VideoFailureReporter(
      enabled: () => true,
      capture: (event) async => events.add(event),
      now: () => now,
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  VideoPlaybackDiagnostics session({
    VideoPlaybackLocation location = VideoPlaybackLocation.player,
    String? mimeType = 'video/mp4',
  }) => VideoPlaybackDiagnostics(
    location: location,
    mimeType: mimeType,
    reporter: reporter,
  );

  test(
    'disabled telemetry and capture failures never escape into playback',
    () async {
      final disabled = VideoFailureReporter(
        enabled: () => false,
        capture: (event) async => events.add(event),
      );
      VideoPlaybackDiagnostics(
        location: VideoPlaybackLocation.player,
        reporter: disabled,
      ).reportTerminal();
      expect(events, isEmpty);
      final broken = VideoFailureReporter(
        enabled: () => true,
        capture: (_) => throw StateError('offline'),
      );
      VideoPlaybackDiagnostics(
        location: VideoPlaybackLocation.player,
        reporter: broken,
      ).reportTerminal();
      await Future<void>.value();
    },
  );

  test(
    'history is bounded and an unrecognized MIME type is never transmitted',
    () {
      final diagnostics = session(mimeType: 'video/PRIVATE-TITLE');
      for (var i = 0; i < 30; i++) {
        diagnostics.beginAttempt(
          source: VideoPlaybackSource.file,
          viewType: VideoViewType.textureView,
        );
        diagnostics.recordFailure(
          TimeoutException('PRIVATE'),
          stage: VideoFailureStage.initialization,
        );
      }
      diagnostics.reportTerminal();
      final context = events.single.contexts['video_playback'] as Map;
      expect(context['failures'], hasLength(6));
      expect(context['attempts'], 30);
      expect(context['mime_type'], 'unknown');
      expect(events.single.tags!['video.reason'], 'timeout');
      expect(jsonEncode(events.single.toJson()), isNot(contains('PRIVATE')));
    },
  );

  test(
    'beforeSend removes ambient private data but retains device diagnostics',
    () {
      session().reportTerminal();
      final event = events.single;
      final device = SentryDevice.fromJson({
        'name': 'PRIVATE',
        'id': 'PRIVATE',
        'model': 'A142',
        'manufacturer': 'Nothing',
        'arch': 'arm64',
        'low_memory': true,
      });
      event.contexts.device = device;
      event.contexts.operatingSystem = SentryOperatingSystem(
        name: 'Android',
        version: '14',
        rawDescription: 'PRIVATE',
        kernelVersion: 'PRIVATE',
      );
      final app = SentryApp.fromJson({
        'app_identifier': 'ad.neko.mithka',
        'app_version': '1.5.3',
        'app_memory': 123456,
        'device_app_hash': 'PRIVATE',
        'view_names': ['PRIVATE'],
        'future_sdk_field': 'PRIVATE',
      });
      event.contexts.app = app;
      event.contexts.runtimes = [
        SentryRuntime.fromJson({
          'name': 'Dart',
          'version': '3.12.2',
          'raw_description': 'PRIVATE',
          'future_sdk_field': 'PRIVATE',
        }),
      ];
      event.contexts.gpu = SentryGpu.fromJson({
        'name': 'Adreno',
        'api_type': 'OpenGL ES',
        'future_sdk_field': 'PRIVATE',
      });
      event.contexts['chat'] = {'title': 'PRIVATE'};
      event.release = 'mithka@1.5.3';
      event.tags!['git.commit'] = 'abc123';
      event.tags!['chat_id'] = 'PRIVATE';
      event.user = SentryUser(id: 'PRIVATE', email: 'PRIVATE');
      event.request = SentryRequest(url: 'https://PRIVATE/video.mp4');
      event.breadcrumbs = [Breadcrumb(message: 'PRIVATE')];
      event.transaction = '/chat/PRIVATE/video';
      event.serverName = 'PRIVATE';
      // ignore: deprecated_member_use
      event.extra = {'source': 'PRIVATE'};
      sanitizeVideoPlaybackEvent(event);
      expect(jsonEncode(event.toJson()), isNot(contains('PRIVATE')));
      expect(event.contexts.device!.model, 'A142');
      expect(event.contexts.device!.lowMemory, isTrue);
      expect(event.contexts.operatingSystem!.version, '14');
      expect(event.contexts.app!.version, '1.5.3');
      expect(event.contexts.app!.appMemory, 123456);
      expect(event.contexts.runtimes.single.version, '3.12.2');
      expect(event.contexts.gpu!.name, 'Adreno');
      expect(event.release, 'mithka@1.5.3');
      expect(event.tags!['git.commit'], 'abc123');
      expect(event.transaction, 'video.playback');
      expect(
        device.name,
        'PRIVATE',
        reason: 'Do not mutate shared SDK context',
      );
      expect(app.deviceAppHash, 'PRIVATE');
      expect(app.viewNames, ['PRIVATE']);
    },
  );

  test('a URL query or platform details cannot become a native error code', () {
    session()
      ..recordFailure(
        PlatformException(
          code: 'VideoError',
          message: 'Decoder failed https://private.invalid/file?code=123456',
          details: 'errorCode=987654',
        ),
        stage: VideoFailureStage.initialization,
      )
      ..reportTerminal();
    final failure =
        events.single.contexts['video_playback']['failures'].single as Map;
    expect(failure.containsKey('native_code'), isFalse);
    expect(
      jsonEncode(events.single.toJson()),
      isNot(contains('private.invalid')),
    );
  });
}
