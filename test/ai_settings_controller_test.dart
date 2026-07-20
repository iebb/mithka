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
        await controller.setEndpoint(
          ' https://ai.example.com/v1/chat/completions ',
        );
        await controller.setModel(' example-model ');
        await controller.setApiKey(' $secret ');

        expect(controller.enabled, isTrue);
        expect(controller.provider, AiProviderMode.openAiCompatible);
        expect(
          controller.endpoint,
          'https://ai.example.com/v1/chat/completions',
        );
        expect(controller.model, 'example-model');
        expect(controller.apiKey, secret);
        expect(controller.isConfiguredForCurrentProvider, isTrue);
        expect(secureValues[AiSettingsController.apiKeyStorageKey], secret);
        expect(preferences.getKeys(), isNot(contains(secret)));
        for (final key in preferences.getKeys()) {
          expect(preferences.get(key), isNot(secret));
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
        expect(restored.isConfiguredForCurrentProvider, isTrue);

        await controller.setApiKey('');
        expect(controller.apiKey, isEmpty);
        expect(secureValues, isEmpty);
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
