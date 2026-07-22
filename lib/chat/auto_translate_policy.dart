import '../settings/translation_controller.dart';
import '../tdlib/td_models.dart';

String automaticTranslationSourceText(ChatMessage message) {
  final parts = [
    message.text,
    message.linkPreview?.title ?? '',
    message.linkPreview?.description ?? '',
  ].where((part) => part.trim().isNotEmpty);
  return parts.join('\n');
}

const _languageDetectionIgnoredEntityTypes = <String>{
  'textEntityTypePre',
  'textEntityTypePreCode',
  'textEntityTypeCode',
  'textEntityTypeUrl',
  'textEntityTypeEmailAddress',
  'textEntityTypeMention',
  'textEntityTypeHashtag',
  'textEntityTypeBotCommand',
};

String automaticTranslationLanguageText(ChatMessage message) {
  var text = message.text.length > 256
      ? message.text.substring(0, 256)
      : message.text;
  final ranges =
      message.textEntities
          .where(
            (entity) =>
                _languageDetectionIgnoredEntityTypes.contains(entity.type) &&
                entity.offset >= 0 &&
                entity.offset < text.length,
          )
          .map(
            (entity) => (
              start: entity.offset,
              end: entity.end.clamp(entity.offset, text.length),
            ),
          )
          .where((range) => range.end > range.start)
          .toList()
        ..sort((a, b) => b.start.compareTo(a.start));
  for (final range in ranges) {
    text = text.replaceRange(range.start, range.end, '');
  }
  return text.trim();
}

List<ChatMessage> automaticTranslationCandidates(
  List<ChatMessage> messages, {
  required String targetLanguageCode,
  Set<int> excludedMessageIds = const {},
  int limit = 12,
}) {
  final target = TranslationController.normalizeLanguageCode(
    targetLanguageCode,
  );
  final result = <ChatMessage>[];
  for (final message in messages.reversed) {
    if (result.length >= limit) break;
    if (message.id <= 0 ||
        message.isOutgoing ||
        message.isService ||
        message.isTranslating ||
        excludedMessageIds.contains(message.id) ||
        automaticTranslationSourceText(message).trim().isEmpty) {
      continue;
    }
    final hasTargetTranslation =
        (message.translationText?.trim().isNotEmpty ?? false) &&
        TranslationController.normalizeLanguageCode(
              message.translationLanguageCode,
            ) ==
            target;
    if (!hasTargetTranslation) result.add(message);
  }
  return result;
}

List<String> automaticTranslationLanguageSamples(
  List<ChatMessage> messages, {
  int maximumMessages = 16,
  int minimumMessageLength = 10,
}) {
  final samples = <String>[];
  for (final message in messages.reversed) {
    if (samples.length >= maximumMessages) break;
    if (message.isOutgoing || message.isService) continue;
    final source = automaticTranslationLanguageText(message);
    if (source.length < minimumMessageLength) continue;
    samples.add(source);
  }
  return samples.reversed.toList(growable: false);
}

String automaticTranslationLanguageSample(
  List<ChatMessage> messages, {
  int maximumMessages = 16,
  int minimumMessageLength = 10,
}) => automaticTranslationLanguageSamples(
  messages,
  maximumMessages: maximumMessages,
  minimumMessageLength: minimumMessageLength,
).join('\n');

class AutomaticTranslationLanguageEvidence {
  const AutomaticTranslationLanguageEvidence({
    required this.languageCode,
    required this.confidence,
    required this.characterCount,
  });

  final String languageCode;
  final double confidence;
  final int characterCount;
}

String? dominantAutomaticTranslationLanguage(
  Iterable<AutomaticTranslationLanguageEvidence> evidence,
) {
  final weights = <String, double>{};
  for (final item in evidence) {
    final language = TranslationController.normalizeLanguageCode(
      item.languageCode,
    );
    if (language == null ||
        language == 'und' ||
        item.confidence <= 0 ||
        item.characterCount <= 0) {
      continue;
    }
    weights.update(
      language,
      (weight) => weight + item.characterCount * item.confidence,
      ifAbsent: () => item.characterCount * item.confidence,
    );
  }
  if (weights.isEmpty) return null;
  return weights.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
}
