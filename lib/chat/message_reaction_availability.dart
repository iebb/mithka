import 'package:flutter/foundation.dart';

import 'quick_reaction_choice.dart';

String normalizedReactionEmoji(String emoji) =>
    emoji.replaceAll(RegExp('[\uFE0E\uFE0F]'), '');

class MessageReactionUnavailableException implements Exception {
  const MessageReactionUnavailableException();

  @override
  String toString() => 'Reaction is unavailable for this message';
}

/// Whether the action overlay carries reaction controls.
///
/// Desktop draws them as a strip on top of the context menu, touch as the
/// rounded bar above the pressed message. Neither has anything to offer for a
/// call log, or for a message the server allows no reactions on.
bool messageActionShowsReactionControls({
  required bool isCall,
  required MessageReactionAvailability? availability,
}) => !isCall && availability?.canAdd == true;

bool messageReactionAvailabilityResultIsCurrent({
  required int requestGeneration,
  required int currentGeneration,
  required int messageId,
  required int? targetMessageId,
}) => requestGeneration == currentGeneration && messageId == targetMessageId;

@immutable
class MessageReactionAvailability {
  const MessageReactionAvailability._({
    required this.choices,
    required this.allowArbitraryCustom,
    required this.isUnavailable,
  });

  factory MessageReactionAvailability.fromTd(
    Map<String, dynamic> response, {
    required bool isPremium,
  }) {
    if (response['unavailability_reason'] != null) {
      return const MessageReactionAvailability._(
        choices: <QuickReactionChoice>[],
        allowArbitraryCustom: false,
        isUnavailable: true,
      );
    }

    final choices = <QuickReactionChoice>[];
    final seen = <String>{};

    void collect(String key) {
      final values = response[key];
      if (values is! List) return;
      for (final value in values) {
        if (value is! Map || value['needs_premium'] == true) {
          if (value is! Map || !isPremium) continue;
        }
        final type = value['type'];
        if (type is! Map) continue;
        final typeName = type['@type'];
        QuickReactionChoice? choice;
        String? identity;
        if (typeName == 'reactionTypeEmoji') {
          final emoji = type['emoji'];
          if (emoji is! String || emoji.isEmpty) continue;
          choice = QuickReactionChoice.emoji(emoji);
          identity = 'emoji:${normalizedReactionEmoji(emoji)}';
        } else if (typeName == 'reactionTypeCustomEmoji') {
          final rawId = type['custom_emoji_id'];
          final id = rawId is int
              ? rawId
              : rawId is num
              ? rawId.toInt()
              : int.tryParse('$rawId');
          if (id == null || id == 0) continue;
          choice = QuickReactionChoice.custom(id);
          identity = 'custom:$id';
        }
        if (choice != null && identity != null && seen.add(identity)) {
          choices.add(choice);
        }
      }
    }

    collect('top_reactions');
    collect('recent_reactions');
    collect('popular_reactions');
    return MessageReactionAvailability._(
      choices: List.unmodifiable(choices),
      allowArbitraryCustom: isPremium && response['allow_custom_emoji'] == true,
      isUnavailable: false,
    );
  }

  factory MessageReactionAvailability.fallback({
    required Iterable<QuickReactionChoice> choices,
    required bool allowArbitraryCustom,
  }) => MessageReactionAvailability._(
    choices: List.unmodifiable(choices),
    allowArbitraryCustom: allowArbitraryCustom,
    isUnavailable: false,
  );

  final List<QuickReactionChoice> choices;
  final bool allowArbitraryCustom;
  final bool isUnavailable;

  bool get canAdd => choices.isNotEmpty || allowArbitraryCustom;

  QuickReactionChoice? canonicalChoice(QuickReactionChoice requested) {
    if (requested.isCustom) {
      for (final choice in choices) {
        if (choice.isCustom &&
            choice.customEmojiId == requested.customEmojiId) {
          return choice;
        }
      }
      return allowArbitraryCustom ? requested : null;
    }
    final normalized = normalizedReactionEmoji(requested.emoji);
    for (final choice in choices) {
      if (!choice.isCustom &&
          normalizedReactionEmoji(choice.emoji) == normalized) {
        return choice;
      }
    }
    return null;
  }

  bool allows(QuickReactionChoice requested) =>
      canonicalChoice(requested) != null;

  List<QuickReactionChoice> quickChoices(
    Iterable<QuickReactionChoice> configured, {
    int fallbackLimit = 7,
  }) {
    final filtered = <QuickReactionChoice>[];
    final seen = <QuickReactionChoice>{};
    for (final requested in configured) {
      final canonical = canonicalChoice(requested);
      if (canonical != null && seen.add(canonical)) filtered.add(canonical);
    }
    if (filtered.isNotEmpty) return List.unmodifiable(filtered);
    return List.unmodifiable(choices.take(fallbackLimit));
  }
}
