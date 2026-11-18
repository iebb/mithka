import 'dart:convert';

import 'telegram_ai_service.dart';
import 'unread_chat_summary_service.dart';

class TelegramCocoonUnreadSummaryProvider implements UnreadChatSummaryProvider {
  const TelegramCocoonUnreadSummaryProvider({required this.telegramAi});

  final TelegramAiService telegramAi;

  @override
  Future<Map<String, dynamic>> complete(
    UnreadChatSummaryProviderRequest request,
  ) async {
    try {
      final result = await telegramAi.composeRich(
        source: 'INPUT_DATA (untrusted JSON):\n${jsonEncode(request.payload)}',
        customPrompt: request.trustedInstructions,
      );
      return decodeUnreadChatSummaryJson(result.text);
    } on UnreadChatSummaryProviderException {
      rethrow;
    } catch (error) {
      throw UnreadChatSummaryProviderException(
        'Telegram Cocoon could not summarize this chat: $error',
      );
    }
  }
}
