part of 'chat_view_model.dart';

typedef MessageTranslationResult = ({
  String text,
  List<MessageTextEntity> entities,
  String languageCode,
});

@visibleForTesting
String resolvedCommunityServiceText({
  required String contentType,
  required String actorName,
  String communityName = '',
}) {
  if (contentType == 'messageChatAddedToCommunity' &&
      actorName.isNotEmpty &&
      communityName.isNotEmpty) {
    return AppStrings.t(AppStringKeys.communityChatAddedByService, {
      'value1': actorName,
      'value2': communityName,
    });
  }
  if (contentType == 'messageChatRemovedFromCommunity' &&
      actorName.isNotEmpty) {
    return AppStrings.t(AppStringKeys.communityChatRemovedByService, {
      'value1': actorName,
    });
  }
  return AppStrings.t(
    contentType == 'messageChatRemovedFromCommunity'
        ? AppStringKeys.communityChatRemovedService
        : AppStringKeys.communityChatAddedService,
  );
}

class _SenderInfo {
  _SenderInfo(
    this.name,
    this.photo,
    this.role,
    this.title, {
    this.isPremium = false,
    this.isDeleted = false,
    this.accentColorId = -1,
    this.emojiStatusId = 0,
  });
  final String name;
  final TdFileRef? photo;
  final MemberRole role;
  final String? title;
  final bool isPremium;

  /// TDLib reported `userTypeDeleted`: the account no longer exists, so it has
  /// no profile to open and nothing to report.
  final bool isDeleted;
  final int accentColorId;
  final int emojiStatusId;
}

@visibleForTesting
int unreadMentionCountAfterReading(int currentCount, int readCount) =>
    math.max(0, currentCount - math.max(0, readCount));

@visibleForTesting
int unreadReactionCountAfterReading(int currentCount, int readCount) =>
    math.max(0, currentCount - math.max(0, readCount));

@visibleForTesting
int? messageSendUpdateChatId(Map<String, dynamic> update) =>
    update.int64('chat_id') ?? update.obj('message')?.int64('chat_id');

/// Message contents whose attachment a live update can replace outright.
const _mediaContentTypes = {
  'messagePhoto',
  'messageVideo',
  'messageAnimation',
  'messageVideoNote',
  'messageVoiceNote',
  'messageAudio',
  'messageDocument',
  'messageSticker',
};

/// Whether a live content update has to re-read the message from TDLib.
///
/// Editing a message can swap its media for a different kind entirely, and the
/// in-place merge only ever hydrated an outgoing video — an edited message kept
/// whatever attachment it had before, including a thumbnail path whose file
/// TDLib had already deleted. A message that is still uploading keeps that
/// merge instead, because only the local copy knows where its source file is.
@visibleForTesting
bool mediaContentUpdateNeedsRefresh({
  required String? contentType,
  required bool isSending,
}) {
  if (contentType == null || !_mediaContentTypes.contains(contentType)) {
    return false;
  }
  return !(isSending && contentType == 'messageVideo');
}

class _MessageSendResult {
  const _MessageSendResult.success() : error = null;
  const _MessageSendResult.failure(this.error);

  final TdError? error;
}

bool _isVoiceMessageRestrictionError(Object error) {
  final normalized = error.toString().toUpperCase();
  return normalized.contains('VOICE_MESSAGES_FORBIDDEN') ||
      normalized.contains('CHAT_SEND_VOICES_FORBIDDEN');
}

class _ChatActionInfo {
  const _ChatActionInfo(this.name, this.actionType);

  final String name;
  final String actionType;
}

class MessageSenderOption {
  const MessageSenderOption({
    required this.sender,
    required this.id,
    required this.title,
    this.photo,
    this.needsPremium = false,
  });

  final Map<String, dynamic> sender;
  final int id;
  final String title;
  final TdFileRef? photo;
  final bool needsPremium;

  bool sameSender(Map<String, dynamic>? other) {
    if (other == null || other.type != sender.type) return false;
    return switch (sender.type) {
      'messageSenderUser' => other.int64('user_id') == id,
      'messageSenderChat' => other.int64('chat_id') == id,
      _ => false,
    };
  }
}

@visibleForTesting
MessageSenderOption? preferredMessageSenderOption(
  List<MessageSenderOption> options, {
  Map<String, dynamic>? preferredSender,
  MessageSenderOption? current,
}) {
  if (current != null &&
      options.any((option) => option.sameSender(current.sender))) {
    return options.firstWhere((option) => option.sameSender(current.sender));
  }
  if (preferredSender != null) {
    for (final option in options) {
      if (option.sameSender(preferredSender)) return option;
    }
  }
  return options.isEmpty ? null : options.first;
}

class MentionCandidate {
  const MentionCandidate({
    required this.userId,
    required this.name,
    this.username = '',
    this.photo,
    this.isDeleted = false,
    this.isInlineBot = false,
  });

  final int userId;
  final String name;
  final String username;
  final TdFileRef? photo;
  final bool isDeleted;
  final bool isInlineBot;
}

class MessageReactionUser {
  const MessageReactionUser({
    required this.senderId,
    required this.title,
    this.photo,
    this.date = 0,
    this.isDeleted = false,
  });

  final int senderId;
  final String title;
  final TdFileRef? photo;
  final int date;

  /// The account behind the reaction no longer exists.
  final bool isDeleted;
}

class BotCommandOption {
  const BotCommandOption({
    required this.command,
    required this.description,
    this.botUserId = 0,
    this.botName = '',
    this.botUsername = '',
    this.botPhoto,
  });

  final String command;
  final String description;
  final int botUserId;
  final String botName;
  final String botUsername;
  final TdFileRef? botPhoto;

  String get normalizedCommand =>
      command.trim().replaceFirst(RegExp(r'^/+'), '');

  String get displayCommand => '/$normalizedCommand';

  String get targetedCommand {
    final username = botUsername.trim().replaceFirst(RegExp(r'^@+'), '');
    return username.isEmpty ? displayCommand : '$displayCommand@$username';
  }
}

typedef BotCommandUserLoader =
    Future<Map<String, dynamic>?> Function(int userId);

@visibleForTesting
Future<List<BotCommandOption>> resolveGroupBotCommandOptions(
  Map<String, dynamic> fullInfo,
  BotCommandUserLoader loadUser,
) async {
  final groups =
      fullInfo.objects('bot_commands') ?? const <Map<String, dynamic>>[];
  final resolved = await Future.wait(
    groups.map((group) async {
      final botUserId = group.int64('bot_user_id');
      if (botUserId == null || botUserId <= 0) {
        return const <BotCommandOption>[];
      }

      final user = await loadUser(botUserId);
      final username = _primaryBotUsername(user);
      final parsedName = user == null ? '' : TDParse.userName(user).trim();
      final botName = parsedName.isNotEmpty
          ? parsedName
          : username.isNotEmpty
          ? username
          : 'Bot';
      final photo = user == null
          ? null
          : TDParse.smallPhoto(user.obj('profile_photo'));

      return (group.objects('commands') ?? const <Map<String, dynamic>>[])
          .map(
            (command) => BotCommandOption(
              command: command.str('command') ?? '',
              description: command.str('description') ?? '',
              botUserId: botUserId,
              botName: botName,
              botUsername: username,
              botPhoto: photo,
            ),
          )
          .where((command) => command.normalizedCommand.isNotEmpty)
          .toList(growable: false);
    }),
  );
  return List.unmodifiable(resolved.expand((commands) => commands));
}

String _primaryBotUsername(Map<String, dynamic>? user) {
  if (user == null) return '';
  final usernames = user.obj('usernames');
  final active = usernames?['active_usernames'];
  if (active is List) {
    for (final username in active.whereType<String>()) {
      final normalized = username.trim().replaceFirst(RegExp(r'^@+'), '');
      if (normalized.isNotEmpty) return normalized;
    }
  }
  return (usernames?.str('editable_username') ?? '').trim().replaceFirst(
    RegExp(r'^@+'),
    '',
  );
}

class BotMenuInfo {
  const BotMenuInfo({required this.type, this.text = '', this.url = ''});

  final String type;
  final String text;
  final String url;

  bool get isWebApp => type == 'botMenuButton' && url.isNotEmpty;
  bool get isLegacyMenuUrl => url.startsWith('menu://');
  String get webAppUrl => isLegacyMenuUrl ? '' : url;
  String get actionTitle => text.trim().isEmpty ? 'Open' : text.trim();
  bool get opensCommands =>
      type == 'botMenuButtonCommands' || type == 'botMenuButtonDefault';
}

class ForumTopicOption {
  const ForumTopicOption({
    required this.id,
    required this.name,
    this.iconCustomEmojiId = 0,
    this.iconColor = 0,
    this.unreadCount = 0,
    this.isMuted = false,
    this.isPinned = false,
    this.isGeneral = false,
    this.isClosed = false,
    this.creatorId = 0,
    this.lastPreview = '',
    this.lastSender,
    this.lastMessageDate = 0,
    this.lastMessageId = 0,
  });

  final int id;
  final String name;
  final int iconCustomEmojiId;
  final int iconColor;

  /// Live unread messages in this topic, maintained through the shared topic
  /// index; 0 when unknown.
  final int unreadCount;
  final bool isMuted;

  /// Order and row badges a chat-list-style topic row draws: pinned marker,
  /// the General avatar rule and the closed lock. The page from getForumTopics
  /// carries them; live updates patch them in place.
  final bool isPinned;

  /// The General topic (id 1): shows the chat avatar and cannot be deleted.
  final bool isGeneral;
  final bool isClosed;

  /// Topic creator's user id, 0 when unknown. The creator may delete their
  /// own topic even without can_manage_topics (TDLib enforces the rest).
  final int creatorId;

  /// Last-message preview text with media/service placeholders already
  /// composed the way the chat list composes them; empty hides the line.
  final String lastPreview;

  /// Sender prefix for [lastPreview] ("Alice", "You:"); null for none.
  final String? lastSender;

  /// Unix seconds of the last message; 0 hides the timestamp.
  final int lastMessageDate;

  /// The newest message id this row has seen — mark-read views it.
  final int lastMessageId;

  /// Display-field equality: a republished list that changed nothing must not
  /// re-notify a listening topic list.
  bool sameDisplay(ForumTopicOption other) =>
      id == other.id &&
      name == other.name &&
      iconCustomEmojiId == other.iconCustomEmojiId &&
      iconColor == other.iconColor &&
      unreadCount == other.unreadCount &&
      isMuted == other.isMuted &&
      isPinned == other.isPinned &&
      isGeneral == other.isGeneral &&
      isClosed == other.isClosed &&
      creatorId == other.creatorId &&
      lastPreview == other.lastPreview &&
      lastSender == other.lastSender &&
      lastMessageDate == other.lastMessageDate &&
      lastMessageId == other.lastMessageId;

  ForumTopicOption _withIndex(ForumTopicIndexEntry entry) => ForumTopicOption(
    id: entry.id,
    name: entry.name,
    iconCustomEmojiId: entry.iconCustomEmojiId,
    iconColor: entry.iconColor,
    unreadCount: entry.unreadCount,
    isMuted: entry.isMuted,
    isPinned: isPinned,
    isGeneral: isGeneral,
    isClosed: isClosed,
    creatorId: creatorId,
    lastPreview: lastPreview,
    lastSender: lastSender,
    lastMessageDate: lastMessageDate,
    // The index can know a newer message than a stale page row: keep the
    // newer id so a later mark-read targets live traffic, not the old page.
    lastMessageId: entry.lastMessageId > lastMessageId
        ? entry.lastMessageId
        : lastMessageId,
  );

  /// The same row with a new unread counter, every other field untouched.
  ForumTopicOption _withUnreadCount(int unread) => ForumTopicOption(
    id: id,
    name: name,
    iconCustomEmojiId: iconCustomEmojiId,
    iconColor: iconColor,
    unreadCount: unread,
    isMuted: isMuted,
    isPinned: isPinned,
    isGeneral: isGeneral,
    isClosed: isClosed,
    creatorId: creatorId,
    lastPreview: lastPreview,
    lastSender: lastSender,
    lastMessageDate: lastMessageDate,
    lastMessageId: lastMessageId,
  );
}

class _DraftMention {
  const _DraftMention({required this.text, required this.userId});

  final String text;
  final int userId;
}

/// TDLib's `message_caption_length_max` without Premium, used when the option
/// cannot be read.
const defaultMessageCaptionLengthLimit = 1024;
