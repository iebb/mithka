import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/settings/ai_settings_controller.dart';
import 'package:mithka/settings/apple_pcc_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AiSettingsController', () {
    test('defaults off and reports unavailable PCC as unconfigured', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final controller = AiSettingsController(
        preferences,
        pccApi: _pccApi(available: false),
        secureRead: (_) async => null,
        secureWrite: (_, _) async {},
      );

      expect(controller.initialized, isFalse);
      expect(controller.enabled, isFalse);
      expect(controller.provider, AiProviderMode.applePcc);

      await controller.initialize();

      expect(controller.initialized, isTrue);
      expect(controller.enabled, isFalse);
      expect(
        preferences.getBool(AiSettingsController.enabledPreferenceKey),
        AiSettingsController.defaultUnreadSummaryEnabled,
      );
      expect(controller.endpoint, isEmpty);
      expect(controller.model, isEmpty);
      expect(controller.apiKey, isEmpty);
      expect(controller.pccCapabilities?.available, isFalse);
      expect(controller.isConfiguredForCurrentProvider, isFalse);
      expect(controller.modelCandidates, hasLength(2));
      expect(
        controller.modelCandidatesForFeature(AiFeature.translation),
        hasLength(3),
      );
      expect(
        controller.modelCandidatesForFeature(AiFeature.summary),
        hasLength(3),
      );
      expect(
        controller.modelCandidatesForFeature(AiFeature.reply),
        hasLength(3),
      );
      expect(
        controller.translationModelCandidate.kind,
        AiModelCandidateKind.applePcc,
      );
      expect(
        controller.summaryModelCandidate.kind,
        AiModelCandidateKind.applePcc,
      );
      expect(
        controller.replyModelCandidate.kind,
        AiModelCandidateKind.telegramCocoon,
      );
      expect(controller.isConfiguredForFeature(AiFeature.reply), isTrue);
    });

    test(
      'persists ordinary values but keeps API key in secure storage',
      () async {
        const secret = 'sk-private-test-value';
        SharedPreferences.setMockInitialValues({});
        final preferences = await SharedPreferences.getInstance();
        final secureValues = <String, String>{};
        final controller = AiSettingsController(
          preferences,
          pccApi: _pccApi(available: true),
          secureRead: (key) async => secureValues[key],
          secureWrite: (key, value) async {
            if (value == null) {
              secureValues.remove(key);
            } else {
              secureValues[key] = value;
            }
          },
        );
        await controller.initialize();

        await controller.setEnabled(true);
        await controller.setProvider(AiProviderMode.openAiCompatible);
        final provider = await controller.saveServerProvider(
          name: 'Example AI',
          endpoint: ' https://ai.example.com/v1/chat/completions ',
          apiKey: ' $secret ',
        );
        await controller.saveModelProfile(
          providerId: provider.id,
          model: ' example-model ',
          contextWindowTokens: 131072,
          contextWindowDetected: true,
        );

        expect(controller.enabled, isTrue);
        expect(controller.provider, AiProviderMode.openAiCompatible);
        expect(
          controller.endpoint,
          'https://ai.example.com/v1/chat/completions',
        );
        expect(controller.model, 'example-model');
        expect(controller.apiKey, secret);
        expect(controller.activeServerProvider?.name, 'Example AI');
        expect(controller.activeModelProfile?.contextWindowTokens, 131072);
        expect(controller.activeModelProfile?.contextWindowDetected, isTrue);
        expect(controller.serverProviders, hasLength(1));
        expect(controller.modelProfiles, hasLength(1));
        expect(controller.isConfiguredForCurrentProvider, isTrue);
        expect(secureValues.values, contains(secret));
        expect(
          secureValues,
          isNot(contains(AiSettingsController.apiKeyStorageKey)),
        );
        expect(preferences.getKeys(), isNot(contains(secret)));
        for (final key in preferences.getKeys()) {
          expect('${preferences.get(key)}', isNot(contains(secret)));
        }

        final restored = AiSettingsController(
          preferences,
          pccApi: _pccApi(available: false),
          secureRead: (key) async => secureValues[key],
          secureWrite: (_, _) async {},
        );
        await restored.initialize();
        expect(restored.enabled, isTrue);
        expect(restored.provider, AiProviderMode.openAiCompatible);
        expect(restored.model, 'example-model');
        expect(restored.apiKey, secret);
        expect(restored.activeModelProfile?.contextWindowDetected, isTrue);
        expect(restored.isConfiguredForCurrentProvider, isTrue);

        await controller.deleteServerProvider(provider.id);
        expect(controller.serverProviders, isEmpty);
        expect(controller.modelProfiles, isEmpty);
        expect(secureValues, isEmpty);
      },
    );

    test(
      'migrates the legacy endpoint and key into a secure profile',
      () async {
        const secret = 'legacy-secret';
        SharedPreferences.setMockInitialValues({
          AiSettingsController.providerPreferenceKey: 'open_ai_compatible',
          AiSettingsController.endpointPreferenceKey:
              'https://legacy.example/v1/chat/completions',
          AiSettingsController.modelPreferenceKey: 'legacy-model',
        });
        final secureValues = <String, String>{
          AiSettingsController.apiKeyStorageKey: secret,
        };
        final preferences = await SharedPreferences.getInstance();
        final controller = AiSettingsController(
          preferences,
          pccApi: _pccApi(available: false),
          secureRead: (key) async => secureValues[key],
          secureWrite: (key, value) async {
            if (value == null) {
              secureValues.remove(key);
            } else {
              secureValues[key] = value;
            }
          },
        );

        await controller.initialize();

        expect(controller.serverProviders, hasLength(1));
        expect(controller.activeServerProvider?.id, 'legacy');
        expect(
          controller.activeModelProfile?.contextWindowTokens,
          AiModelProfile.defaultContextWindowTokens,
        );
        expect(controller.apiKey, secret);
        expect(
          secureValues,
          isNot(contains(AiSettingsController.apiKeyStorageKey)),
        );
        expect(secureValues.values, contains(secret));
        expect(
          preferences.getString(
            AiSettingsController.serverProvidersPreferenceKey,
          ),
          isNot(contains(secret)),
        );
      },
    );
  });

  group('hosted AI endpoint validation', () {
    test('rejects insecure remote, inexact, and credential-bearing URLs', () {
      const invalid = [
        '',
        'api.example.com/v1/chat/completions',
        'http://api.example.com/v1/chat/completions',
        'ftp://localhost/v1/chat/completions',
        'https://api.example.com/v1/chat/completions/',
        'https://api.example.com/chat/completions',
        'https://api.example.com/v1/chat/completions?key=secret',
        'https://api.example.com/v1/chat/completions#fragment',
        'https://user:secret@api.example.com/v1/chat/completions',
      ];

      for (final endpoint in invalid) {
        expect(
          AiSettingsController.isValidOpenAiCompatibleEndpoint(endpoint),
          isFalse,
          reason: endpoint,
        );
      }
    });
  });
}

ApplePccApi _pccApi({required bool available}) => ApplePccApi(
  invokeMethod: (_, _) async => {
    'sdkAvailable': available,
    'available': available,
    'reason': available ? '' : 'unsupported',
    'contextSize': available ? 32768 : 0,
    'quotaLimitReached': false,
    'quotaApproachingLimit': false,
  },
);
