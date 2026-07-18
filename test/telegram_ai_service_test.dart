import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/telegram_ai_service.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  test('AI composition request matches pinned TDLib schema', () {
    expect(
      buildComposeTextWithAiRequest(
        text: const TelegramAiFormattedText(text: 'Hello'),
        translateToLanguageCode: 'ja',
        styleName: 'formal',
        addEmojis: true,
      ),
      {
        '@type': 'composeTextWithAi',
        'text': {
          '@type': 'formattedText',
          'text': 'Hello',
          'entities': <Map<String, dynamic>>[],
        },
        'translate_to_language_code': 'ja',
        'style_name': 'formal',
        'add_emojis': true,
      },
    );
  });

  test('AI summary request includes chat, message, translation and tone', () {
    expect(
      buildSummarizeMessageRequest(
        chatId: -1001,
        messageId: 77,
        translateToLanguageCode: 'en',
        tone: 'formal',
      ),
      {
        '@type': 'summarizeMessage',
        'chat_id': -1001,
        'message_id': 77,
        'translate_to_language_code': 'en',
        'tone': 'formal',
      },
    );
  });

  test('message parser preserves the server AI summary capability hint', () {
    final message = TDParse.message({
      '@type': 'message',
      'id': 7,
      'chat_id': 9,
      'date': 1,
      'is_outgoing': false,
      'summary_language_code': 'en',
      'sender_id': {'@type': 'messageSenderUser', 'user_id': 3},
      'content': {
        '@type': 'messageText',
        'text': {
          '@type': 'formattedText',
          'text': 'A long channel post',
          'entities': <Map<String, dynamic>>[],
        },
      },
    });
    expect(message, isNotNull);
    expect(message!.summaryLanguageCode, 'en');
  });

  test('video-note parser preserves Telegram speech recognition state', () {
    final message = TDParse.message({
      '@type': 'message',
      'id': 8,
      'chat_id': 9,
      'date': 1,
      'is_outgoing': false,
      'sender_id': {'@type': 'messageSenderUser', 'user_id': 3},
      'content': {
        '@type': 'messageVideoNote',
        'video_note': {
          '@type': 'videoNote',
          'duration': 12,
          'length': 240,
          'video': {'@type': 'file', 'id': 42},
          'speech_recognition_result': {
            '@type': 'speechRecognitionResultText',
            'text': 'Recognized video message',
          },
        },
      },
    });
    expect(message, isNotNull);
    expect(message!.videoNoteTranscription, 'Recognized video message');
    expect(message.videoNoteTranscriptionPending, isFalse);
  });
}
