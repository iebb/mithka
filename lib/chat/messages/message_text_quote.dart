import 'dart:math' as math;

import '../../tdlib/td_models.dart';

const defaultMessageQuoteLengthLimit = 1024;

bool canQuoteMessageText(ChatMessage message) =>
    !message.isService &&
    !message.isSending &&
    !message.isContentRestricted &&
    message.id > 0 &&
    message.quoteSourceText.isNotEmpty &&
    const {
      'messageText',
      'messagePhoto',
      'messageVideo',
      'messageAnimation',
      'messageAudio',
      'messageDocument',
    }.contains(message.contentType);

/// TDLib quotes address UTF-16 offsets and retain only these entity types.
/// Preserve whitespace and the selected occurrence of repeated text exactly.
MessageTextQuote? quoteMessageRange(
  ChatMessage message, {
  required int start,
  required int end,
  int maxLength = defaultMessageQuoteLengthLimit,
}) {
  final text = message.quoteSourceText;
  if (!canQuoteMessageText(message) ||
      start < 0 ||
      end > text.length ||
      start >= end ||
      end - start > maxLength ||
      !_isUtf16Boundary(text, start) ||
      !_isUtf16Boundary(text, end)) {
    return null;
  }
  final entities = <MessageTextEntity>[];
  for (final entity in message.quoteSourceEntities) {
    if (!const {
      'textEntityTypeBold',
      'textEntityTypeItalic',
      'textEntityTypeUnderline',
      'textEntityTypeStrikethrough',
      'textEntityTypeSpoiler',
      'textEntityTypeCustomEmoji',
    }.contains(entity.type)) {
      continue;
    }
    final clippedStart = math.max(start, entity.offset);
    final clippedEnd = math.min(end, entity.end);
    if (clippedEnd <= clippedStart) continue;
    if (entity.isCustomEmoji &&
        (clippedStart != entity.offset || clippedEnd != entity.end)) {
      return null;
    }
    entities.add(
      MessageTextEntity(
        offset: clippedStart - start,
        length: clippedEnd - clippedStart,
        type: entity.type,
        customEmojiId: entity.customEmojiId,
        typeData: entity.typeData,
      ),
    );
  }
  return MessageTextQuote(
    text: text.substring(start, end),
    position: start,
    entities: List.unmodifiable(entities),
  );
}

bool _isUtf16Boundary(String text, int offset) {
  if (offset == 0 || offset == text.length) return true;
  final before = text.codeUnitAt(offset - 1);
  final after = text.codeUnitAt(offset);
  return !(before >= 0xd800 &&
      before <= 0xdbff &&
      after >= 0xdc00 &&
      after <= 0xdfff);
}
