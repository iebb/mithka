import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/settings/ai_translation_prompt.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'AI translation prompt persists and resets to the safe default',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final controller = TranslationController(preferences);

      expect(controller.aiTranslationPrompt, defaultAiTranslationPrompt.trim());
      expect(controller.hasCustomAiTranslationPrompt, isFalse);

      controller.setAiTranslationPrompt(
        'Translate concisely and preserve the speaker’s register.',
      );

      expect(controller.hasCustomAiTranslationPrompt, isTrue);
      expect(
        preferences.getString(
          TranslationController.aiTranslationPromptPreferenceKey,
        ),
        'Translate concisely and preserve the speaker’s register.',
      );

      final restored = TranslationController(preferences);
      expect(restored.aiTranslationPrompt, controller.aiTranslationPrompt);

      restored.resetAiTranslationPrompt();
      expect(restored.aiTranslationPrompt, defaultAiTranslationPrompt.trim());
      expect(restored.hasCustomAiTranslationPrompt, isFalse);
      expect(
        preferences.containsKey(
          TranslationController.aiTranslationPromptPreferenceKey,
        ),
        isFalse,
      );
    },
  );
}
