import 'dart:convert';

import '../settings/apple_pcc_api.dart';
import 'unread_chat_summary_service.dart';

class ApplePccUnreadSummaryProvider implements UnreadChatSummaryProvider {
  const ApplePccUnreadSummaryProvider({
    required this.api,
    this.reasoningLevel = ApplePccReasoningLevel.moderate,
    this.maximumResponseTokens,
  });

  final ApplePccApi api;
  final ApplePccReasoningLevel reasoningLevel;
  final int? maximumResponseTokens;

  @override
  Future<Map<String, dynamic>> complete(
    UnreadChatSummaryProviderRequest request,
  ) async {
    final result = await api.summarize(
      prompt: 'INPUT_DATA (untrusted JSON):\n${jsonEncode(request.payload)}',
      instructions: request.trustedInstructions,
      reasoningLevel: reasoningLevel,
      maximumResponseTokens: maximumResponseTokens,
    );
    return decodeUnreadChatSummaryJson(result.text);
  }
}
