import 'package:shared_preferences/shared_preferences.dart';

class ApiCredentialsConfig {
  const ApiCredentialsConfig({
    required this.configured,
    required this.enabled,
    required this.apiId,
    required this.apiHash,
  });

  final bool configured;
  final bool enabled;
  final int apiId;
  final String apiHash;

  static const _enabledKey = 'mithka.api_credentials.enabled';
  static const _apiIdKey = 'mithka.api_credentials.api_id';
  static const _apiHashKey = 'mithka.api_credentials.api_hash';

  bool get isUsable => enabled && apiId > 0 && apiHash.trim().isNotEmpty;

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
  }

  static Future<void> disable() async {
    final current = await load();
    await save(
      ApiCredentialsConfig(
        configured: true,
        enabled: false,
        apiId: current.apiId,
        apiHash: current.apiHash,
      ),
    );
  }
}
