import 'outgoing_attachment.dart';

const telegramTextMessageMaxCharacters = 4096;
const telegramRichMessageMaxCharacters = 32768;

enum TelegramMessageLengthTier { standard, rich, exceeded }

int telegramUtf8CharacterCount(String text) => text.runes.length;

TelegramMessageLengthTier telegramMessageLengthTier(String text) {
  final length = telegramUtf8CharacterCount(text);
  if (length <= telegramTextMessageMaxCharacters) {
    return TelegramMessageLengthTier.standard;
  }
  if (length <= telegramRichMessageMaxCharacters) {
    return TelegramMessageLengthTier.rich;
  }
  return TelegramMessageLengthTier.exceeded;
}

class RichMessageSendSegment {
  const RichMessageSendSegment.html(
    this.html, {
    this.richFiles = const [],
    this.blocks = const [],
  }) : attachments = const [];
  const RichMessageSendSegment.attachments(this.attachments)
    : html = '',
      richFiles = const [],
      blocks = const [];

  final String html;
  final List<RichMessageSendFile> richFiles;
  final List<Map<String, dynamic>> blocks;
  final List<OutgoingAttachment> attachments;

  bool get isHtml => html.trim().isNotEmpty || blocks.isNotEmpty;
}

class RichMessageSendFile {
  const RichMessageSendFile({required this.id, required this.attachment});

  final String id;
  final OutgoingAttachment attachment;
}

Map<String, dynamic> richMessageFilePayload(RichMessageSendFile file) {
  final attachment = file.attachment;
  final inputFile = attachmentInputFile(attachment);
  final segments = Uri.file(attachment.path).pathSegments;
  final fileName = segments.isEmpty ? attachment.path : segments.last;
  return switch (attachment.kind) {
    OutgoingAttachmentKind.photo => {
      '@type': 'inputRichMessageMedia',
      'id': file.id,
      'media': {
        '@type': 'inputMessagePhoto',
        'photo': {
          '@type': 'inputPhoto',
          'photo': inputFile,
          'added_sticker_file_ids': <int>[],
          'width': attachment.width ?? 0,
          'height': attachment.height ?? 0,
        },
      },
    },
    OutgoingAttachmentKind.video => {
      '@type': 'inputRichMessageMedia',
      'id': file.id,
      'media': {
        '@type': 'inputMessageVideo',
        'video': {
          '@type': 'inputVideo',
          'video': inputFile,
          'start_timestamp': 0,
          'added_sticker_file_ids': <int>[],
          'duration': attachment.duration,
          'width': attachment.width ?? 0,
          'height': attachment.height ?? 0,
          'supports_streaming': true,
        },
      },
    },
    OutgoingAttachmentKind.animation => {
      '@type': 'inputRichMessageMedia',
      'id': file.id,
      'media': {
        '@type': 'inputMessageAnimation',
        'animation': {
          '@type': 'inputAnimation',
          'animation': inputFile,
          'added_sticker_file_ids': <int>[],
          'duration': attachment.duration,
          'width': attachment.width ?? 0,
          'height': attachment.height ?? 0,
        },
      },
    },
    OutgoingAttachmentKind.audio => {
      '@type': 'inputRichMessageMedia',
      'id': file.id,
      'media': {
        '@type': 'inputMessageAudio',
        'audio': {
          '@type': 'inputAudio',
          'audio': inputFile,
          'duration': attachment.duration,
          'title': attachment.title.isEmpty ? fileName : attachment.title,
          'performer': attachment.performer,
        },
      },
    },
    OutgoingAttachmentKind.voiceNote => {
      '@type': 'inputRichMessageMedia',
      'id': file.id,
      'media': {
        '@type': 'inputMessageVoiceNote',
        'voice_note': {
          '@type': 'inputVoiceNote',
          'voice_note': inputFile,
          'duration': attachment.duration,
          'waveform': '',
        },
      },
    },
    OutgoingAttachmentKind.document => throw ArgumentError.value(
      attachment.kind,
      'attachment.kind',
      'Documents are not supported rich-message media',
    ),
  };
}

Map<String, dynamic> richMessageInputContent(
  List<Map<String, dynamic>> blocks,
) {
  if (blocks.isEmpty) {
    throw ArgumentError.value(blocks, 'blocks', 'Rich message blocks required');
  }
  return {
    '@type': 'inputMessageRichMessage',
    'message': {
      '@type': 'inputRichMessage',
      'source': {'@type': 'richMessageSourceBlocks', 'blocks': blocks},
      'is_rtl': false,
      'detect_automatic_blocks': true,
    },
    'clear_draft': true,
  };
}

Map<String, dynamic> formattedTextToRichText(
  String text,
  List<Map<String, dynamic>> entities, {
  int sourceOffset = 0,
}) {
  if (text.isEmpty) return {'@type': 'richTextPlain', 'text': ''};
  final endOffset = sourceOffset + text.length;
  final valid = entities.where((entity) {
    final offset = entity['offset'];
    final length = entity['length'];
    return offset is int &&
        length is int &&
        length > 0 &&
        offset < endOffset &&
        offset + length > sourceOffset;
  }).toList();
  final cuts = <int>{sourceOffset, endOffset};
  for (final entity in valid) {
    final start = (entity['offset'] as int).clamp(sourceOffset, endOffset);
    final end = ((entity['offset'] as int) + (entity['length'] as int)).clamp(
      sourceOffset,
      endOffset,
    );
    cuts
      ..add(start)
      ..add(end);
  }
  final ordered = cuts.toList()..sort();
  final nodes = <Map<String, dynamic>>[];
  for (var index = 0; index < ordered.length - 1; index++) {
    final start = ordered[index];
    final end = ordered[index + 1];
    if (start >= end) continue;
    final active =
        valid.where((entity) {
            final entityStart = entity['offset'] as int;
            final entityEnd = entityStart + (entity['length'] as int);
            return entityStart < end && entityEnd > start;
          }).toList()
          ..sort((a, b) => _entityPriority(a).compareTo(_entityPriority(b)));
    final value = text.substring(start - sourceOffset, end - sourceOffset);
    Map<String, dynamic> node = {'@type': 'richTextPlain', 'text': value};
    for (final entity in active.reversed) {
      node = _wrapRichTextNode(node, value, entity);
    }
    nodes.add(node);
  }
  if (nodes.length == 1) return nodes.single;
  return {'@type': 'richTexts', 'texts': nodes};
}

Map<String, dynamic> _wrapRichTextNode(
  Map<String, dynamic> child,
  String alternativeText,
  Map<String, dynamic> entity,
) {
  final rawType = entity['type'];
  if (rawType is! Map) return child;
  final type = rawType['@type'] as String?;
  final wrapperType = switch (type) {
    'textEntityTypeBold' => 'richTextBold',
    'textEntityTypeItalic' => 'richTextItalic',
    'textEntityTypeUnderline' => 'richTextUnderline',
    'textEntityTypeStrikethrough' => 'richTextStrikethrough',
    'textEntityTypeSpoiler' => 'richTextSpoiler',
    'textEntityTypeCode' ||
    'textEntityTypePre' ||
    'textEntityTypePreCode' => 'richTextFixed',
    'textEntityTypeMarked' => 'richTextMarked',
    'textEntityTypeSubscript' => 'richTextSubscript',
    'textEntityTypeSuperscript' => 'richTextSuperscript',
    _ => null,
  };
  if (wrapperType != null) return {'@type': wrapperType, 'text': child};
  return switch (type) {
    'textEntityTypeDateTime' when rawType['unix_time'] is int => {
      '@type': 'richTextDateTime',
      'text': child,
      'unix_time': rawType['unix_time'],
      if (rawType['formatting_type'] is Map<String, dynamic>)
        'formatting_type': rawType['formatting_type'],
    },
    'textEntityTypeTextUrl' => {
      '@type': 'richTextUrl',
      'text': child,
      'url': '${rawType['url'] ?? ''}',
      'is_cached': false,
    },
    'textEntityTypeUrl' => {
      '@type': 'richTextUrl',
      'text': child,
      'url': alternativeText,
      'is_cached': false,
    },
    'textEntityTypeMentionName' => {
      '@type': 'richTextMentionName',
      'text': child,
      'user_id': rawType['user_id'],
    },
    'textEntityTypeCustomEmoji' => {
      '@type': 'richTextCustomEmoji',
      'custom_emoji_id': rawType['custom_emoji_id'],
      'alternative_text': alternativeText,
    },
    'textEntityTypeMathematicalExpression' => {
      '@type': 'richTextMathematicalExpression',
      'expression': alternativeText,
    },
    'textEntityTypeEmailAddress' => {
      '@type': 'richTextEmailAddress',
      'text': child,
      'email_address': alternativeText,
    },
    'textEntityTypePhoneNumber' => {
      '@type': 'richTextPhoneNumber',
      'text': child,
      'phone_number': alternativeText,
    },
    'textEntityTypeHashtag' => {
      '@type': 'richTextHashtag',
      'text': child,
      'hashtag': alternativeText.replaceFirst(RegExp(r'^#'), ''),
    },
    'textEntityTypeCashtag' => {
      '@type': 'richTextCashtag',
      'text': child,
      'cashtag': alternativeText.replaceFirst(RegExp(r'^\$'), ''),
    },
    'textEntityTypeBotCommand' => {
      '@type': 'richTextBotCommand',
      'text': child,
      'bot_command': alternativeText,
    },
    'textEntityTypeBankCardNumber' => {
      '@type': 'richTextBankCardNumber',
      'text': child,
      'bank_card_number': alternativeText,
    },
    'textEntityTypeMention' => {
      '@type': 'richTextMention',
      'text': child,
      'username': alternativeText.replaceFirst(RegExp(r'^@'), ''),
    },
    _ => child,
  };
}

Map<String, dynamic> richMessageMediaBlockPayload(
  OutgoingAttachment attachment,
) {
  final inputFile = attachmentInputFile(attachment);
  final caption = attachment.caption.trim().isEmpty
      ? null
      : {
          '@type': 'pageBlockCaption',
          'text': formattedTextToRichText(
            attachment.caption,
            attachment.captionEntities,
          ),
          'credit': null,
        };
  return switch (attachment.kind) {
    OutgoingAttachmentKind.photo => {
      '@type': 'inputPageBlockPhoto',
      'photo': {
        '@type': 'inputPhoto',
        'photo': inputFile,
        'added_sticker_file_ids': <int>[],
        'width': attachment.width ?? 0,
        'height': attachment.height ?? 0,
      },
      'caption': caption,
      'has_spoiler': false,
    },
    OutgoingAttachmentKind.video => {
      '@type': 'inputPageBlockVideo',
      'video': {
        '@type': 'inputVideo',
        'video': inputFile,
        'start_timestamp': 0,
        'added_sticker_file_ids': <int>[],
        'duration': attachment.duration,
        'width': attachment.width ?? 0,
        'height': attachment.height ?? 0,
        'supports_streaming': true,
      },
      'caption': caption,
      'has_spoiler': false,
    },
    OutgoingAttachmentKind.animation => {
      '@type': 'inputPageBlockAnimation',
      'animation': {
        '@type': 'inputAnimation',
        'animation': inputFile,
        'added_sticker_file_ids': <int>[],
        'duration': attachment.duration,
        'width': attachment.width ?? 0,
        'height': attachment.height ?? 0,
      },
      'caption': caption,
      'has_spoiler': false,
    },
    OutgoingAttachmentKind.audio => {
      '@type': 'inputPageBlockAudio',
      'audio': {
        '@type': 'inputAudio',
        'audio': inputFile,
        'duration': attachment.duration,
        'title': attachment.title,
        'performer': attachment.performer,
      },
      'caption': caption,
    },
    OutgoingAttachmentKind.voiceNote => {
      '@type': 'inputPageBlockVoiceNote',
      'voice_note': {
        '@type': 'inputVoiceNote',
        'voice_note': inputFile,
        'duration': attachment.duration,
        'waveform': '',
      },
      'caption': caption,
    },
    OutgoingAttachmentKind.document => throw ArgumentError.value(
      attachment.kind,
      'attachment.kind',
      'Documents are not rich-message media blocks',
    ),
  };
}

String formattedTextToRichHtml(
  String text,
  List<Map<String, dynamic>> entities, {
  int headingLevel = 0,
}) {
  if (text.trim().isEmpty) return '';
  if (headingLevel > 0) {
    final level = headingLevel.clamp(1, 6);
    return '<h$level>${_inlineHtml(text.trim(), entities, 0)}</h$level>';
  }

  final lines = text.split('\n');
  final buffer = StringBuffer();
  String? openList;
  var offset = 0;

  void closeList() {
    if (openList == null) return;
    buffer.write('</$openList>');
    openList = null;
  }

  for (final line in lines) {
    final task = RegExp(r'^\s*-\s*\[([ xX])\]\s*(.*)$').firstMatch(line);
    final unordered = RegExp(r'^\s*[-*+]\s+(.*)$').firstMatch(line);
    final ordered = RegExp(r'^\s*\d+[.)]\s+(.*)$').firstMatch(line);
    String? listType;
    String content = line;
    String prefix = '';
    var contentOffset = offset;
    if (task != null) {
      listType = 'ul';
      content = task.group(2) ?? '';
      contentOffset += line.indexOf(content);
      prefix =
          '<input type="checkbox"${task.group(1)!.toLowerCase() == 'x' ? ' checked' : ''}>';
    } else if (unordered != null) {
      listType = 'ul';
      content = unordered.group(1) ?? '';
      contentOffset += line.indexOf(content);
    } else if (ordered != null) {
      listType = 'ol';
      content = ordered.group(1) ?? '';
      contentOffset += line.indexOf(content);
    }

    if (listType != null) {
      if (openList != listType) {
        closeList();
        openList = listType;
        buffer.write('<$listType>');
      }
      buffer
        ..write('<li>')
        ..write(prefix)
        ..write(_inlineHtml(content, entities, contentOffset))
        ..write('</li>');
    } else {
      closeList();
      if (line.trim().isNotEmpty) {
        buffer
          ..write('<p>')
          ..write(_inlineHtml(line, entities, offset))
          ..write('</p>');
      }
    }
    offset += line.length + 1;
  }
  closeList();
  return buffer.toString();
}

String formattedTextToRichInlineHtml(
  String text,
  List<Map<String, dynamic>> entities,
) => _inlineHtml(text, entities, 0);

String _inlineHtml(
  String text,
  List<Map<String, dynamic>> entities,
  int sourceOffset,
) {
  if (text.isEmpty) return '';
  final endOffset = sourceOffset + text.length;
  final valid = entities.where((entity) {
    final offset = entity['offset'];
    final length = entity['length'];
    return offset is int &&
        length is int &&
        length > 0 &&
        offset < endOffset &&
        offset + length > sourceOffset;
  }).toList();
  final cuts = <int>{sourceOffset, endOffset};
  for (final entity in valid) {
    final start = (entity['offset'] as int).clamp(sourceOffset, endOffset);
    final end = ((entity['offset'] as int) + (entity['length'] as int)).clamp(
      sourceOffset,
      endOffset,
    );
    cuts
      ..add(start)
      ..add(end);
  }
  final ordered = cuts.toList()..sort();
  final buffer = StringBuffer();
  for (var index = 0; index < ordered.length - 1; index++) {
    final start = ordered[index];
    final end = ordered[index + 1];
    if (start >= end) continue;
    final active =
        valid.where((entity) {
            final entityStart = entity['offset'] as int;
            final entityEnd = entityStart + (entity['length'] as int);
            return entityStart < end && entityEnd > start;
          }).toList()
          ..sort((a, b) => _entityPriority(a).compareTo(_entityPriority(b)));
    var segment = _escapeHtml(
      text.substring(start - sourceOffset, end - sourceOffset),
    );
    for (final entity in active.reversed) {
      segment = _wrapEntity(segment, entity);
    }
    buffer.write(segment);
  }
  return buffer.toString();
}

int _entityPriority(Map<String, dynamic> entity) {
  final type = entity['type'];
  final name = type is Map ? type['@type'] as String? : null;
  return switch (name) {
    'textEntityTypeTextUrl' || 'textEntityTypeMentionName' => 0,
    'textEntityTypeBold' => 1,
    'textEntityTypeItalic' => 2,
    'textEntityTypeUnderline' => 3,
    'textEntityTypeStrikethrough' => 4,
    'textEntityTypeSpoiler' => 5,
    'textEntityTypeCode' || 'textEntityTypePre' || 'textEntityTypePreCode' => 6,
    _ => 7,
  };
}

String _wrapEntity(String value, Map<String, dynamic> entity) {
  final rawType = entity['type'];
  if (rawType is! Map) return value;
  final type = rawType['@type'] as String?;
  return switch (type) {
    'textEntityTypeBold' => '<b>$value</b>',
    'textEntityTypeItalic' => '<i>$value</i>',
    'textEntityTypeUnderline' => '<u>$value</u>',
    'textEntityTypeStrikethrough' => '<s>$value</s>',
    'textEntityTypeSpoiler' => '<tg-spoiler>$value</tg-spoiler>',
    'textEntityTypeCode' => '<code>$value</code>',
    'textEntityTypePre' || 'textEntityTypePreCode' => '<pre>$value</pre>',
    'textEntityTypeMarked' => '<mark>$value</mark>',
    'textEntityTypeSubscript' => '<sub>$value</sub>',
    'textEntityTypeSuperscript' => '<sup>$value</sup>',
    'textEntityTypeBlockQuote' ||
    'textEntityTypeExpandableBlockQuote' => '<blockquote>$value</blockquote>',
    'textEntityTypeMathematicalExpression' => '<tg-math>$value</tg-math>',
    'textEntityTypeDateTime' => _wrapDateTimeEntity(value, rawType),
    'textEntityTypeTextUrl' =>
      '<a href="${_escapeAttribute('${rawType['url'] ?? ''}')}">$value</a>',
    'textEntityTypeMentionName' =>
      '<a href="tg://user?id=${_escapeAttribute('${rawType['user_id'] ?? ''}')}">$value</a>',
    'textEntityTypeCustomEmoji' =>
      '<tg-emoji emoji-id="${_escapeAttribute('${rawType['custom_emoji_id'] ?? ''}')}">$value</tg-emoji>',
    _ => value,
  };
}

String _wrapDateTimeEntity(String value, Map<dynamic, dynamic> type) {
  final unixTime = type['unix_time'];
  if (unixTime is! int) return value;
  final format = _dateTimeFormat(type['formatting_type']);
  final formatAttribute = format.isEmpty
      ? ''
      : ' format="${_escapeAttribute(format)}"';
  return '<tg-time unix="$unixTime"$formatAttribute>$value</tg-time>';
}

String _dateTimeFormat(Object? formattingType) {
  if (formattingType is! Map<String, dynamic>) return '';
  if (formattingType['@type'] == 'dateTimeFormattingTypeRelative') return 'r';
  if (formattingType['@type'] != 'dateTimeFormattingTypeAbsolute') return '';
  final buffer = StringBuffer();
  if (formattingType['show_day_of_week'] == true) buffer.write('w');
  final dateType = formattingType['date_precision'];
  if (dateType is Map<String, dynamic>) {
    if (dateType['@type'] == 'dateTimePartPrecisionShort') buffer.write('d');
    if (dateType['@type'] == 'dateTimePartPrecisionLong') buffer.write('D');
  }
  final timeType = formattingType['time_precision'];
  if (timeType is Map<String, dynamic>) {
    if (timeType['@type'] == 'dateTimePartPrecisionShort') buffer.write('t');
    if (timeType['@type'] == 'dateTimePartPrecisionLong') buffer.write('T');
  }
  return buffer.toString();
}

String escapeRichHtml(String value) => _escapeHtml(value);

String _escapeHtml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

String _escapeAttribute(String value) => _escapeHtml(value);
