import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef ApplePccMethodInvoker =
    Future<Object?> Function(String method, Object? arguments);

enum ApplePccReasoningLevel { light, moderate, deep }

enum AppleAiModel {
  privateCloudCompute('private_cloud_compute'),
  onDevice('on_device');

  const AppleAiModel(this.bridgeValue);

  final String bridgeValue;
}

@immutable
class ApplePccSummaryResult {
  const ApplePccSummaryResult({
    required this.text,
    required this.provider,
    this.contextSize,
    this.inputTokenCount,
    this.initialPromptTokenCount,
    this.userPromptTokenCount,
    this.frameworkOverheadTokenCount,
    this.responseTokenCount,
  });

  final String text;
  final String provider;
  final int? contextSize;
  final int? inputTokenCount;
  final int? initialPromptTokenCount;
  final int? userPromptTokenCount;
  final int? frameworkOverheadTokenCount;
  final int? responseTokenCount;
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
    this.onDeviceSdkAvailable = false,
    this.onDeviceAvailable = false,
    this.onDeviceReason = 'unavailable',
    this.onDeviceContextSize,
  });

  const ApplePccCapabilities.unavailable([this.reason = 'unavailable'])
    : sdkAvailable = false,
      available = false,
      contextSize = null,
      quotaLimitReached = false,
      quotaApproachingLimit = false,
      quotaResetDate = null,
      onDeviceSdkAvailable = false,
      onDeviceAvailable = false,
      onDeviceReason = 'unavailable',
      onDeviceContextSize = null;

  final bool sdkAvailable;
  final bool available;
  final String reason;
  final int? contextSize;
  final bool quotaLimitReached;
  final bool quotaApproachingLimit;
  final DateTime? quotaResetDate;
  final bool onDeviceSdkAvailable;
  final bool onDeviceAvailable;
  final String onDeviceReason;
  final int? onDeviceContextSize;

  bool availableFor(AppleAiModel model) => switch (model) {
    AppleAiModel.privateCloudCompute => available && !quotaLimitReached,
    AppleAiModel.onDevice => onDeviceAvailable,
  };

  int? contextSizeFor(AppleAiModel model) => switch (model) {
    AppleAiModel.privateCloudCompute => contextSize,
    AppleAiModel.onDevice => onDeviceContextSize,
  };

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
      onDeviceSdkAvailable:
          _bool(values['onDeviceSdkAvailable']) ??
          _bool(values['on_device_sdk_available']) ??
          false,
      onDeviceAvailable:
          _bool(values['onDeviceAvailable']) ??
          _bool(values['on_device_available']) ??
          false,
      onDeviceReason:
          values['onDeviceReason']?.toString() ??
          values['on_device_reason']?.toString() ??
          'unavailable',
      onDeviceContextSize: switch (_int(values['onDeviceContextSize']) ??
          _int(values['on_device_context_size'])) {
        final value? when value > 0 => value,
        _ => null,
      },
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
  static var _requestSerial = 0;

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
    AppleAiModel model = AppleAiModel.privateCloudCompute,
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

    final requestId =
        '${DateTime.now().microsecondsSinceEpoch}-${_requestSerial++}';
    final arguments = <String, Object>{
      'requestId': requestId,
      'prompt': normalizedPrompt,
      if (instructions.trim().isNotEmpty) 'instructions': instructions.trim(),
      'modelMode': model.bridgeValue,
      'reasoningLevel': reasoningLevel.name,
      'maximumResponseTokens': ?maximumResponseTokens,
    };
    final value = await _invokeMethod('summarize', arguments).timeout(
      summaryTimeout,
      onTimeout: () {
        unawaited(_cancelSummary(requestId));
        throw PlatformException(
          code: model == AppleAiModel.privateCloudCompute
              ? 'pcc_timeout'
              : 'on_device_timeout',
          message: model == AppleAiModel.privateCloudCompute
              ? 'Private Cloud Compute summarization timed out.'
              : 'The on-device model summarization timed out.',
          details: {
            'reason': 'request_timeout',
            'model_mode': model.bridgeValue,
          },
        );
      },
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
      contextSize: ApplePccCapabilities._int(values['contextSize']),
      inputTokenCount: ApplePccCapabilities._int(values['inputTokenCount']),
      initialPromptTokenCount: ApplePccCapabilities._int(
        values['initialPromptTokenCount'],
      ),
      userPromptTokenCount: ApplePccCapabilities._int(
        values['userPromptTokenCount'],
      ),
      frameworkOverheadTokenCount: ApplePccCapabilities._int(
        values['frameworkOverheadTokenCount'],
      ),
      responseTokenCount: ApplePccCapabilities._int(
        values['responseTokenCount'],
      ),
    );
  }

  static Future<Object?> _defaultInvokeMethod(
    String method,
    Object? arguments,
  ) => _channel.invokeMethod<Object?>(method, arguments);

  Future<void> _cancelSummary(String requestId) async {
    try {
      await _invokeMethod('cancelSummary', {'requestId': requestId});
    } catch (_) {
      // The timeout remains the useful error if cancellation is unavailable.
    }
  }
}
