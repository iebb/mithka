import 'package:shared_preferences/shared_preferences.dart';

import 'bot_api_account.dart';

/// The process-wide Telegram Bot API server root used by every bot account.
///
/// Tokens remain account-scoped, but mixing server roots inside one client is
/// surprising and makes media/profile requests easy to route incorrectly. The
/// selected root is therefore stored once and applied to every restored bot.
abstract final class BotApiEndpointConfig {
  static const preferenceKey = 'mithka.bot_api.endpoint.v1';
  static final Uri defaultEndpoint = Uri.parse('https://api.telegram.org');

  static Uri load(SharedPreferences preferences, {Uri? legacyFallback}) {
    final stored = preferences.getString(preferenceKey);
    if (stored != null) {
      try {
        return normalizeBotApiEndpoint(stored);
      } on FormatException {
        // Fall through to a valid legacy/default value.
      }
    }
    return legacyFallback ?? defaultEndpoint;
  }

  static Future<Uri> save(
    SharedPreferences preferences,
    String endpoint,
  ) async {
    final normalized = normalizeBotApiEndpoint(endpoint);
    await preferences.setString(preferenceKey, normalized.toString());
    return normalized;
  }
}
