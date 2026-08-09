import '../settings/ai_settings_controller.dart';
import '../settings/translation_controller.dart';
import '../tdlib/td_client.dart';

bool isTelegramTranslationRateLimit(Object error) {
  final code = error is TdError ? error.code : 0;
  if (code == 429) return true;
  final message = (error is TdError ? error.message : error.toString())
      .toUpperCase();
  return message.contains('FLOOD_WAIT') ||
      message.contains('TOO MANY REQUESTS') ||
      (message.contains('TRANSLAT') &&
          (message.contains('LIMIT') || message.contains('FLOOD')));
}

List<String> effectiveTranslationOptionIds({
  required TranslationController translation,
  required AiSettingsController? ai,
  required Set<TranslationProvider> nativeProviders,
  required bool isBotApiAccount,
}) {
  final candidates = <String, AiModelCandidate>{};
  if (ai != null) {
    for (final candidate in ai.modelCandidatesForFeature(
      AiFeature.translation,
    )) {
      candidates[candidate.id] = candidate;
    }
  }
  final availableIds = <String>[
    for (final provider in TranslationProvider.selectableProviders)
      TranslationOptionIds.provider(provider),
    for (final candidate in candidates.values)
      TranslationOptionIds.ai(candidate.id),
  ];
  return translation
      .orderedEnabledTranslationOptions(availableIds)
      .where((id) {
        final provider = TranslationOptionIds.translationProvider(id);
        if (provider != null) {
          return switch (provider) {
            TranslationProvider.tdlib =>
              !isBotApiAccount && translation.isTelegramTranslationAvailable(),
            TranslationProvider.iosSystem || TranslationProvider.androidMlKit =>
              nativeProviders.contains(provider),
            TranslationProvider.libreTranslate =>
              translation.libreTranslateEndpoint.isNotEmpty,
            TranslationProvider.myMemory || TranslationProvider.lingva => true,
          };
        }
        final candidateId = TranslationOptionIds.aiCandidateId(id);
        final candidate = candidates[candidateId];
        if (candidate == null) return false;
        if (isBotApiAccount &&
            candidate.kind == AiModelCandidateKind.telegramCocoon) {
          return false;
        }
        return ai?.isConfiguredCandidate(candidate) ?? false;
      })
      .toList(growable: false);
}
