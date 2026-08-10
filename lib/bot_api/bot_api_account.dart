import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Non-secret metadata for one Telegram Bot API account.
///
/// Tokens deliberately live in secure storage. The endpoint never contains a
/// token, query, fragment, or embedded credentials, which keeps preference
/// exports and diagnostics safe to inspect.
class BotApiAccount {
  const BotApiAccount({
    required this.slot,
    required this.endpoint,
    required this.bot,
  });

  final int slot;
  final Uri endpoint;
  final Map<String, dynamic> bot;

  BotApiAccount copyWith({Uri? endpoint, Map<String, dynamic>? bot}) =>
      BotApiAccount(
        slot: slot,
        endpoint: endpoint ?? this.endpoint,
        bot: bot ?? this.bot,
      );

  int get botId => _int(bot['id']) ?? 0;
  String get username => (bot['username'] as String?)?.trim() ?? '';
  String get displayName {
    final first = (bot['first_name'] as String?)?.trim() ?? '';
    final last = (bot['last_name'] as String?)?.trim() ?? '';
    final full = [first, last].where((part) => part.isNotEmpty).join(' ');
    return full.isNotEmpty ? full : username;
  }

  Map<String, dynamic> toJson() => {
    'slot': slot,
    'endpoint': endpoint.toString(),
    'bot': bot,
  };

  static BotApiAccount? fromJson(Object? value) {
    if (value is! Map) return null;
    final map = Map<String, dynamic>.from(value);
    final slot = _int(map['slot']);
    final endpointValue = map['endpoint'];
    final botValue = map['bot'];
    if (slot == null || endpointValue is! String || botValue is! Map) {
      return null;
    }
    try {
      return BotApiAccount(
        slot: slot,
        endpoint: normalizeBotApiEndpoint(endpointValue),
        bot: Map<String, dynamic>.from(botValue),
      );
    } on FormatException {
      return null;
    }
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

/// A secret-safe failure while persisting a Bot API credential.
class BotApiCredentialStoreException implements Exception {
  const BotApiCredentialStoreException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Validates and canonicalizes a Bot API server root.
///
/// Public servers must use HTTPS. Plain HTTP is accepted for loopback and
/// private-network local Bot API servers, which are common for self-hosted
/// Telegram Bot API deployments.
Uri normalizeBotApiEndpoint(String value) {
  final input = value.trim();
  if (input.isEmpty) {
    throw const FormatException('The Bot API endpoint is required.');
  }
  final parsed = Uri.tryParse(input);
  if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
    throw const FormatException('The Bot API endpoint is not a valid URL.');
  }
  final scheme = parsed.scheme.toLowerCase();
  if (scheme != 'https' && scheme != 'http') {
    throw const FormatException('The Bot API endpoint must use HTTP or HTTPS.');
  }
  if (parsed.userInfo.isNotEmpty) {
    throw const FormatException(
      'Credentials must not be embedded in the Bot API endpoint.',
    );
  }
  if (parsed.hasQuery || parsed.hasFragment) {
    throw const FormatException(
      'The Bot API endpoint must not contain a query or fragment.',
    );
  }
  if (RegExp(r'/bot\d+:[A-Za-z0-9_-]+(?:/|$)').hasMatch(parsed.path)) {
    throw const FormatException(
      'Enter the Bot API server root without the bot token.',
    );
  }
  if (scheme == 'http' && !_isLocalHost(parsed.host)) {
    throw const FormatException('Public Bot API endpoints must use HTTPS.');
  }
  final normalizedPath = parsed.path == '/'
      ? ''
      : parsed.path.replaceFirst(RegExp(r'/+$'), '');
  return parsed.replace(scheme: scheme, path: normalizedPath);
}

bool _isLocalHost(String host) {
  final value = host.toLowerCase();
  if (value == 'localhost' || value == '::1' || value.endsWith('.local')) {
    return true;
  }
  final parts = value.split('.').map(int.tryParse).toList();
  if (parts.length != 4 || parts.any((part) => part == null)) return false;
  final a = parts[0]!;
  final b = parts[1]!;
  return a == 10 ||
      a == 127 ||
      (a == 169 && b == 254) ||
      (a == 172 && b >= 16 && b <= 31) ||
      (a == 192 && b == 168);
}

String normalizeBotToken(String value) {
  final token = value.trim();
  if (!RegExp(r'^\d+:[A-Za-z0-9_-]{20,}$').hasMatch(token)) {
    throw const FormatException('Enter a valid Telegram bot token.');
  }
  return token;
}

abstract final class BotApiAccountRegistry {
  static const metadataKey = 'mithka.bot_api.accounts.v1';
  static const _tokenPrefix = 'mithka.bot_api.token.';
  static const _appleKeychainService = 'ad.neko.mithka.bot-api';
  static const _secureStorage = FlutterSecureStorage(
    // The signed iOS and macOS targets use the same bundle identifier, so both
    // receive the same team-prefixed default Keychain access group. Leaving
    // groupId unset selects that shared group. Synchronizable stores the token
    // in iCloud Keychain, while macOS's data-protection Keychain avoids the
    // legacy per-signature ACL that can show a login-keychain password dialog.
    iOptions: IOSOptions(
      accountName: _appleKeychainService,
      synchronizable: true,
    ),
    mOptions: MacOsOptions(
      accountName: _appleKeychainService,
      synchronizable: true,
    ),
  );

  static List<BotApiAccount> load(SharedPreferences preferences) {
    final values = preferences.getStringList(metadataKey) ?? const [];
    final accounts = <BotApiAccount>[];
    for (final value in values) {
      try {
        final account = BotApiAccount.fromJson(jsonDecode(value));
        if (account != null) accounts.add(account);
      } on FormatException {
        // Keep startup resilient to one malformed preference entry.
      }
    }
    accounts.sort((a, b) => a.slot.compareTo(b.slot));
    return accounts;
  }

  static Future<void> replaceMetadata(
    SharedPreferences preferences,
    Iterable<BotApiAccount> accounts,
  ) => preferences.setStringList(metadataKey, [
    for (final account in accounts) jsonEncode(account.toJson()),
  ]);

  static Future<void> save(
    SharedPreferences preferences,
    BotApiAccount account,
    String token,
  ) async {
    final normalizedToken = normalizeBotToken(token);
    await _writeToken(account.slot, normalizedToken);
    final accounts = load(preferences)
      ..removeWhere((existing) => existing.slot == account.slot)
      ..add(account);
    accounts.sort((a, b) => a.slot.compareTo(b.slot));
    await preferences.setStringList(
      metadataKey,
      accounts.map((value) => jsonEncode(value.toJson())).toList(),
    );
  }

  static Future<String?> readToken(int slot) async {
    try {
      final value = await _secureStorage.read(key: '$_tokenPrefix$slot');
      final token = value?.trim() ?? '';
      return token.isEmpty ? null : token;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      // A locked or temporarily unavailable platform credential store must not
      // prevent the rest of the app's accounts from starting.
      return null;
    }
  }

  static Future<void> remove(SharedPreferences preferences, int slot) async {
    final accounts = load(preferences)
      ..removeWhere((account) => account.slot == slot);
    await preferences.setStringList(
      metadataKey,
      accounts.map((value) => jsonEncode(value.toJson())).toList(),
    );
    try {
      await _secureStorage.delete(key: '$_tokenPrefix$slot');
    } on MissingPluginException {
      // Tests and secondary engines can run without the storage plugin.
    } on PlatformException {
      // Metadata is already removed; a later platform cleanup can discard an
      // inaccessible orphan without exposing its value.
    }
  }

  static Future<void> _writeToken(int slot, String token) async {
    try {
      await _secureStorage.write(key: '$_tokenPrefix$slot', value: token);
    } on MissingPluginException {
      throw const BotApiCredentialStoreException(
        'Mithka could not save the bot token securely on this device.',
      );
    } on PlatformException {
      throw const BotApiCredentialStoreException(
        'Mithka could not save the bot token securely on this device.',
      );
    }
  }
}
