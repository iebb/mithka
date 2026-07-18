import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/settings/transfer_boost_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('TransferBoostConfig', () {
    test(
      'defaults download boost on with protocol-safe tuning values',
      () async {
        SharedPreferences.setMockInitialValues({});

        final config = await TransferBoostConfig.load();

        expect(config.downloadEnabled, isTrue);
        expect(
          config.downloadChunkSizeBytes,
          TransferBoostConfig.defaultDownloadChunkSizeBytes,
        );
        expect(
          config.downloadParallelism,
          TransferBoostConfig.defaultDownloadParallelism,
        );
        expect(config.uploadEnabled, isFalse);
        expect(
          config.uploadChunkSizeBytes,
          TransferBoostConfig.defaultUploadChunkSizeBytes,
        );
        expect(
          config.uploadParallelism,
          TransferBoostConfig.defaultUploadParallelism,
        );
        expect(config.enabled, isTrue);
      },
    );

    test('honors an explicit opt-out from download boost', () async {
      SharedPreferences.setMockInitialValues({
        'mithka.transfer_boost.download_enabled': false,
      });

      final config = await TransferBoostConfig.load();

      expect(config.downloadEnabled, isFalse);
      expect(config.enabled, isFalse);
    });

    test('persists independent download and upload tuning', () async {
      SharedPreferences.setMockInitialValues({});
      const expected = TransferBoostConfig(
        downloadChunkSizeBytes: 512 * 1024,
        downloadParallelism: 18,
        uploadEnabled: true,
        uploadChunkSizeBytes: 256 * 1024,
        uploadParallelism: 21,
      );

      await TransferBoostConfig.save(expected);
      final actual = await TransferBoostConfig.load();

      expect(actual.downloadEnabled, isTrue);
      expect(actual.downloadChunkSizeBytes, 512 * 1024);
      expect(actual.downloadParallelism, 18);
      expect(actual.uploadEnabled, isTrue);
      expect(actual.uploadChunkSizeBytes, 256 * 1024);
      expect(actual.uploadParallelism, 21);
      expect(actual.enabled, isTrue);
    });

    test('migrates the previous Swiftgram presets', () async {
      SharedPreferences.setMockInitialValues({
        'mithka.transfer_boost.download': 'medium',
        'mithka.transfer_boost.upload': true,
      });

      final config = TransferBoostConfig.fromPrefs(
        await SharedPreferences.getInstance(),
      );

      expect(config.downloadEnabled, isTrue);
      expect(config.downloadChunkSizeBytes, 512 * 1024);
      expect(config.downloadParallelism, 8);
      expect(config.uploadEnabled, isTrue);
    });

    test('limits settings to Telegram protocol bounds', () {
      expect(TransferBoostConfig.downloadChunkSizesBytes.last, 1024 * 1024);
      expect(TransferBoostConfig.uploadChunkSizesBytes.last, 512 * 1024);
      expect(TransferBoostConfig.maxParallelism, 24);
    });
  });
}
