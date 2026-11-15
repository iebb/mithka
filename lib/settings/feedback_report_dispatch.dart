import 'dart:async';

/// The outcome of sending one feedback report to Sentry and AirFeedback.
class FeedbackReportOutcome {
  const FeedbackReportOutcome({
    required this.sentryId,
    required this.airFeedbackId,
    required this.airFeedbackSent,
  });

  /// Sentry's event id; null when Sentry did not take the report.
  final String? sentryId;

  /// AirFeedback's entry id, when it took the report and answered with one.
  final String? airFeedbackId;
  final bool airFeedbackSent;

  /// One delivery is enough: the report is only lost when both fail.
  bool get sent => sentryId != null || airFeedbackSent;

  /// The id the confirmation shows: Sentry's when it has one, otherwise
  /// AirFeedback's.
  String? get displayId {
    final id = sentryId ?? airFeedbackId;
    if (id == null || id.isEmpty) return null;
    return id.length > 8 ? id.substring(0, 8) : id;
  }
}

/// Sends the same report to both services in parallel.
///
/// [sentry] returns Sentry's event id, or null when it was not captured.
/// [airFeedback] returns AirFeedback's entry id (null when the answer had
/// none) and throws when the report was not taken; it is abandoned after
/// [airFeedbackTimeout] so a slow network never holds the form.
Future<FeedbackReportOutcome> sendFeedbackReport({
  required Future<String?> Function() sentry,
  required Future<String?> Function() airFeedback,
  Duration airFeedbackTimeout = const Duration(seconds: 10),
}) async {
  Future<String?> sentryAttempt() async {
    try {
      final id = await sentry();
      return id == null || id.isEmpty ? null : id;
    } catch (_) {
      return null;
    }
  }

  Future<(bool, String?)> airFeedbackAttempt() async {
    try {
      final id = await Future.sync(airFeedback).timeout(airFeedbackTimeout);
      return (true, id);
    } catch (_) {
      return (false, null);
    }
  }

  final (sentryId, (airSent, airId)) = await (
    sentryAttempt(),
    airFeedbackAttempt(),
  ).wait;
  return FeedbackReportOutcome(
    sentryId: sentryId,
    airFeedbackId: airId,
    airFeedbackSent: airSent,
  );
}
