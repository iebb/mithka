//
//  message_text_entity_runs.dart
//
//  Lookups shared by the message-text renderers over the entities active on
//  one run of text. Where entities conflict, the later one wins, matching the
//  order the renderers apply styles in.
//

import '../../tdlib/td_models.dart';

extension MessageTextEntityRun on List<MessageTextEntity> {
  int? get customEmojiId {
    for (final entity in reversed) {
      if (entity.isCustomEmoji && entity.customEmojiId != null) {
        return entity.customEmojiId;
      }
    }
    return null;
  }

  int? get mentionUserId {
    for (final entity in reversed) {
      if (entity.type == 'textEntityTypeMentionName' && entity.userId != null) {
        return entity.userId;
      }
    }
    return null;
  }

  bool get hasMathematicalExpression =>
      any((entity) => entity.isMathematicalExpression);

  /// Identifies the spoiler covering this run, so every run of one spoiler
  /// reveals together.
  String? get spoilerKey {
    for (final entity in this) {
      if (entity.type == 'textEntityTypeSpoiler') {
        return '${entity.offset}:${entity.length}';
      }
    }
    return null;
  }
}

/// [tag] trimmed and prefixed with `#` when it lacks one.
String normalizedHashtag(String tag) {
  final trimmed = tag.trim();
  return trimmed.startsWith('#') ? trimmed : '#$trimmed';
}

final RegExp _nonDialable = RegExp(r'[^0-9+]');

/// The `tel:` URI for a phone-number entity's [text].
String telephoneUri(String text) => 'tel:${text.replaceAll(_nonDialable, '')}';
