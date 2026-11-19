import 'package:flutter_test/flutter_test.dart';
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

    final draft = request['draft_message'] as Map<String, dynamic>;
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
}
