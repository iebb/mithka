//
//  keyword_blocker.dart
//
//  Local keyword-based spam blocker. Keywords are stored in SharedPreferences
//  and applied client-side to message text/notifications.
//

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class KeywordBlocker extends ChangeNotifier {
  KeywordBlocker._();
  static final KeywordBlocker shared = KeywordBlocker._();

  static const _prefsKey = 'spamBlockKeywords';
  static const _urlKey = 'spamBlockKeywordListUrl';
  static const _senderKey = 'spamBlockSenderIds';

  SharedPreferences? _prefs;
  List<String> _keywords = const [];
  String _listUrl = '';
  Set<int> _blockedSenderIds = const <int>{};

  List<String> get keywords => List.unmodifiable(_keywords);
  String get listUrl => _listUrl;
  bool get isEnabled => _keywords.isNotEmpty || _blockedSenderIds.isNotEmpty;

  void initialize(SharedPreferences prefs) {
    _prefs = prefs;
    _keywords = _normalizeList(prefs.getStringList(_prefsKey) ?? const []);
    _listUrl = prefs.getString(_urlKey)?.trim() ?? '';
    _blockedSenderIds = _parseSenderIds(
      prefs.getStringList(_senderKey) ?? const [],
    );
    notifyListeners();
  }

  bool matches(String text) {
    if (_keywords.isEmpty || text.trim().isEmpty) return false;
    final normalized = text.toLowerCase();
    for (final keyword in _keywords) {
      final regex = _regexFromRule(keyword);
      if (regex != null) {
        if (regex.hasMatch(text)) return true;
      } else if (normalized.contains(keyword.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  bool isSenderBlocked(int? senderId) {
    return senderId != null && _blockedSenderIds.contains(senderId);
  }

  void add(String value) {
    final keyword = _normalize(value);
    if (keyword == null) return;
    if (_keywords.any((k) => k.toLowerCase() == keyword.toLowerCase())) return;
    _keywords = [..._keywords, keyword];
    _save();
  }

  void remove(String value) {
    final lower = value.toLowerCase();
    final next = _keywords.where((k) => k.toLowerCase() != lower).toList();
    if (next.length == _keywords.length) return;
    _keywords = next;
    _save();
  }

  void addBlockedSender(int senderId) {
    if (senderId <= 0 || _blockedSenderIds.contains(senderId)) return;
    _blockedSenderIds = {..._blockedSenderIds, senderId};
    _saveBlockedSenders();
  }

  void removeBlockedSender(int senderId) {
    if (!_blockedSenderIds.contains(senderId)) return;
    _blockedSenderIds = {..._blockedSenderIds}..remove(senderId);
    _saveBlockedSenders();
  }

  void replaceAll(List<String> values) {
    _keywords = _normalizeList(values);
    _save();
  }

  void setListUrl(String value) {
    _listUrl = value.trim();
    _prefs?.setString(_urlKey, _listUrl);
    notifyListeners();
  }

  Future<int> refreshFromUrl() async {
    final uri = Uri.tryParse(_listUrl);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      throw const FormatException('Invalid keyword list URL');
    }
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'text/plain,*/*');
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}', uri: uri);
      }
      final body = await utf8.decodeStream(response);
      final remote = _parseList(body);
      final before = _keywords.length;
      _keywords = _normalizeList([..._keywords, ...remote]);
      _save();
      return _keywords.length - before;
    } finally {
      client.close(force: true);
    }
  }

  static List<String> _normalizeList(List<String> values) {
    final out = <String>[];
    final seen = <String>{};
    for (final value in values) {
      final keyword = _normalize(value);
      if (keyword == null) continue;
      final key = keyword.toLowerCase();
      if (seen.add(key)) out.add(keyword);
    }
    return out;
  }

  static String? _normalize(String value) {
    final keyword = value.trim();
    return keyword.isEmpty ? null : keyword;
  }

  static List<String> _parseList(String body) {
    return body.split(RegExp(r'\r?\n')).map((line) => line.trim()).where((
      line,
    ) {
      if (line.isEmpty) return false;
      if (line.startsWith('#') || line.startsWith('//')) return false;
      return true;
    }).toList();
  }

  static Set<int> _parseSenderIds(List<String> values) {
    return values
        .map((value) => int.tryParse(value.trim()))
        .whereType<int>()
        .where((value) => value > 0)
        .toSet();
  }

  static RegExp? _regexFromRule(String rule) {
    final trimmed = rule.trim();
    if (trimmed.startsWith('re:') || trimmed.startsWith('regex:')) {
      final pattern = trimmed.substring(trimmed.indexOf(':') + 1).trim();
      if (pattern.isEmpty) return null;
      return _safeRegex(pattern, caseSensitive: false);
    }
    if (trimmed.length >= 2 && trimmed.startsWith('/')) {
      final lastSlash = trimmed.lastIndexOf('/');
      if (lastSlash > 0) {
        final pattern = trimmed.substring(1, lastSlash);
        final flags = trimmed.substring(lastSlash + 1);
        return _safeRegex(pattern, caseSensitive: !flags.contains('i'));
      }
    }
    return null;
  }

  static RegExp? _safeRegex(String pattern, {required bool caseSensitive}) {
    try {
      return RegExp(pattern, caseSensitive: caseSensitive);
    } catch (_) {
      return null;
    }
  }

  void _save() {
    _prefs?.setStringList(_prefsKey, _keywords);
    notifyListeners();
  }

  void _saveBlockedSenders() {
    _prefs?.setStringList(
      _senderKey,
      _blockedSenderIds.map((id) => id.toString()).toList()..sort(),
    );
    notifyListeners();
  }
}
