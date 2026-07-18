/// Builds the current TDLib request for a text draft in a chat or topic.
///
/// TDLib 1b08 stores draft text under [draftMessage.content] as
/// [draftMessageContentText]. Older `message_thread_id` and
/// `input_message_text` fields are not accepted by the pinned schema.
Map<String, dynamic> setTextChatDraftRequest({
  required int chatId,
  required Map<String, dynamic>? formattedText,
  Map<String, dynamic>? topicId,
  required int date,
}) => {
  '@type': 'setChatDraftMessage',
  'chat_id': chatId,
  'topic_id': topicId,
  'draft_message': formattedText == null
      ? null
      : {
          '@type': 'draftMessage',
          'reply_to': null,
          'date': date,
          'content': {
            '@type': 'draftMessageContentText',
            'text': formattedText,
            'link_preview_options': null,
          },
          'effect_id': 0,
          'suggested_post_info': null,
        },
};
