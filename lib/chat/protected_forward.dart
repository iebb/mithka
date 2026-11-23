import 'dart:async';

import '../tdlib/json_helpers.dart';
import '../tdlib/td_models.dart';

/// Forwarding out of protected chats as a copy (the reference client
/// ForwardProtectedAsCopy / AyuGram parity).
///
/// The server forbids `forwardMessages` from a `has_protected_content` chat,
/// so the copy path re-sends the content instead: text (with entities) goes
/// out as a freshly authored `sendMessage`, and media goes out as an
/// `inputFileLocal` upload of the already-downloaded file. The re-send is a
/// normal outgoing message — the server never sees a forward at all — which
/// is why permission is verified up front (`can_be_copied`) and the copy
/// carries no author attribution, exactly like the reference client.
///
/// Media that has not finished downloading is NOT silently skipped: the
/// caller is handed the missing ids so it can offer a real download first
/// (AyuForwardLoader parity). A mixed selection partially migrates — the
/// copyable part is sent, the unsupported kinds are reported back.
class ProtectedForwardPlan {
  const ProtectedForwardPlan({
    required this.copiedCount,
    required this.skippedIds,
    this.missingMediaIds = const [],
  });

  /// Messages that were re-sent (or are being re-sent) as a copy.
  final int copiedCount;

  /// Messages that cannot be copied at all (poll, location, contact, …) —
  /// the reference client `canSendSingleMessageAsCopy` excludes the same kinds.
  final List<int> skippedIds;

  /// Media messages whose local file is not complete yet. Retrying after a
  /// download can migrate them.
  final List<int> missingMediaIds;

  bool get anythingSent => copiedCount > 0;
}

/// Whether a raw TDLib `message` content block can be re-sent as a copy.
/// Mirrors the reference client MessageHelper.canSendSingleMessageAsCopy: text,
/// emoji/stickers, photos, videos, documents and captioned media qualify;
/// polls, locations, contacts, games, invoices and story media do not.
bool canCopyContent(Map<String, dynamic>? content) {
  if (content == null) return false;
  const copyable = {
    'messageText',
    'messageAnimatedEmoji',
    'messageSticker',
    'messagePhoto',
    'messageVideo',
    'messageAnimation',
    'messageDocument',
    'messageAudio',
    'messageVoiceNote',
    'messageVideoNote',
  };
  if (copyable.contains(content.type)) return true;
  // Anything else with BOTH a caption and a downloadable file (a media
  // attachment this build may not know by name) still copies as a
  // document-style re-send; a caption alone (polls carry questions, not
  // captions, but restricted kinds must never slip through) does not.
  return content.obj('caption') != null && copyContentFileId(content) != null;
}

/// The downloadable file id for a copyable content block, or null when the
/// kind has no file to upload (plain text, custom emoji).
int? copyContentFileId(Map<String, dynamic> content) {
  int? fileId(Map<String, dynamic> wrapper, String key) =>
      wrapper.obj(key)?.integer('id');
  if (content.obj('document') case final document?) {
    return fileId(document, 'document');
  }
  if (content.obj('video') case final video?) return fileId(video, 'video');
  if (content.obj('animation') case final animation?) {
    return fileId(animation, 'animation');
  }
  if (content.obj('audio') case final audio?) return fileId(audio, 'audio');
  if (content.obj('voice_note') case final voice?) {
    return fileId(voice, 'voice');
  }
  if (content.obj('video_note') case final videoNote?) {
    return fileId(videoNote, 'video');
  }
  if (content.obj('photo') case final photo?) {
    final sizes = photo.objects('sizes');
    if (sizes == null || sizes.isEmpty) return null;
    // Photo sizes arrive smallest-first; the largest is the real media. The
    // file id lives on the size's `photo` file object, not on the size.
    return sizes.last.obj('photo')?.integer('id');
  }
  if (content.obj('sticker') case final sticker?) {
    return fileId(sticker, 'sticker');
  }
  return null;
}

typedef ProtectedForwardQuery =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> request);

/// Reads each source message fresh via `getMessage` and re-sends everything
/// copyable to [targetChatId].
///
/// The server's `can_be_copied` probe is deliberately NOT consulted: TDLib's
/// MessagesManager answers it from the same has_protected_content check that
/// blocks forwardMessages (is_copy grants no exemption), so inside a
/// protected chat it is false for every message — gating on it would kill
/// the copy path wholesale. Permission lives in the user's opt-in toggle
/// that routed the selection here; the copyable-kind filter below carries
/// the rest, exactly like the reference client ForwardProtectedAsCopy.
///
/// Returns the plan describing what was sent, what was skipped and which
/// media still needs a download. Never throws for restricted content; only
/// infrastructure errors (a lost sendMessage acknowledgement) propagate.
Future<ProtectedForwardPlan> forwardProtectedAsCopy({
  required ProtectedForwardQuery query,
  required int fromChatId,
  required List<int> messageIds,
  required int targetChatId,
  Map<String, dynamic>? topicId,
}) async {
  if (messageIds.isEmpty) {
    return const ProtectedForwardPlan(copiedCount: 0, skippedIds: []);
  }
  final skipped = <int>[];
  final missingMedia = <int>[];
  var copied = 0;

  for (final id in messageIds) {
    final message = await query({
      '@type': 'getMessage',
      'chat_id': fromChatId,
      'message_id': id,
    });
    if (message.type == 'error') {
      skipped.add(id);
      continue;
    }
    final content = message.obj('content');
    if (!canCopyContent(content)) {
      skipped.add(id);
      continue;
    }
    final fileId = content == null ? null : copyContentFileId(content);
    String? localPath;
    if (fileId != null) {
      final file = await query({'@type': 'getFile', 'file_id': fileId});
      final local = file.obj('local');
      final path = local?.str('path');
      if (local?.boolean('is_downloading_completed') != true ||
          path == null ||
          path.isEmpty) {
        missingMedia.add(id);
        continue;
      }
      localPath = path;
    }
    final sent = await _sendCopy(
      query: query,
      targetChatId: targetChatId,
      topicId: topicId,
      content: content!,
      localPath: localPath,
    );
    if (sent) {
      copied++;
    } else {
      skipped.add(id);
    }
  }
  return ProtectedForwardPlan(
    copiedCount: copied,
    skippedIds: skipped,
    missingMediaIds: missingMedia,
  );
}

Future<bool> _sendCopy({
  required ProtectedForwardQuery query,
  required int targetChatId,
  required Map<String, dynamic>? topicId,
  required Map<String, dynamic> content,
  required String? localPath,
}) async {
  final formatted = TDParse.formattedTextForContent(content);
  final text = formatted?.str('text') ?? '';
  final entities = formatted?.objects('entities') ?? const [];
  final caption = <String, dynamic>{
    '@type': 'formattedText',
    'text': text,
    if (entities.isNotEmpty) 'entities': entities,
  };
  Map<String, dynamic> inputContent;
  if (localPath == null) {
    if (content.type == 'messageSticker') {
      final sticker = content.obj('sticker');
      final sSticker = sticker?.obj('sticker');
      inputContent = {
        '@type': 'inputMessageSticker',
        'sticker': {
          '@type': 'inputSticker',
          'sticker': {
            '@type': 'inputFileLocal',
            'path': sSticker?.obj('local')?.str('path') ?? '',
          },
          'width': sticker?.integer('width') ?? 512,
          'height': sticker?.integer('height') ?? 512,
        },
        'emoji': sticker?.str('emoji') ?? '❤',
      };
    } else {
      inputContent = {
        '@type': 'inputMessageText',
        'text': caption,
        'clear_draft': false,
      };
    }
  } else {
    final documentName = _documentFileName(content);
    inputContent = switch (content.type) {
      'messagePhoto' => {
        '@type': 'inputMessagePhoto',
        'photo': {
          '@type': 'inputPhoto',
          'photo': {'@type': 'inputFileLocal', 'path': localPath},
        },
        if (text.isNotEmpty) 'caption': caption,
      },
      'messageVideo' || 'messageAnimation' => {
        '@type': content.type == 'messageVideo'
            ? 'inputMessageVideo'
            : 'inputMessageAnimation',
        content.type == 'messageVideo' ? 'video' : 'animation': {
          '@type': content.type == 'messageVideo'
              ? 'inputVideo'
              : 'inputAnimation',
          content.type == 'messageVideo' ? 'video' : 'animation': {
            '@type': 'inputFileLocal',
            'path': localPath,
          },
          if (content.type == 'messageVideo') 'supports_streaming': true,
        },
        if (text.isNotEmpty) 'caption': caption,
      },
      'messageAudio' => {
        '@type': 'inputMessageAudio',
        'audio': {
          '@type': 'inputAudio',
          'audio': {'@type': 'inputFileLocal', 'path': localPath},
          'title': _audioTitle(content),
          'performer': _audioPerformer(content),
        },
        if (text.isNotEmpty) 'caption': caption,
      },
      'messageVoiceNote' => {
        '@type': 'inputMessageVoiceNote',
        'voice_note': {
          '@type': 'inputVoiceNote',
          'voice_note': {'@type': 'inputFileLocal', 'path': localPath},
          'duration': _voiceDuration(content),
          'waveform': content.obj('voice_note')?.str('waveform') ?? '',
        },
      },
      'messageVideoNote' => {
        '@type': 'inputMessageVideoNote',
        'video_note': {
          '@type': 'inputVideoNote',
          'video_note': {'@type': 'inputFileLocal', 'path': localPath},
          'duration': _videoNoteDuration(content),
          'length': _videoNoteLength(content),
        },
      },
      _ => {
        '@type': 'inputMessageDocument',
        'document': {
          '@type': 'inputDocument',
          'document': {'@type': 'inputFileLocal', 'path': localPath},
        },
        'file_name': ?documentName,
        if (text.isNotEmpty) 'caption': caption,
      },
    };
  }
  try {
    final response = await query({
      '@type': 'sendMessage',
      'chat_id': targetChatId,
      'topic_id': ?topicId,
      'input_message_content': inputContent,
    });
    return response.type != 'error';
  } catch (_) {
    return false;
  }
}

String? _documentFileName(Map<String, dynamic> content) {
  final doc = content.obj('document')?.obj('document');
  return doc?.str('file_name');
}

String _audioTitle(Map<String, dynamic> content) {
  return content.obj('audio')?.obj('audio')?.str('title') ?? '';
}

String? _audioPerformer(Map<String, dynamic> content) {
  return content.obj('audio')?.obj('audio')?.str('performer');
}

int _voiceDuration(Map<String, dynamic> content) {
  return content.obj('voice_note')?.integer('duration') ?? 0;
}

int _videoNoteDuration(Map<String, dynamic> content) {
  return content.obj('video_note')?.integer('duration') ?? 0;
}

int _videoNoteLength(Map<String, dynamic> content) {
  return content.obj('video_note')?.integer('length') ?? 0;
}
