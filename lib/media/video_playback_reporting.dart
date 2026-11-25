import 'dart:async';

import 'package:cineplay/cineplay.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:video_player/video_player.dart';

import '../app/telemetry_config.dart';

enum VideoPlaybackLocation { player, desktopWindow, inline, sticker, story }

enum VideoPlaybackSource { file, loopback }

enum VideoFailureStage { source, initialization, playback, stall, download }

enum VideoFailureReason {
  sourceUnavailable,
  timeout,
  stalled,
  resource,
  platformUnavailable,
  surface,
  decoder,
  unsupportedFormat,
  network,
  unknown,
}

/// One diagnostics session per media selection. Recovery records stay local;
/// only a terminal failure is submitted, including when the user retries it.
/// Never retains an exception, URL, file name/path, media ID or chat identity.
class VideoPlaybackDiagnostics {
  VideoPlaybackDiagnostics({
    required this.location,
    String? mimeType,
    int? width,
    int? height,
    VideoFailureReporter? reporter,
  }) : _mimeType = _safeMimeType(mimeType),
       _width = _safeDimension(width),
       _height = _safeDimension(height),
       _reporter = reporter ?? VideoFailureReporter.instance;

  final VideoPlaybackLocation location;
  final String _mimeType;
  final VideoFailureReporter _reporter;
  int? _width;
  int? _height;
  final List<Map<String, Object>> _failures = [];
  VideoPlaybackSource _source = VideoPlaybackSource.file;
  VideoViewType _viewType = VideoViewType.textureView;
  int _attempts = 0;
  bool _initialized = false;
  bool _reported = false;

  void beginAttempt({
    required VideoPlaybackSource source,
    required VideoViewType viewType,
  }) {
    _source = source;
    _viewType = viewType;
    _attempts++;
  }

  void initialized({VideoPlayerValue? value}) {
    _initialized = true;
    if (value != null && value.isInitialized) {
      _width = _safeDimension(value.size.width.toInt()) ?? _width;
      _height = _safeDimension(value.size.height.toInt()) ?? _height;
    }
  }

  void recordFailure(
    Object? error, {
    required VideoFailureStage stage,
    VideoFailureReason? reason,
    VideoPlaybackSource? source,
  }) {
    if (_reported) return;
    // FVideoPlayerError's own text can be a translated UI label. Its cause
    // carries the native error; neither string is ever included in the event.
    while (error is FVideoPlayerError && error.cause != null) {
      error = error.cause;
    }
    // Platform details often contain the whole data source. Do not inspect
    // those, and discard URLs before extracting even numeric diagnostic codes.
    final description = error is PlatformException
        ? '${error.code} ${error.message ?? ''}'
        : error?.toString() ?? '';
    final text = description.toLowerCase().replaceAll(
      RegExp(r'\b[a-z][a-z0-9+.-]*://\S+'),
      '',
    );
    final failure = <String, Object>{
      'attempt': _attempts,
      'source': (source ?? _source).name,
      'view_type': _viewType.name,
      'stage': stage.name,
      'reason': (reason ?? _classify(error, text)).name,
    };
    // Numeric native error codes and a fixed codec vocabulary are useful
    // across devices without forwarding messages containing private URLs.
    final code = RegExp(
      r'\b(?:errorcode|code)\s*[:=]\s*(-?\d{1,8})\b',
    ).firstMatch(text)?.group(1);
    if (code != null) failure['native_code'] = int.parse(code);
    final codec = RegExp(
      r'\b(avc|h264|hevc|h265|av1|vp9|vp8)\b',
    ).firstMatch(text)?.group(1);
    if (codec != null) failure['codec_hint'] = codec;
    if (_failures.length == 6) _failures.removeAt(0);
    _failures.add(failure);
  }

  void reportTerminal({
    int streamRecoveries = 0,
    bool completedFileFallback = false,
  }) {
    if (_reported) return;
    if (_failures.isEmpty) {
      recordFailure(null, stage: VideoFailureStage.source);
    }
    _reported = true;
    final last = _failures.last;
    final platform = kIsWeb ? 'web' : defaultTargetPlatform.name;
    final backend = kIsWeb
        ? 'web'
        : defaultTargetPlatform == TargetPlatform.android
        ? 'android_routed'
        : 'mdk';
    final tags = <String, String>{
      'video.location': location.name,
      'video.stage': last['stage']! as String,
      'video.reason': last['reason']! as String,
      'video.source': last['source']! as String,
      'video.view_type': last['view_type']! as String,
      'video.backend': backend,
      'video.platform': platform,
    };
    final fingerprint = [
      'mithka.video.v1',
      platform,
      location.name,
      tags['video.stage']!,
      tags['video.reason']!,
    ];
    final contexts = Contexts();
    contexts['video_playback'] = <String, Object>{
      'schema_version': 1,
      'mime_type': _mimeType,
      'width': ?_width,
      'height': ?_height,
      'attempts': _attempts,
      'ever_initialized': _initialized,
      'stream_recoveries': streamRecoveries,
      'completed_file_fallback': completedFileFallback,
      'failures': List<Map<String, Object>>.of(_failures),
    };
    _reporter.report(
      SentryEvent(
        logger: videoPlaybackLogger,
        level: SentryLevel.error,
        transaction: 'video.playback',
        message: SentryMessage('Video playback failed'),
        exceptions: [
          SentryException(
            type: 'VideoPlaybackFailure',
            value: '${last['stage']}: ${last['reason']}',
            mechanism: Mechanism(type: videoPlaybackLogger, handled: true),
          ),
        ],
        fingerprint: fingerprint,
        tags: tags,
        contexts: contexts,
      ),
    );
  }
}

/// Error events are independent of the 2% transaction sample rate. Bound them
/// per isolate: one per signature / 10 minutes, at most 20 total / rolling hour.
/// This is diagnostic sampling, not a count of all failed playback attempts.
class VideoFailureReporter {
  VideoFailureReporter({
    bool Function()? enabled,
    Future<void> Function(SentryEvent)? capture,
    DateTime Function()? now,
  }) : _enabled = enabled ?? (() => sentryEnabled),
       _capture = capture ?? _captureSentry,
       _now = now ?? DateTime.now;

  @visibleForTesting
  static VideoFailureReporter instance = VideoFailureReporter();

  final bool Function() _enabled;
  final Future<void> Function(SentryEvent) _capture;
  final DateTime Function() _now;
  final List<({DateTime at, String signature})> _sent = [];

  void report(SentryEvent event) {
    if (!_enabled()) return;
    final now = _now();
    _sent.removeWhere((s) => now.difference(s.at) >= const Duration(hours: 1));
    final signature = event.fingerprint!.join('/');
    if (_sent.length >= 20 ||
        _sent.any(
          (s) =>
              s.signature == signature &&
              now.difference(s.at) < const Duration(minutes: 10),
        )) {
      return;
    }
    // Reserve before starting the asynchronous send to prevent burst races.
    _sent.add((at: now, signature: signature));
    unawaited(_send(event));
  }

  Future<void> _send(SentryEvent event) async {
    try {
      await _capture(event);
    } catch (_) {
      // Telemetry failure must not change recovery, UI or controller disposal.
    }
  }

  static Future<void> _captureSentry(SentryEvent event) async {
    await Sentry.captureEvent(event);
  }
}

const videoPlaybackLogger = 'mithka.video';

/// Runs in beforeSend, AFTER scope/native enrichment. The SDK's device/OS data
/// is valuable, but ambient navigation breadcrumbs can contain private media
/// URLs and titles even though the video payload itself is allowlisted.
SentryEvent sanitizeVideoPlaybackEvent(SentryEvent event) {
  if (event.logger != videoPlaybackLogger) return event;
  final original = event.contexts;
  final device = original.device?.toJson();
  final os = original.operatingSystem;
  final app = original.app;
  final gpu = original.gpu;
  event.contexts = Contexts(
    device: device == null
        ? null
        : SentryDevice.fromJson({
            for (final key in const [
              'manufacturer',
              'brand',
              'family',
              'model',
              'model_id',
              'arch',
              'simulator',
              'memory_size',
              'free_memory',
              'usable_memory',
              'low_memory',
              'screen_width_pixels',
              'screen_height_pixels',
              'screen_density',
              'processor_count',
              'processor_frequency',
              'supports_vibration',
            ])
              if (device[key] != null) key: device[key],
          }),
    operatingSystem: os == null
        ? null
        : SentryOperatingSystem(
            name: os.name,
            version: os.version,
            build: os.build,
            rooted: os.rooted,
          ),
    runtimes: [
      for (final runtime in original.runtimes)
        SentryRuntime(
          name: runtime.name,
          version: runtime.version,
          compiler: runtime.compiler,
        ),
    ],
    // App context also contains a device-specific hash and visible view names.
    // Rebuild allowlisted contexts so neither these nor future SDK fields leak.
    app: app == null
        ? null
        : SentryApp(
            identifier: app.identifier,
            version: app.version,
            build: app.build,
            buildType: app.buildType,
            appMemory: app.appMemory,
            inForeground: app.inForeground,
          ),
    gpu: gpu == null
        ? null
        : SentryGpu(
            name: gpu.name,
            vendorName: gpu.vendorName,
            version: gpu.version,
            memorySize: gpu.memorySize,
            apiType: gpu.apiType,
            maxTextureSize: gpu.maxTextureSize,
          ),
  )..['video_playback'] = original['video_playback'];
  event.tags = {
    for (final entry in (event.tags ?? <String, String>{}).entries)
      if (const {
        'video.location',
        'video.stage',
        'video.reason',
        'video.source',
        'video.view_type',
        'video.backend',
        'video.platform',
        'app.version',
        'app.build_number',
        'git.commit',
      }.contains(entry.key))
        entry.key: entry.value,
  };
  event.breadcrumbs = [];
  event.request = null;
  event.user = null;
  event.serverName = null;
  event.transaction = 'video.playback';
  // ignore: deprecated_member_use
  event.extra = null;
  return event;
}

String _safeMimeType(String? value) =>
    const {
      'video/mp4',
      'video/webm',
      'video/quicktime',
      'video/x-matroska',
      'video/3gpp',
      'video/avi',
      'video/mpeg',
    }.contains(value)
    ? value!
    : 'unknown';

int? _safeDimension(int? value) =>
    value != null && value > 0 && value <= 16384 ? value : null;

VideoFailureReason _classify(Object? error, String text) {
  if (error == null) return VideoFailureReason.sourceUnavailable;
  if (text.contains('resource') ||
      text.contains('out of memory') ||
      text.contains('outofmemory') ||
      text.contains('thread constructor')) {
    return VideoFailureReason.resource;
  }
  if (error is MissingPluginException || text.contains('channel-error')) {
    return VideoFailureReason.platformUnavailable;
  }
  if (error is TimeoutException ||
      text.contains('timed out') ||
      text.contains('timeout')) {
    return VideoFailureReason.timeout;
  }
  if (text.contains('surface') || text.contains('anativewindow')) {
    return VideoFailureReason.surface;
  }
  if (text.contains('decoder') ||
      text.contains('mediacodec') ||
      text.contains('codecvideo') ||
      text.contains('framereader')) {
    return VideoFailureReason.decoder;
  }
  if (text.contains('unsupported') || text.contains('format')) {
    return VideoFailureReason.unsupportedFormat;
  }
  if (text.contains('http') ||
      text.contains('socket') ||
      text.contains('network') ||
      text.contains('no content') ||
      text.contains('connection')) {
    return VideoFailureReason.network;
  }
  return VideoFailureReason.unknown;
}
