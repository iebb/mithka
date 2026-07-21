import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mithka/settings/ai_settings_controller.dart';
import 'package:mithka/settings/apple_pcc_api.dart';
import 'package:mithka/settings/openai_compatible_models_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AiSettingsController', () {
    test('hosted models default to a 200K context window', () {
      expect(AiServerProfile.defaultContextWindowTokens, 200000);
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
        final profile = await controller.saveServerProfile(
          name: 'Example AI',
          endpoint: ' https://ai.example.com/v1/chat/completions ',
          model: ' example-model ',
          apiKey: ' $secret ',
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
        expect(controller.activeServerProfile?.name, 'Example AI');
        expect(controller.activeServerProfile?.contextWindowTokens, 131072);
        expect(controller.activeServerProfile?.contextWindowDetected, isTrue);
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
        expect(restored.activeServerProfile?.contextWindowDetected, isTrue);
        expect(restored.isConfiguredForCurrentProvider, isTrue);

        await controller.deleteServerProfile(profile.id);
        expect(controller.serverProfiles, isEmpty);
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

        final first = await controller.saveServerProfile(
          name: 'First',
          endpoint: 'https://first.example/v1/chat/completions',
          model: 'first-model',
          apiKey: 'first-key',
          contextWindowTokens: 32768,
        );
        final second = await controller.saveServerProfile(
          name: 'Second',
          endpoint: 'https://second.example/v1/chat/completions',
          model: 'second-model',
          apiKey: 'second-key',
          contextWindowTokens: 2097152,
        );

        expect(controller.serverProfiles, hasLength(2));
        expect(controller.activeServerProfileId, second.id);
        expect(controller.activeServerProfile?.contextWindowTokens, 2097152);
        expect(controller.apiKey, 'second-key');
        await controller.selectServerProfile(first.id);
        expect(controller.model, 'first-model');
        expect(controller.apiKey, 'first-key');
        await controller.deleteServerProfile(first.id);
        expect(controller.activeServerProfileId, second.id);
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

        expect(controller.serverProfiles, hasLength(1));
        expect(controller.activeServerProfile?.id, 'legacy');
        expect(
          controller.activeServerProfile?.contextWindowTokens,
          AiServerProfile.defaultContextWindowTokens,
        );
        expect(controller.apiKey, secret);
        expect(
          secureValues,
          isNot(contains(AiSettingsController.apiKeyStorageKey)),
        );
        expect(secureValues.values, contains(secret));
        expect(
          preferences.getString(
            AiSettingsController.serverProfilesPreferenceKey,
          ),
          isNot(contains(secret)),
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
  });

  group('OpenAI-compatible endpoint validation', () {
    test('accepts HTTPS and HTTP loopback chat-completions URLs', () {
      const valid = [
        'https://api.openai.com/v1/chat/completions',
        'https://ai.example.com:8443/v1/chat/completions',
        'https://ai.example.com/custom/v1/chat/completions',
        'http://localhost:11434/v1/chat/completions',
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
