import 'package:sentry_flutter/sentry_flutter.dart';

import 'telemetry_config.dart';

/// Low-volume, privacy-safe Sentry measurements for known UI hot paths.
///
/// These metrics contain only durations and aggregate counts. Reporting is
/// rate-limited so observability cannot itself become part of the problem.
abstract final class AppPerformanceMetrics {
  static const _chatListReportInterval = Duration(seconds: 30);
  static const _avatarReportInterval = Duration(seconds: 10);

  static DateTime _nextChatListReport = DateTime.fromMillisecondsSinceEpoch(0);
  static DateTime _nextAvatarReport = DateTime.fromMillisecondsSinceEpoch(0);
  static double _slowestChatListResortMs = 0;
  static int _largestChatList = 0;
  static int _mostCoalescedUpdates = 0;
  static int _activeAnimatedAvatarPlayers = 0;

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

  static void animatedAvatarPlayerStarted() {
    _activeAnimatedAvatarPlayers++;
    _reportAnimatedAvatarPlayers();
  }

  static void animatedAvatarPlayerStopped() {
    if (_activeAnimatedAvatarPlayers > 0) _activeAnimatedAvatarPlayers--;
    _reportAnimatedAvatarPlayers(forceWhenIdle: true);
  }

  static void _reportAnimatedAvatarPlayers({bool forceWhenIdle = false}) {
    if (!sentryEnabled) return;
    final now = DateTime.now();
    if ((!forceWhenIdle || _activeAnimatedAvatarPlayers != 0) &&
        now.isBefore(_nextAvatarReport)) {
      return;
    }
    _nextAvatarReport = now.add(_avatarReportInterval);
    Sentry.metrics.gauge(
      'mithka.ui.animated_avatar.active_players',
      _activeAnimatedAvatarPlayers,
    );
  }
}
