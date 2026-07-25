import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'telemetry_config.dart';

typedef PerformanceMetricClock = DateTime Function();
typedef AnimatedAvatarGaugeReporter = void Function(int activePlayers);

/// Rate-limits animated-avatar player gauges while preserving active-to-idle
/// transitions. Repeated stop notifications while already idle are ignored.
@visibleForTesting
final class AnimatedAvatarMetricThrottle {
  AnimatedAvatarMetricThrottle({
    required this.onReport,
    this.reportInterval = const Duration(seconds: 10),
    PerformanceMetricClock? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration reportInterval;
  final AnimatedAvatarGaugeReporter onReport;
  final PerformanceMetricClock _clock;

  DateTime _nextReport = DateTime.fromMillisecondsSinceEpoch(0);
  int _activePlayers = 0;
  int? _lastReportedPlayers;

  void playerStarted() {
    _activePlayers++;
    _reportIfNeeded();
  }

  void playerStopped() {
    if (_activePlayers == 0) return;
    _activePlayers--;
    _reportIfNeeded(forceIdleTransition: _activePlayers == 0);
  }

  void _reportIfNeeded({bool forceIdleTransition = false}) {
    final now = _clock();
    final shouldForceIdle =
        forceIdleTransition &&
        _lastReportedPlayers != null &&
        _lastReportedPlayers != 0;
    if (!shouldForceIdle && now.isBefore(_nextReport)) return;
    _nextReport = now.add(reportInterval);
    _lastReportedPlayers = _activePlayers;
    onReport(_activePlayers);
  }
}

/// Low-volume, privacy-safe Sentry measurements for known UI hot paths.
///
/// These metrics contain only durations and aggregate counts. Reporting is
/// rate-limited so observability cannot itself become part of the problem.
abstract final class AppPerformanceMetrics {
  static const _chatListReportInterval = Duration(seconds: 30);

  static DateTime _nextChatListReport = DateTime.fromMillisecondsSinceEpoch(0);
  static double _slowestChatListResortMs = 0;
  static int _largestChatList = 0;
  static int _mostCoalescedUpdates = 0;
  static final _animatedAvatarMetrics = AnimatedAvatarMetricThrottle(
    onReport: (activePlayers) {
      if (!sentryEnabled) return;
      Sentry.metrics.gauge(
        'mithka.ui.animated_avatar.active_players',
        activePlayers,
      );
    },
  );

  static void chatListResorted({
    required Duration elapsed,
    required int chatCount,
    required int coalescedUpdates,
    required bool folderSelected,
  }) {
    if (!sentryEnabled) return;
    final elapsedMs =
        elapsed.inMicroseconds / Duration.microsecondsPerMillisecond;
    if (elapsedMs > _slowestChatListResortMs) {
      _slowestChatListResortMs = elapsedMs;
    }
    if (chatCount > _largestChatList) _largestChatList = chatCount;
    if (coalescedUpdates > _mostCoalescedUpdates) {
      _mostCoalescedUpdates = coalescedUpdates;
    }

    final now = DateTime.now();
    if (now.isBefore(_nextChatListReport)) return;
    _nextChatListReport = now.add(_chatListReportInterval);
    final attributes = <String, SentryAttribute>{
      'folder_selected': SentryAttribute.bool(folderSelected),
    };
    Sentry.metrics.distribution(
      'mithka.ui.chat_list.resort.duration',
      _slowestChatListResortMs,
      unit: SentryMetricUnit.millisecond,
      attributes: attributes,
    );
    Sentry.metrics.gauge(
      'mithka.ui.chat_list.chat_count',
      _largestChatList,
      attributes: attributes,
    );
    Sentry.metrics.gauge(
      'mithka.ui.chat_list.coalesced_updates',
      _mostCoalescedUpdates,
      attributes: attributes,
    );
    _slowestChatListResortMs = 0;
    _largestChatList = 0;
    _mostCoalescedUpdates = 0;
  }

  static void animatedAvatarPlayerStarted() =>
      _animatedAvatarMetrics.playerStarted();

  static void animatedAvatarPlayerStopped() =>
      _animatedAvatarMetrics.playerStopped();
}
