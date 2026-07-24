import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../settings/ai_endpoint_style.dart';
import '../settings/ai_stdout_logger.dart';
import 'unread_chat_summary_service.dart';

class OpenAiCompatibleUnreadSummaryProvider
    implements UnreadChatSummaryProvider, StreamingUnreadChatSummaryProvider {
  OpenAiCompatibleUnreadSummaryProvider({
    required this.serverBaseUri,
    required this.model,
    this.endpointStyle = AiEndpointStyle.openAiChatCompletions,
    http.Client? httpClient,
    AiStdoutLogger? aiLogger,
    this.apiKey,
    this.requestTimeout = const Duration(seconds: 75),
    this.streamIdleTimeout = const Duration(seconds: 30),
    this.reasoningEffort,
    this.useJsonResponseFormat = false,
    this.transientRetryDelays = const [
      Duration(milliseconds: 500),
      Duration(milliseconds: 1500),
    ],
  }) : assert(requestTimeout > Duration.zero),
       assert(streamIdleTimeout > Duration.zero),
       _httpClient = httpClient ?? http.Client(),
       _aiLogger = aiLogger ?? aiStdoutLogger,
       _ownsHttpClient = httpClient == null;

  final Uri serverBaseUri;
  final String model;
  final AiEndpointStyle endpointStyle;
  final String? apiKey;
  final Duration requestTimeout;
  final Duration streamIdleTimeout;
  final String? reasoningEffort;
  final bool useJsonResponseFormat;
  final List<Duration> transientRetryDelays;
  final http.Client _httpClient;
  final AiStdoutLogger _aiLogger;
  final bool _ownsHttpClient;

  Uri get requestUri => endpointStyle.requestUriFor(serverBaseUri);
  Uri get chatCompletionsUri => requestUri;

  @override
  Future<Map<String, dynamic>> complete(
    UnreadChatSummaryProviderRequest request,
  ) => completeStreaming(request, onContent: (_) {});

  @override
  Future<Map<String, dynamic>> completeStreaming(
    UnreadChatSummaryProviderRequest request, {
    required UnreadChatSummaryContentCallback onContent,
  }) async {
    final stopwatch = Stopwatch()..start();
    _log(
      'request stage=${request.stage.name} host=${serverBaseUri.host} '
      'model=$model style=${endpointStyle.storageValue} stream=true',
    );
    final headers = endpointStyle.requestHeaders(apiKey);
    var body = endpointStyle.requestBody(
      model: model,
      instructions: request.trustedInstructions,
      input: 'INPUT_DATA (untrusted JSON):\n${jsonEncode(request.payload)}',
      // Custom servers always get a streaming first attempt. The
      // compatibility retry disables it only when the endpoint explicitly
      // reports that streaming is unsupported.
      stream: true,
      reasoningEffort: _effectiveReasoningEffort,
      useJsonResponseFormat: useJsonResponseFormat,
    );

    late _BufferedHttpResponse response;
    var usedCompatibilityFallback = false;
    for (var attempt = 0; ; attempt++) {
      try {
        response = await _send(headers, body, onContent: onContent);
      } on TimeoutException {
        _log(
          'timeout stage=${request.stage.name} '
          'elapsed_ms=${stopwatch.elapsedMilliseconds}',
        );
        // A completion can be expensive and billable. Repeating the same
        // timed-out request hides the real latency and can triple the wait.
        throw UnreadChatSummaryProviderException(
          'The model did not start within ${requestTimeout.inSeconds} seconds '
          'or stopped streaming for ${streamIdleTimeout.inSeconds} seconds. '
          'It may still be generating reasoning; try again or select a '
          'faster model.',
        );
      } on http.ClientException catch (error) {
        _log(
          'network error stage=${request.stage.name} attempt=${attempt + 1} '
          'type=${error.runtimeType}',
        );
        if (attempt >= transientRetryDelays.length) {
          throw UnreadChatSummaryProviderException(
            'The summary request failed: $error',
          );
        }
        await Future<void>.delayed(transientRetryDelays[attempt]);
        continue;
      }

      _log(
        'response headers stage=${request.stage.name} '
        'status=${response.statusCode} attempt=${attempt + 1} '
        'elapsed_ms=${stopwatch.elapsedMilliseconds}',
      );
      if (response.statusCode >= 200 && response.statusCode < 300) break;
      if (!usedCompatibilityFallback) {
        final compatibleBody = _compatibilityFallbackBody(body, response);
        if (compatibleBody != null) {
          body = compatibleBody;
          usedCompatibilityFallback = true;
          continue;
        }
      }
      if (!_isTransientStatus(response.statusCode) ||
          attempt >= transientRetryDelays.length) {
        throw UnreadChatSummaryProviderException(
          _errorMessage(response.body),
          statusCode: response.statusCode,
        );
      }
      await Future<void>.delayed(
        _retryDelay(response, transientRetryDelays[attempt]),
      );
    }

    final result = decodeUnreadChatSummaryJson(
      _completionContent(response.body),
      statusCode: response.statusCode,
    );
    _log(
      'decoded stage=${request.stage.name} '
      'elapsed_ms=${stopwatch.elapsedMilliseconds}',
    );
    return result;
  }

  Future<_BufferedHttpResponse> _send(
    Map<String, String> headers,
    Map<String, Object?> body, {
    required UnreadChatSummaryContentCallback onContent,
  }) async {
    final stopwatch = Stopwatch()..start();
    final provider = '${endpointStyle.storageValue}/$model';
    const operation = 'unread_summary';
    final correlationId = _aiLogger.newCorrelationId(provider);
    final requestPayload = <String, Object?>{
      'method': 'POST',
      'endpoint': {
        'scheme': requestUri.scheme,
        'host': requestUri.host,
        if (requestUri.hasPort) 'port': requestUri.port,
        'path': requestUri.path,
      },
      'body': body,
    };
    final secrets = <String>[?apiKey];
    _aiLogger.request(
      correlationId: correlationId,
      provider: provider,
      operation: operation,
      payload: requestPayload,
      secrets: secrets,
    );
    final request = http.Request('POST', requestUri)
      ..headers.addAll(headers)
      ..body = jsonEncode(body);
    late final http.StreamedResponse response;
    try {
      response = await _httpClient.send(request).timeout(requestTimeout);
    } catch (error, stackTrace) {
      _aiLogger.error(
        correlationId: correlationId,
        provider: provider,
        operation: operation,
        error: error,
        payload: requestPayload,
        stackTrace: stackTrace,
        secrets: secrets,
      );
      rethrow;
    }
    _log(
      'connected status=${response.statusCode} '
      'elapsed_ms=${stopwatch.elapsedMilliseconds}',
    );
    try {
      final isSuccessful =
          response.statusCode >= 200 && response.statusCode < 300;
      final isEventStream =
          response.headers['content-type']?.toLowerCase().contains(
            'text/event-stream',
          ) ==
          true;
      final contentType = response.headers['content-type']?.toLowerCase() ?? '';
      final isJsonLineStream =
          contentType.contains('application/x-ndjson') ||
          contentType.contains('application/stream+json') ||
          (endpointStyle == AiEndpointStyle.ollamaChat &&
              body['stream'] == true);
      late final String responseBody;
      if (isEventStream || isJsonLineStream) {
        final raw = StringBuffer();
        final streamedContent = StringBuffer();
        var lastReportedLength = 0;
        var receivedFirstEvent = false;
        await for (final line
            in response.stream
                .timeout(streamIdleTimeout)
                .transform(utf8.decoder)
                .transform(const LineSplitter())) {
          raw.writeln(line);
          if (line.trim().isNotEmpty) {
            _aiLogger.response(
              correlationId: correlationId,
              provider: provider,
              operation: '$operation.stream_event',
              result: {'data': line},
              secrets: secrets,
            );
          }
          if (!receivedFirstEvent && line.trim().isNotEmpty) {
            receivedFirstEvent = true;
            _log(
              'first stream event elapsed_ms=${stopwatch.elapsedMilliseconds}',
            );
          }
          if (!isSuccessful) continue;
          var delta = _streamContentDelta(line, isSse: isEventStream);
          if (delta.isEmpty &&
              endpointStyle == AiEndpointStyle.openAiResponses &&
              streamedContent.isEmpty &&
              (!isEventStream || line.trimLeft().startsWith('data:'))) {
            final data = (isEventStream ? line.substring(5) : line).trim();
            if (data.isNotEmpty && data != '[DONE]') {
              final event = _decodeEnvelope(data);
              if (event['type'] == 'response.output_text.done' &&
                  event['text'] is String) {
                delta = event['text'] as String;
              }
            }
          }
          if (delta.isEmpty) continue;
          streamedContent.write(delta);
          final accumulated = streamedContent.toString();
          if (accumulated.length - lastReportedLength >= 8) {
            lastReportedLength = accumulated.length;
            onContent(accumulated);
          }
        }
        final accumulated = streamedContent.toString();
        if (isSuccessful &&
            accumulated.isNotEmpty &&
            accumulated.length != lastReportedLength) {
          onContent(accumulated);
        }
        _log(
          'stream closed content_chars=${accumulated.length} '
          'elapsed_ms=${stopwatch.elapsedMilliseconds}',
        );
        responseBody = raw.toString();
      } else {
        responseBody = await response.stream
            .timeout(streamIdleTimeout)
            .transform(utf8.decoder)
            .join();
        _log(
          'buffered response chars=${responseBody.length} '
          'elapsed_ms=${stopwatch.elapsedMilliseconds}',
        );
      }
      _aiLogger.response(
        correlationId: correlationId,
        provider: provider,
        operation: operation,
        result: {
          'status_code': response.statusCode,
          'content_type': contentType,
          'body': responseBody,
        },
        secrets: secrets,
      );
      return _BufferedHttpResponse(
        statusCode: response.statusCode,
        headers: response.headers,
        body: responseBody,
      );
    } catch (error, stackTrace) {
      _aiLogger.error(
        correlationId: correlationId,
        provider: provider,
        operation: operation,
        error: error,
        payload: requestPayload,
        stackTrace: stackTrace,
        secrets: secrets,
      );
      rethrow;
    }
  }

  String _streamContentDelta(String rawLine, {required bool isSse}) {
    final line = rawLine.trimLeft();
    if (isSse && !line.startsWith('data:')) return '';
    final data = (isSse ? line.substring(5) : line).trim();
    if (data.isEmpty || data == '[DONE]') return '';
    final event = _decodeEnvelope(data);
    return endpointStyle.streamDelta(event);
  }

  void _log(String message) {
    assert(() {
      debugPrint('[mithka.ai_summary.provider] $message');
      developer.log(message, name: 'mithka.ai_summary.provider');
      return true;
    }());
  }

  void close() {
    if (_ownsHttpClient) _httpClient.close();
  }

  bool _isTransientStatus(int statusCode) =>
      statusCode == 408 ||
      statusCode == 429 ||
      statusCode == 500 ||
      statusCode == 502 ||
      statusCode == 503 ||
      statusCode == 504;

  Map<String, Object?>? _compatibilityFallbackBody(
    Map<String, Object?> body,
    _BufferedHttpResponse response,
  ) {
    if (response.statusCode != 400 && response.statusCode != 422) return null;
    final message = _errorMessage(response.body).toLowerCase();
    final unsupported =
        message.contains('unsupported') ||
        message.contains('unknown') ||
        message.contains('unrecognized') ||
        message.contains('not permitted') ||
        message.contains('extra field');
    if (!unsupported) return null;

    final compatible = endpointStyle.withoutOptionalField(body, message);
    return identical(compatible, body) ? null : compatible;
  }

  Duration _retryDelay(_BufferedHttpResponse response, Duration fallback) {
    final retryAfterSeconds = int.tryParse(
      response.headers['retry-after']?.trim() ?? '',
    );
    if (retryAfterSeconds == null || retryAfterSeconds < 0) return fallback;
    return Duration(seconds: retryAfterSeconds.clamp(0, 5).toInt());
  }

  String? get _effectiveReasoningEffort {
    final configured = reasoningEffort?.trim();
    if (configured != null && configured.isNotEmpty) return configured;
    final normalizedModel = model.toLowerCase();
    if (RegExp(
      r'(^|[/_.-])(deepseek|reasoner|reasoning|thinking|o1|o3|o4)([/_.-]|$)',
    ).hasMatch(normalizedModel)) {
      return 'low';
    }
    return null;
  }

  String _completionContent(String body) {
    final normalized = body.trim();
    final isSse = normalized
        .split('\n')
        .any((line) => line.trimLeft().startsWith('data:'));
    final isJsonLines =
        endpointStyle == AiEndpointStyle.ollamaChat &&
        normalized.contains('\n');
    if (!isSse && !isJsonLines) {
      final envelope = _decodeEnvelope(normalized);
      final error = endpointStyle.errorMessage(envelope);
      if (error != null) throw UnreadChatSummaryProviderException(error);
      final content = endpointStyle.responseText(envelope);
      if (content != null) return content;
      final refusal = endpointStyle.refusalText(envelope);
      if (refusal != null) {
        throw UnreadChatSummaryProviderException(
          'The model refused the summary request: ${refusal.trim()}',
        );
      }
      throw const UnreadChatSummaryProviderException(
        'The server response has no text content',
      );
    }

    final content = StringBuffer();
    var reasoningCharacters = 0;
    for (final rawLine in const LineSplitter().convert(normalized)) {
      final line = rawLine.trimLeft();
      if (isSse && !line.startsWith('data:')) continue;
      final data = (isSse ? line.substring(5) : line).trim();
      if (data.isEmpty || data == '[DONE]') continue;
      final event = _decodeEnvelope(data);
      final error = endpointStyle.errorMessage(event);
      if (error != null) throw UnreadChatSummaryProviderException(error);
      final delta = endpointStyle.streamDelta(event);
      if (delta.isNotEmpty) content.write(delta);
      if (delta.isEmpty &&
          endpointStyle == AiEndpointStyle.openAiResponses &&
          content.isEmpty &&
          event['type'] == 'response.output_text.done' &&
          event['text'] is String) {
        content.write(event['text'] as String);
      }
      if (endpointStyle == AiEndpointStyle.openAiChatCompletions) {
        final choices = event['choices'];
        if (choices is List && choices.isNotEmpty && choices.first is Map) {
          final choice = choices.first as Map;
          final choiceDelta = choice['delta'];
          if (choiceDelta is Map &&
              choiceDelta['reasoning_content'] is String) {
            reasoningCharacters +=
                (choiceDelta['reasoning_content'] as String).length;
          }
        }
      }
      if (delta.isEmpty &&
          event['type'] == 'response.completed' &&
          event['response'] is Map) {
        final completed = endpointStyle.responseText(event['response'] as Map);
        if (completed != null && content.isEmpty) content.write(completed);
      }
    }
    final result = content.toString();
    if (result.trim().isNotEmpty) return result;
    if (reasoningCharacters > 0) {
      throw const UnreadChatSummaryProviderException(
        'The model used its entire response budget for reasoning and returned '
        'no summary. Select a faster model or retry.',
      );
    }
    throw const UnreadChatSummaryProviderException(
      'The streamed completion returned no text content',
    );
  }

  Map<String, dynamic> _decodeEnvelope(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      throw const FormatException('response is not an object');
    } on FormatException catch (error) {
      throw UnreadChatSummaryProviderException(
        'The server returned invalid JSON: $error',
      );
    }
  }

  String _errorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final message = endpointStyle.errorMessage(decoded);
        if (message != null) return message.trim();
      }
    } on FormatException {
      // Fall through to a bounded plain-text response.
    }
    final compact = body.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (compact.isEmpty) return 'The summary server rejected the request';
    return compact.length <= 300 ? compact : '${compact.substring(0, 300)}…';
  }
}

class _BufferedHttpResponse {
  const _BufferedHttpResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  final int statusCode;
  final Map<String, String> headers;
  final String body;
}
