import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mithka/settings/ai_endpoint_style.dart';
import 'package:mithka/settings/ai_settings_controller.dart';
import 'package:mithka/settings/apple_pcc_api.dart';
import 'package:mithka/settings/openai_compatible_models_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AiSettingsController', () {
    test('hosted models default to a 200K context window', () {
      expect(AiModelProfile.defaultContextWindowTokens, 200000);
    });

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
      expect(controller.endpoint, isEmpty);
      expect(controller.model, isEmpty);
      expect(controller.apiKey, isEmpty);
      expect(controller.pccCapabilities?.available, isFalse);
      expect(controller.isConfiguredForCurrentProvider, isFalse);
      expect(controller.modelCandidates, hasLength(2));
      expect(
        controller.modelCandidatesForFeature(AiFeature.translation),
        hasLength(2),
      );
      expect(
        controller.modelCandidatesForFeature(AiFeature.summary),
        hasLength(2),
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
      'scopes Telegram Cocoon to replies and persists a reply choice',
      () async {
        SharedPreferences.setMockInitialValues({});
        final preferences = await SharedPreferences.getInstance();
        final controller = AiSettingsController(
          preferences,
          pccApi: _pccApi(available: false),
          secureRead: (_) async => null,
          secureWrite: (_, _) async {},
        );
        await controller.initialize();

        expect(
          controller.modelCandidates
              .where(
                (candidate) =>
                    candidate.kind == AiModelCandidateKind.telegramCocoon,
              )
              .isEmpty,
          isTrue,
        );
        expect(
          controller
              .modelCandidatesForFeature(AiFeature.translation)
              .where(
                (candidate) =>
                    candidate.kind == AiModelCandidateKind.telegramCocoon,
              )
              .isEmpty,
          isTrue,
        );
        expect(
          controller
              .modelCandidatesForFeature(AiFeature.summary)
              .where(
                (candidate) =>
                    candidate.kind == AiModelCandidateKind.telegramCocoon,
              )
              .isEmpty,
          isTrue,
        );
        expect(
          controller.modelCandidatesForFeature(AiFeature.reply).first.kind,
          AiModelCandidateKind.telegramCocoon,
        );

        await controller.setFeatureModelCandidate(
          AiFeature.translation,
          AiSettingsController.telegramCocoonModelCandidateId,
        );
        await controller.setFeatureModelCandidate(
          AiFeature.summary,
          AiSettingsController.telegramCocoonModelCandidateId,
        );
        expect(
          controller.translationModelCandidate.kind,
          AiModelCandidateKind.applePcc,
        );
        expect(
          controller.summaryModelCandidate.kind,
          AiModelCandidateKind.applePcc,
        );

        await controller.setFeatureModelCandidate(
          AiFeature.reply,
          AiSettingsController.appleOnDeviceModelCandidateId,
        );
        expect(
          preferences.getString(
            AiSettingsController.replyModelCandidatePreferenceKey,
          ),
          AiSettingsController.appleOnDeviceModelCandidateId,
        );

        final restored = AiSettingsController(
          preferences,
          pccApi: _pccApi(available: false),
          secureRead: (_) async => null,
          secureWrite: (_, _) async {},
        );
        await restored.initialize();
        expect(
          restored.replyModelCandidate.kind,
          AiModelCandidateKind.appleOnDevice,
        );
      },
    );

    test(
      'persists independent translation and summary model choices',
      () async {
        SharedPreferences.setMockInitialValues({});
        final preferences = await SharedPreferences.getInstance();
        final secureValues = <String, String>{};
        final appleApi = ApplePccApi(
          invokeMethod: (_, _) async => const {
            'sdkAvailable': true,
            'available': true,
            'reason': '',
            'contextSize': 32768,
            'quotaLimitReached': false,
            'onDeviceSdkAvailable': true,
            'onDeviceAvailable': true,
            'onDeviceReason': 'available',
            'onDeviceContextSize': 4096,
          },
        );
        final controller = AiSettingsController(
          preferences,
          pccApi: appleApi,
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
        final provider = await controller.saveServerProvider(
          name: 'Translation Server',
          endpoint: 'https://translate.example/v1/chat/completions',
          apiKey: 'secret',
        );
        final model = await controller.saveModelProfile(
          providerId: provider.id,
          model: 'translate-model',
          contextWindowTokens: 65536,
        );
        final serverCandidateId = AiSettingsController.serverModelCandidateId(
          model.id,
        );

        await controller.setFeatureModelCandidate(
          AiFeature.translation,
          serverCandidateId,
        );
        await controller.setFeatureModelCandidate(
          AiFeature.summary,
          AiSettingsController.appleOnDeviceModelCandidateId,
        );

        final translation = controller.configurationForFeature(
          AiFeature.translation,
        );
        final summary = controller.configurationForFeature(AiFeature.summary);
        expect(controller.modelCandidates, hasLength(3));
        expect(translation.providerMode, AiProviderMode.openAiCompatible);
        expect(translation.model, 'translate-model');
        expect(translation.apiKey, 'secret');
        expect(summary.providerMode, AiProviderMode.appleOnDevice);
        expect(summary.contextWindowTokens, 4096);
        expect(
          controller.isConfiguredForFeature(AiFeature.translation),
          isTrue,
        );
        expect(controller.isConfiguredForFeature(AiFeature.summary), isTrue);

        final restored = AiSettingsController(
          preferences,
          pccApi: appleApi,
          secureRead: (key) async => secureValues[key],
          secureWrite: (_, _) async {},
        );
        await restored.initialize();
        expect(restored.translationModelCandidate.id, serverCandidateId);
        expect(
          restored.summaryModelCandidate.id,
          AiSettingsController.appleOnDeviceModelCandidateId,
        );

        await controller.deleteModelProfile(model.id);
        expect(
          controller.translationModelCandidate.id,
          AiSettingsController.applePccModelCandidateId,
        );
        expect(
          controller.summaryModelCandidate.id,
          AiSettingsController.appleOnDeviceModelCandidateId,
        );
      },
    );

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
      'stores, selects, and deletes multiple endpoint-key profiles',
      () async {
        SharedPreferences.setMockInitialValues({});
        final secureValues = <String, String>{};
        final controller = AiSettingsController(
          await SharedPreferences.getInstance(),
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

        final first = await controller.saveServerProvider(
          name: 'First',
          endpoint: 'https://first.example/v1/chat/completions',
          apiKey: 'first-key',
        );
        await controller.saveModelProfile(
          providerId: first.id,
          model: 'first-model',
          contextWindowTokens: 32768,
        );
        final second = await controller.saveServerProvider(
          name: 'Second',
          endpoint: 'https://second.example/v1/chat/completions',
          apiKey: 'second-key',
        );
        await controller.saveModelProfile(
          providerId: second.id,
          model: 'second-model',
          contextWindowTokens: 2097152,
        );

        expect(controller.serverProviders, hasLength(2));
        expect(controller.modelProfiles, hasLength(2));
        expect(controller.activeServerProviderId, second.id);
        expect(controller.activeModelProfile?.contextWindowTokens, 2097152);
        expect(controller.apiKey, 'second-key');
        await controller.selectServerProvider(first.id);
        expect(controller.model, 'first-model');
        expect(controller.apiKey, 'first-key');
        await controller.deleteServerProvider(first.id);
        expect(controller.activeServerProviderId, second.id);
        expect(controller.modelProfiles, hasLength(1));
        expect(controller.apiKey, 'second-key');
        expect(secureValues.values, isNot(contains('first-key')));
      },
    );

    test('server configuration does not require an API key', () async {
      SharedPreferences.setMockInitialValues({
        AiSettingsController.providerPreferenceKey: 'open_ai_compatible',
        AiSettingsController.endpointPreferenceKey:
            'http://127.0.0.1:11434/v1/chat/completions',
        AiSettingsController.modelPreferenceKey: 'local-model',
      });
      final controller = AiSettingsController(
        await SharedPreferences.getInstance(),
        pccApi: _pccApi(available: false),
        secureRead: (_) async => null,
        secureWrite: (_, _) async {},
      );

      await controller.initialize();

      expect(controller.apiKey, isEmpty);
      expect(controller.isConfiguredForCurrentProvider, isTrue);
    });

    test('model discovery enriches the selected model context', () async {
      SharedPreferences.setMockInitialValues({});
      final modelsApi = OpenAiCompatibleModelsApi(
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/v1/models')) {
            return http.Response(
              '{"data":[{"id":"first"},{"id":"selected"}]}',
              200,
            );
          }
          expect(request.url.pathSegments.last, 'selected');
          return http.Response(
            '{"id":"selected","max_input_tokens":262144}',
            200,
          );
        }),
      );
      final controller = AiSettingsController(
        await SharedPreferences.getInstance(),
        pccApi: _pccApi(available: false),
        modelsApi: modelsApi,
        secureRead: (_) async => null,
        secureWrite: (_, _) async {},
      );
      await controller.initialize();

      final models = await controller.discoverModels(
        endpoint: 'https://ai.example/v1/chat/completions',
        apiKey: 'secret',
        preferredModel: 'selected',
      );

      expect(models.first.contextWindowTokens, isNull);
      expect(models.last.id, 'selected');
      expect(models.last.contextWindowTokens, 262144);
    });

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

    test(
      'splits combined provider profiles into provider and model records',
      () async {
        SharedPreferences.setMockInitialValues({
          AiSettingsController.serverProfilesPreferenceKey: jsonEncode([
            {
              'id': 'old-provider',
              'name': 'Existing Server',
              'endpoint': 'https://existing.example/v1/chat/completions',
              'model': 'existing-model',
              'context_window_tokens': 65536,
              'context_window_detected': true,
              'available_models': [
                {'id': 'existing-model', 'context_window_tokens': 65536},
              ],
            },
          ]),
          AiSettingsController.activeServerProfileIdPreferenceKey:
              'old-provider',
        });
        final preferences = await SharedPreferences.getInstance();
        final controller = AiSettingsController(
          preferences,
          pccApi: _pccApi(available: false),
          secureRead: (key) async =>
              key.contains('old-provider') ? 'existing-secret' : null,
          secureWrite: (_, _) async {},
        );

        await controller.initialize();

        expect(controller.serverProviders, hasLength(1));
        expect(controller.modelProfiles, hasLength(1));
        expect(controller.activeServerProvider?.name, 'Existing Server');
        expect(controller.activeModelProfile?.model, 'existing-model');
        expect(controller.activeModelProfile?.contextWindowTokens, 65536);
        expect(controller.activeModelProfile?.contextWindowDetected, isTrue);
        expect(controller.apiKey, 'existing-secret');
        final storedProviders =
            jsonDecode(
                  preferences.getString(
                    AiSettingsController.serverProvidersPreferenceKey,
                  )!,
                )
                as List;
        expect((storedProviders.single as Map).containsKey('model'), isFalse);
        expect(
          preferences.getString(
            AiSettingsController.modelProfilesPreferenceKey,
          ),
          contains('existing-model'),
        );
      },
    );

    test('on-device configuration uses its independent availability', () async {
      SharedPreferences.setMockInitialValues({
        AiSettingsController.providerPreferenceKey: 'apple_on_device',
      });
      final controller = AiSettingsController(
        await SharedPreferences.getInstance(),
        pccApi: ApplePccApi(
          invokeMethod: (_, _) async => const {
            'sdkAvailable': true,
            'available': false,
            'reason': 'requires_ios_27',
            'contextSize': 0,
            'onDeviceSdkAvailable': true,
            'onDeviceAvailable': true,
            'onDeviceReason': 'available',
            'onDeviceContextSize': 4096,
          },
        ),
        secureRead: (_) async => null,
        secureWrite: (_, _) async {},
      );

      await controller.initialize();

      expect(controller.provider, AiProviderMode.appleOnDevice);
      expect(controller.pccCapabilities?.onDeviceContextSize, 4096);
      expect(controller.isConfiguredForCurrentProvider, isTrue);
      expect(
        controller.translationModelCandidate.kind,
        AiModelCandidateKind.appleOnDevice,
      );
      expect(
        controller.summaryModelCandidate.kind,
        AiModelCandidateKind.appleOnDevice,
      );
    });

    test(
      'PCC configuration follows refreshed availability and quota',
      () async {
        var response = <String, Object>{
          'sdkAvailable': true,
          'available': false,
          'reason': 'temporarily_unavailable',
          'contextSize': 32768,
          'quotaLimitReached': false,
          'quotaApproachingLimit': false,
        };
        final api = ApplePccApi(invokeMethod: (_, _) async => response);
        SharedPreferences.setMockInitialValues({});
        final controller = AiSettingsController(
          await SharedPreferences.getInstance(),
          pccApi: api,
          secureRead: (_) async => null,
          secureWrite: (_, _) async {},
        );
        await controller.initialize();
        expect(controller.isConfiguredForCurrentProvider, isFalse);

        response = {
          'sdkAvailable': true,
          'available': true,
          'reason': '',
          'contextSize': 32768,
          'quotaLimitReached': false,
          'quotaApproachingLimit': true,
        };
        await controller.refreshPccCapabilities();

        expect(controller.pccCapabilities?.contextSize, 32768);
        expect(controller.pccCapabilities?.quotaApproachingLimit, isTrue);
        expect(controller.isConfiguredForCurrentProvider, isTrue);
      },
    );

    test('invalid persisted endpoint is discarded', () async {
      SharedPreferences.setMockInitialValues({
        AiSettingsController.providerPreferenceKey: 'open_ai_compatible',
        AiSettingsController.endpointPreferenceKey:
            'http://example.com/v1/chat/completions',
        AiSettingsController.modelPreferenceKey: 'model',
      });
      final controller = AiSettingsController(
        await SharedPreferences.getInstance(),
        pccApi: _pccApi(available: false),
        secureRead: (_) async => null,
        secureWrite: (_, _) async {},
      );

      await controller.initialize();

      expect(controller.endpoint, isEmpty);
      expect(controller.isConfiguredForCurrentProvider, isFalse);
    });

    test('persists and restores the selected hosted API style', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final controller = AiSettingsController(
        preferences,
        pccApi: _pccApi(available: false),
        secureRead: (_) async => null,
        secureWrite: (_, _) async {},
      );
      await controller.initialize();

      final provider = await controller.saveServerProvider(
        name: 'Responses Provider',
        endpoint: 'https://api.example/v1/responses',
        endpointStyle: AiEndpointStyle.openAiResponses,
        apiKey: '',
      );
      final model = await controller.saveModelProfile(
        providerId: provider.id,
        model: 'response-model',
        contextWindowTokens: 128000,
      );
      await controller.setFeatureModelCandidate(
        AiFeature.summary,
        AiSettingsController.serverModelCandidateId(model.id),
      );

      final encoded = preferences.getString(
        AiSettingsController.serverProvidersPreferenceKey,
      );
      expect(encoded, contains('open_ai_responses'));
      final restored = AiSettingsController(
        preferences,
        pccApi: _pccApi(available: false),
        secureRead: (_) async => null,
        secureWrite: (_, _) async {},
      );
      await restored.initialize();

      expect(
        restored.serverProviders.single.endpointStyle,
        AiEndpointStyle.openAiResponses,
      );
      expect(
        restored.configurationForFeature(AiFeature.summary).endpointStyle,
        AiEndpointStyle.openAiResponses,
      );
    });
  });

  group('hosted AI endpoint validation', () {
    test('accepts supported HTTPS styles and HTTP loopback URLs', () {
      const valid = [
        'https://api.openai.com/v1/chat/completions',
        'https://api.openai.com/v1/responses',
        'https://api.anthropic.com/v1/messages',
        'https://ai.example.com:8443/v1/chat/completions',
        'https://ai.example.com/custom/v1/chat/completions',
        'http://localhost:11434/v1/chat/completions',
        'http://localhost:11434/api/chat',
        'http://api.localhost/v1/chat/completions',
        'http://127.0.0.1:8080/v1/chat/completions',
        'http://127.12.3.4/v1/chat/completions',
        'http://[::1]:8080/v1/chat/completions',
      ];

      for (final endpoint in valid) {
        expect(
          AiSettingsController.isValidOpenAiCompatibleEndpoint(endpoint),
          isTrue,
          reason: endpoint,
        );
      }
    });

    test('requires the endpoint to match an explicitly selected style', () {
      expect(
        AiSettingsController.isValidOpenAiCompatibleEndpoint(
          'https://api.example/v1/responses',
          endpointStyle: AiEndpointStyle.openAiResponses,
        ),
        isTrue,
      );
      expect(
        AiSettingsController.isValidOpenAiCompatibleEndpoint(
          'https://api.example/v1/chat/completions',
          endpointStyle: AiEndpointStyle.openAiResponses,
        ),
        isFalse,
      );
    });

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
