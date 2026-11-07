//
//  message_history_models.dart
//
//  Data model shared by the kept-message mirror (store, viewer, per-message
//  revision sheet). Every record is owned by the account whose TDLib client
//  received it. Part of the Telegram API Terms §1.4 feature set; see
//  message_history_store.dart for the guard design.
//

import 'package:flutter/foundation.dart';

/// What the counterpart did to a mirrored message.
enum MessageHistoryState {
  /// The message still exists in the chat.
  active,

  /// The counterpart deleted the message; the copy is kept here only.
  deleted,
}

@immutable
class MessageHistoryEvent {
  const MessageHistoryEvent({
    required this.at,
    required this.oldText,
    required this.newText,
    this.editDate = 0,
  });

  /// Unix seconds at which mithka observed the change.
  final int at;

  /// Text before the change, or null when unknown (e.g. the mirror was
  /// populated by an older build).
  final String? oldText;

  /// Text after the change.
  final String newText;

  /// TDLib's edit_date for the edit that caused the event, 0 if unknown.
  final int editDate;

  Map<String, Object?> toJson() => {
    'at': at,
    'old': oldText,
    'new': newText,
    'editDate': editDate,
  };

  static MessageHistoryEvent? fromJson(Object? json) {
    if (json is! Map) return null;
    final at = json['at'];
    final newText = json['new'];
    if (at is! int || newText is! String) return null;
    final oldText = json['old'];
    final editDate = json['editDate'];
    return MessageHistoryEvent(
      at: at,
      oldText: oldText is String ? oldText : null,
      newText: newText,
      editDate: editDate is int ? editDate : 0,
    );
  }
}

/// One kept copy of one message, together with its edit trail and the media
/// snapshot path (when the media was already fully on disk when the message
/// was observed).
@immutable
class MessageHistoryEntry {
  const MessageHistoryEntry({
    required this.accountUserId,
    required this.chatId,
    required this.messageId,
    required this.senderId,
    required this.date,
    required this.text,
    required this.kindKey,
    required this.state,
    required this.deletedAt,
    required this.events,
    this.mediaPath = '',
    this.hasLiveChat = true,
  });

  /// User id of the account that received the message. Two accounts that see
  /// the same chat/message ids keep two separate records.
  final int accountUserId;

  final int chatId;
  final int messageId;

  /// A user id (positive) or, when the chat itself posted, that chat's id
  /// (negative). Display names are resolved on view, never stored.
  final int senderId;

  /// Unix seconds the message was originally sent.
  final int date;

  /// Latest known text, or the caption for media messages. Empty for media
  /// without a caption — [kindKey] then names the content.
  final String text;

  /// Content kind suffix (e.g. `historyKindPhoto`); empty for plain text.
  final String kindKey;

  final MessageHistoryState state;

  /// Unix seconds at which the deletion was observed, 0 while active.
  final int deletedAt;

  /// Content changes in observation order (oldest first).
  final List<MessageHistoryEvent> events;

  /// Path of the mirrored media file inside the mirror's attachment
  /// directory, empty when no snapshot exists.
  final String mediaPath;

  /// False once TDLib reported the chat gone (deleted account/chat): the
  /// kept copy renders in the ghost style because there is no chat to open.
  final bool hasLiveChat;

  bool get isEdited => events.isNotEmpty;

  String get key => '$accountUserId:$chatId:$messageId';

  /// Localized kind label key; [AppStringKeys.historyKindUnknown] when the
  /// kind cannot be named.
  String kindLabel() => kindKey.isEmpty ? '' : kindKey;

  @override
  bool operator ==(Object other) =>
      other is MessageHistoryEntry &&
      other.accountUserId == accountUserId &&
      other.chatId == chatId &&
      other.messageId == messageId &&
      other.senderId == senderId &&
      other.date == date &&
      other.text == text &&
      other.kindKey == kindKey &&
      other.state == state &&
      other.deletedAt == deletedAt &&
      other.mediaPath == mediaPath &&
      other.hasLiveChat == hasLiveChat &&
      listEquals(other.events, events);

  @override
  int get hashCode => Object.hash(
    accountUserId,
    chatId,
    messageId,
    senderId,
    date,
    text,
    kindKey,
    state,
    deletedAt,
    mediaPath,
    hasLiveChat,
    Object.hashAll(events),
  );

  MessageHistoryEntry copyWith({
    int? accountUserId,
    String? text,
    String? kindKey,
    int? senderId,
    MessageHistoryState? state,
    int? deletedAt,
    List<MessageHistoryEvent>? events,
    String? mediaPath,
    bool? hasLiveChat,
  }) => MessageHistoryEntry(
    accountUserId: accountUserId ?? this.accountUserId,
    chatId: chatId,
    messageId: messageId,
    senderId: senderId ?? this.senderId,
    date: date,
    text: text ?? this.text,
    kindKey: kindKey ?? this.kindKey,
    state: state ?? this.state,
    deletedAt: deletedAt ?? this.deletedAt,
    events: events ?? this.events,
    mediaPath: mediaPath ?? this.mediaPath,
    hasLiveChat: hasLiveChat ?? this.hasLiveChat,
  );

  Map<String, Object?> toJson() => {
    'account': accountUserId,
    'chat': chatId,
    'id': messageId,
    'sender': senderId,
    'date': date,
    'text': text,
    'kind': kindKey,
    'state': state.name,
    'deletedAt': deletedAt,
    'events': [for (final event in events) event.toJson()],
    if (mediaPath.isNotEmpty) 'media': mediaPath,
    if (!hasLiveChat) 'noChat': true,
  };

  /// Entries without an 'account' field (mirror files from before the
  /// account identity existed) are dropped on load: an entry whose owning
  /// account is unknown must never be attributed to whichever account
  /// happens to be active.
  static MessageHistoryEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final account = json['account'];
    final chat = json['chat'];
    final id = json['id'];
    final date = json['date'];
    final text = json['text'];
    if (account is! int ||
        chat is! int ||
        id is! int ||
        date is! int ||
        text is! String) {
      return null;
    }
    final sender = json['sender'];
    final kind = json['kind'];
    final state = json['state'];
    final deletedAt = json['deletedAt'];
    final events = json['events'];
    final media = json['media'];
    final noChat = json['noChat'];
    return MessageHistoryEntry(
      accountUserId: account,
      chatId: chat,
      messageId: id,
      senderId: sender is int ? sender : 0,
      date: date,
      text: text,
      kindKey: kind is String ? kind : '',
      state: state == 'deleted'
          ? MessageHistoryState.deleted
          : MessageHistoryState.active,
      deletedAt: deletedAt is int ? deletedAt : 0,
      events: events is List
          ? events
                .map(MessageHistoryEvent.fromJson)
                .whereType<MessageHistoryEvent>()
                .toList()
          : const [],
      mediaPath: media is String ? media : '',
      hasLiveChat: noChat is bool ? !noChat : true,
    );
  }
}
