import 'dart:convert';

import 'package:flutter/foundation.dart';

typedef AiStdoutSink = void Function(String line);

/// Always writes complete AI lifecycle events as one JSON object per line.
///
/// Callers should pass model payloads rather than transport headers. Known
/// credential fields are recursively redacted as a final safeguard.
class AiStdoutLogger {
  AiStdoutLogger({AiStdoutSink? sink, Iterable<String> secrets = const []})
    : _sink = sink ?? _defaultSink,
      _secrets = _normalizedSecrets(secrets);

  final AiStdoutSink _sink;
  final List<String> _secrets;
  static int _correlationSerial = 0;

  String newCorrelationId(String provider) {
    final normalizedProvider = provider.trim().replaceAll(
      RegExp(r'[^a-zA-Z0-9._-]+'),
      '_',
    );
    return '${normalizedProvider.isEmpty ? 'ai' : normalizedProvider}-'
        '${DateTime.now().microsecondsSinceEpoch}-${_correlationSerial++}';
  }

  void request({
    required String correlationId,
    required String provider,
    required String operation,
    required Object? payload,
    Iterable<String> secrets = const [],
  }) => _emit({
    'event': 'ai.request',
    'timestamp': DateTime.now().toUtc().toIso8601String(),
    'correlation_id': correlationId,
    'provider': provider,
    'operation': operation,
    'payload': payload,
  }, secrets: secrets);

  void response({
    required String correlationId,
    required String provider,
    required String operation,
    required Object? result,
    Iterable<String> secrets = const [],
  }) => _emit({
    'event': 'ai.response',
    'timestamp': DateTime.now().toUtc().toIso8601String(),
    'correlation_id': correlationId,
    'provider': provider,
    'operation': operation,
    'result': result,
  }, secrets: secrets);

  void error({
    required String correlationId,
    required String provider,
    required String operation,
    required Object error,
    Object? payload,
    StackTrace? stackTrace,
    Iterable<String> secrets = const [],
  }) => _emit({
    'event': 'ai.error',
    'timestamp': DateTime.now().toUtc().toIso8601String(),
    'correlation_id': correlationId,
    'provider': provider,
    'operation': operation,
    'payload': ?payload,
    'error': {
      'type': error.runtimeType.toString(),
      'message': error.toString(),
      if (stackTrace != null) 'stack_trace': stackTrace.toString(),
    },
  }, secrets: secrets);

  void _emit(
    Map<String, Object?> event, {
    Iterable<String> secrets = const [],
  }) {
    try {
      final eventSecrets = [..._secrets, ..._normalizedSecrets(secrets)];
      _sink(jsonEncode(_jsonSafe(event, secrets: eventSecrets)));
    } catch (_) {
      // Observability must never change the outcome of an AI operation.
    }
  }

  Object? _jsonSafe(
    Object? value, {
    String? fieldName,
    required List<String> secrets,
  }) {
    if (fieldName != null && _isCredentialField(fieldName)) {
      return '[REDACTED]';
    }
    if (value == null || value is bool || value is num) {
      return value;
    }
    if (value is String) return _redactSecrets(value, secrets);
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          _redactSecrets('${entry.key}', secrets): _jsonSafe(
            entry.value,
            fieldName: '${entry.key}',
            secrets: secrets,
          ),
      };
    }
    if (value is Iterable) {
      return [for (final item in value) _jsonSafe(item, secrets: secrets)];
    }
    return _redactSecrets(value.toString(), secrets);
  }

  bool _isCredentialField(String value) {
    final normalized = value.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
    return const {
      'authorization',
      'proxyauthorization',
      'apikey',
      'xapikey',
      'accesstoken',
      'refreshtoken',
      'idtoken',
      'clientsecret',
      'password',
      'cookie',
      'setcookie',
    }.contains(normalized);
  }

  static List<String> _normalizedSecrets(Iterable<String> values) {
    final result = <String>{};
    for (final value in values) {
      if (value.trim().isEmpty) continue;
      result.add(value);
      result.add(value.trim());
    }
    final sorted = result.toList(growable: false);
    sorted.sort((left, right) => right.length.compareTo(left.length));
    return sorted;
  }

  String _redactSecrets(String value, List<String> secrets) {
    var result = value;
    for (final secret in secrets) {
      result = result.replaceAll(secret, '[REDACTED]');
    }
    return result;
  }

  @visibleForTesting
  static List<String> terminalLinesForTesting(String line) =>
      _terminalLines(line);

  static void _defaultSink(String line) {
    for (final terminalLine in _terminalLines(line)) {
      debugPrintSynchronously(terminalLine);
    }
  }

  /// iOS truncates oversized stdout records. Preserve the complete JSON event
  /// as ordered, individually valid JSON chunk records below that limit.
  static List<String> _terminalLines(String line) {
    if (utf8.encode(line).length <= 900) return [line];
    final chunks = _splitByUtf8Bytes(line, 240);
    String? sourceEvent;
    String? correlationId;
    String? provider;
    String? operation;
    try {
      final decoded = jsonDecode(line);
      if (decoded is Map) {
        sourceEvent = decoded['event']?.toString();
        correlationId = decoded['correlation_id']?.toString();
        provider = decoded['provider']?.toString();
        operation = decoded['operation']?.toString();
      }
    } on FormatException {
      // The logger emits JSON, but retain lossless fallback chunking if a
      // custom caller gives the default sink malformed input.
    }
    return [
      for (var index = 0; index < chunks.length; index++)
        jsonEncode({
          'event': 'ai.stdout.chunk',
          'source_event': ?sourceEvent,
          'correlation_id': ?correlationId,
          'provider': ?provider,
          'operation': ?operation,
          'chunk_index': index + 1,
          'chunk_count': chunks.length,
          'data': chunks[index],
        }),
    ];
  }

  static List<String> _splitByUtf8Bytes(String value, int maximumBytes) {
    final chunks = <String>[];
    var buffer = StringBuffer();
    var byteCount = 0;
    for (final rune in value.runes) {
      final character = String.fromCharCode(rune);
      final characterBytes = utf8.encode(character).length;
      if (byteCount > 0 && byteCount + characterBytes > maximumBytes) {
        chunks.add(buffer.toString());
        buffer = StringBuffer();
        byteCount = 0;
      }
      buffer.write(character);
      byteCount += characterBytes;
    }
    if (buffer.isNotEmpty) chunks.add(buffer.toString());
    return chunks;
  }
}

final AiStdoutLogger aiStdoutLogger = AiStdoutLogger();
