import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'bot_api_account.dart';

class BotApiException implements Exception {
  const BotApiException(this.code, this.message);

  final int code;
  final String message;

  @override
  String toString() => message;
}

/// Secret-safe HTTP client for Telegram-compatible Bot API endpoints.
class BotApiClient {
  BotApiClient({
    required String token,
    required Uri endpoint,
    http.Client? httpClient,
  }) : _token = normalizeBotToken(token),
       endpoint = normalizeBotApiEndpoint(endpoint.toString()),
       _http = httpClient ?? http.Client();

  final String _token;
  final Uri endpoint;
  final http.Client _http;
  bool _closed = false;

  Future<Object?> call(
    String method, [
    Map<String, dynamic> parameters = const {},
  ]) async {
    _ensureOpen();
    try {
      final response = await _http
          .post(
            _methodUri(method),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode(parameters),
          )
          .timeout(_timeoutFor(method));
      return _decode(response);
    } on BotApiException {
      rethrow;
    } on TimeoutException {
      throw const BotApiException(408, 'The Bot API request timed out.');
    } on Object {
      // http exceptions include the request URI, which contains the token. Do
      // not forward their text to logs, diagnostics, or the UI.
      throw const BotApiException(503, 'Could not reach the Bot API endpoint.');
    }
  }

  Future<Object?> callMultipart(
    String method, {
    required Map<String, String> fields,
    required Map<String, String> files,
  }) async {
    _ensureOpen();
    try {
      final request = http.MultipartRequest('POST', _methodUri(method))
        ..fields.addAll(fields);
      for (final entry in files.entries) {
        request.files.add(
          await http.MultipartFile.fromPath(entry.key, entry.value),
        );
      }
      final streamed = await _http
          .send(request)
          .timeout(const Duration(minutes: 3));
      final response = await http.Response.fromStream(streamed);
      return _decode(response);
    } on BotApiException {
      rethrow;
    } on TimeoutException {
      throw const BotApiException(408, 'The Bot API upload timed out.');
    } on Object {
      throw const BotApiException(
        503,
        'Could not upload the file to the Bot API endpoint.',
      );
    }
  }

  Future<File> downloadFile(String remotePath, File destination) async {
    _ensureOpen();
    try {
      final response = await _http
          .get(_fileUri(remotePath))
          .timeout(const Duration(minutes: 2));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw BotApiException(
          response.statusCode,
          'The Bot API file download failed.',
        );
      }
      await destination.parent.create(recursive: true);
      await destination.writeAsBytes(response.bodyBytes, flush: true);
      return destination;
    } on BotApiException {
      rethrow;
    } on TimeoutException {
      throw const BotApiException(408, 'The Bot API download timed out.');
    } on Object {
      throw const BotApiException(
        503,
        'Could not download the file from the Bot API endpoint.',
      );
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _http.close();
  }

  Uri _methodUri(String method) =>
      endpoint.replace(path: '${endpoint.path}/bot$_token/$method');

  Uri _fileUri(String remotePath) {
    final path = remotePath.replaceFirst(RegExp(r'^/+'), '');
    return endpoint.replace(path: '${endpoint.path}/file/bot$_token/$path');
  }

  Duration _timeoutFor(String method) => method == 'getUpdates'
      ? const Duration(seconds: 40)
      : const Duration(seconds: 30);

  Object? _decode(http.Response response) {
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw BotApiException(
        response.statusCode,
        'The Bot API endpoint returned an invalid response.',
      );
    }
    if (decoded is! Map) {
      throw BotApiException(
        response.statusCode,
        'The Bot API endpoint returned an invalid response.',
      );
    }
    final payload = Map<String, dynamic>.from(decoded);
    if (payload['ok'] == true) return payload['result'];
    final code = _asInt(payload['error_code']) ?? response.statusCode;
    final description = payload['description'];
    throw BotApiException(
      code,
      description is String && description.trim().isNotEmpty
          ? _sanitizeRemoteDescription(description)
          : 'The Bot API request failed.',
    );
  }

  String _sanitizeRemoteDescription(String value) => value
      .trim()
      .replaceAll(_token, '[redacted]')
      .replaceAll(RegExp(r'\d+:[A-Za-z0-9_-]{20,}'), '[redacted]');

  void _ensureOpen() {
    if (_closed) throw const BotApiException(499, 'Bot API client is closed.');
  }
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
