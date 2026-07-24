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

  static void _defaultSink(String line) => debugPrintSynchronously(line);
}

final AiStdoutLogger aiStdoutLogger = AiStdoutLogger();
