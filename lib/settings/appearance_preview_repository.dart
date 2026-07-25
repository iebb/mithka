import 'dart:async';

import 'package:flutter/foundation.dart';

import '../chat/chat_message_merge.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../tdlib/td_user_index.dart';
import 'blocked_user_service.dart';
import 'keyword_blocker.dart';

typedef AppearancePreviewQuery =
    Future<Map<String, dynamic>> Function(
      Map<String, dynamic> request,
      int clientId,
    );

typedef AppearancePreviewCachedUser =
    Map<String, dynamic>? Function(int accountSlot, int userId);

/// One real TDLib message plus the delivery state used by `MessageBubble`.
///
/// The repository deliberately does not expose message actions. Consumers must
/// render these inside an ignored-pointer preview and leave every action
/// callback unset.
@immutable
class AppearancePreviewMessage {
  const AppearancePreviewMessage({required this.message, required this.isRead});

  final ChatMessage message;
  final bool isRead;
}

/// A small, account-scoped snapshot for appearance-setting previews.
///
/// All content comes from the active TDLib account. The lists are bounded so a
/// settings page cannot accidentally reproduce the chat list's or transcript's
/// loading work.
@immutable
class AppearancePreviewSnapshot {
  const AppearancePreviewSnapshot({
    required this.clientId,
    required this.accountSlot,
    required this.loadedAt,
    required this.meId,
    required this.meName,
    required this.mePhone,
    required this.mePhoto,
    required this.chatRows,
    required this.groupChat,
    required this.transcriptChat,
    required this.messages,
  });

  final int clientId;
  final int accountSlot;
  final DateTime loadedAt;
  final int? meId;
  final String meName;
  final String mePhone;
  final TdFileRef? mePhoto;

  /// The first two chats in TDLib's current main-list order.
  final List<ChatSummary> chatRows;

  /// The first real group/channel among the four inspected main-list chats.
  final ChatSummary? groupChat;

  /// The chat that owns [messages], or null when no safe local transcript was
  /// available. Secret and protected-content chats are never selected.
  final ChatSummary? transcriptChat;

  /// At most three chronological, non-service, plain-text messages.
  final List<AppearancePreviewMessage> messages;

  String get peerTitle => transcriptChat?.title ?? '';
  TdFileRef? get peerPhoto => transcriptChat?.photo;
  bool get isGroup => switch (transcriptChat?.kind) {
    ChatKind.group || ChatKind.channel => true,
    _ => false,
  };
}

class AppearancePreviewRepository {
  AppearancePreviewRepository({
    int Function()? activeClientId,
    int Function()? activeSlot,
    AppearancePreviewQuery? queryTo,
    AppearancePreviewCachedUser? cachedUser,
    DateTime Function()? now,
    this.cacheDuration = const Duration(seconds: 30),
  }) : _activeClientId =
           activeClientId ?? (() => TdClient.shared.activeClientId),
       _activeSlot = activeSlot ?? (() => TdClient.shared.activeSlot),
       _queryTo = queryTo ?? TdClient.shared.queryTo,
       _cachedUser = cachedUser ?? TdUserIndex.shared.userFor,
       _now = now ?? DateTime.now;

  static final AppearancePreviewRepository shared =
      AppearancePreviewRepository();

  static const int inspectedChatLimit = 4;
  static const int renderedChatLimit = 2;
  static const int historyRequestLimit = 12;
  static const int renderedMessageLimit = 3;

  final int Function() _activeClientId;
  final int Function() _activeSlot;
  final AppearancePreviewQuery _queryTo;
  final AppearancePreviewCachedUser _cachedUser;
  final DateTime Function() _now;
  final Duration cacheDuration;

  AppearancePreviewSnapshot? _cached;
  Future<AppearancePreviewSnapshot?>? _inFlight;
  int? _inFlightClientId;
  int _generation = 0;

  /// Loads a bounded snapshot without opening a chat or viewing any messages.
  ///
  /// The only TDLib requests issued here are `getMe`, `getChats`, `getChat`,
  /// and a single local-only `getChatHistory`. Every request is pinned to the
  /// captured client id. A response is discarded if the active account changes
  /// while it is in flight.
  Future<AppearancePreviewSnapshot?> load({bool refresh = false}) {
    final clientId = _activeClientId();
    if (clientId <= 0) return Future.value();

    final cached = _cached;
    if (!refresh &&
        cached != null &&
        cached.clientId == clientId &&
        _now().difference(cached.loadedAt) <= cacheDuration) {
      return Future.value(cached);
    }

    final inFlight = _inFlight;
    if (!refresh && inFlight != null && _inFlightClientId == clientId) {
      return inFlight;
    }

    final generation = ++_generation;
    final accountSlot = _activeSlot();
    final future = _load(
      clientId: clientId,
      accountSlot: accountSlot,
      generation: generation,
    );
    _inFlight = future;
    _inFlightClientId = clientId;
    unawaited(
      future.then<void>(
        (_) {
          if (identical(_inFlight, future)) {
            _inFlight = null;
            _inFlightClientId = null;
          }
        },
        onError: (Object _, StackTrace _) {
          if (identical(_inFlight, future)) {
            _inFlight = null;
            _inFlightClientId = null;
          }
        },
      ),
    );
    return future;
  }

  void invalidate() {
    _generation++;
    _cached = null;
    _inFlight = null;
    _inFlightClientId = null;
  }

  Future<AppearancePreviewSnapshot?> _load({
    required int clientId,
    required int accountSlot,
    required int generation,
  }) async {
    bool isCurrent() =>
        generation == _generation && _activeClientId() == clientId;

    Map<String, dynamic> me;
    Map<String, dynamic> chatIdsResponse;
    try {
      final results = await Future.wait([
        _queryTo({'@type': 'getMe'}, clientId),
        _queryTo({
          '@type': 'getChats',
          'chat_list': {'@type': 'chatListMain'},
          'limit': inspectedChatLimit,
        }, clientId),
      ]);
      if (!isCurrent()) return null;
      me = results[0];
      chatIdsResponse = results[1];
    } catch (_) {
      return null;
    }

    final meId = me.int64('id');
    final meName = TDParse.userName(me);
    final mePhone = TDParse.formatPhone(me.str('phone_number'));
    final mePhoto = TDParse.smallPhoto(me.obj('profile_photo'));
    final ids = (chatIdsResponse.int64Array('chat_ids') ?? const <int>[])
        .take(inspectedChatLimit)
        .toList(growable: false);

    final rawChats = await Future.wait([
      for (final chatId in ids) _getChat(clientId, chatId),
    ]);
    if (!isCurrent()) return null;

    final records = <_PreviewChatRecord>[];
    final rawChatsById = <int, Map<String, dynamic>>{};
    for (final raw in rawChats.whereType<Map<String, dynamic>>()) {
      final summary = TDParse.chat(raw);
      if (summary == null) continue;
      summary.isSavedMessages = meId != null && summary.peerUserId == meId;
      rawChatsById[summary.id] = raw;
      records.add(_PreviewChatRecord(raw: raw, summary: summary));
    }

    for (final record in records) {
      _hydrateChatSummary(
        record.summary,
        accountSlot: accountSlot,
        meId: meId,
        meName: meName,
        mePhoto: mePhoto,
        rawChatsById: rawChatsById,
      );
    }

    final chatRows = List<ChatSummary>.unmodifiable(
      records.take(renderedChatLimit).map((record) => record.summary),
    );
    final groupChat = records
        .map((record) => record.summary)
        .where(
          (chat) =>
              chat.kind == ChatKind.group || chat.kind == ChatKind.channel,
        )
        .firstOrNull;

    final safeRecords = records.where(_isSafeTranscriptChat).toList();
    final transcriptRecord = safeRecords.firstWhere(
      (record) => record.summary.lastChatMessage?.isPlainText == true,
      orElse: () => safeRecords.firstOrNull ?? _PreviewChatRecord.empty,
    );
    final hasTranscriptChat = transcriptRecord.summary.id != 0;
    var messages = <AppearancePreviewMessage>[];
    if (hasTranscriptChat) {
      messages = await _loadMessages(
        clientId: clientId,
        accountSlot: accountSlot,
        record: transcriptRecord,
        meId: meId,
        meName: meName,
        mePhoto: mePhoto,
        rawChatsById: rawChatsById,
      );
      if (!isCurrent()) return null;
    }

    final snapshot = AppearancePreviewSnapshot(
      clientId: clientId,
      accountSlot: accountSlot,
      loadedAt: _now(),
      meId: meId,
      meName: meName,
      mePhone: mePhone,
      mePhoto: mePhoto,
      chatRows: chatRows,
      groupChat: groupChat,
      transcriptChat: hasTranscriptChat ? transcriptRecord.summary : null,
      messages: List<AppearancePreviewMessage>.unmodifiable(messages),
    );
    if (!isCurrent()) return null;
    _cached = snapshot;
    return snapshot;
  }

  Future<Map<String, dynamic>?> _getChat(int clientId, int chatId) async {
    try {
      return await _queryTo({'@type': 'getChat', 'chat_id': chatId}, clientId);
    } catch (_) {
      return null;
    }
  }

  bool _isSafeTranscriptChat(_PreviewChatRecord record) =>
      record.summary.kind != ChatKind.secret &&
      record.raw.boolean('has_protected_content') != true &&
      TDParse.restrictionReasonFor(record.raw) == null;

  Future<List<AppearancePreviewMessage>> _loadMessages({
    required int clientId,
    required int accountSlot,
    required _PreviewChatRecord record,
    required int? meId,
    required String meName,
    required TdFileRef? mePhoto,
    required Map<int, Map<String, dynamic>> rawChatsById,
  }) async {
    List<Map<String, dynamic>> rawMessages = const [];
    try {
      final response = await _queryTo({
        '@type': 'getChatHistory',
        'chat_id': record.summary.id,
        'from_message_id': 0,
        'offset': 0,
        'limit': historyRequestLimit,
        'only_local': true,
      }, clientId);
      rawMessages = response.objects('messages') ?? const [];
    } catch (_) {
      // `getChat.last_message` is still a real, already-cached fallback.
    }

    if (rawMessages.isEmpty) {
      final last = record.raw.obj('last_message');
      if (last != null) rawMessages = [last];
    }

    final parsed =
        rawMessages
            .map(TDParse.message)
            .whereType<ChatMessage>()
            .where(_isSafePreviewMessage)
            .toList()
          ..sort(compareChatMessagesChronologically);
    final bounded = parsed.length <= renderedMessageLimit
        ? parsed
        : parsed.sublist(parsed.length - renderedMessageLimit);
    final lastReadOutboxId =
        record.raw.int64('last_read_outbox_message_id') ?? 0;

    return [
      for (final message in bounded)
        AppearancePreviewMessage(
          message: _hydrateMessage(
            message,
            chat: record.summary,
            accountSlot: accountSlot,
            meId: meId,
            meName: meName,
            mePhoto: mePhoto,
            rawChatsById: rawChatsById,
          ),
          isRead: isOutgoingServerMessageRead(
            message: message,
            lastReadOutboxId: lastReadOutboxId,
          ),
        ),
    ];
  }

  bool _isSafePreviewMessage(ChatMessage message) {
    if (message.isService ||
        !message.isPlainText ||
        message.text.trim().isEmpty ||
        message.isContentRestricted) {
      return false;
    }
    if (KeywordBlocker.shared.isSenderBlocked(message.senderId) ||
        KeywordBlocker.shared.matches(message.text)) {
      return false;
    }
    final senderId = message.senderId;
    return !(BlockedUserService.shared.enabled &&
        senderId != null &&
        senderId > 0 &&
        BlockedUserService.shared.isBlocked(senderId));
  }

  void _hydrateChatSummary(
    ChatSummary summary, {
    required int accountSlot,
    required int? meId,
    required String meName,
    required TdFileRef? mePhoto,
    required Map<int, Map<String, dynamic>> rawChatsById,
  }) {
    final peerUserId = summary.peerUserId;
    if (peerUserId != null) {
      final user = _cachedUser(accountSlot, peerUserId);
      if (user != null) {
        summary.peerIsContact = user.boolean('is_contact') ?? false;
        summary.peerPhoneNumber = user.str('phone_number');
        summary.peerIsPremium = user.boolean('is_premium') ?? false;
        summary.peerAccentColorId = user.integer('accent_color_id') ?? -1;
        summary.peerEmojiStatusId = TDParse.emojiStatusCustomEmojiId(
          user.obj('emoji_status'),
        );
      }
    }
    final last = summary.lastChatMessage;
    if (last == null) return;
    _hydrateMessage(
      last,
      chat: summary,
      accountSlot: accountSlot,
      meId: meId,
      meName: meName,
      mePhoto: mePhoto,
      rawChatsById: rawChatsById,
    );
    if ((summary.kind == ChatKind.group || summary.kind == ChatKind.channel) &&
        (last.senderName?.trim().isNotEmpty ?? false)) {
      summary.lastSender = last.senderName;
    }
  }

  ChatMessage _hydrateMessage(
    ChatMessage message, {
    required ChatSummary chat,
    required int accountSlot,
    required int? meId,
    required String meName,
    required TdFileRef? mePhoto,
    required Map<int, Map<String, dynamic>> rawChatsById,
  }) {
    if (message.isOutgoing && !message.senderIsChat) {
      message.senderName = meName;
      message.senderPhoto = mePhoto;
      return message;
    }
    if (chat.kind != ChatKind.group && chat.kind != ChatKind.channel) {
      message.senderName = message.isOutgoing ? meName : chat.title;
      message.senderPhoto = message.isOutgoing ? mePhoto : chat.photo;
      return message;
    }

    final senderId = message.senderId;
    if (senderId == null) return message;
    if (!message.senderIsChat && senderId > 0) {
      final user = senderId == meId ? null : _cachedUser(accountSlot, senderId);
      if (senderId == meId) {
        message.senderName = meName;
        message.senderPhoto = mePhoto;
      } else if (user != null) {
        message.senderName = TDParse.userName(user);
        message.senderPhoto = TDParse.smallPhoto(user.obj('profile_photo'));
        message.senderIsPremium = user.boolean('is_premium') ?? false;
        message.senderAccentColorId = user.integer('accent_color_id') ?? -1;
        message.senderEmojiStatusId = TDParse.emojiStatusCustomEmojiId(
          user.obj('emoji_status'),
        );
      }
      return message;
    }

    final senderChat = rawChatsById[senderId];
    if (senderChat != null) {
      message.senderName = senderChat.str('title');
      message.senderPhoto = TDParse.smallPhoto(senderChat.obj('photo'));
      message.senderRole = MemberRole.channel;
    }
    return message;
  }
}

class _PreviewChatRecord {
  const _PreviewChatRecord({required this.raw, required this.summary});

  static final empty = _PreviewChatRecord(
    raw: const <String, dynamic>{},
    summary: ChatSummary(
      id: 0,
      title: '',
      lastMessage: '',
      lastMessageId: 0,
      date: 0,
      unreadCount: 0,
      order: 0,
      isMuted: false,
    ),
  );

  final Map<String, dynamic> raw;
  final ChatSummary summary;
}
