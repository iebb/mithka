//
//  gif_item.dart
//
//  A saved Telegram animation shown in the composer's GIF tab.
//

import '../tdlib/td_models.dart';

class GifItem {
  const GifItem({
    required this.id,
    this.remoteId,
    this.inlineQueryId,
    this.inlineResultId,
    required this.duration,
    required this.width,
    required this.height,
    required this.mimeType,
    required this.file,
    this.thumbnail,
  });

  final int id;
  final String? remoteId;
  final int? inlineQueryId;
  final String? inlineResultId;
  final int duration;
  final int width;
  final int height;
  final String mimeType;
  final TdFileRef file;
  final TdFileRef? thumbnail;

  GifItem asInlineResult({required int queryId, required String resultId}) =>
      GifItem(
        id: id,
        remoteId: remoteId,
        inlineQueryId: queryId,
        inlineResultId: resultId,
        duration: duration,
        width: width,
        height: height,
        mimeType: mimeType,
        file: file,
        thumbnail: thumbnail,
      );
}

Map<String, dynamic> gifMessageContent(GifItem gif) => {
  '@type': 'inputMessageAnimation',
  // The bundled TDLib schema carries file metadata in inputAnimation.
  'animation': {
    '@type': 'inputAnimation',
    // Saved animations already belong to the active TDLib account. Reusing
    // the account-local file id retains the file reference required to send.
    'animation': {'@type': 'inputFileId', 'id': gif.id},
    'duration': gif.duration,
    'width': gif.width,
    'height': gif.height,
  },
};

Map<String, dynamic> gifSendRequest({
  required int chatId,
  required GifItem gif,
}) {
  final inlineQueryId = gif.inlineQueryId;
  final inlineResultId = gif.inlineResultId?.trim();
  if (inlineQueryId != null &&
      inlineQueryId > 0 &&
      inlineResultId != null &&
      inlineResultId.isNotEmpty) {
    return {
      '@type': 'sendInlineQueryResultMessage',
      'chat_id': chatId,
      'query_id': inlineQueryId,
      'result_id': inlineResultId,
      'hide_via_bot': true,
    };
  }
  return {
    '@type': 'sendMessage',
    'chat_id': chatId,
    'input_message_content': gifMessageContent(gif),
  };
}
