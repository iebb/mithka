import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'message_send_options.dart';

enum OutgoingAttachmentKind {
  photo,
  video,
  animation,
  document,
  audio,
  voiceNote,
}

OutgoingAttachmentKind galleryAttachmentKind({
  required bool sendAsFile,
  required bool isVideo,
  required bool isAnimation,
}) {
  if (sendAsFile) return OutgoingAttachmentKind.document;
  if (isVideo) return OutgoingAttachmentKind.video;
  if (isAnimation) return OutgoingAttachmentKind.animation;
  return OutgoingAttachmentKind.photo;
}

enum AttachmentAlbumKind { visual, document, audio, standalone }

class OutgoingAttachment {
  const OutgoingAttachment({
    required this.path,
    required this.kind,
    this.caption = '',
    this.captionEntities = const [],
    this.previewBytes,
    this.width,
    this.height,
    this.fileId,
    this.duration = 0,
    this.title = '',
    this.performer = '',
    this.fileName,
    this.originalPath,
    this.coverPath,
    this.startTimestamp = 0,
  });

  final String path;
  final OutgoingAttachmentKind kind;
  final String caption;
  final List<Map<String, dynamic>> captionEntities;
  final Uint8List? previewBytes;
  final int? width;
  final int? height;
  final int? fileId;
  final int duration;
  final String title;
  final String performer;
  final String? fileName;
  final String? originalPath;
  final String? coverPath;
  final int startTimestamp;

  AttachmentAlbumKind get albumKind => switch (kind) {
    OutgoingAttachmentKind.photo ||
    OutgoingAttachmentKind.video => AttachmentAlbumKind.visual,
    OutgoingAttachmentKind.document => AttachmentAlbumKind.document,
    OutgoingAttachmentKind.audio => AttachmentAlbumKind.audio,
    OutgoingAttachmentKind.animation ||
    OutgoingAttachmentKind.voiceNote => AttachmentAlbumKind.standalone,
  };

  OutgoingAttachment copyWith({
    String? path,
    OutgoingAttachmentKind? kind,
    String? caption,
    List<Map<String, dynamic>>? captionEntities,
    Uint8List? previewBytes,
    bool clearPreviewBytes = false,
    int? width,
    int? height,
    bool clearDimensions = false,
    int? fileId,
    bool clearFileId = false,
    int? duration,
    String? title,
    String? performer,
    String? fileName,
    String? originalPath,
    bool clearOriginalPath = false,
    String? coverPath,
    bool clearCoverPath = false,
    int? startTimestamp,
  }) {
    return OutgoingAttachment(
      path: path ?? this.path,
      kind: kind ?? this.kind,
      caption: caption ?? this.caption,
      captionEntities: captionEntities ?? this.captionEntities,
      previewBytes: clearPreviewBytes
          ? null
          : previewBytes ?? this.previewBytes,
      width: clearDimensions ? null : width ?? this.width,
      height: clearDimensions ? null : height ?? this.height,
      fileId: clearFileId ? null : fileId ?? this.fileId,
      duration: duration ?? this.duration,
      title: title ?? this.title,
      performer: performer ?? this.performer,
      fileName: fileName ?? this.fileName,
      originalPath: clearOriginalPath
          ? null
          : originalPath ?? this.originalPath,
      coverPath: clearCoverPath ? null : coverPath ?? this.coverPath,
      startTimestamp: startTimestamp ?? this.startTimestamp,
    );
  }
}

Map<String, dynamic> attachmentInputFile(OutgoingAttachment attachment) {
  final fileId = attachment.fileId;
  final originalPath = attachment.originalPath?.trim();
  final usesOriginalDocument =
      attachment.kind == OutgoingAttachmentKind.document &&
      originalPath != null &&
      originalPath.isNotEmpty;
  if (!usesOriginalDocument && fileId != null && fileId > 0) {
    return {'@type': 'inputFileId', 'id': fileId};
  }
  return {
    '@type': 'inputFileLocal',
    'path': usesOriginalDocument ? originalPath : attachment.path,
  };
}

Future<OutgoingAttachment> resolveAttachmentDimensions(
  OutgoingAttachment attachment,
) async {
  if (attachment.kind != OutgoingAttachmentKind.photo &&
      attachment.kind != OutgoingAttachmentKind.animation) {
    return attachment;
  }
  if ((attachment.width ?? 0) > 0 && (attachment.height ?? 0) > 0) {
    return attachment;
  }
  try {
    final data = await File(attachment.path).readAsBytes();
    final codec = await ui.instantiateImageCodec(data);
    final frame = await codec.getNextFrame();
    final result = attachment.copyWith(
      width: frame.image.width,
      height: frame.image.height,
    );
    frame.image.dispose();
    codec.dispose();
    return result;
  } catch (_) {
    return attachment;
  }
}

Future<List<OutgoingAttachment>> resolveAttachmentListDimensions(
  Iterable<OutgoingAttachment> attachments,
) => Future.wait(attachments.map(resolveAttachmentDimensions));

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
  MessageSendConfiguration sendConfiguration = const MessageSendConfiguration(),
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
  final inputFile = attachmentInputFile(attachment);

  return switch (attachment.kind) {
    OutgoingAttachmentKind.photo => {
      '@type': 'inputMessagePhoto',
      'photo': {
        '@type': 'inputPhoto',
        'photo': inputFile,
        'added_sticker_file_ids': <int>[],
        'width': attachment.width ?? 0,
        'height': attachment.height ?? 0,
      },
      if ((attachment.width ?? 0) > 0) 'width': attachment.width,
      if ((attachment.height ?? 0) > 0) 'height': attachment.height,
      'caption': ?formattedCaption,
      'show_caption_above_media': sendConfiguration.showCaptionAboveMedia,
      'self_destruct_type': ?sendConfiguration.selfDestructType,
      'has_spoiler': sendConfiguration.hasSpoiler,
    },
    OutgoingAttachmentKind.video => {
      '@type': 'inputMessageVideo',
      'video': {
        '@type': 'inputVideo',
        'video': inputFile,
        if (attachment.coverPath case final path?)
          'cover': {'@type': 'inputFileLocal', 'path': path},
        'start_timestamp': attachment.startTimestamp,
        'supports_streaming': true,
      },
      'caption': ?formattedCaption,
      'show_caption_above_media': sendConfiguration.showCaptionAboveMedia,
      'self_destruct_type': ?sendConfiguration.selfDestructType,
      'has_spoiler': sendConfiguration.hasSpoiler,
    },
    OutgoingAttachmentKind.animation => {
      '@type': 'inputMessageAnimation',
      'animation': {
        '@type': 'inputAnimation',
        'animation': inputFile,
        'duration': attachment.duration,
        'width': attachment.width ?? 0,
        'height': attachment.height ?? 0,
      },
      'caption': ?formattedCaption,
      'show_caption_above_media': sendConfiguration.showCaptionAboveMedia,
      'has_spoiler': sendConfiguration.hasSpoiler,
    },
    OutgoingAttachmentKind.document => {
      '@type': 'inputMessageDocument',
      'document': {'@type': 'inputDocument', 'document': inputFile},
      'caption': ?formattedCaption,
    },
    OutgoingAttachmentKind.audio => {
      '@type': 'inputMessageAudio',
      'audio': {
        '@type': 'inputAudio',
        'audio': inputFile,
        'duration': attachment.duration,
        'title': attachment.title,
        'performer': attachment.performer,
      },
      'caption': ?formattedCaption,
    },
    OutgoingAttachmentKind.voiceNote => {
      '@type': 'inputMessageVoiceNote',
      'voice_note': {
        '@type': 'inputVoiceNote',
        'voice_note': inputFile,
        'duration': attachment.duration,
        'waveform': '',
      },
      'caption': ?formattedCaption,
      'self_destruct_type': ?sendConfiguration.selfDestructType,
    },
  };
}

List<Map<String, dynamic>> buildAttachmentSendRequests({
  required int chatId,
  required List<OutgoingAttachment> attachments,
  String caption = '',
  List<Map<String, dynamic>> captionEntities = const [],
  Map<String, dynamic>? replyTo,
  MessageSendConfiguration sendConfiguration = const MessageSendConfiguration(),
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
          sendConfiguration: sendConfiguration,
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
      'options': sendConfiguration.messageSendOptions(),
    });
  }
  return requests;
}
