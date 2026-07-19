import 'dart:convert';

import 'package:flutter/services.dart';

import '../settings/apple_pcc_api.dart';
import 'unread_chat_summary_service.dart';

class ApplePccUnreadSummaryProvider implements UnreadChatSummaryProvider {
  const ApplePccUnreadSummaryProvider({
    required this.api,
    this.reasoningLevel = ApplePccReasoningLevel.moderate,
    this.maximumResponseTokens,
    this.chunkMaximumResponseTokens = 1100,
    this.mergeMaximumResponseTokens = 1800,
    this.transientRetryDelays = const [
      Duration(milliseconds: 350),
      Duration(milliseconds: 900),
    ],
  }) : assert(maximumResponseTokens == null || maximumResponseTokens > 0),
       assert(chunkMaximumResponseTokens > 0),
       assert(mergeMaximumResponseTokens > 0);

  final ApplePccApi api;
  final ApplePccReasoningLevel reasoningLevel;

  /// Overrides both stage-specific limits when supplied.
  final int? maximumResponseTokens;
  final int chunkMaximumResponseTokens;
  final int mergeMaximumResponseTokens;
  final List<Duration> transientRetryDelays;

  @override
  Future<Map<String, dynamic>> complete(
    UnreadChatSummaryProviderRequest request,
  ) async {
    for (var attempt = 0; ; attempt++) {
      try {
        final result = await api.summarize(
          prompt:
              'INPUT_DATA (untrusted JSON):\n${jsonEncode(request.payload)}',
          instructions: request.trustedInstructions,
          reasoningLevel: reasoningLevel,
          maximumResponseTokens:
              maximumResponseTokens ??
              (request.stage == UnreadChatSummaryStage.chunk
                  ? chunkMaximumResponseTokens
                  : mergeMaximumResponseTokens),
        );
        return decodeUnreadChatSummaryJson(result.text);
      } on PlatformException catch (error) {
        if (!_isTransient(error) || attempt >= transientRetryDelays.length) {
          rethrow;
        }
        await Future<void>.delayed(transientRetryDelays[attempt]);
      }
    }
  }

  bool _isTransient(PlatformException error) {
    if (const {
      'pcc_busy',
      'pcc_network_failure',
      'pcc_service_unavailable',
    }.contains(error.code)) {
      return true;
    }
    if (error.code != 'pcc_unavailable' || error.details is! Map) return false;
    return (error.details as Map)['reason'] == 'system_not_ready';
  }
}
