import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import 'outgoing_attachment.dart';
import 'rich_message_source.dart';

enum RichMessageRelayStage { upload, compose, waitForMessage, forward }

class RichMessageRelayProgress {
  const RichMessageRelayProgress({
    required this.stage,
    required this.step,
    required this.totalSteps,
    this.mediaIndex = 0,
    this.mediaCount = 0,
    this.complete = false,
  });

  final RichMessageRelayStage stage;
  final int step;
  final int totalSteps;
  final int mediaIndex;
  final int mediaCount;
  final bool complete;

  double get fraction =>
      complete ? 1 : ((step - 1) / totalSteps).clamp(0.0, 1.0).toDouble();
}

typedef RichMessageRelayProgressCallback =
    void Function(RichMessageRelayProgress progress);

class RichMessageRelayBot {
  const RichMessageRelayBot({
    required this.id,
    required this.displayName,
    required this.username,
  });

  final int id;
  final String displayName;
  final String username;
}

class RichMessageRelayException implements Exception {
  const RichMessageRelayException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

class RichMessageRelayResult {
  const RichMessageRelayResult({required this.senderRemoved});

  final bool senderRemoved;
}

String replaceRichMessageMediaIds(String html, Map<String, String> fileIds) {
  var result = html;
  for (final entry in fileIds.entries) {
    result = result
        .replaceAll('src="${entry.key}"', 'src="${entry.value}"')
        .replaceAll("src='${entry.key}'", "src='${entry.value}'");
  }
  return result;
}

String stripRichMessageMediaBlocks(String html) {
  var result = html.replaceAllMapped(
    RegExp(
      r'<figure\b[^>]*>.*?<figcaption\b[^>]*>(.*?)</figcaption>.*?</figure>',
      caseSensitive: false,
      dotAll: true,
    ),
    (match) => '<p>${match.group(1) ?? ''}</p>',
  );
  result = result
      .replaceAll(
        RegExp(r'<img\b[^>]*?/?>', caseSensitive: false, dotAll: true),
        '',
      )
      .replaceAll(
        RegExp(
          r'<(?:video|audio)\b[^>]*>.*?</(?:video|audio)>',
          caseSensitive: false,
          dotAll: true,
        ),
        '',
      )
      .replaceAll(
        RegExp(
          r'<(?:tg-collage|tg-slideshow)\b[^>]*>\s*</(?:tg-collage|tg-slideshow)>',
          caseSensitive: false,
          dotAll: true,
        ),
        '',
      );
  return result.trim();
}

List<Map<String, dynamic>> parseRelayForwardResponse(
  Map<String, dynamic> response,
) {
  final rawMessages = response['messages'];
  if (rawMessages is! List || rawMessages.isEmpty) {
    throw const RichMessageRelayException(
      'forward_rejected',
      'Telegram did not forward the relay message.',
    );
  }
  final messages = <Map<String, dynamic>>[];
  for (final value in rawMessages) {
    if (value is! Map) {
      throw const RichMessageRelayException(
        'forward_rejected',
        'Telegram did not allow this relay message to be copied.',
      );
    }
    messages.add(Map<String, dynamic>.from(value));
  }
  return messages;
}

int? relayMessageIdFromHistory(
  Map<String, dynamic> history, {
  required int botApiMessageId,
  required int botUserId,
  required int sentDate,
  Set<String> expectedContentTypes = const {
    'messageRichMessage',
    'messageRichText',
  },
}) {
  final messages = history.objects('messages') ?? const [];
  final expectedId = botApiMessageId << 20;
  for (final message in messages) {
    final id = message.int64('id');
    if (id == expectedId || id == botApiMessageId) return id;
    if (id != null && id > 0 && (id >> 20) == botApiMessageId) return id;
  }

  Map<String, dynamic>? closest;
  var closestDistance = 31;
  for (final message in messages) {
    final id = message.int64('id');
    final sender = message.obj('sender_id');
    final date = message.integer('date');
    if (id == null ||
        sender?.type != 'messageSenderUser' ||
        sender?.int64('user_id') != botUserId ||
        date == null ||
        !expectedContentTypes.contains(message.obj('content')?.type)) {
      continue;
    }
    final distance = (date - sentDate).abs();
    if (distance <= 30 && distance < closestDistance) {
      closest = message;
      closestDistance = distance;
    }
  }
  return closest?.int64('id');
}

class RichMessageBotRelay {
  RichMessageBotRelay({http.Client? httpClient, Uri? apiBase})
    : _http = httpClient ?? http.Client(),
      _apiBase = apiBase ?? Uri.parse('https://api.telegram.org');

  final http.Client _http;
  final Uri _apiBase;

  void close() => _http.close();

  Future<RichMessageRelayBot> validateToken(String token) async {
    final result = await _call(token, 'getMe');
    final id = result.int64('id');
    if (id == null || id <= 0 || result.boolean('is_bot') != true) {
      throw const RichMessageRelayException(
        'invalid_bot',
        'The token does not identify a Telegram bot.',
      );
    }
    final firstName = result.str('first_name')?.trim() ?? '';
    final username = result.str('username')?.trim() ?? '';
    return RichMessageRelayBot(
      id: id,
      displayName: firstName.isEmpty ? username : firstName,
      username: username,
    );
  }

  Future<RichMessageRelayResult> sendAndCopy({
    required String token,
    required String html,
    required int currentUserId,
    required int targetChatId,
    required TdClient tdClient,
    List<RichMessageSendFile> files = const [],
    RichMessageRelayProgressCallback? onProgress,
  }) async {
    final bot = await validateToken(token);
    final totalSteps = files.length + 3;
    final uploads =
        <({OutgoingAttachmentKind kind, int messageId, int date})>[];
    for (var index = 0; index < files.length; index++) {
      onProgress?.call(
        RichMessageRelayProgress(
          stage: RichMessageRelayStage.upload,
          step: index + 1,
          totalSteps: totalSteps,
          mediaIndex: index + 1,
          mediaCount: files.length,
        ),
      );
      final file = files[index];
      final uploaded = await _uploadMedia(
        token,
        currentUserId,
        file.attachment,
      );
      uploads.add((
        kind: file.attachment.kind,
        messageId: uploaded.messageId,
        date: uploaded.date,
      ));
    }
    onProgress?.call(
      RichMessageRelayProgress(
        stage: RichMessageRelayStage.compose,
        step: files.length + 1,
        totalSteps: totalSteps,
        mediaCount: files.length,
      ),
    );
    Map<String, dynamic>? sent;
    final mediaFallback = files.isNotEmpty;
    if (mediaFallback) {
      final fallbackHtml = stripRichMessageMediaBlocks(html);
      if (fallbackHtml.isNotEmpty) {
        sent = await _call(token, 'sendRichMessage', {
          'chat_id': currentUserId,
          'rich_message': {
            'html': fallbackHtml,
            'is_rtl': false,
            'skip_entity_detection': false,
          },
        });
      }
    } else {
      sent = await _call(token, 'sendRichMessage', {
        'chat_id': currentUserId,
        'rich_message': {
          'html': html,
          'is_rtl': false,
          'skip_entity_detection': false,
        },
      });
    }
    final botApiMessageId = sent?.integer('message_id');
    final sentDate = sent?.integer('date') ?? 0;
    if (!mediaFallback && (botApiMessageId == null || botApiMessageId <= 0)) {
      throw const RichMessageRelayException(
        'missing_message',
        'Telegram did not return the relayed message.',
      );
    }

    final botChat = await tdClient.query({
      '@type': 'createPrivateChat',
      'user_id': bot.id,
      'force': true,
    });
    final fromChatId = botChat.int64('id');
    if (fromChatId == null) {
      throw const RichMessageRelayException(
        'missing_bot_chat',
        'The relay bot chat could not be opened.',
      );
    }

    onProgress?.call(
      RichMessageRelayProgress(
        stage: RichMessageRelayStage.waitForMessage,
        step: files.length + 2,
        totalSteps: totalSteps,
        mediaCount: files.length,
      ),
    );
    final sourceMessageIds = <int>[];
    if (botApiMessageId != null && botApiMessageId > 0) {
      sourceMessageIds.add(
        await _waitForTdMessage(
          tdClient,
          fromChatId,
          botApiMessageId: botApiMessageId,
          botUserId: bot.id,
          sentDate: sentDate,
        ),
      );
    }
    if (mediaFallback) {
      for (final upload in uploads) {
        sourceMessageIds.add(
          await _waitForTdMessage(
            tdClient,
            fromChatId,
            botApiMessageId: upload.messageId,
            botUserId: bot.id,
            sentDate: upload.date,
            expectedContentTypes: _contentTypesForAttachment(upload.kind),
          ),
        );
      }
    }
    if (sourceMessageIds.isEmpty) {
      throw const RichMessageRelayException(
        'missing_message',
        'Telegram did not return the relayed message.',
      );
    }
    var forwarded = false;
    try {
      onProgress?.call(
        RichMessageRelayProgress(
          stage: RichMessageRelayStage.forward,
          step: files.length + 3,
          totalSteps: totalSteps,
          mediaCount: files.length,
        ),
      );
      await _forward(
        tdClient,
        _forwardRequest(
          targetChatId: targetChatId,
          fromChatId: fromChatId,
          sourceMessageIds: sourceMessageIds,
          sendCopy: false,
        ),
      );
      forwarded = true;
      onProgress?.call(
        RichMessageRelayProgress(
          stage: RichMessageRelayStage.forward,
          step: totalSteps,
          totalSteps: totalSteps,
          mediaCount: files.length,
          complete: true,
        ),
      );
    } catch (error) {
      throw RichMessageRelayException('copy_failed', error.toString());
    } finally {
      if (forwarded) {
        final cleanupIds = <int>{
          ?botApiMessageId,
          for (final upload in uploads) upload.messageId,
        };
        for (final messageId in cleanupIds) {
          try {
            await _call(token, 'deleteMessage', {
              'chat_id': currentUserId,
              'message_id': messageId,
            });
          } catch (_) {
            // Cleanup failure must not turn a successful relay into a send failure.
          }
        }
      }
    }
    return const RichMessageRelayResult(senderRemoved: false);
  }

  Future<RichMessageRelayResult> sendAttachmentAndCopy({
    required String token,
    required OutgoingAttachment attachment,
    required int currentUserId,
    required int targetChatId,
    required TdClient tdClient,
    RichMessageRelayProgressCallback? onProgress,
  }) async {
    final bot = await validateToken(token);
    const totalSteps = 4;
    onProgress?.call(
      const RichMessageRelayProgress(
        stage: RichMessageRelayStage.upload,
        step: 1,
        totalSteps: totalSteps,
        mediaIndex: 1,
        mediaCount: 1,
      ),
    );
    final uploaded = await _uploadMedia(token, currentUserId, attachment);
    onProgress?.call(
      const RichMessageRelayProgress(
        stage: RichMessageRelayStage.compose,
        step: 2,
        totalSteps: totalSteps,
        mediaCount: 1,
      ),
    );
    onProgress?.call(
      const RichMessageRelayProgress(
        stage: RichMessageRelayStage.waitForMessage,
        step: 3,
        totalSteps: totalSteps,
        mediaCount: 1,
      ),
    );
    final botChat = await tdClient.query({
      '@type': 'createPrivateChat',
      'user_id': bot.id,
      'force': true,
    });
    final fromChatId = botChat.int64('id');
    if (fromChatId == null) {
      throw const RichMessageRelayException(
        'missing_bot_chat',
        'The relay bot chat could not be opened.',
      );
    }
    final sourceMessageId = await _waitForTdMessage(
      tdClient,
      fromChatId,
      botApiMessageId: uploaded.messageId,
      botUserId: bot.id,
      sentDate: uploaded.date,
      expectedContentTypes: _contentTypesForAttachment(attachment.kind),
    );
    onProgress?.call(
      const RichMessageRelayProgress(
        stage: RichMessageRelayStage.forward,
        step: 4,
        totalSteps: totalSteps,
        mediaCount: 1,
      ),
    );
    final result = await _forwardSourceMessage(
      tdClient,
      targetChatId: targetChatId,
      fromChatId: fromChatId,
      sourceMessageId: sourceMessageId,
    );
    try {
      await _call(token, 'deleteMessage', {
        'chat_id': currentUserId,
        'message_id': uploaded.messageId,
      });
    } catch (_) {}
    onProgress?.call(
      const RichMessageRelayProgress(
        stage: RichMessageRelayStage.forward,
        step: 4,
        totalSteps: totalSteps,
        mediaCount: 1,
        complete: true,
      ),
    );
    return result;
  }

  Future<({String fileId, int messageId, int date})> _uploadMedia(
    String token,
    int chatId,
    OutgoingAttachment attachment,
  ) async {
    final (method, field) = switch (attachment.kind) {
      OutgoingAttachmentKind.photo => ('sendPhoto', 'photo'),
      OutgoingAttachmentKind.video => ('sendVideo', 'video'),
      OutgoingAttachmentKind.animation => ('sendAnimation', 'animation'),
      OutgoingAttachmentKind.audio => ('sendAudio', 'audio'),
      OutgoingAttachmentKind.document => ('sendDocument', 'document'),
    };
    final result = await _callMultipart(
      token,
      method,
      fields: {
        'chat_id': '$chatId',
        if (attachment.caption.trim().isNotEmpty)
          'caption': attachment.caption.trim(),
      },
      field: field,
      path: attachment.path,
    );
    final fileId = _uploadedFileId(result, attachment.kind);
    final messageId = result.integer('message_id');
    if (fileId == null || messageId == null || messageId <= 0) {
      throw const RichMessageRelayException(
        'upload_failed',
        'Telegram did not return the uploaded media.',
      );
    }
    return (
      fileId: fileId,
      messageId: messageId,
      date: result.integer('date') ?? 0,
    );
  }

  String? _uploadedFileId(
    Map<String, dynamic> message,
    OutgoingAttachmentKind kind,
  ) {
    if (kind == OutgoingAttachmentKind.photo) {
      final photo = message['photo'];
      if (photo is List) {
        for (final value in photo.reversed) {
          if (value is Map<String, dynamic>) {
            final id = value.str('file_id');
            if (id != null && id.isNotEmpty) return id;
          }
        }
      }
      return null;
    }
    final key = switch (kind) {
      OutgoingAttachmentKind.video => 'video',
      OutgoingAttachmentKind.animation => 'animation',
      OutgoingAttachmentKind.audio => 'audio',
      OutgoingAttachmentKind.document => 'document',
      OutgoingAttachmentKind.photo => 'photo',
    };
    return message.obj(key)?.str('file_id');
  }

  Set<String> _contentTypesForAttachment(OutgoingAttachmentKind kind) {
    return switch (kind) {
      OutgoingAttachmentKind.photo => const {'messagePhoto'},
      OutgoingAttachmentKind.video => const {'messageVideo'},
      OutgoingAttachmentKind.animation => const {'messageAnimation'},
      OutgoingAttachmentKind.audio => const {'messageAudio'},
      OutgoingAttachmentKind.document => const {'messageDocument'},
    };
  }

  Future<RichMessageRelayResult> _forwardSourceMessage(
    TdClient client, {
    required int targetChatId,
    required int fromChatId,
    required int sourceMessageId,
  }) async {
    await _forward(
      client,
      _forwardRequest(
        targetChatId: targetChatId,
        fromChatId: fromChatId,
        sourceMessageIds: [sourceMessageId],
        sendCopy: false,
      ),
    );
    return const RichMessageRelayResult(senderRemoved: false);
  }

  Map<String, dynamic> _forwardRequest({
    required int targetChatId,
    required int fromChatId,
    required List<int> sourceMessageIds,
    required bool sendCopy,
  }) {
    return {
      '@type': 'forwardMessages',
      'chat_id': targetChatId,
      'from_chat_id': fromChatId,
      'message_ids': sourceMessageIds,
      'options': {'@type': 'messageSendOptions'},
      'send_copy': sendCopy,
      'remove_caption': false,
    };
  }

  Future<int> _waitForTdMessage(
    TdClient client,
    int chatId, {
    required int botApiMessageId,
    required int botUserId,
    required int sentDate,
    Set<String> expectedContentTypes = const {
      'messageRichMessage',
      'messageRichText',
    },
  }) async {
    Object? lastError;
    try {
      await client.query({'@type': 'openChat', 'chat_id': chatId});
    } catch (_) {
      // History loading below also opens/synchronizes the private chat.
    }
    for (var attempt = 0; attempt < 32; attempt++) {
      try {
        final history = await client.query({
          '@type': 'getChatHistory',
          'chat_id': chatId,
          'from_message_id': 0,
          'offset': 0,
          'limit': 50,
          'only_local': false,
        });
        final historyMessageId = relayMessageIdFromHistory(
          history,
          botApiMessageId: botApiMessageId,
          botUserId: botUserId,
          sentDate: sentDate,
          expectedContentTypes: expectedContentTypes,
        );
        if (historyMessageId != null) return historyMessageId;
      } catch (error) {
        lastError = error;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw RichMessageRelayException(
      'message_not_synced',
      lastError?.toString() ?? 'The relay message did not arrive in time.',
    );
  }

  Future<void> _forward(TdClient client, Map<String, dynamic> request) async {
    final response = await client.query(request);
    parseRelayForwardResponse(response);
  }

  Future<Map<String, dynamic>> _call(
    String token,
    String method, [
    Map<String, dynamic>? parameters,
  ]) async {
    final normalizedToken = token.trim();
    if (!RegExp(r'^\d+:[A-Za-z0-9_-]{20,}$').hasMatch(normalizedToken)) {
      throw const RichMessageRelayException(
        'invalid_token',
        'The bot token format is invalid.',
      );
    }
    final endpoint = _apiBase.replace(
      path: '${_apiBase.path}/bot$normalizedToken/$method',
    );
    http.Response response;
    try {
      response = await _http
          .post(
            endpoint,
            headers: const {'content-type': 'application/json'},
            body: jsonEncode(parameters ?? const <String, dynamic>{}),
          )
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const RichMessageRelayException(
        'timeout',
        'Telegram did not respond in time.',
      );
    } catch (_) {
      throw const RichMessageRelayException(
        'network_error',
        'The relay bot could not connect to Telegram.',
      );
    }
    return _decodeApiResponse(response.body, response.statusCode);
  }

  Future<Map<String, dynamic>> _callMultipart(
    String token,
    String method, {
    required Map<String, String> fields,
    required String field,
    required String path,
  }) async {
    final normalizedToken = token.trim();
    if (!RegExp(r'^\d+:[A-Za-z0-9_-]{20,}$').hasMatch(normalizedToken)) {
      throw const RichMessageRelayException(
        'invalid_token',
        'The bot token format is invalid.',
      );
    }
    final endpoint = _apiBase.replace(
      path: '${_apiBase.path}/bot$normalizedToken/$method',
    );
    try {
      final request = http.MultipartRequest('POST', endpoint)
        ..fields.addAll(fields)
        ..files.add(await http.MultipartFile.fromPath(field, path));
      final streamed = await _http
          .send(request)
          .timeout(const Duration(minutes: 5));
      final body = await streamed.stream.bytesToString();
      return _decodeApiResponse(body, streamed.statusCode);
    } on RichMessageRelayException {
      rethrow;
    } on TimeoutException {
      throw const RichMessageRelayException(
        'timeout',
        'Telegram did not respond in time.',
      );
    } catch (_) {
      throw const RichMessageRelayException(
        'network_error',
        'The relay bot could not upload the media.',
      );
    }
  }

  Map<String, dynamic> _decodeApiResponse(String body, int statusCode) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      throw RichMessageRelayException(
        'invalid_response',
        'Telegram returned HTTP $statusCode.',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const RichMessageRelayException(
        'invalid_response',
        'Telegram returned an invalid response.',
      );
    }
    if (decoded['ok'] != true) {
      final description = decoded['description']?.toString().trim();
      final code = description?.toLowerCase().contains('chat not found') == true
          ? 'bot_not_started'
          : 'telegram_error';
      throw RichMessageRelayException(
        code,
        description?.isNotEmpty == true
            ? description!
            : 'Telegram rejected the request.',
      );
    }
    final result = decoded['result'];
    if (result is Map<String, dynamic>) return result;
    return <String, dynamic>{'value': result};
  }
}
