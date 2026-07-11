import 'dart:typed_data';

enum OutgoingAttachmentKind { photo, video, animation, document, audio }

enum AttachmentAlbumKind { visual, document, audio, standalone }

class OutgoingAttachment {
  const OutgoingAttachment({
    required this.path,
    required this.kind,
    this.caption = '',
    this.captionEntities = const [],
    this.previewBytes,
  });

  final String path;
  final OutgoingAttachmentKind kind;
  final String caption;
  final List<Map<String, dynamic>> captionEntities;
  final Uint8List? previewBytes;

  AttachmentAlbumKind get albumKind => switch (kind) {
    OutgoingAttachmentKind.photo ||
    OutgoingAttachmentKind.video => AttachmentAlbumKind.visual,
    OutgoingAttachmentKind.document => AttachmentAlbumKind.document,
    OutgoingAttachmentKind.audio => AttachmentAlbumKind.audio,
    OutgoingAttachmentKind.animation => AttachmentAlbumKind.standalone,
  };

  OutgoingAttachment copyWith({
    String? path,
    OutgoingAttachmentKind? kind,
    String? caption,
    List<Map<String, dynamic>>? captionEntities,
    Uint8List? previewBytes,
    bool clearPreviewBytes = false,
  }) {
    return OutgoingAttachment(
      path: path ?? this.path,
      kind: kind ?? this.kind,
      caption: caption ?? this.caption,
      captionEntities: captionEntities ?? this.captionEntities,
      previewBytes: clearPreviewBytes
          ? null
          : previewBytes ?? this.previewBytes,
    );
  }
}

class OutgoingAttachmentBatch {
  const OutgoingAttachmentBatch(this.attachments);

  final List<OutgoingAttachment> attachments;

  bool get isAlbum =>
      attachments.length > 1 &&
      attachments.first.albumKind != AttachmentAlbumKind.standalone;
}

/// Partitions attachments without reordering them. TDLib albums contain 2-10
/// compatible items: photos and videos may mix, while documents and audio can
/// only be grouped with their own kind. Animations are always standalone.
List<OutgoingAttachmentBatch> groupOutgoingAttachments(
  List<OutgoingAttachment> attachments,
) {
  if (attachments.isEmpty) return const [];
  final batches = <OutgoingAttachmentBatch>[];
  var current = <OutgoingAttachment>[];
  AttachmentAlbumKind? currentKind;

  void flush() {
    if (current.isEmpty) return;
    batches.add(OutgoingAttachmentBatch(List.unmodifiable(current)));
    current = <OutgoingAttachment>[];
    currentKind = null;
  }

  for (final attachment in attachments) {
    final kind = attachment.albumKind;
    if (kind == AttachmentAlbumKind.standalone) {
      flush();
      batches.add(OutgoingAttachmentBatch([attachment]));
      continue;
    }
    if (currentKind != kind || current.length == 10) flush();
    currentKind = kind;
    current.add(attachment);
  }
  flush();
  return List.unmodifiable(batches);
}

Map<String, dynamic> attachmentInputMessageContent(
  OutgoingAttachment attachment, {
  String? caption,
  List<Map<String, dynamic>>? captionEntities,
}) {
  final resolvedCaption = caption ?? attachment.caption;
  final resolvedEntities = captionEntities ?? attachment.captionEntities;
  final formattedCaption = resolvedCaption.trim().isEmpty
      ? null
      : <String, dynamic>{
          '@type': 'formattedText',
          'text': resolvedEntities.isEmpty
              ? resolvedCaption.trim()
              : resolvedCaption,
          if (resolvedEntities.isNotEmpty) 'entities': resolvedEntities,
        };
  final localFile = {'@type': 'inputFileLocal', 'path': attachment.path};

  return switch (attachment.kind) {
    OutgoingAttachmentKind.photo => {
      '@type': 'inputMessagePhoto',
      'photo': {'@type': 'inputPhoto', 'photo': localFile},
      'caption': ?formattedCaption,
    },
    OutgoingAttachmentKind.video => {
      '@type': 'inputMessageVideo',
      'video': {
        '@type': 'inputVideo',
        'video': localFile,
        'supports_streaming': true,
      },
      'caption': ?formattedCaption,
    },
    OutgoingAttachmentKind.animation => {
      '@type': 'inputMessageAnimation',
      'animation': localFile,
      'duration': 0,
      'width': 0,
      'height': 0,
      'caption': ?formattedCaption,
    },
    OutgoingAttachmentKind.document => {
      '@type': 'inputMessageDocument',
      'document': {'@type': 'inputDocument', 'document': localFile},
      'caption': ?formattedCaption,
    },
    OutgoingAttachmentKind.audio => {
      '@type': 'inputMessageAudio',
      'audio': {
        '@type': 'inputAudio',
        'audio': localFile,
        'duration': 0,
        'title': '',
        'performer': '',
      },
      'caption': ?formattedCaption,
    },
  };
}

List<Map<String, dynamic>> buildAttachmentSendRequests({
  required int chatId,
  required List<OutgoingAttachment> attachments,
  String caption = '',
  List<Map<String, dynamic>> captionEntities = const [],
  Map<String, dynamic>? replyTo,
}) {
  final requests = <Map<String, dynamic>>[];
  var primaryCaptionApplied = false;
  for (final batch in groupOutgoingAttachments(attachments)) {
    final contents = <Map<String, dynamic>>[];
    for (final attachment in batch.attachments) {
      final appliesPrimaryCaption =
          !primaryCaptionApplied && caption.trim().isNotEmpty;
      contents.add(
        attachmentInputMessageContent(
          attachment,
          caption: appliesPrimaryCaption ? caption : null,
          captionEntities: appliesPrimaryCaption ? captionEntities : null,
        ),
      );
      primaryCaptionApplied = primaryCaptionApplied || appliesPrimaryCaption;
    }
    requests.add({
      '@type': batch.isAlbum ? 'sendMessageAlbum' : 'sendMessage',
      'chat_id': chatId,
      if (batch.isAlbum)
        'input_message_contents': contents
      else
        'input_message_content': contents.single,
      if (replyTo != null && requests.isEmpty) 'reply_to': replyTo,
    });
  }
  return requests;
}
