import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tdlib/td_models.dart';

class MessageTranslationCacheKey {
  const MessageTranslationCacheKey({
    required this.accountSlot,
    required this.chatId,
    required this.messageId,
    required this.sourceText,
    required this.targetLanguageCode,
  });

  final int accountSlot;
  final int chatId;
  final int messageId;
  final String sourceText;
  final String targetLanguageCode;

  String get digest => sha256
      .convert(
        utf8.encode(
          jsonEncode({
            'accountSlot': '$accountSlot',
            'chatId': '$chatId',
            'messageId': '$messageId',
            'sourceText': sourceText,
            'targetLanguageCode': targetLanguageCode,
          }),
        ),
      )
      .toString();
}

class MessageTranslationValue {
  const MessageTranslationValue({
    required this.text,
    required this.entities,
    required this.languageCode,
  });

  final String text;
  final List<MessageTextEntity> entities;
  final String languageCode;
}

/// A short-lived, on-device cache for successful message translations.
///
/// Cache keys include the account, message identity, source text and target
/// language, so edits, account switches and target-language changes cannot reuse a
/// stale translation. Entries remain available for seven full days and are
/// pruned after that window. In-flight work is shared process-wide so two open
/// windows cannot issue the same translation request simultaneously.
class MessageTranslationCache {
  MessageTranslationCache(this._preferences, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  static const retention = Duration(days: 7);
  static const _storagePrefix = 'translation.messageCache.v1.';
  static final Map<String, Future<MessageTranslationValue>> _inFlight = {};

  final SharedPreferences _preferences;
  final DateTime Function() _now;

  MessageTranslationValue? read(MessageTranslationCacheKey key) =>
      _readStorageKey('$_storagePrefix${key.digest}');

  Future<MessageTranslationValue> resolve(
    MessageTranslationCacheKey key,
    Future<MessageTranslationValue> Function() load,
  ) async {
    final storageKey = '$_storagePrefix${key.digest}';
    final cached = _readStorageKey(storageKey);
    if (cached != null) return cached;

    final pending = _inFlight[storageKey];
    if (pending != null) return pending;

    final future = _loadAndStore(storageKey, load);
    _inFlight[storageKey] = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlight[storageKey], future)) {
        final _ = _inFlight.remove(storageKey);
      }
    }
  }

  void pruneExpired() {
    for (final key in _preferences.getKeys()) {
      if (key.startsWith(_storagePrefix)) _readStorageKey(key);
    }
  }

  Future<MessageTranslationValue> _loadAndStore(
    String storageKey,
    Future<MessageTranslationValue> Function() load,
  ) async {
    // A second controller/window may have filled the shared preferences record
    // between the first read and its turn to install the in-flight operation.
    final cached = _readStorageKey(storageKey);
    if (cached != null) return cached;

    final value = await load();
    if (value.text.trim().isEmpty) return value;
    final payload = jsonEncode({
      'cachedAtMs': _now().millisecondsSinceEpoch,
      'text': value.text,
      'languageCode': value.languageCode,
      'entities': value.entities
          .map((entity) => entity.toTdJson())
          .toList(growable: false),
    });
    try {
      await _preferences.setString(storageKey, payload);
    } catch (_) {
      // A storage failure must not discard a translation the provider returned.
    }
    return value;
  }

  MessageTranslationValue? _readStorageKey(String storageKey) {
    final encoded = _preferences.getString(storageKey);
    if (encoded == null) return null;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      final cachedAtMs = decoded['cachedAtMs'];
      final text = decoded['text'];
      final languageCode = decoded['languageCode'];
      if (cachedAtMs is! int ||
          text is! String ||
          text.trim().isEmpty ||
          languageCode is! String ||
          languageCode.isEmpty) {
        throw const FormatException();
      }
      final cachedAt = DateTime.fromMillisecondsSinceEpoch(cachedAtMs);
      if (!_now().isBefore(cachedAt.add(retention))) {
        unawaited(_preferences.remove(storageKey));
        return null;
      }
      final rawEntities = decoded['entities'];
      final entities = rawEntities is List
          ? TDParse.textEntities({
              '@type': 'formattedText',
              'text': text,
              'entities': rawEntities
                  .whereType<Map<String, dynamic>>()
                  .toList(),
            })
          : const <MessageTextEntity>[];
      return MessageTranslationValue(
        text: text,
        entities: entities,
        languageCode: languageCode,
      );
    } catch (_) {
      unawaited(_preferences.remove(storageKey));
      return null;
    }
  }
}
