import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';

class TelegramLoginPasskey {
  const TelegramLoginPasskey({
    required this.id,
    required this.name,
    required this.additionDate,
    required this.lastUsageDate,
    required this.softwareIconCustomEmojiId,
  });

  factory TelegramLoginPasskey.fromJson(Map<String, dynamic> json) =>
      TelegramLoginPasskey(
        id: json.str('id') ?? '',
        name: json.str('name') ?? '',
        additionDate: DateTime.fromMillisecondsSinceEpoch(
          (json.integer('addition_date') ?? 0) * 1000,
        ),
        lastUsageDate: (json.integer('last_usage_date') ?? 0) > 0
            ? DateTime.fromMillisecondsSinceEpoch(
                json.integer('last_usage_date')! * 1000,
              )
            : null,
        softwareIconCustomEmojiId:
            json.int64('software_icon_custom_emoji_id') ?? 0,
      );

  final String id;
  final String name;
  final DateTime additionDate;
  final DateTime? lastUsageDate;
  final int softwareIconCustomEmojiId;
}

class TelegramPasskeyException implements Exception {
  const TelegramPasskeyException(this.code, [this.message]);

  final String code;
  final String? message;

  bool get isCancelled => code == 'passkey_cancelled';

  @override
  String toString() => message == null ? code : '$code: $message';
}

class TelegramPasskeyService {
  TelegramPasskeyService._();

  static final TelegramPasskeyService shared = TelegramPasskeyService._();
  static const MethodChannel _channel = MethodChannel('mithka/passkeys');

  final TdClient _client = TdClient.shared;

  Future<bool> isPlatformSupported() async {
    if (!telegramPasskeyPlatformSupported(
      isAndroid: Platform.isAndroid,
      isIOS: Platform.isIOS,
    )) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> canUse({int? clientId}) async {
    if (!await isPlatformSupported()) return false;
    final id = clientId ?? _client.activeClientId;
    if (id == 0) return false;
    try {
      final option = await _client.queryTo({
        '@type': 'getOption',
        'name': 'can_use_login_passkey',
      }, id);
      return option.type == 'optionValueBoolean' &&
          (option.boolean('value') ?? false);
    } catch (_) {
      return false;
    }
  }

  Future<void> authenticate({required int clientId}) async {
    try {
      final parameters = await _client.queryTo({
        '@type': 'getAuthenticationPasskeyParameters',
      }, clientId);
      final publicKeyJson = telegramPublicKeyJson(parameters.str('text') ?? '');
      final native = await _invoke('get', publicKeyJson);
      final userId = telegramUserIdFromPasskeyResponse(native.responseJson);
      final credential = telegramPasskeyAssertion(
        native.responseJson,
        native.clientDataJson,
      );
      if (userId != null) {
        await _ensureAccountIsNotConfigured(userId, clientId);
      }
      await _client.queryTo({
        '@type': 'checkAuthenticationPasskey',
        ...credential,
      }, clientId);
    } on PlatformException catch (error) {
      throw TelegramPasskeyException(error.code, error.message);
    } on MissingPluginException catch (error) {
      throw TelegramPasskeyException('passkey_unavailable', error.message);
    }
  }

  Future<TelegramLoginPasskey> create({int? clientId}) async {
    final id = clientId ?? _client.activeClientId;
    try {
      final parameters = await _client.queryTo({
        '@type': 'getPasskeyParameters',
      }, id);
      final publicKeyJson = telegramPublicKeyJson(parameters.str('text') ?? '');
      final native = await _invoke('create', publicKeyJson);
      final response = _jsonObject(native.responseJson, 'credential response');
      final responseObject = response['response'];
      if (responseObject is! Map<String, dynamic>) {
        throw const TelegramPasskeyException(
          'passkey_invalid',
          'Missing registration response',
        );
      }
      final attestation = responseObject['attestationObject'];
      if (attestation is! String || attestation.isEmpty) {
        throw const TelegramPasskeyException(
          'passkey_invalid',
          'Missing passkey attestation',
        );
      }
      final added = await _client.queryTo({
        '@type': 'addLoginPasskey',
        'client_data': native.clientDataJson,
        'attestation_object': tdlibBase64FromBase64Url(attestation),
      }, id);
      return TelegramLoginPasskey.fromJson(added);
    } on PlatformException catch (error) {
      throw TelegramPasskeyException(error.code, error.message);
    } on MissingPluginException catch (error) {
      throw TelegramPasskeyException('passkey_unavailable', error.message);
    }
  }

  Future<List<TelegramLoginPasskey>> list({int? clientId}) async {
    final id = clientId ?? _client.activeClientId;
    final response = await _client.queryTo({'@type': 'getLoginPasskeys'}, id);
    final values = response['passkeys'];
    if (values is! List) return const [];
    return values
        .whereType<Map<String, dynamic>>()
        .map(TelegramLoginPasskey.fromJson)
        .where((passkey) => passkey.id.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> remove(String passkeyId, {int? clientId}) => _client.queryTo({
    '@type': 'removeLoginPasskey',
    'passkey_id': passkeyId,
  }, clientId ?? _client.activeClientId);

  Future<void> openCredentialSettings() async {
    try {
      await _channel.invokeMethod<void>('openSettings');
    } on PlatformException catch (error) {
      throw TelegramPasskeyException(error.code, error.message);
    } on MissingPluginException catch (error) {
      throw TelegramPasskeyException('passkey_unavailable', error.message);
    }
  }

  Future<_NativePasskeyResponse> _invoke(
    String method,
    String publicKeyJson,
  ) async {
    final response = await _channel.invokeMapMethod<String, dynamic>(method, {
      'publicKeyJson': publicKeyJson,
    });
    final responseJson = response?['responseJson'];
    final clientDataJson = response?['clientDataJson'];
    if (responseJson is! String || clientDataJson is! String) {
      throw const TelegramPasskeyException(
        'passkey_invalid',
        'Credential provider returned an invalid response',
      );
    }
    return _NativePasskeyResponse(responseJson, clientDataJson);
  }

  Future<void> _ensureAccountIsNotConfigured(
    int userId,
    int targetClientId,
  ) async {
    for (final slot in _client.configuredSlots) {
      final clientId = _client.clientId(slot);
      if (clientId == null || clientId == targetClientId) continue;
      try {
        final state = await _client
            .queryTo({'@type': 'getAuthorizationState'}, clientId)
            .timeout(const Duration(seconds: 2));
        if (state.type != 'authorizationStateReady') continue;
        final me = await _client
            .queryTo({'@type': 'getMe'}, clientId)
            .timeout(const Duration(seconds: 2));
        if (me.int64('id') == userId) {
          throw const TelegramPasskeyException('passkey_already_signed_in');
        }
      } on TelegramPasskeyException {
        rethrow;
      } catch (_) {
        // A stale secondary slot must not block login to the active slot.
      }
    }
  }
}

@visibleForTesting
bool telegramPasskeyPlatformSupported({
  required bool isAndroid,
  required bool isIOS,
}) {
  if (isIOS) return false;
  return isAndroid;
}

class _NativePasskeyResponse {
  const _NativePasskeyResponse(this.responseJson, this.clientDataJson);

  final String responseJson;
  final String clientDataJson;
}

@visibleForTesting
String telegramPublicKeyJson(String serializedParameters) {
  final parameters = _jsonObject(serializedParameters, 'passkey parameters');
  final publicKey = parameters['publicKey'];
  if (publicKey is! Map<String, dynamic>) {
    throw const TelegramPasskeyException(
      'passkey_invalid',
      'Missing public-key parameters',
    );
  }
  return jsonEncode(publicKey);
}

@visibleForTesting
String tdlibBase64FromBase64Url(String value) {
  try {
    return base64.encode(base64Url.decode(base64Url.normalize(value)));
  } on FormatException catch (error) {
    throw TelegramPasskeyException('passkey_invalid', error.message);
  }
}

@visibleForTesting
int? telegramUserIdFromPasskeyUserHandle(String value) {
  if (value.isEmpty) return null;
  try {
    final decoded = utf8.decode(base64Url.decode(base64Url.normalize(value)));
    final match = RegExp(r'^\d+:(\d+)$').firstMatch(decoded);
    return match == null ? null : int.tryParse(match.group(1)!);
  } catch (_) {
    return null;
  }
}

@visibleForTesting
int? telegramUserIdFromPasskeyResponse(String responseJson) {
  final credential = _jsonObject(responseJson, 'credential response');
  final response = credential['response'];
  if (response is! Map<String, dynamic>) return null;
  final userHandle = response['userHandle'];
  return userHandle is String
      ? telegramUserIdFromPasskeyUserHandle(userHandle)
      : null;
}

@visibleForTesting
Map<String, dynamic> telegramPasskeyAssertion(
  String responseJson,
  String clientDataJson,
) {
  final credential = _jsonObject(responseJson, 'credential response');
  final credentialId = credential['id'];
  final response = credential['response'];
  if (credentialId is! String ||
      credentialId.isEmpty ||
      response is! Map<String, dynamic>) {
    throw const TelegramPasskeyException(
      'passkey_invalid',
      'Missing passkey assertion',
    );
  }
  final authenticatorData = response['authenticatorData'];
  final signature = response['signature'];
  final userHandle = response['userHandle'];
  if (authenticatorData is! String || signature is! String) {
    throw const TelegramPasskeyException(
      'passkey_invalid',
      'Incomplete passkey assertion',
    );
  }
  final normalizedUserHandle = userHandle is String ? userHandle : '';
  return {
    'credential_id': credentialId,
    'client_data': clientDataJson,
    'authenticator_data': tdlibBase64FromBase64Url(authenticatorData),
    'signature': tdlibBase64FromBase64Url(signature),
    'user_handle': tdlibBase64FromBase64Url(normalizedUserHandle),
  };
}

Map<String, dynamic> _jsonObject(String value, String label) {
  try {
    final decoded = jsonDecode(value);
    if (decoded is Map<String, dynamic>) return decoded;
  } on FormatException catch (error) {
    throw TelegramPasskeyException('passkey_invalid', error.message);
  }
  throw TelegramPasskeyException('passkey_invalid', 'Invalid $label');
}
