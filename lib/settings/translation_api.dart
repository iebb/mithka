//
//  translation_api.dart
//
//  Lightweight clients for optional third-party message translation providers.
//

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'translation_controller.dart';

class NativeTranslationApi {
  const NativeTranslationApi._();

  static const _channel = MethodChannel('mithka/native_translation');

  static Future<Set<TranslationProvider>> availableProviders() async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('capabilities');
      final values = raw?.whereType<String>().toSet() ?? const <String>{};
      return TranslationProvider.selectableProviders
          .where((provider) => values.contains(provider.storageValue))
          .toSet();
    } on PlatformException {
      return const <TranslationProvider>{};
    } on MissingPluginException {
      return const <TranslationProvider>{};
    }
  }

  static Future<String> translate({
    required String text,
    required String sourceLanguageCode,
    required String targetLanguageCode,
  }) async {
    try {
      final translated = await _channel
          .invokeMethod<String>('translate', {
            'text': text,
            'sourceLanguageCode': sourceLanguageCode,
            'targetLanguageCode': targetLanguageCode,
          })
          .timeout(
            const Duration(seconds: 60),
            onTimeout: () => throw TranslationApiException('本机翻译已取消或超时'),
          );
      if (translated == null || translated.isEmpty) {
        throw TranslationApiException('本机翻译没有返回译文');
      }
      return translated;
    } on PlatformException catch (e) {
      throw TranslationApiException(e.message ?? e.code);
    }
  }
}

class ThirdPartyTranslationApi {
  const ThirdPartyTranslationApi._();

  static Future<String> translate({
    required TranslationProvider provider,
    required String text,
    required String sourceLanguageCode,
    required String targetLanguageCode,
    required String lingvaEndpoint,
    required String libreTranslateEndpoint,
    required String libreTranslateApiKey,
  }) {
    final source = _sourceLanguage(sourceLanguageCode);
    final target = _apiLanguage(targetLanguageCode);
    return switch (provider) {
      TranslationProvider.iosSystem || TranslationProvider.androidMlKit =>
        throw TranslationApiException('本机翻译不走外部 API'),
      TranslationProvider.myMemory => _translateMyMemory(text, source, target),
      TranslationProvider.lingva => _translateLingva(
        text,
        source,
        target,
        lingvaEndpoint,
      ),
      TranslationProvider.libreTranslate => _translateLibreTranslate(
        text,
        source,
        target,
        libreTranslateEndpoint,
        libreTranslateApiKey,
      ),
      TranslationProvider.tdlib => throw TranslationApiException(
        '内部翻译不走外部 API',
      ),
    };
  }

  static Future<String> _translateMyMemory(
    String text,
    String source,
    String target,
  ) async {
    final chunks = _chunksByUtf8Bytes(text, 480);
    final translated = <String>[];
    for (final chunk in chunks) {
      final uri = Uri.https('api.mymemory.translated.net', '/get', {
        'q': chunk,
        'langpair': '$source|$target',
      });
      final json = await _getJson(uri);
      final responseData = json['responseData'];
      final value = responseData is Map
          ? responseData['translatedText']?.toString()
          : null;
      if (value == null || value.isEmpty) {
        throw TranslationApiException('MyMemory 没有返回译文');
      }
      translated.add(value);
    }
    return translated.join('\n');
  }

  static Future<String> _translateLingva(
    String text,
    String source,
    String target,
    String endpoint,
  ) async {
    final base = _endpointUri(
      endpoint.isEmpty ? TranslationController.defaultLingvaEndpoint : endpoint,
    );
    final chunks = _chunksByRunes(text, 1500);
    final translated = <String>[];
    for (final chunk in chunks) {
      final uri = _appendPath(base, ['api', 'v1', source, target, chunk]);
      final json = await _getJson(uri);
      final value = json['translation']?.toString();
      if (value == null || value.isEmpty) {
        throw TranslationApiException('Lingva 没有返回译文');
      }
      translated.add(value);
    }
    return translated.join('\n');
  }

  static Future<String> _translateLibreTranslate(
    String text,
    String source,
    String target,
    String endpoint,
    String apiKey,
  ) async {
    if (endpoint.trim().isEmpty) {
      throw TranslationApiException('请先设置 LibreTranslate 地址');
    }
    final uri = _appendPath(_endpointUri(endpoint), ['translate']);
    final body = <String, Object>{
      'q': text,
      'source': source,
      'target': target,
      'format': 'text',
    };
    if (apiKey.trim().isNotEmpty) body['api_key'] = apiKey.trim();
    final json = await _postJson(uri, body);
    final value = json['translatedText']?.toString();
    if (value == null || value.isEmpty) {
      throw TranslationApiException('LibreTranslate 没有返回译文');
    }
    return value;
  }

  static String _sourceLanguage(String languageCode) {
    final normalized = TranslationController.normalizeLanguageCode(
      languageCode,
    );
    if (normalized == null || normalized == 'auto') return 'autodetect';
    return _apiLanguage(normalized);
  }

  static String _apiLanguage(String code) {
    final lower = code.toLowerCase();
    if (lower == 'zh' || lower == 'zh-hans' || lower == 'zh-cn') {
      return 'zh-CN';
    }
    if (lower == 'zh-hant' || lower == 'zh-tw' || lower == 'zh-hk') {
      return 'zh-TW';
    }
    return lower.split('-').first;
  }

  static Uri _endpointUri(String endpoint) {
    final normalized = TranslationController.normalizeEndpoint(endpoint);
    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw TranslationApiException('翻译服务地址无效');
    }
    return uri;
  }

  static Uri _appendPath(Uri base, List<String> segments) {
    final existing = base.pathSegments.where((s) => s.isNotEmpty).toList();
    return base.replace(pathSegments: [...existing, ...segments]);
  }

  static Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final client = HttpClient();
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 15));
      request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      return _decodeJson(response);
    } finally {
      client.close(force: true);
    }
  }

  static Future<Map<String, dynamic>> _postJson(
    Uri uri,
    Map<String, Object> body,
  ) async {
    final client = HttpClient();
    try {
      final request = await client
          .postUrl(uri)
          .timeout(const Duration(seconds: 15));
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
      request.write(jsonEncode(body));
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      return _decodeJson(response);
    } finally {
      client.close(force: true);
    }
  }

  static Future<Map<String, dynamic>> _decodeJson(
    HttpClientResponse response,
  ) async {
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TranslationApiException('翻译服务返回 ${response.statusCode}');
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw TranslationApiException('翻译服务响应格式不正确');
    }
    return decoded;
  }

  static List<String> _chunksByUtf8Bytes(String text, int maxBytes) {
    final chunks = <String>[];
    final buffer = StringBuffer();
    var bytes = 0;
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      final length = utf8.encode(char).length;
      if (buffer.isNotEmpty && bytes + length > maxBytes) {
        chunks.add(buffer.toString());
        buffer.clear();
        bytes = 0;
      }
      buffer.write(char);
      bytes += length;
    }
    if (buffer.isNotEmpty) chunks.add(buffer.toString());
    return chunks;
  }

  static List<String> _chunksByRunes(String text, int maxRunes) {
    final chunks = <String>[];
    final buffer = StringBuffer();
    var count = 0;
    for (final rune in text.runes) {
      if (buffer.isNotEmpty && count >= maxRunes) {
        chunks.add(buffer.toString());
        buffer.clear();
        count = 0;
      }
      buffer.write(String.fromCharCode(rune));
      count++;
    }
    if (buffer.isNotEmpty) chunks.add(buffer.toString());
    return chunks;
  }
}

class TranslationApiException implements Exception {
  TranslationApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
