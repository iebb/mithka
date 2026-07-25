import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/performance_metrics.dart';

void main() {
  test('idle avatar stops do not bypass gauge throttling', () {
    var now = DateTime.utc(2026, 7, 25);
    final reports = <int>[];
    final metrics = AnimatedAvatarMetricThrottle(
      clock: () => now,
      onReport: reports.add,
    );

    metrics.playerStarted();
    metrics.playerStopped();
    metrics.playerStopped();
    expect(reports, [1, 0]);

    metrics.playerStarted();
    metrics.playerStopped();
    expect(
      reports,
      [1, 0],
      reason: 'a repeated idle transition remains inside the throttle window',
    );

    now = now.add(const Duration(seconds: 10));
    metrics.playerStarted();
    metrics.playerStopped();
    expect(reports, [1, 0, 1, 0]);
  });
}
