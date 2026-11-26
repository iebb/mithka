import 'package:shared_preferences/shared_preferences.dart';

class ApiCredentialsConfig {
  const ApiCredentialsConfig({
    required this.configured,
    required this.enabled,
    required this.apiId,
    required this.apiHash,
    this.deviceModel = '',
    this.systemVersion = '',
    this.applicationVersion = '',
  });

  final bool configured;
  final bool enabled;
  final int apiId;
  final String apiHash;
  final String deviceModel;
  final String systemVersion;
  final String applicationVersion;

  static const _enabledKey = 'mithka.api_credentials.enabled';
  static const _apiIdKey = 'mithka.api_credentials.api_id';
  static const _apiHashKey = 'mithka.api_credentials.api_hash';
  static const _deviceModelKey = 'mithka.api_credentials.device_model';
  static const _systemVersionKey = 'mithka.api_credentials.system_version';
  static const _applicationVersionKey =
      'mithka.api_credentials.application_version';

  bool get isUsable => enabled && apiId > 0 && apiHash.trim().isNotEmpty;

  bool get hasCustomUserAgent =>
      deviceModel.trim().isNotEmpty ||
      systemVersion.trim().isNotEmpty ||
      applicationVersion.trim().isNotEmpty;

  String resolvedDeviceModel(String fallback) =>
      _resolvedUserAgentValue(deviceModel, fallback);

  String resolvedSystemVersion(String fallback) =>
      _resolvedUserAgentValue(systemVersion, fallback);

  String resolvedApplicationVersion(String fallback) =>
      _resolvedUserAgentValue(applicationVersion, fallback);

  static ApiCredentialsConfig fromPrefs(SharedPreferences prefs) {
    final rawApiId = prefs.get(_apiIdKey);
    final apiId = rawApiId is num
        ? rawApiId.toInt()
        : rawApiId is String
        ? int.tryParse(rawApiId) ?? 0
        : 0;
    return ApiCredentialsConfig(
      configured: prefs.containsKey(_enabledKey),
      enabled: prefs.getBool(_enabledKey) ?? false,
      apiId: apiId,
      apiHash: prefs.getString(_apiHashKey) ?? '',
      deviceModel: prefs.getString(_deviceModelKey) ?? '',
      systemVersion: prefs.getString(_systemVersionKey) ?? '',
      applicationVersion: prefs.getString(_applicationVersionKey) ?? '',
    );
  }

  static Future<ApiCredentialsConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    return fromPrefs(prefs);
  }

  static Future<void> save(ApiCredentialsConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, config.enabled);
    await prefs.setString(_apiIdKey, config.apiId > 0 ? '${config.apiId}' : '');
    await prefs.setString(_apiHashKey, config.apiHash.trim());
    await prefs.setString(_deviceModelKey, config.deviceModel.trim());
    await prefs.setString(_systemVersionKey, config.systemVersion.trim());
    await prefs.setString(
      _applicationVersionKey,
      config.applicationVersion.trim(),
    );
  }

  static Future<void> disable() async {
    final current = await load();
    await save(
      ApiCredentialsConfig(
        configured: true,
        enabled: false,
        apiId: current.apiId,
        apiHash: current.apiHash,
        deviceModel: current.deviceModel,
        systemVersion: current.systemVersion,
        applicationVersion: current.applicationVersion,
      ),
    );
  }

  static String _resolvedUserAgentValue(String value, String fallback) {
    final normalized = value.trim();
    return normalized.isEmpty ? fallback : normalized;
  }
}
