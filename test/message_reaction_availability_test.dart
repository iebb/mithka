import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/message_reaction_availability.dart';
import 'package:mithka/chat/quick_reaction_choice.dart';

Map<String, dynamic> _available({
  List<Map<String, dynamic>> top = const [],
  List<Map<String, dynamic>> recent = const [],
  List<Map<String, dynamic>> popular = const [],
  bool allowCustom = false,
  Map<String, dynamic>? unavailable,
}) => {
  '@type': 'availableReactions',
  'top_reactions': top,
  'recent_reactions': recent,
  'popular_reactions': popular,
  'allow_custom_emoji': allowCustom,
  'are_tags': false,
  'unavailability_reason': unavailable,
};

Map<String, dynamic> _emoji(String emoji, {bool premium = false}) => {
  '@type': 'availableReaction',
  'type': {'@type': 'reactionTypeEmoji', 'emoji': emoji},
  'needs_premium': premium,
};

Map<String, dynamic> _custom(int id, {bool premium = false}) => {
  '@type': 'availableReaction',
  'type': {'@type': 'reactionTypeCustomEmoji', 'custom_emoji_id': id},
  'needs_premium': premium,
};

void main() {
  test('late availability cannot replace a newer message target', () {
    expect(
      messageReactionAvailabilityResultIsCurrent(
        requestGeneration: 4,
        currentGeneration: 5,
        messageId: 10,
        targetMessageId: 11,
      ),
      isFalse,
    );
    expect(
      messageReactionAvailabilityResultIsCurrent(
        requestGeneration: 5,
        currentGeneration: 5,
        messageId: 11,
        targetMessageId: 11,
      ),
      isTrue,
    );
  });

  test('preserves server order and deduplicates all availability rows', () {
    final availability = MessageReactionAvailability.fromTd(
      _available(
        top: [_emoji('👍'), _custom(42)],
        recent: [_emoji('❤️'), _emoji('👍')],
        popular: [_custom(42), _emoji('🔥')],
      ),
      isPremium: false,
    );

    expect(availability.choices, const [
      QuickReactionChoice.emoji('👍'),
      QuickReactionChoice.custom(42),
      QuickReactionChoice.emoji('❤️'),
      QuickReactionChoice.emoji('🔥'),
    ]);
    expect(availability.canAdd, isTrue);
  });

  test('filters Premium choices and gates arbitrary custom emoji', () {
    final response = _available(
      top: [_emoji('👍'), _emoji('🔥', premium: true)],
      recent: [_custom(42, premium: true)],
      allowCustom: true,
    );

    final regular = MessageReactionAvailability.fromTd(
      response,
      isPremium: false,
    );
    expect(regular.choices, const [QuickReactionChoice.emoji('👍')]);
    expect(regular.allowArbitraryCustom, isFalse);
    expect(regular.allows(const QuickReactionChoice.custom(99)), isFalse);

    final premium = MessageReactionAvailability.fromTd(
      response,
      isPremium: true,
    );
    expect(premium.choices, const [
      QuickReactionChoice.emoji('👍'),
      QuickReactionChoice.emoji('🔥'),
      QuickReactionChoice.custom(42),
    ]);
    expect(premium.allowArbitraryCustom, isTrue);
    expect(premium.allows(const QuickReactionChoice.custom(99)), isTrue);
  });

  test('unavailability reason blocks additions despite populated rows', () {
    final availability = MessageReactionAvailability.fromTd(
      _available(
        top: [_emoji('👍')],
        allowCustom: true,
        unavailable: const {'@type': 'reactionUnavailabilityReasonRestricted'},
      ),
      isPremium: true,
    );

    expect(availability.isUnavailable, isTrue);
    expect(availability.choices, isEmpty);
    expect(availability.allowArbitraryCustom, isFalse);
    expect(availability.canAdd, isFalse);
  });

  test('uses server canonical spelling for variation-selector matches', () {
    final availability = MessageReactionAvailability.fromTd(
      _available(top: [_emoji('❤')]),
      isPremium: false,
    );

    expect(
      availability.canonicalChoice(const QuickReactionChoice.emoji('❤️')),
      const QuickReactionChoice.emoji('❤'),
    );
    expect(
      availability.quickChoices(const [
        QuickReactionChoice.emoji('❤️'),
        QuickReactionChoice.emoji('🔥'),
      ]),
      const [QuickReactionChoice.emoji('❤')],
    );
  });

  test(
    'falls back to server choices when configured choices are disallowed',
    () {
      final availability = MessageReactionAvailability.fromTd(
        _available(top: [_emoji('👍'), _custom(42)]),
        isPremium: false,
      );

      expect(
        availability.quickChoices(const [QuickReactionChoice.emoji('🔥')]),
        const [QuickReactionChoice.emoji('👍'), QuickReactionChoice.custom(42)],
      );
    },
  );

  test('empty authoritative availability stays empty', () {
    final availability = MessageReactionAvailability.fromTd(
      _available(),
      isPremium: false,
    );

    expect(availability.canAdd, isFalse);
    expect(availability.quickChoices(defaultQuickReactions), isEmpty);
  });

  test('message action controls wait for a non-empty mobile result', () {
    final empty = MessageReactionAvailability.fromTd(
      _available(),
      isPremium: false,
    );
    final allowed = MessageReactionAvailability.fromTd(
      _available(top: [_emoji('👍')]),
      isPremium: false,
    );

    expect(
      messageActionShowsReactionControls(
        isDesktop: false,
        isCall: false,
        availability: null,
      ),
      isFalse,
    );
    expect(
      messageActionShowsReactionControls(
        isDesktop: false,
        isCall: false,
        availability: empty,
      ),
      isFalse,
    );
    expect(
      messageActionShowsReactionControls(
        isDesktop: false,
        isCall: false,
        availability: allowed,
      ),
      isTrue,
    );
    expect(
      messageActionShowsReactionControls(
        isDesktop: true,
        isCall: false,
        availability: allowed,
      ),
      isFalse,
    );
  });
}
