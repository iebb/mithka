import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import 'forward_options.dart';
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

Map<String, dynamic> botApiRichMessageMediaPayload(
  OutgoingAttachment attachment,
  String fileId,
) {
  return switch (attachment.kind) {
    OutgoingAttachmentKind.photo => {'type': 'photo', 'media': fileId},
    OutgoingAttachmentKind.video => {
      'type': 'video',
      'media': fileId,
      'supports_streaming': true,
      if ((attachment.width ?? 0) > 0) 'width': attachment.width,
      if ((attachment.height ?? 0) > 0) 'height': attachment.height,
      if (attachment.duration > 0) 'duration': attachment.duration,
    },
    OutgoingAttachmentKind.animation => {
      'type': 'animation',
      'media': fileId,
      if ((attachment.width ?? 0) > 0) 'width': attachment.width,
      if ((attachment.height ?? 0) > 0) 'height': attachment.height,
      if (attachment.duration > 0) 'duration': attachment.duration,
    },
    OutgoingAttachmentKind.audio => {
      'type': 'audio',
      'media': fileId,
      if (attachment.duration > 0) 'duration': attachment.duration,
      if (attachment.title.isNotEmpty) 'title': attachment.title,
      if (attachment.performer.isNotEmpty) 'performer': attachment.performer,
    },
    OutgoingAttachmentKind.voiceNote => {
      'type': 'voice_note',
      'media': fileId,
      if (attachment.duration > 0) 'duration': attachment.duration,
    },
    OutgoingAttachmentKind.document => throw ArgumentError.value(
      attachment.kind,
      'attachment.kind',
      'Documents are not rich-message media',
    ),
  };
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
    await _ensureBotCanMessageUser(
      token: token,
      currentUserId: currentUserId,
      botUserId: bot.id,
      tdClient: tdClient,
    );
    const totalSteps = 3;
    onProgress?.call(
      RichMessageRelayProgress(
        stage: files.isEmpty
            ? RichMessageRelayStage.compose
            : RichMessageRelayStage.upload,
        step: 1,
        totalSteps: totalSteps,
      ),
    );
    final richMessage = <String, dynamic>{
      'html': html,
      if (files.isNotEmpty)
        'media': [
          for (var index = 0; index < files.length; index++)
            {
              'id': files[index].id,
              'media': botApiRichMessageMediaPayload(
                files[index].attachment,
                'attach://rich_media_$index',
              ),
            },
        ],
      'is_rtl': false,
      'skip_entity_detection': false,
    };
    final sent = files.isEmpty
        ? await _call(token, 'sendRichMessage', {
            'chat_id': currentUserId,
            'rich_message': richMessage,
          })
        : await _callMultipartFiles(
            token,
            'sendRichMessage',
            fields: {
              'chat_id': '$currentUserId',
              'rich_message': jsonEncode(richMessage),
            },
            files: [
              for (var index = 0; index < files.length; index++)
                (
                  field: 'rich_media_$index',
                  path: files[index].attachment.path,
                ),
            ],
          );
    final botApiMessageId = sent.integer('message_id');
    final sentDate = sent.integer('date') ?? 0;
    if (botApiMessageId == null || botApiMessageId <= 0) {
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
        step: 2,
        totalSteps: totalSteps,
        mediaCount: files.length,
      ),
    );
    final sourceMessageIds = <int>[];
    sourceMessageIds.add(
      await _waitForTdMessage(
        tdClient,
        fromChatId,
        botApiMessageId: botApiMessageId,
        botUserId: bot.id,
        sentDate: sentDate,
      ),
    );
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
          step: 3,
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
        try {
          await _call(token, 'deleteMessage', {
            'chat_id': currentUserId,
            'message_id': botApiMessageId,
          });
        } catch (_) {
          // Cleanup failure must not turn a successful relay into a send failure.
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
    await _ensureBotCanMessageUser(
      token: token,
      currentUserId: currentUserId,
      botUserId: bot.id,
      tdClient: tdClient,
    );
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

  Future<void> _ensureBotCanMessageUser({
    required String token,
    required int currentUserId,
    required int botUserId,
    required TdClient tdClient,
  }) async {
    try {
      await _call(token, 'getChat', {'chat_id': currentUserId});
      return;
    } on RichMessageRelayException catch (error) {
      if (error.code != 'bot_not_started') rethrow;
    }

    final botChat = await tdClient.query({
      '@type': 'createPrivateChat',
      'user_id': botUserId,
      'force': true,
    });
    final botChatId = botChat.int64('id');
    if (botChatId == null) {
      throw const RichMessageRelayException(
        'missing_bot_chat',
        'The relay bot chat could not be opened.',
      );
    }
    await tdClient.query({
      '@type': 'sendMessage',
      'chat_id': botChatId,
      'input_message_content': {
        '@type': 'inputMessageText',
        'text': {'@type': 'formattedText', 'text': '/start'},
      },
    });

    for (var attempt = 0; attempt < 20; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      try {
        await _call(token, 'getChat', {'chat_id': currentUserId});
        return;
      } on RichMessageRelayException catch (error) {
        if (error.code != 'bot_not_started') rethrow;
      }
    }
    throw const RichMessageRelayException(
      'bot_not_started',
      'Start the relay bot in Telegram before using it.',
    );
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
      OutgoingAttachmentKind.voiceNote => ('sendVoice', 'voice'),
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
      OutgoingAttachmentKind.voiceNote => 'voice',
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
      OutgoingAttachmentKind.voiceNote => const {'messageVoiceNote'},
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
    final fromChatId = request.int64('from_chat_id');
    final messageIds = request.int64Array('message_ids');
    if (fromChatId != null && messageIds != null && messageIds.isNotEmpty) {
      await assertForwardAllowed(
        query: client.query,
        fromChatId: fromChatId,
        messageIds: messageIds,
        options: ForwardOptions(
          removeSender: request.boolean('send_copy') ?? false,
          removeCaption: request.boolean('remove_caption') ?? false,
        ),
      );
    }
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

  Future<Map<String, dynamic>> _callMultipartFiles(
    String token,
    String method, {
    required Map<String, String> fields,
    required List<({String field, String path})> files,
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
        ..fields.addAll(fields);
      for (final file in files) {
        request.files.add(
          await http.MultipartFile.fromPath(file.field, file.path),
        );
      }
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
        'The relay bot could not upload the rich-message media.',
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
      final normalizedDescription = description?.toLowerCase() ?? '';
      final code = switch (normalizedDescription) {
        final value when value.contains('chat not found') => 'bot_not_started',
        final value
            when value.contains('voice_messages_forbidden') ||
                value.contains('restricted receiving of voice note messages') =>
          'voice_messages_forbidden',
        _ => 'telegram_error',
      };
      throw RichMessageRelayException(
        code,
        code == 'voice_messages_forbidden'
            ? 'Telegram privacy settings block voice-note rich messages.'
            : description?.isNotEmpty == true
            ? description!
            : 'Telegram rejected the request.',
      );
    }
    final result = decoded['result'];
    if (result is Map<String, dynamic>) return result;
    return <String, dynamic>{'value': result};
  }
}
