import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef ApplePccMethodInvoker =
    Future<Object?> Function(String method, Object? arguments);

enum ApplePccReasoningLevel { light, moderate, deep }

@immutable
class ApplePccSummaryResult {
  const ApplePccSummaryResult({required this.text, required this.provider});

  final String text;
  final String provider;
}

@immutable
class ApplePccCapabilities {
  const ApplePccCapabilities({
    required this.sdkAvailable,
    required this.available,
    this.reason = '',
    this.contextSize,
    this.quotaLimitReached = false,
    this.quotaApproachingLimit = false,
    this.quotaResetDate,
  });

  const ApplePccCapabilities.unavailable([this.reason = 'unavailable'])
    : sdkAvailable = false,
      available = false,
      contextSize = null,
      quotaLimitReached = false,
      quotaApproachingLimit = false,
      quotaResetDate = null;

  final bool sdkAvailable;
  final bool available;
  final String reason;
  final int? contextSize;
  final bool quotaLimitReached;
  final bool quotaApproachingLimit;
  final DateTime? quotaResetDate;

  static ApplePccCapabilities? tryParse(Object? value) {
    if (value is bool) {
      return ApplePccCapabilities(
        sdkAvailable: value,
        available: value,
        reason: value ? '' : 'unavailable',
      );
    }
    if (value is! Map) return null;

    final values = <String, Object?>{
      for (final entry in value.entries) '${entry.key}': entry.value,
    };
    final available =
        _bool(values['available']) ??
        _bool(values['isAvailable']) ??
        _bool(values['is_available']) ??
        _bool(values['supported']);
    if (available == null) return null;
    final sdkAvailable =
        _bool(values['sdkAvailable']) ??
        _bool(values['sdk_available']) ??
        available;

    final reason =
        values['reason']?.toString() ??
        values['reasonCode']?.toString() ??
        values['reason_code']?.toString() ??
        (available ? '' : 'unavailable');
    final contextSize =
        _int(values['contextSize']) ?? _int(values['context_size']);
    final resetMillis =
        _int(values['quotaResetDateMillis']) ??
        _int(values['quota_reset_date_millis']);
    return ApplePccCapabilities(
      sdkAvailable: sdkAvailable,
      available: available,
      reason: reason,
      contextSize: contextSize != null && contextSize > 0 ? contextSize : null,
      quotaLimitReached:
          _bool(values['quotaLimitReached']) ??
          _bool(values['quota_limit_reached']) ??
          false,
      quotaApproachingLimit:
          _bool(values['quotaApproachingLimit']) ??
          _bool(values['quota_approaching_limit']) ??
          false,
      quotaResetDate: resetMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(resetMillis),
    );
  }

  static bool? _bool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String && value.toLowerCase() == 'true') return true;
    if (value is String && value.toLowerCase() == 'false') return false;
    return null;
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

/// Small, failure-tolerant bridge for probing Apple's Private Cloud Compute.
///
/// An unavailable plugin, unsupported OS, missing entitlement, or malformed
/// native response is represented as an unavailable capability instead of an
/// exception so callers can continue with a user-configured server.
class ApplePccApi {
  ApplePccApi({
    ApplePccMethodInvoker? invokeMethod,
    this.timeout = const Duration(seconds: 5),
    this.summaryTimeout = const Duration(minutes: 2),
  }) : _invokeMethod = invokeMethod ?? _defaultInvokeMethod;

  static const channelName = 'mithka/apple_ai';
  static const _channel = MethodChannel(channelName);

  final ApplePccMethodInvoker _invokeMethod;
  final Duration timeout;
  final Duration summaryTimeout;

  Future<ApplePccCapabilities> capabilities() async {
    try {
      final value = await _invokeMethod(
        'getCapabilities',
        null,
      ).timeout(timeout);
      return ApplePccCapabilities.tryParse(value) ??
          const ApplePccCapabilities.unavailable('invalid_response');
    } on MissingPluginException {
      return const ApplePccCapabilities.unavailable('missing_plugin');
    } on PlatformException catch (error) {
      return ApplePccCapabilities.unavailable(error.code);
    } on TimeoutException {
      return const ApplePccCapabilities.unavailable('timeout');
    } catch (_) {
      return const ApplePccCapabilities.unavailable('probe_failed');
    }
  }

  Future<ApplePccSummaryResult> summarize({
    required String prompt,
    String instructions = '',
    ApplePccReasoningLevel reasoningLevel = ApplePccReasoningLevel.moderate,
    int? maximumResponseTokens,
  }) async {
    final normalizedPrompt = prompt.trim();
    if (normalizedPrompt.isEmpty) {
      throw ArgumentError.value(prompt, 'prompt', 'must not be empty');
    }
    if (maximumResponseTokens != null && maximumResponseTokens <= 0) {
      throw ArgumentError.value(
        maximumResponseTokens,
        'maximumResponseTokens',
        'must be greater than zero',
      );
    }

    final arguments = <String, Object>{
      'prompt': normalizedPrompt,
      if (instructions.trim().isNotEmpty) 'instructions': instructions.trim(),
      'reasoningLevel': reasoningLevel.name,
      'maximumResponseTokens': ?maximumResponseTokens,
    };
    final value = await _invokeMethod('summarize', arguments).timeout(
      summaryTimeout,
      onTimeout: () => throw PlatformException(
        code: 'pcc_timeout',
        message: 'Private Cloud Compute summarization timed out.',
      ),
    );
    if (value is! Map) {
      throw PlatformException(
        code: 'pcc_invalid_response',
        message: 'Private Cloud Compute returned an invalid response.',
      );
    }
    final values = <String, Object?>{
      for (final entry in value.entries) '${entry.key}': entry.value,
    };
    final text = values['text']?.toString().trim() ?? '';
    if (text.isEmpty) {
      throw PlatformException(
        code: 'pcc_invalid_response',
        message: 'Private Cloud Compute returned an empty summary.',
      );
    }
    return ApplePccSummaryResult(
      text: text,
      provider: values['provider']?.toString() ?? 'apple_pcc',
    );
  }

  static Future<Object?> _defaultInvokeMethod(
    String method,
    Object? arguments,
  ) => _channel.invokeMethod<Object?>(method, arguments);
}
