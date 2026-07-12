import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract final class RichMessageRelayConfig {
  static const _tokenKey = 'mithka.rich_message_relay.bot_token';
  static const _storage = FlutterSecureStorage();

  static Future<String?> readToken() async {
    final token = (await _storage.read(key: _tokenKey))?.trim();
    return token == null || token.isEmpty ? null : token;
  }

  static Future<bool> isConfigured() async => await readToken() != null;

  static Future<void> saveToken(String token) async {
    final value = token.trim();
    if (value.isEmpty) {
      await clear();
      return;
    }
    await _storage.write(key: _tokenKey, value: value);
  }

  static Future<void> clear() => _storage.delete(key: _tokenKey);
}
