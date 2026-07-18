import 'package:shared_preferences/shared_preferences.dart';

class TransferBoostConfig {
  const TransferBoostConfig({
    this.downloadEnabled = true,
    this.downloadChunkSizeBytes = defaultDownloadChunkSizeBytes,
    this.downloadParallelism = defaultDownloadParallelism,
    this.uploadEnabled = false,
    this.uploadChunkSizeBytes = defaultUploadChunkSizeBytes,
    this.uploadParallelism = defaultUploadParallelism,
  });

  static const kibibyte = 1024;
  static const mebibyte = 1024 * 1024;

  // Telegram download requests are limited to 1 MiB and upload parts to
  // 512 KiB. Keep these values aligned with the protocol instead of exposing
  // choices that TDLib would reject at runtime.
  static const downloadChunkSizesBytes = <int>[
    128 * kibibyte,
    256 * kibibyte,
    512 * kibibyte,
    mebibyte,
  ];
  static const uploadChunkSizesBytes = <int>[
    64 * kibibyte,
    128 * kibibyte,
    256 * kibibyte,
    512 * kibibyte,
  ];

  static const defaultDownloadChunkSizeBytes = mebibyte;
  static const defaultDownloadParallelism = 12;
  static const defaultUploadChunkSizeBytes = 512 * kibibyte;
  static const defaultUploadParallelism = 24;
  static const minParallelism = 1;
  static const maxParallelism = 24;

  static const _legacyDownloadKey = 'mithka.transfer_boost.download';
  static const _downloadEnabledKey = 'mithka.transfer_boost.download_enabled';
  static const _downloadChunkSizeKey =
      'mithka.transfer_boost.download_chunk_size';
  static const _downloadParallelismKey =
      'mithka.transfer_boost.download_parallelism';
  static const _uploadEnabledKey = 'mithka.transfer_boost.upload';
  static const _uploadChunkSizeKey = 'mithka.transfer_boost.upload_chunk_size';
  static const _uploadParallelismKey =
      'mithka.transfer_boost.upload_parallelism';

  final bool downloadEnabled;
  final int downloadChunkSizeBytes;
  final int downloadParallelism;
  final bool uploadEnabled;
  final int uploadChunkSizeBytes;
  final int uploadParallelism;

  bool get enabled => downloadEnabled || uploadEnabled;

  TransferBoostConfig copyWith({
    bool? downloadEnabled,
    int? downloadChunkSizeBytes,
    int? downloadParallelism,
    bool? uploadEnabled,
    int? uploadChunkSizeBytes,
    int? uploadParallelism,
  }) => TransferBoostConfig(
    downloadEnabled: downloadEnabled ?? this.downloadEnabled,
    downloadChunkSizeBytes:
        downloadChunkSizeBytes ?? this.downloadChunkSizeBytes,
    downloadParallelism: downloadParallelism ?? this.downloadParallelism,
    uploadEnabled: uploadEnabled ?? this.uploadEnabled,
    uploadChunkSizeBytes: uploadChunkSizeBytes ?? this.uploadChunkSizeBytes,
    uploadParallelism: uploadParallelism ?? this.uploadParallelism,
  );

  static TransferBoostConfig fromPrefs(SharedPreferences prefs) {
    final hasExplicitDownloadSetting = prefs.containsKey(_downloadEnabledKey);
    final legacyDownloadLevel = prefs.getString(_legacyDownloadKey);
    final migratedDownloadEnabled =
        legacyDownloadLevel == null ||
        legacyDownloadLevel == 'medium' ||
        legacyDownloadLevel == 'maximum';
    final migratedDownloadChunkSize = legacyDownloadLevel == 'medium'
        ? 512 * kibibyte
        : defaultDownloadChunkSizeBytes;
    final migratedDownloadParallelism = legacyDownloadLevel == 'medium'
        ? 8
        : defaultDownloadParallelism;

    return TransferBoostConfig(
      downloadEnabled: hasExplicitDownloadSetting
          ? prefs.getBool(_downloadEnabledKey) ?? false
          : migratedDownloadEnabled,
      downloadChunkSizeBytes: _validChunkSize(
        prefs.getInt(_downloadChunkSizeKey) ?? migratedDownloadChunkSize,
        downloadChunkSizesBytes,
        defaultDownloadChunkSizeBytes,
      ),
      downloadParallelism: _validParallelism(
        prefs.getInt(_downloadParallelismKey) ?? migratedDownloadParallelism,
        defaultDownloadParallelism,
      ),
      uploadEnabled: prefs.getBool(_uploadEnabledKey) ?? false,
      uploadChunkSizeBytes: _validChunkSize(
        prefs.getInt(_uploadChunkSizeKey) ?? defaultUploadChunkSizeBytes,
        uploadChunkSizesBytes,
        defaultUploadChunkSizeBytes,
      ),
      uploadParallelism: _validParallelism(
        prefs.getInt(_uploadParallelismKey) ?? defaultUploadParallelism,
        defaultUploadParallelism,
      ),
    );
  }

  static int _validChunkSize(int value, List<int> validValues, int fallback) =>
      validValues.contains(value) ? value : fallback;

  static int _validParallelism(int value, int fallback) =>
      value >= minParallelism && value <= maxParallelism ? value : fallback;

  static Future<TransferBoostConfig> load() async =>
      fromPrefs(await SharedPreferences.getInstance());

  static Future<void> save(TransferBoostConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_downloadEnabledKey, config.downloadEnabled);
    await prefs.setInt(
      _downloadChunkSizeKey,
      _validChunkSize(
        config.downloadChunkSizeBytes,
        downloadChunkSizesBytes,
        defaultDownloadChunkSizeBytes,
      ),
    );
    await prefs.setInt(
      _downloadParallelismKey,
      _validParallelism(config.downloadParallelism, defaultDownloadParallelism),
    );
    await prefs.setBool(_uploadEnabledKey, config.uploadEnabled);
    await prefs.setInt(
      _uploadChunkSizeKey,
      _validChunkSize(
        config.uploadChunkSizeBytes,
        uploadChunkSizesBytes,
        defaultUploadChunkSizeBytes,
      ),
    );
    await prefs.setInt(
      _uploadParallelismKey,
      _validParallelism(config.uploadParallelism, defaultUploadParallelism),
    );
  }
}
