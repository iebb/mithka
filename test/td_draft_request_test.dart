import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/tdlib/td_requests.dart';

void main() {
  test('text chat drafts use pinned TDLib draftMessageContentText', () {
    final request = setTextChatDraftRequest(
      chatId: 42,
      date: 123,
      formattedText: {
        '@type': 'formattedText',
        'text': 'Hello',
        'entities': const <Map<String, dynamic>>[],
      },
    );

    expect(request['topic_id'], isNull);
    expect(request, isNot(contains('message_thread_id')));
    final draft = request['draft_message'] as Map<String, dynamic>;
    expect(draft, isNot(contains('input_message_text')));
    expect(draft['content'], {
      '@type': 'draftMessageContentText',
      'text': {
        '@type': 'formattedText',
        'text': 'Hello',
        'entities': const <Map<String, dynamic>>[],
      },
      'link_preview_options': null,
    });
  });

  test('draft parser reads pinned content and ignores non-text content', () {
    expect(
      TDParse.draftText({
        '@type': 'draftMessage',
        'content': {
          '@type': 'draftMessageContentText',
          'text': {'@type': 'formattedText', 'text': 'Pinned draft'},
        },
      }),
      'Pinned draft',
    );
    expect(
      TDParse.draftText({
        '@type': 'draftMessage',
        'content': {
          '@type': 'draftMessageContentVoiceNote',
          'file_path': '/tmp/voice.ogg',
        },
      }),
      isEmpty,
    );
  });
}
