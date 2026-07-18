import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract final class RichMessageRelayConfig {
  static const _tokenKey = 'mithka.rich_message_relay.bot_token';
  static const _storage = FlutterSecureStorage();

  static Future<String?> readToken() async {
    try {
      final token = (await _storage.read(key: _tokenKey))?.trim();
      return token == null || token.isEmpty ? null : token;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<bool> isConfigured() async => await readToken() != null;

  static Future<void> saveToken(String token) async {
    final value = token.trim();
    if (value.isEmpty) {
      await clear();
      return;
    }
    try {
      await _storage.write(key: _tokenKey, value: value);
    } on MissingPluginException {
      return;
    }
  }

  static Future<void> clear() async {
    try {
      await _storage.delete(key: _tokenKey);
    } on MissingPluginException {
      return;
    }
  }
}
