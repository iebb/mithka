import 'dart:convert';

import 'package:flutter/services.dart';

import '../settings/apple_pcc_api.dart';
import 'unread_chat_summary_service.dart';

class ApplePccUnreadSummaryProvider implements UnreadChatSummaryProvider {
  const ApplePccUnreadSummaryProvider({
    required this.api,
    this.model = AppleAiModel.privateCloudCompute,
    this.reasoningLevel = ApplePccReasoningLevel.moderate,
    this.maximumResponseTokens,
    this.chunkMaximumResponseTokens = 1100,
    this.mergeMaximumResponseTokens = 1800,
    this.transientRetryDelays = const [
      Duration(milliseconds: 350),
      Duration(milliseconds: 900),
    ],
    this.invalidResponseRetryCount = 1,
  }) : assert(maximumResponseTokens == null || maximumResponseTokens > 0),
       assert(chunkMaximumResponseTokens > 0),
       assert(mergeMaximumResponseTokens > 0),
       assert(invalidResponseRetryCount >= 0);

  final ApplePccApi api;
  final AppleAiModel model;
  final ApplePccReasoningLevel reasoningLevel;

  /// Overrides both stage-specific limits when supplied.
  final int? maximumResponseTokens;
  final int chunkMaximumResponseTokens;
  final int mergeMaximumResponseTokens;
  final List<Duration> transientRetryDelays;
  final int invalidResponseRetryCount;

  @override
  Future<Map<String, dynamic>> complete(
    UnreadChatSummaryProviderRequest request,
  ) async {
    var transientAttempt = 0;
    var invalidResponseAttempt = 0;
    while (true) {
      try {
        final result = await api.summarize(
          prompt:
              '$unreadChatSummaryPromptPrefix${jsonEncode(request.payload)}',
          instructions: model == AppleAiModel.onDevice
              ? unreadChatSummaryCompactTrustedInstructions
              : request.trustedInstructions,
          model: model,
          reasoningLevel: reasoningLevel,
          maximumResponseTokens:
              maximumResponseTokens ??
              (request.stage == UnreadChatSummaryStage.chunk
                  ? chunkMaximumResponseTokens
                  : mergeMaximumResponseTokens),
        );
        return decodeUnreadChatSummaryJson(result.text);
      } on PlatformException catch (error) {
        if (!_isTransient(error) ||
            transientAttempt >= transientRetryDelays.length) {
          rethrow;
        }
        await Future<void>.delayed(transientRetryDelays[transientAttempt++]);
      } on UnreadChatSummaryProviderException {
        if (invalidResponseAttempt >= invalidResponseRetryCount) rethrow;
        invalidResponseAttempt++;
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    }
  }

  bool _isTransient(PlatformException error) {
    if (const {
      'pcc_busy',
      'pcc_network_failure',
      'pcc_service_unavailable',
      'on_device_busy',
      'on_device_rate_limited',
    }.contains(error.code)) {
      return true;
    }
    if (error.code != 'pcc_unavailable' || error.details is! Map) return false;
    return (error.details as Map)['reason'] == 'system_not_ready';
  }
}
