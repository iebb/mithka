import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _bytesPerMiB = 1024 * 1024;
const _slowFrameThreshold = Duration(microseconds: 16667);

/// A decoded-image budget sized for chat surfaces with many small thumbnails.
///
/// Flutter's default cache is 100 MiB and 1000 images. Mithka supplies decode
/// dimensions for chat avatars and media, so a smaller entry count and byte
/// budget retain useful thumbnails without keeping an excessive decoded-image
/// working set alive.
@immutable
class AppImageCacheBudget {
  const AppImageCacheBudget({required this.entries, required this.bytes});

  final int entries;
  final int bytes;
}

AppImageCacheBudget appImageCacheBudgetFor(TargetPlatform platform) {
  return switch (platform) {
    TargetPlatform.android => const AppImageCacheBudget(
      entries: 320,
      bytes: 64 * _bytesPerMiB,
    ),
    TargetPlatform.iOS => const AppImageCacheBudget(
      entries: 400,
      bytes: 80 * _bytesPerMiB,
    ),
    _ => const AppImageCacheBudget(entries: 600, bytes: 128 * _bytesPerMiB),
  };
}

void configureAppImageCache({ImageCache? cache, TargetPlatform? platform}) {
  final target = cache ?? PaintingBinding.instance.imageCache;
  final budget = appImageCacheBudgetFor(platform ?? defaultTargetPlatform);
  target.maximumSize = budget.entries;
  target.maximumSizeBytes = budget.bytes;
}

@immutable
class AppFrameStats {
  const AppFrameStats({
    required this.sampleCount,
    required this.slowFrameCount,
    required this.averageBuildMs,
    required this.averageRasterMs,
    required this.p95TotalMs,
  });

  const AppFrameStats.empty()
    : sampleCount = 0,
      slowFrameCount = 0,
      averageBuildMs = 0,
      averageRasterMs = 0,
      p95TotalMs = 0;

  final int sampleCount;
  final int slowFrameCount;
  final double averageBuildMs;
  final double averageRasterMs;
  final double p95TotalMs;
}

class _AppFrameSample {
  const _AppFrameSample({
    required this.build,
    required this.raster,
    required this.total,
  });

  final Duration build;
  final Duration raster;
  final Duration total;
}

/// Fixed-size sampling window so enabling diagnostics cannot create a leak.
class AppFramePerformanceWindow {
  AppFramePerformanceWindow({this.capacity = 240}) : assert(capacity > 0);

  final int capacity;
  final ListQueue<_AppFrameSample> _samples = ListQueue<_AppFrameSample>();

  void add({
    required Duration build,
    required Duration raster,
    required Duration total,
  }) {
    _samples.addLast(
      _AppFrameSample(build: build, raster: raster, total: total),
    );
    while (_samples.length > capacity) {
      _samples.removeFirst();
    }
  }

  void addTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      add(
        build: timing.buildDuration,
        raster: timing.rasterDuration,
        total: timing.totalSpan,
      );
    }
  }

  AppFrameStats get stats {
    if (_samples.isEmpty) return const AppFrameStats.empty();
    var buildMicros = 0;
    var rasterMicros = 0;
    var slowFrames = 0;
    final totals = <int>[];
    for (final sample in _samples) {
      buildMicros += sample.build.inMicroseconds;
      rasterMicros += sample.raster.inMicroseconds;
      totals.add(sample.total.inMicroseconds);
      if (sample.total > _slowFrameThreshold) slowFrames++;
    }
    totals.sort();
    final p95Index = ((totals.length * 0.95).ceil() - 1).clamp(
      0,
      totals.length - 1,
    );
    return AppFrameStats(
      sampleCount: _samples.length,
      slowFrameCount: slowFrames,
      averageBuildMs: buildMicros / _samples.length / 1000,
      averageRasterMs: rasterMicros / _samples.length / 1000,
      p95TotalMs: totals[p95Index] / 1000,
    );
  }

  void clear() => _samples.clear();
}

@immutable
class AppPerformanceSnapshot {
  const AppPerformanceSnapshot({
    required this.processRssBytes,
    required this.imageCacheBytes,
    required this.imageCacheEntries,
    required this.liveImageCount,
    required this.frameStats,
  });

  final int processRssBytes;
  final int imageCacheBytes;
  final int imageCacheEntries;
  final int liveImageCount;
  final AppFrameStats frameStats;
}

typedef AppMemoryTrimmer = void Function();
typedef AppRssReader = int Function();

/// Opt-in frame/RSS diagnostics plus always-on memory-pressure handling.
///
/// Frame timings and periodic RSS sampling are attached only while profiling is
/// enabled and the app is foregrounded. Cache trimming remains available in
/// production without a sampling timer.
class AppPerformanceController extends ChangeNotifier
    with WidgetsBindingObserver {
  AppPerformanceController(
    this._preferences, {
    ImageCache? imageCache,
    List<AppMemoryTrimmer> memoryTrimmers = const [],
    AppRssReader? rssReader,
  }) : _imageCache = imageCache ?? PaintingBinding.instance.imageCache,
       _memoryTrimmers = List<AppMemoryTrimmer>.unmodifiable(memoryTrimmers),
       _rssReader = rssReader ?? _readCurrentRss,
       _profilingEnabled = _preferences.getBool(_profilingEnabledKey) ?? false,
       _snapshot = AppPerformanceSnapshot(
         processRssBytes: 0,
         imageCacheBytes: (imageCache ?? PaintingBinding.instance.imageCache)
             .currentSizeBytes,
         imageCacheEntries:
             (imageCache ?? PaintingBinding.instance.imageCache).currentSize,
         liveImageCount:
             (imageCache ?? PaintingBinding.instance.imageCache).liveImageCount,
         frameStats: const AppFrameStats.empty(),
       );

  static const _profilingEnabledKey =
      'developer_mode.performance_profiler_enabled';
  static const _sampleInterval = Duration(seconds: 2);

  final SharedPreferences _preferences;
  final ImageCache _imageCache;
  final List<AppMemoryTrimmer> _memoryTrimmers;
  final AppRssReader _rssReader;
  final AppFramePerformanceWindow _frames = AppFramePerformanceWindow();

  bool _started = false;
  bool _foregrounded = true;
  bool _timingsAttached = false;
  bool _profilingEnabled;
  Timer? _sampleTimer;
  AppPerformanceSnapshot _snapshot;

  bool get profilingEnabled => _profilingEnabled;
  AppPerformanceSnapshot get snapshot => _snapshot;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _foregrounded =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (_profilingEnabled && _foregrounded) _startSampling();
  }

  set profilingEnabled(bool value) {
    if (_profilingEnabled == value) return;
    _profilingEnabled = value;
    unawaited(_preferences.setBool(_profilingEnabledKey, value));
    if (value && _started && _foregrounded) {
      _startSampling();
    } else {
      _stopSampling();
    }
    _updateSnapshot();
  }

  void resetFrameSamples() {
    _frames.clear();
    _updateSnapshot();
  }

  /// Releases reusable memory. Active image widgets remain valid and can
  /// repopulate the cache after the trim.
  void trimMemoryCaches() {
    _imageCache.clear();
    _imageCache.clearLiveImages();
    for (final trim in _memoryTrimmers) {
      try {
        trim();
      } catch (error) {
        debugPrint('Memory cache trim failed: $error');
      }
    }
    _updateSnapshot();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foregrounded = state == AppLifecycleState.resumed;
    if (_foregrounded == foregrounded) return;
    _foregrounded = foregrounded;
    if (foregrounded) {
      if (_profilingEnabled) _startSampling();
      return;
    }

    _stopSampling();
    // Keep live images needed by mounted widgets, but release completed cached
    // images while the app is in the background.
    _imageCache.clear();
  }

  @override
  void didHaveMemoryPressure() => trimMemoryCaches();

  void _startSampling() {
    if (!_timingsAttached) {
      WidgetsBinding.instance.addTimingsCallback(_handleFrameTimings);
      _timingsAttached = true;
    }
    _sampleTimer ??= Timer.periodic(_sampleInterval, (_) => _updateSnapshot());
    _updateSnapshot();
  }

  void _stopSampling() {
    _sampleTimer?.cancel();
    _sampleTimer = null;
    if (_timingsAttached) {
      WidgetsBinding.instance.removeTimingsCallback(_handleFrameTimings);
      _timingsAttached = false;
    }
  }

  void _handleFrameTimings(List<FrameTiming> timings) {
    _frames.addTimings(timings);
  }

  void _updateSnapshot() {
    var rss = 0;
    if (_profilingEnabled) {
      try {
        rss = _rssReader();
      } catch (_) {
        // RSS is not available on every Flutter target.
      }
    }
    _snapshot = AppPerformanceSnapshot(
      processRssBytes: rss,
      imageCacheBytes: _imageCache.currentSizeBytes,
      imageCacheEntries: _imageCache.currentSize,
      liveImageCount: _imageCache.liveImageCount,
      frameStats: _frames.stats,
    );
    notifyListeners();
  }

  static int _readCurrentRss() => ProcessInfo.currentRss;

  @override
  void dispose() {
    _stopSampling();
    if (_started) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
