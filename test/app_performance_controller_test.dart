import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/app_performance_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('mobile image cache budgets stay below Flutter defaults', () {
    final android = appImageCacheBudgetFor(TargetPlatform.android);
    final ios = appImageCacheBudgetFor(TargetPlatform.iOS);

    expect(android.entries, 320);
    expect(android.bytes, 64 * 1024 * 1024);
    expect(ios.entries, 400);
    expect(ios.bytes, 80 * 1024 * 1024);

    final cache = ImageCache();
    configureAppImageCache(cache: cache, platform: TargetPlatform.android);
    expect(cache.maximumSize, android.entries);
    expect(cache.maximumSizeBytes, android.bytes);
  });

  test('frame profiler keeps a bounded rolling window', () {
    final window = AppFramePerformanceWindow(capacity: 3);
    window.add(
      build: const Duration(milliseconds: 1),
      raster: const Duration(milliseconds: 2),
      total: const Duration(milliseconds: 10),
    );
    window.add(
      build: const Duration(milliseconds: 2),
      raster: const Duration(milliseconds: 3),
      total: const Duration(milliseconds: 20),
    );
    window.add(
      build: const Duration(milliseconds: 3),
      raster: const Duration(milliseconds: 4),
      total: const Duration(milliseconds: 30),
    );
    window.add(
      build: const Duration(milliseconds: 4),
      raster: const Duration(milliseconds: 5),
      total: const Duration(milliseconds: 40),
    );

    final stats = window.stats;
    expect(stats.sampleCount, 3);
    expect(stats.slowFrameCount, 3);
    expect(stats.averageBuildMs, closeTo(3, 0.001));
    expect(stats.averageRasterMs, closeTo(4, 0.001));
    expect(stats.p95TotalMs, closeTo(40, 0.001));

    window.clear();
    expect(window.stats.sampleCount, 0);
  });

  test('manual trim invokes registered app cache trimmers', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    var trimCount = 0;
    final controller = AppPerformanceController(
      preferences,
      imageCache: ImageCache(),
      memoryTrimmers: [() => trimCount++],
      rssReader: () => 12 * 1024 * 1024,
    );
    addTearDown(controller.dispose);

    controller.profilingEnabled = true;
    expect(controller.snapshot.processRssBytes, 12 * 1024 * 1024);

    controller.trimMemoryCaches();
    expect(trimCount, 1);
  });
}
