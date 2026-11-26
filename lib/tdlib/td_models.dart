//
//  td_models.dart
//
//  View-facing models parsed from TDLib JSON, plus content→text helpers.
//  The Flutter port of the Swift `TDModels` / `TDParse`.
//

import 'dart:convert';

import 'package:dlibphonenumber/dlibphonenumber.dart';
import 'package:flutter/foundation.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/l10n/gram_amount.dart';
import 'package:mithka/notifications/scope_notification_settings.dart';

import '../history/message_history_models.dart';
import 'json_helpers.dart';
import 'message_gift.dart';
import 'message_gram_transfer.dart';

export 'message_gift.dart';
export 'message_gram_transfer.dart';

part 'td_parse.dart';

/// Reference to a downloadable TDLib file (profile photo, thumbnail, …).
class TdFileRef {
  TdFileRef({
    required this.id,
    this.localPath,
    this.fileName,
    this.mimeType,
    this.size,
    this.miniThumb,
    this.thumbnail,
    this.hasAnimation = false,
    this.photoId,
  });
  final int id;
  final String? localPath;
  final String? fileName;
  final String? mimeType;

  /// Bytes TDLib knows for this file: the real size once it is known,
  /// otherwise the server's estimate. Null when neither is available.
  final int? size;
  final bool hasAnimation;
  final int? photoId;
  Uint8List? miniThumb; // decoded JPEG for instant placeholder
  TdFileRef? thumbnail; // downloadable thumbnail with the real aspect ratio

  TdFileRef inheritLocalPathFrom(TdFileRef? previous) {
    return TdFileRef(
      id: id,
      localPath: _usablePath(localPath) ?? _usablePath(previous?.localPath),
      fileName: _usablePath(fileName) ?? _usablePath(previous?.fileName),
      mimeType: _usablePath(mimeType) ?? _usablePath(previous?.mimeType),
      size: size ?? previous?.size,
      miniThumb: miniThumb ?? previous?.miniThumb,
      hasAnimation: hasAnimation || (previous?.hasAnimation ?? false),
      photoId: photoId ?? previous?.photoId,
      thumbnail:
          thumbnail?.inheritLocalPathFrom(previous?.thumbnail) ??
          previous?.thumbnail,
    );
  }

  static String? _usablePath(String? path) {
    final value = path?.trim();
    return value == null || value.isEmpty ? null : value;
  }
}

/// Categories surfaced by the search hub and the media browser.
enum ChatMediaCategory {
  media, // 图片/视频
  file, // 文件
  audio, // 音频/音乐
  link, // 链接
  sticker, // 表情
  voice, // 语音
  member; // 群成员

  String get title => switch (this) {
    ChatMediaCategory.media => AppStrings.t(AppStringKeys.tdMessagePhotoVideo),
    ChatMediaCategory.file => AppStrings.t(AppStringKeys.topicPostContentFile),
    ChatMediaCategory.audio => AppStrings.t(AppStringKeys.composerAudio),
    ChatMediaCategory.link => AppStrings.t(AppStringKeys.sharedMediaLinks),
    ChatMediaCategory.sticker => AppStrings.t(AppStringKeys.tdMessageSticker),
    ChatMediaCategory.voice => AppStrings.t(AppStringKeys.sharedMediaVoice),
    ChatMediaCategory.member => AppStrings.t(
      AppStringKeys.chatInfoGroupMembers,
    ),
  };

  /// The TDLib SearchMessagesFilter `@type`, or null for non-message categories.
  String? get tdFilter => switch (this) {
    ChatMediaCategory.media => 'searchMessagesFilterPhotoAndVideo',
    ChatMediaCategory.file => 'searchMessagesFilterDocument',
    ChatMediaCategory.audio => 'searchMessagesFilterAudio',
    ChatMediaCategory.link => 'searchMessagesFilterUrl',
    ChatMediaCategory.sticker => 'searchMessagesFilterAnimation',
    ChatMediaCategory.voice => 'searchMessagesFilterVoiceNote',
    ChatMediaCategory.member => null,
  };

  String get emptyText => switch (this) {
    ChatMediaCategory.media => AppStrings.t(
      AppStringKeys.tdMessageNoPhotoVideo,
    ),
    ChatMediaCategory.file => AppStrings.t(AppStringKeys.tdMessageNoFiles),
    ChatMediaCategory.audio => AppStrings.t(AppStringKeys.tdMessageNoAudio),
    ChatMediaCategory.link => AppStrings.t(AppStringKeys.tdMessageNoLinks),
    ChatMediaCategory.sticker => AppStrings.t(
      AppStringKeys.tdMessageNoStickers,
    ),
    ChatMediaCategory.voice => AppStrings.t(AppStringKeys.tdMessageNoVoice),
    ChatMediaCategory.member => AppStrings.t(AppStringKeys.tdMessageNoMembers),
  };
}

enum ChatKind { privateChat, group, channel, bot, secret, unknown }

/// A custom (premium) emoji span in a message's text — covers [length] UTF-16
/// units at [offset], rendered inline from custom_emoji_id [id].
class CustomEmojiEntity {
  const CustomEmojiEntity(this.offset, this.length, this.id);
  final int offset;
  final int length;
  final int id;
}

/// A TDLib formattedText entity in message text/caption. Offsets and lengths
/// are UTF-16 code units, matching Dart String indexing.
class MessageTextEntity {
  const MessageTextEntity({
    required this.offset,
    required this.length,
    required this.type,
    this.url,
    this.userId,
    this.customEmojiId,
    this.language,
    this.button,
    this.typeData = const {},
  });

  final int offset;
  final int length;
  final String type;
  final String? url;
  final int? userId;
  final int? customEmojiId;
  final String? language;
  final MessageButton? button;

  /// Full TDLib `TextEntityType` payload, including fields introduced after
  /// this client was built. Known convenience fields above remain available.
  final Map<String, dynamic> typeData;

  int get end => offset + length;
  bool get isCustomEmoji => type == 'textEntityTypeCustomEmoji';
  bool get isBlockQuote =>
      type == 'textEntityTypeBlockQuote' ||
      type == 'textEntityTypeExpandableBlockQuote';
  bool get isExpandableBlockQuote =>
      type == 'textEntityTypeExpandableBlockQuote';
  bool get isPreBlock =>
      type == 'textEntityTypePre' || type == 'textEntityTypePreCode';
  bool get isMathematicalExpression =>
      type == 'textEntityTypeMathematicalExpression';

  Map<String, dynamic> toTdJson() {
    final entityType = <String, dynamic>{...typeData, '@type': type};
    if (url != null) entityType['url'] = url;
    if (userId != null) entityType['user_id'] = userId;
    if (customEmojiId != null) {
      entityType['custom_emoji_id'] = customEmojiId.toString();
    }
    if (language != null) entityType['language'] = language;
    return {
      '@type': 'textEntity',
      'offset': offset,
      'length': length,
      'type': entityType,
    };
  }
}

/// A server quote or a manually selected UTF-16 range from a message.
class MessageTextQuote {
  const MessageTextQuote({
    required this.text,
    required this.position,
    this.entities = const [],
    this.isManual = true,
  });

  final String text;
  final int position;
  final List<MessageTextEntity> entities;
  final bool isManual;

  Map<String, dynamic> toInputJson() => {
    '@type': 'inputTextQuote',
    'text': {
      '@type': 'formattedText',
      'text': text,
      'entities': [for (final entity in entities) entity.toTdJson()],
    },
    'position': position,
  };
}

class RichMessageTableCell {
  const RichMessageTableCell({
    required this.text,
    this.entities = const [],
    this.isHeader = false,
    this.horizontalAlignment = 'left',
    this.verticalAlignment = 'top',
  });

  final String text;
  final List<MessageTextEntity> entities;
  final bool isHeader;
  final String horizontalAlignment;
  final String verticalAlignment;
}

enum RichMessageBlockKind {
  paragraph,
  heading,
  preformatted,
  footer,
  thinking,
  divider,
  math,
  anchor,
  buttonRow,
  list,
  blockQuote,
  pullQuote,
  animation,
  audio,
  photo,
  video,
  voiceNote,
  document,
  collage,
  slideshow,
  table,
  details,
  map,
}

class RichMessageListItem {
  const RichMessageListItem({
    required this.blocks,
    this.label = '',
    this.hasCheckbox = false,
    this.isChecked = false,
    this.value = 0,
    this.numberingType = '',
  });

  final List<RichMessageBlock> blocks;
  final String label;
  final bool hasCheckbox;
  final bool isChecked;
  final int value;
  final String numberingType;
}

class RichMessageBlock {
  const RichMessageBlock._({
    required this.kind,
    this.text = '',
    this.textEntities = const [],
    this.size = 0,
    this.language = '',
    this.name = '',
    this.children = const [],
    this.listItems = const [],
    this.isOpen = false,
    this.image,
    this.imageWidth,
    this.imageHeight,
    this.video,
    this.videoDuration = 0,
    this.music,
    this.voice,
    this.document,
    this.hasSpoiler = false,
    this.tableRows = const [],
    this.mathExpression,
    this.mapLocation,
    this.mapZoom = 16,
    this.mapWidth = 0,
    this.mapHeight = 0,
    this.caption = '',
    this.captionEntities = const [],
    this.isBordered = false,
    this.isStriped = false,
    this.buttons = const [],
    this.horizontalAlignment = 'left',
  });

  const RichMessageBlock.text({
    required RichMessageBlockKind kind,
    required String text,
    List<MessageTextEntity> entities = const [],
    int size = 0,
    String language = '',
  }) : this._(
         kind: kind,
         text: text,
         textEntities: entities,
         size: size,
         language: language,
       );

  const RichMessageBlock.container({
    required RichMessageBlockKind kind,
    List<RichMessageBlock> children = const [],
    List<RichMessageListItem> listItems = const [],
    String text = '',
    List<MessageTextEntity> textEntities = const [],
    bool isOpen = false,
    String name = '',
    String caption = '',
    List<MessageTextEntity> captionEntities = const [],
  }) : this._(
         kind: kind,
         children: children,
         listItems: listItems,
         text: text,
         textEntities: textEntities,
         isOpen: isOpen,
         name: name,
         caption: caption,
         captionEntities: captionEntities,
       );

  const RichMessageBlock.media({
    required RichMessageBlockKind kind,
    TdFileRef? image,
    int? imageWidth,
    int? imageHeight,
    TdFileRef? video,
    int videoDuration = 0,
    MessageMusic? music,
    MessageVoice? voice,
    MessageDocument? document,
    bool hasSpoiler = false,
    String caption = '',
    List<MessageTextEntity> captionEntities = const [],
  }) : this._(
         kind: kind,
         image: image,
         imageWidth: imageWidth,
         imageHeight: imageHeight,
         video: video,
         videoDuration: videoDuration,
         music: music,
         voice: voice,
         document: document,
         hasSpoiler: hasSpoiler,
         caption: caption,
         captionEntities: captionEntities,
       );

  const RichMessageBlock.table(
    List<List<RichMessageTableCell>> tableRows, {
    bool isBordered = true,
    bool isStriped = false,
  }) : this._(
         kind: RichMessageBlockKind.table,
         tableRows: tableRows,
         isBordered: isBordered,
         isStriped: isStriped,
       );

  const RichMessageBlock.math(String? expression)
    : this._(kind: RichMessageBlockKind.math, mathExpression: expression);

  const RichMessageBlock.buttonRow(
    List<MessageButton> buttons, {
    String horizontalAlignment = 'left',
  }) : this._(
         kind: RichMessageBlockKind.buttonRow,
         buttons: buttons,
         horizontalAlignment: horizontalAlignment,
       );

  const RichMessageBlock.map({
    required MessageLocation? mapLocation,
    int mapZoom = 16,
    int mapWidth = 220,
    int mapHeight = 120,
    String caption = '',
    List<MessageTextEntity> captionEntities = const [],
  }) : this._(
         kind: RichMessageBlockKind.map,
         mapLocation: mapLocation,
         mapZoom: mapZoom,
         mapWidth: mapWidth,
         mapHeight: mapHeight,
         caption: caption,
         captionEntities: captionEntities,
       );

  const RichMessageBlock.captionedTable({
    required List<List<RichMessageTableCell>> tableRows,
    String caption = '',
    List<MessageTextEntity> captionEntities = const [],
    bool isBordered = true,
    bool isStriped = false,
  }) : this._(
         kind: RichMessageBlockKind.table,
         tableRows: tableRows,
         caption: caption,
         captionEntities: captionEntities,
         isBordered: isBordered,
         isStriped: isStriped,
       );

  final RichMessageBlockKind kind;
  final String text;
  final List<MessageTextEntity> textEntities;
  final int size;
  final String language;
  final String name;
  final List<RichMessageBlock> children;
  final List<RichMessageListItem> listItems;
  final bool isOpen;
  final TdFileRef? image;
  final int? imageWidth;
  final int? imageHeight;
  final TdFileRef? video;
  final int videoDuration;
  final MessageMusic? music;
  final MessageVoice? voice;

  /// The attached file of a [RichMessageBlockKind.document] block.
  final MessageDocument? document;
  final bool hasSpoiler;

  final List<List<RichMessageTableCell>> tableRows;
  final String? mathExpression;
  final MessageLocation? mapLocation;
  final int mapZoom;
  final int mapWidth;
  final int mapHeight;
  final String caption;
  final List<MessageTextEntity> captionEntities;
  final bool isBordered;
  final bool isStriped;
  final List<MessageButton> buttons;
  final String horizontalAlignment;

  bool get isTable => kind == RichMessageBlockKind.table;
  bool get isMath => kind == RichMessageBlockKind.math;
  bool get isMap => kind == RichMessageBlockKind.map;
}

class _ParsedMarkdownText {
  const _ParsedMarkdownText(this.text, this.entities);

  final String text;
  final List<MessageTextEntity> entities;
}

class _RichTextBuilder {
  final buffer = StringBuffer();
  final entities = <MessageTextEntity>[];

  int get length => buffer.length;
  bool get isEmpty => buffer.isEmpty;

  void write(String text) => buffer.write(text);

  void blankLine() {
    if (buffer.isEmpty) return;
    final text = buffer.toString();
    if (text.endsWith('\n\n')) return;
    if (text.endsWith('\n')) {
      buffer.write('\n');
    } else {
      buffer.write('\n\n');
    }
  }

  void lineBreak() {
    if (buffer.isNotEmpty && !buffer.toString().endsWith('\n')) {
      buffer.write('\n');
    }
  }

  void entity(
    int start,
    String type, {
    String? url,
    int? userId,
    int? customEmojiId,
    String? language,
    MessageButton? button,
    Map<String, dynamic> typeData = const {},
  }) {
    final length = this.length - start;
    if (length <= 0) return;
    entities.add(
      MessageTextEntity(
        offset: start,
        length: length,
        type: type,
        url: url,
        userId: userId,
        customEmojiId: customEmojiId,
        language: language,
        button: button,
        typeData: typeData,
      ),
    );
  }
}

/// One reaction bucket on a message (emoji or custom-emoji + count + chosen).
class MessageReaction {
  const MessageReaction({
    this.emoji,
    this.customEmojiId = 0,
    required this.count,
    required this.chosen,
  });
  final String? emoji;
  final int customEmojiId;
  final int count;
  final bool chosen;

  /// The TDLib reaction_type for add/removeMessageReaction.
  Map<String, dynamic> get type => customEmojiId != 0
      ? {
          '@type': 'reactionTypeCustomEmoji',
          'custom_emoji_id': customEmojiId.toString(),
        }
      : {'@type': 'reactionTypeEmoji', 'emoji': emoji};
}

/// A sender's role in a group/channel.
enum MemberRole { owner, admin, member, channel }

class ChatSummary {
  ChatSummary({
    required this.id,
    required this.title,
    required this.lastMessage,
    required this.lastMessageId,
    required this.date,
    required this.unreadCount,
    this.lastReadInboxMessageId = 0,
    this.unreadMentionCount = 0,
    this.unreadReactionCount = 0,
    required this.order,
    required this.isMuted,
    this.kind = ChatKind.unknown,
    this.useDefaultMuteFor = true,
    this.muteForOverride = 0,
    this.photo,
    this.lastSender,
    this.isPinned = false,
    this.isVerified = false,
    this.archiveOrder = 0,
    this.isMarkedUnread = false,
    this.draftText = '',
    this.peerUserId,
    this.peerIsContact = false,
    this.peerPhoneNumber,
    this.peerIsPremium = false,
    this.peerAccentColorId = -1,
    this.peerEmojiStatusId = 0,
    this.isForum = false,
    this.supportsBotTopics = false,
    this.lastChatMessage,
    this.isSavedMessages = false,
  });

  final int id;
  String title;
  String lastMessage;
  int lastMessageId;
  int date;
  int unreadCount;
  int lastReadInboxMessageId;
  int unreadMentionCount;
  int unreadReactionCount;
  int order;

  /// Whether the chat's mute state follows its scope's default. A default-
  /// following chat has no mute state of its own (TDLib zeroes its
  /// `mute_for`), so [isMuted] is derived from the scope cache and re-derived
  /// whenever the scope settings change or load.
  bool useDefaultMuteFor;

  /// The chat's own `mute_for` override, valid only when
  /// [useDefaultMuteFor] is false.
  int muteForOverride;
  bool isMuted;
  ChatKind kind;
  TdFileRef? photo;
  String? lastSender; // group preview prefix, e.g. "restart:"
  bool isPinned;
  bool isVerified;
  int archiveOrder; // > 0 when the chat is in the Archive list
  bool isMarkedUnread; // "标为未读" with no unread count
  String draftText; // unsent draft; shown as "[草稿]" prefix when non-empty
  int? peerUserId; // private/secret chat peer, used for chat-list identity UI
  bool peerIsContact;
  String? peerPhoneNumber;
  bool peerIsPremium;
  int peerAccentColorId;
  int peerEmojiStatusId;
  bool isForum;
  bool supportsBotTopics;
  ChatMessage? lastChatMessage;
  bool
  isSavedMessages; // true when this is the Saved Messages chat (private chat with yourself)

  /// Chat folders this chat currently sits in, kept from its TDLib chat-list
  /// positions. Lets a chat-list row draw its folder tags without asking
  /// TDLib — or recomputing folder filters — once per row.
  final Set<int> folderIds = {};

  /// Groups & channels use a rounded-square avatar unless UI preferences
  /// override them; people use a circle.
  bool get usesSquareAvatar =>
      kind == ChatKind.group || kind == ChatKind.channel;

  /// Whether this chat can be browsed and addressed through forum topics.
  ///
  /// TDLib's `chat.view_as_topics` only classifies forum supergroups (and
  /// Saved Messages presentation). Private bot topics are instead advertised
  /// by `userTypeBot.has_topics`, so keep the two sources explicit.
  bool get supportsTopics => isForum || supportsBotTopics;

  bool get isBotTopicChat => supportsBotTopics && !isForum;

  /// Re-derives [isMuted] from the stored per-chat override plus the given
  /// scope-level mute_for. Returns true when the derived value changed.
  ///
  /// A default-following chat has no mute state of its own: TDLib zeroes its
  /// `mute_for` (`DialogNotificationSettings::fix_mute_until`), so the
  /// effective mute state is the scope's. The scope cache loads after the
  /// first chat snapshots on a cold start, which is why this is derived, not
  /// frozen at parse time.
  bool applyScopeMuteFor(int scopeMuteFor) {
    final derived = useDefaultMuteFor ? scopeMuteFor > 0 : muteForOverride > 0;
    if (derived == isMuted) return false;
    isMuted = derived;
    return true;
  }

  bool get showsRedUnreadIndicator =>
      (unreadCount > 0 && !isMuted) || isMarkedUnread;
}

@immutable
class MessageAppearancePreview {
  const MessageAppearancePreview._({
    required this.contentType,
    this.chatBackground,
    this.chatTheme,
  });

  factory MessageAppearancePreview.background(
    Map<String, dynamic> chatBackground,
  ) => MessageAppearancePreview._(
    contentType: 'messageChatSetBackground',
    chatBackground: Map<String, dynamic>.unmodifiable(chatBackground),
  );

  factory MessageAppearancePreview.theme(Map<String, dynamic>? chatTheme) =>
      MessageAppearancePreview._(
        contentType: 'messageChatSetTheme',
        chatTheme: chatTheme == null
            ? null
            : Map<String, dynamic>.unmodifiable(chatTheme),
      );

  static MessageAppearancePreview? fromContent(Map<String, dynamic>? content) {
    if (content?.type == 'messageChatSetBackground') {
      final background = content?.obj('background');
      return background == null
          ? null
          : MessageAppearancePreview.background(background);
    }
    if (content?.type == 'messageChatSetTheme') {
      return MessageAppearancePreview.theme(content?.obj('theme'));
    }
    return null;
  }

  final String contentType;
  final Map<String, dynamic>? chatBackground;
  final Map<String, dynamic>? chatTheme;
}

/// Community identity retained by a chat-added service message.
///
/// The Bot API intentionally supplies only an id and name. Native TDLib
/// sessions can enrich the same model with a cached community photo later.
class MessageCommunityPreview {
  MessageCommunityPreview({required this.id, required this.name, this.photo});

  static MessageCommunityPreview? fromContent(Map<String, dynamic>? content) {
    if (content?.type != 'messageChatAddedToCommunity') return null;
    final community = content?.obj('community');
    return MessageCommunityPreview(
      id: content?.int64('community_id') ?? community?.int64('id') ?? 0,
      name:
          content?.str('community_name') ??
          community?.str('name') ??
          community?.str('title') ??
          '',
    );
  }

  final int id;
  String name;
  TdFileRef? photo;
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.isOutgoing,
    required this.text,
    required this.date,
    this.chatId,
    this.forumTopicId,
    this.senderName,
    this.senderIsChat = false,
    this.isService = false,
    this.isCall = false,
    this.callIsVideo = false,
    this.callDiscardReason,
    this.callDuration = 0,
    this.contentType,
    this.serviceTitle,
    this.restrictionReason,
    this.restrictionReasonCode,
    this.restrictedContentText,
    this.restrictedContentTextEntities = const [],
    this.containsUnreadMention = false,
    this.hasUnreadReactions = false,
    this.senderId,
    this.senderPhoto,
    this.image,
    this.imageWidth,
    this.imageHeight,
    this.document,
    this.music,
    this.senderRole,
    this.senderTitle,
    this.senderIsPremium = false,
    this.senderIsDeleted = false,
    this.senderAccentColorId = -1,
    this.senderEmojiStatusId = 0,
    this.mediaAlbumId = 0,
    this.animatedSticker,
    this.videoSticker,
    this.video,
    this.videoDuration,
    this.videoFileSize,
    this.hasSpoiler = false,
    this.videoNoteTranscription = '',
    this.videoNoteTranscriptionPending = false,
    this.videoNoteTranscriptionError,
    this.diceEmoji,
    this.diceValue,
    this.stickerFileId,
    this.stickerSetId,
    this.isAnimatedEmoji = false,
    this.location,
    this.voice,
    this.contact,
    this.poll,
    this.checklist,
    this.story,
    this.gift,
    this.gramTransfer,
    this.suggestedPostInfo,
    this.summaryCard,
    this.summaryLanguageCode = '',
    this.canRecognizeSpeech = false,
    this.replyToMessageId,
    this.replyToChatId,
    this.replyToQuote,
    this.textQuoteSource,
    this.textQuoteSourceEntities,
    this.replyToDate,
    this.replyToEntities = const [],
    this.replyToImage,
    this.replyToImageWidth,
    this.replyToImageHeight,
    this.serviceUserIds = const [],
    this.appearancePreview,
    this.communityPreview,
    this.customEmoji = const [],
    this.textEntities = const [],
    this.linkPreview,
    this.translationText,
    this.translationEntities = const [],
    this.translationLanguageCode,
    this.isTranslating = false,
    this.buttonRows = const [],
    this.richBlocks = const [],
    this.richMessageIsFull = true,
    this.isEdited = false,
    this.isSending = false,
    this.isSendAcknowledged = false,
    this.viewCount = 0,
    this.forwardCount = 0,
    this.hasCommentThread = false,
    this.commentCount = 0,
    this.lastCommentMessageId,
    bool? commentThreadMetadataKnown,
    this.blockedByUser = false,
    this.viaBotUserId,
    this.viaBotUsername,
    this.mirrorEntry,
  }) : commentThreadMetadataKnown =
           commentThreadMetadataKnown ??
           (hasCommentThread ||
               commentCount > 0 ||
               lastCommentMessageId != null);

  final int id;
  final bool isOutgoing;

  /// Kept-copy mirror entry when this bubble renders a deleted message
  /// (ghost transcript, Telegram §1.4 self-build feature). Null for every
  /// live message. Declared on [ChatMessage] so the bubble layer can render
  /// the ghost styling and the long-press menu can offer mirror actions
  /// without a store lookup per bubble.
  MessageHistoryEntry? mirrorEntry;
  String text;
  final int date;
  int? chatId;

  /// The forum topic this message belongs to, from TDLib's `message.topic_id`.
  /// Null outside forums and for messages TDLib reports without a topic (the
  /// General topic); the chat view's topic sections resolve General from it.
  final int? forumTopicId;
  String? senderName;
  bool senderIsChat;
  bool isService;
  bool isCall; // messageCall — a call log; not reactable
  bool callIsVideo; // messageCall.is_video
  // messageCall.discard_reason @type: callDiscardReasonMissed / Declined /
  // Disconnected / HungUp / Empty. Null until the call ends.
  String? callDiscardReason;
  int callDuration; // messageCall.duration, seconds (0 if never connected)
  /// Raw TDLib content @type (messageText / messagePhoto / messageAudio / …).
  /// Kept so we can distinguish kinds the lossy media fields can't (e.g. a
  /// photo vs a video-thumb, or plain text vs an audio/poll placeholder).
  String? contentType;

  /// The `title` carried by a `messageChatChangeTitle` service message. Kept
  /// so a transcript whose channel type resolves after the first history page
  /// can rebuild the label with channel wording.
  String? serviceTitle;

  /// TDLib's message-level restriction reason. When present, the original
  /// content must be replaced by this server-provided explanation.
  String? restrictionReason;
  String? restrictionReasonCode;
  String? restrictedContentText;
  List<MessageTextEntity> restrictedContentTextEntities;
  bool containsUnreadMention;
  bool hasUnreadReactions;

  int? senderId;
  TdFileRef? senderPhoto;
  TdFileRef? image; // photo / sticker / video-thumb / gif
  int? imageWidth;
  int? imageHeight;
  MessageDocument? document;
  MessageMusic? music;
  MemberRole? senderRole;
  String? senderTitle;
  bool senderIsPremium;
  bool senderIsDeleted;
  int senderAccentColorId;
  int senderEmojiStatusId;
  int mediaAlbumId;
  TdFileRef? animatedSticker; // .tgs (Lottie) sticker file
  TdFileRef? videoSticker; // .webm video sticker file
  TdFileRef? video; // playable video file (messageVideo)
  int? videoDuration; // seconds, for the duration badge
  int? videoFileSize; // bytes, for the inline autoplay budget
  /// Cover the media preview until explicitly revealed.
  bool hasSpoiler;

  /// Non-interactive quote/search previews cannot reveal a media spoiler.
  TdFileRef? get previewImage => hasSpoiler ? null : image;
  String videoNoteTranscription;
  bool videoNoteTranscriptionPending;
  String? videoNoteTranscriptionError;
  String? diceEmoji; // messageDice emoji, e.g. 🎲 / 🎯 / 🏀
  int? diceValue; // messageDice value reported by TDLib
  int? stickerFileId; // any sticker's file id (for "add to favorites")
  int? stickerSetId; // the sticker's set id (for 表情详情)
  bool isAnimatedEmoji; // single-emoji message (messageAnimatedEmoji)
  MessageLocation? location;
  MessageVoice? voice;
  MessageContactCard? contact;
  MessagePoll? poll;
  MessageChecklist? checklist;
  MessageStoryReference? story;

  /// Every gift content type (regular, upgraded, refunded, purchase offer,
  /// Premium, Stars, Gram); see [TDParse.giftContentTypes].
  MessageGift? gift;

  /// A Gram transfer (`messageTonWalletTransfer`).
  MessageGramTransfer? gramTransfer;
  MessageSuggestedPostInfo? suggestedPostInfo;
  MessageSummaryCard? summaryCard;

  /// Server-provided hint that this message can be summarized by Telegram AI.
  final String summaryLanguageCode;
  bool canRecognizeSpeech;
  String? aiSummaryText;
  List<MessageTextEntity> aiSummaryEntities = const [];
  bool aiSummaryLoading = false;

  // 引用 / reply: the message this one replies to, resolved lazily for the quote.
  int? replyToMessageId;
  int? replyToChatId;
  MessageTextQuote? replyToQuote;
  // Rendering can extract tables from the original formatted text. Quotes
  // must still address the unmodified source text, not that rendered subset.
  String? textQuoteSource;
  List<MessageTextEntity>? textQuoteSourceEntities;
  String get quoteSourceText => textQuoteSource ?? text;
  List<MessageTextEntity> get quoteSourceEntities =>
      textQuoteSourceEntities ?? textEntities;
  String? get replyPreviewText => replyToQuote?.text ?? replyToPreview;
  List<MessageTextEntity> get replyPreviewEntities =>
      replyToQuote?.entities ?? replyToEntities;
  int? replyToDate; // unix timestamp of the quoted message
  String? replyToSender; // resolved sender name of the quoted message
  String? replyToPreview; // one-line preview of the quoted message
  List<MessageTextEntity> replyToEntities;
  TdFileRef? replyToImage; // thumbnail/photo shown inside the quote block
  int? replyToImageWidth;
  int? replyToImageHeight;

  // Service messages such as member joins may carry affected user ids, resolved
  // by the chat view model once TDLib can provide display names.
  List<int> serviceUserIds;

  /// The visual payload retained only for Telegram's wallpaper/theme service
  /// messages. Other service content remains text-only.
  final MessageAppearancePreview? appearancePreview;

  /// Rich identity for community membership service events.
  final MessageCommunityPreview? communityPreview;

  // Inline custom (premium) emoji spans within `text`.
  List<CustomEmojiEntity> customEmoji;
  List<MessageTextEntity> textEntities;
  MessageLinkPreview? linkPreview;
  String? translationText;
  List<MessageTextEntity> translationEntities;
  String? translationLanguageCode;
  bool isTranslating;
  List<List<MessageButton>> buttonRows;
  List<RichMessageBlock> richBlocks;
  bool richMessageIsFull;

  bool isEdited; // shows a "已编辑" tag
  bool isSending;
  bool isSendAcknowledged;
  int viewCount;
  int forwardCount;
  bool hasCommentThread;

  /// TDLib `reply_info.reply_count`: channel comments or ordinary group
  /// replies, depending on the containing chat.
  int commentCount;
  int? lastCommentMessageId;

  /// Whether this instance carries an authoritative reply-info snapshot.
  /// False means a partial/cached message omitted interaction metadata, so a
  /// same-ID merge must not erase newer thread information already in memory.
  bool commentThreadMetadataKnown;

  /// When true, this message is from a Telegram-blocked user and the
  /// "hide blocked user messages" feature is on.
  bool blockedByUser;
  List<MessageReaction> reactions = const [];
  String? forwardOrigin; // name of the original author when forwarded
  String? forwardAuthorSignature; // signed author within the origin channel
  int? forwardFromUserId; // origin user, resolved lazily to forwardOrigin
  int? forwardFromChatId; // origin chat/channel, resolved lazily
  int? forwardFromMessageId; // original channel message when TDLib exposes it
  int? viaBotUserId; // inline bot through which this message was sent
  String? viaBotUsername; // resolved lazily to @username or bot display name

  /// Whether TDLib supplied an inline-bot attribution (`via_bot_user_id > 0`).
  bool get hasViaBotAttribution =>
      (viaBotUserId != null && viaBotUserId! > 0) ||
      (viaBotUsername?.trim().isNotEmpty ?? false);

  /// Stable label for the `via @bot` header while the bot's username is being
  /// resolved or when the bot only exposes a display name.
  String get viaBotDisplayName {
    final raw = viaBotUsername?.trim();
    if (raw != null && raw.isNotEmpty) return raw;
    return '@bot';
  }

  /// Whether TDLib supplied enough forwarding metadata to render an
  /// attribution header, even while the display name is still being resolved.
  bool get hasForwardAttribution =>
      (forwardOrigin?.trim().isNotEmpty ?? false) ||
      (forwardFromUserId != null && forwardFromUserId! > 0) ||
      (forwardFromChatId != null && forwardFromChatId != 0) ||
      (forwardFromMessageId != null && forwardFromMessageId! > 0);

  /// Stable text for the header while an asynchronous user/chat lookup is in
  /// flight or when Telegram intentionally hides the original name.
  String get forwardDisplayName {
    final name = forwardOrigin?.trim();
    final signature = forwardAuthorSignature?.trim();
    if (name != null && name.isNotEmpty) {
      if (signature != null && signature.isNotEmpty && signature != name) {
        return '$name ($signature)';
      }
      return name;
    }
    if (signature != null && signature.isNotEmpty) return signature;
    return AppStrings.t(AppStringKeys.groupManagementLogUnknownActor);
  }

  /// A plain text message (messageText) — not an audio/poll/contact placeholder.
  bool get isPlainText => contentType == 'messageText';

  /// A real photo (messagePhoto) — not a sticker / GIF / video thumbnail, all
  /// of which also set [image].
  bool get isPhoto => contentType == 'messagePhoto';

  bool get isContentRestricted =>
      restrictionReason != null && restrictionReason!.trim().isNotEmpty;

  bool get hasRestrictedRevealContent {
    if (!isContentRestricted) return false;
    final originalText = restrictedContentText?.trim();
    if (originalText != null &&
        originalText.isNotEmpty &&
        originalText != text.trim()) {
      return true;
    }
    return image != null ||
        document != null ||
        music != null ||
        animatedSticker != null ||
        videoSticker != null ||
        video != null ||
        diceEmoji != null ||
        location != null ||
        voice != null ||
        contact != null ||
        poll != null ||
        checklist != null ||
        story != null ||
        gift != null ||
        gramTransfer != null ||
        summaryCard != null ||
        linkPreview != null ||
        richBlocks.isNotEmpty;
  }

  /// Visual media that Telegram may place in the same media album.
  ///
  /// Stickers, GIFs and video stickers also have thumbnails in [image], but
  /// they are not part of photo/video album merging.
  bool get isAlbumVisualMedia =>
      image != null &&
      (contentType == 'messagePhoto' || contentType == 'messageVideo');

  bool get hasActualReplies =>
      commentCount > 0 || (lastCommentMessageId ?? 0) > 0;

  bool get isDice =>
      contentType == 'messageDice' && (diceEmoji ?? '').isNotEmpty;

  /// Whether the "+1" (复读) quick-repeat may apply to this kind at all: only
  /// plain text and photos. Audio, voice, location, stickers, polls, files,
  /// videos, contacts and call logs are excluded.
  bool get canRepeat => !isContentRestricted && (isPlainText || isPhoto);

  /// Keeps the source files used by an outgoing pending message after TDLib
  /// replaces it with the server-confirmed message and new file identifiers.
  void inheritLocalMediaFrom(ChatMessage previous) {
    image = image?.inheritLocalPathFrom(previous.image) ?? previous.image;
    if ((imageWidth ?? 0) <= 0 || (imageHeight ?? 0) <= 0) {
      imageWidth = previous.imageWidth;
      imageHeight = previous.imageHeight;
    }
    if ((videoDuration ?? 0) <= 0) {
      videoDuration = previous.videoDuration;
    }
    if ((videoFileSize ?? 0) <= 0) {
      videoFileSize = previous.videoFileSize;
    }
    video = video?.inheritLocalPathFrom(previous.video) ?? previous.video;
    animatedSticker =
        animatedSticker?.inheritLocalPathFrom(previous.animatedSticker) ??
        previous.animatedSticker;
    videoSticker =
        videoSticker?.inheritLocalPathFrom(previous.videoSticker) ??
        previous.videoSticker;

    final currentDocument = document;
    final previousDocument = previous.document;
    if (currentDocument != null && previousDocument != null) {
      document = MessageDocument(
        fileName: currentDocument.fileName,
        size: currentDocument.size,
        ext: currentDocument.ext,
        file:
            currentDocument.file?.inheritLocalPathFrom(previousDocument.file) ??
            previousDocument.file,
      );
    }

    final currentMusic = music;
    final previousMusic = previous.music;
    if (currentMusic != null && previousMusic != null) {
      music = MessageMusic(
        title: currentMusic.title,
        performer: currentMusic.performer,
        cover:
            currentMusic.cover?.inheritLocalPathFrom(previousMusic.cover) ??
            previousMusic.cover,
        file:
            currentMusic.file?.inheritLocalPathFrom(previousMusic.file) ??
            previousMusic.file,
        duration: currentMusic.duration,
      );
    }

    final currentVoice = voice;
    final previousVoice = previous.voice;
    if (currentVoice != null && previousVoice != null) {
      voice = MessageVoice(
        file:
            currentVoice.file?.inheritLocalPathFrom(previousVoice.file) ??
            previousVoice.file,
        duration: currentVoice.duration,
        waveform: currentVoice.waveform,
        transcription: currentVoice.transcription,
        transcriptionPending: currentVoice.transcriptionPending,
        transcriptionError: currentVoice.transcriptionError,
      );
    }
  }
}

enum MessageButtonStyle { standard, primary, danger, success }

enum SwitchInlineTargetKind { currentChat, chooseChat, internalLink }

class SwitchInlineTarget {
  const SwitchInlineTarget.currentChat()
    : kind = SwitchInlineTargetKind.currentChat,
      allowUserChats = false,
      allowBotChats = false,
      allowGroupChats = false,
      allowChannelChats = false,
      internalLink = null;

  const SwitchInlineTarget.chooseChat({
    this.allowUserChats = true,
    this.allowBotChats = true,
    this.allowGroupChats = true,
    this.allowChannelChats = true,
  }) : kind = SwitchInlineTargetKind.chooseChat,
       internalLink = null;

  const SwitchInlineTarget.internalLink(Map<String, dynamic> this.internalLink)
    : kind = SwitchInlineTargetKind.internalLink,
      allowUserChats = false,
      allowBotChats = false,
      allowGroupChats = false,
      allowChannelChats = false;

  final SwitchInlineTargetKind kind;
  final bool allowUserChats;
  final bool allowBotChats;
  final bool allowGroupChats;
  final bool allowChannelChats;
  final Map<String, dynamic>? internalLink;

  bool get isCurrentChat => kind == SwitchInlineTargetKind.currentChat;

  Set<ChatKind> get allowedChatKinds {
    final kinds = <ChatKind>{
      if (allowUserChats) ChatKind.privateChat,
      if (allowBotChats) ChatKind.bot,
      if (allowGroupChats) ChatKind.group,
      if (allowChannelChats) ChatKind.channel,
    };
    if (kinds.isEmpty) {
      return const {
        ChatKind.privateChat,
        ChatKind.bot,
        ChatKind.group,
        ChatKind.channel,
      };
    }
    return kinds;
  }
}

class MessageButton {
  const MessageButton({
    required this.text,
    required this.type,
    this.url,
    this.data,
    this.userId,
    this.copyText,
    this.switchInlineQuery,
    this.switchInlineTarget,
    this.requestId,
    this.suggestedName,
    this.suggestedUsername,
    this.style = MessageButtonStyle.standard,
    this.iconCustomEmojiId = 0,
    this.isReplyKeyboard = false,
  });

  final String text;
  final String type;
  final String? url;
  final String? data;
  final int? userId;
  final String? copyText;
  final String? switchInlineQuery;
  final SwitchInlineTarget? switchInlineTarget;
  final int? requestId;
  final String? suggestedName;
  final String? suggestedUsername;
  final MessageButtonStyle style;
  final int iconCustomEmojiId;
  final bool isReplyKeyboard;

  bool get isCallback =>
      type == 'inlineKeyboardButtonTypeCallback' ||
      type == 'inlineKeyboardButtonTypeCallbackWithPassword' ||
      type == 'inlineKeyboardButtonTypeCallbackGame' ||
      type == 'inlineKeyboardButtonTypeBuy';

  bool get isWebApp =>
      type == 'inlineKeyboardButtonTypeWebApp' ||
      type == 'keyboardButtonTypeWebApp';

  bool get isSwitchInline =>
      type == 'inlineKeyboardButtonTypeSwitchInline' ||
      switchInlineQuery != null;

  bool get isSwitchInlineCurrentChat =>
      isSwitchInline && (switchInlineTarget?.isCurrentChat ?? false);
}

class MessageLinkPreview {
  const MessageLinkPreview({
    required this.url,
    required this.displayUrl,
    required this.siteName,
    required this.title,
    required this.description,
    this.descriptionEntities = const [],
    this.image,
    this.imageWidth,
    this.imageHeight,
    this.video,
    this.videoDuration,
    this.showLargeMedia = false,
    this.showMediaAboveDescription = false,
    this.showAboveText = false,
    this.type = '',
  });

  final String url;
  final String displayUrl;
  final String siteName;
  final String title;
  final String description;
  final List<MessageTextEntity> descriptionEntities;
  final TdFileRef? image;
  final int? imageWidth;
  final int? imageHeight;
  final TdFileRef? video;
  final int? videoDuration;
  final bool showLargeMedia;
  final bool showMediaAboveDescription;
  final bool showAboveText;
  final String type;

  bool get hasText =>
      siteName.isNotEmpty ||
      title.isNotEmpty ||
      description.isNotEmpty ||
      displayUrl.isNotEmpty;

  bool get hasMedia => image != null || video != null;
}

class MessageDocument {
  MessageDocument({
    required this.fileName,
    required this.size,
    required this.ext,
    required this.file,
  });
  final String fileName;
  final int size;
  final String ext;
  final TdFileRef? file;
}

class MessageMusic {
  MessageMusic({
    required this.title,
    this.performer,
    this.cover,
    this.file,
    this.duration = 0,
  });
  final String title;
  final String? performer;
  final TdFileRef? cover;
  final TdFileRef? file;
  final int duration;
}

class MessageLocation {
  MessageLocation({
    required this.latitude,
    required this.longitude,
    this.title,
    this.address,
  });
  final double latitude;
  final double longitude;
  String? title;
  String? address;
}

class MessageVoice {
  MessageVoice({
    required this.file,
    required this.duration,
    this.waveform = '',
    this.transcription = '',
    this.transcriptionPending = false,
    this.transcriptionError,
  });
  final TdFileRef? file;
  final int duration;
  final String waveform;
  final String transcription;
  final bool transcriptionPending;
  final String? transcriptionError;
}

class MessageContactCard {
  const MessageContactCard({
    required this.phoneNumber,
    required this.firstName,
    required this.lastName,
    required this.vcard,
    required this.userId,
  });

  final String phoneNumber;
  final String firstName;
  final String lastName;
  final String vcard;
  final int userId;

  String get displayName {
    final value = '$firstName $lastName'.trim();
    return value.isEmpty ? phoneNumber : value;
  }
}

class MessagePollOption {
  const MessagePollOption({
    required this.index,
    required this.id,
    required this.text,
    required this.voterCount,
    required this.votePercentage,
    required this.isChosen,
    required this.isBeingChosen,
  });

  final int index;
  final String id;
  final String text;
  final int voterCount;
  final int votePercentage;
  final bool isChosen;
  final bool isBeingChosen;
}

class MessagePoll {
  const MessagePoll({
    required this.id,
    required this.question,
    required this.description,
    required this.options,
    required this.totalVoterCount,
    required this.canGetVoters,
    required this.canSeeResults,
    required this.isAnonymous,
    required this.allowsMultipleAnswers,
    required this.allowsRevoting,
    required this.isQuiz,
    required this.isClosed,
    required this.canAddOption,
    this.correctOptionId = -1,
    this.explanation = '',
    this.media,
  });

  final int id;
  final String question;
  final String description;
  final List<MessagePollOption> options;
  final int totalVoterCount;
  final bool canGetVoters;
  final bool canSeeResults;
  final bool isAnonymous;
  final bool allowsMultipleAnswers;
  final bool allowsRevoting;
  final bool isQuiz;
  final bool isClosed;
  final bool canAddOption;
  final int correctOptionId;
  final String explanation;
  final TdFileRef? media;

  List<int> get chosenOptionIndexes => [
    for (final option in options)
      if (option.isChosen) option.index,
  ];
}

class MessageChecklistTask {
  const MessageChecklistTask({
    required this.id,
    required this.text,
    required this.isCompleted,
    this.completedByUserId,
    this.completedByChatId,
    this.completionDate = 0,
  });

  final int id;
  final String text;
  final bool isCompleted;
  final int? completedByUserId;
  final int? completedByChatId;
  final int completionDate;
}

class MessageChecklist {
  const MessageChecklist({
    required this.title,
    required this.tasks,
    required this.othersCanAddTasks,
    required this.canAddTasks,
    required this.othersCanMarkTasksAsDone,
    required this.canMarkTasksAsDone,
  });

  final String title;
  final List<MessageChecklistTask> tasks;
  final bool othersCanAddTasks;
  final bool canAddTasks;
  final bool othersCanMarkTasksAsDone;
  final bool canMarkTasksAsDone;
}

class MessageStoryReference {
  const MessageStoryReference({
    required this.posterChatId,
    required this.storyId,
    required this.viaMention,
  });

  final int posterChatId;
  final int storyId;
  final bool viaMention;
}

enum SuggestedPostPriceKind { stars, ton }

class SuggestedPostPrice {
  const SuggestedPostPrice({required this.kind, required this.amount});

  final SuggestedPostPriceKind kind;

  /// Telegram Stars for [SuggestedPostPriceKind.stars], or hundredths of one
  /// TON for [SuggestedPostPriceKind.ton], matching TDLib's gram_cent_count.
  final int amount;

  Map<String, dynamic> toTdJson() => switch (kind) {
    SuggestedPostPriceKind.stars => {
      '@type': 'suggestedPostPriceStar',
      'star_count': amount,
    },
    SuggestedPostPriceKind.ton => {
      '@type': 'suggestedPostPriceGram',
      'gram_cent_count': amount,
    },
  };
}

enum SuggestedPostState { pending, approved, declined, unknown }

class MessageSuggestedPostInfo {
  const MessageSuggestedPostInfo({
    required this.state,
    required this.canBeApproved,
    required this.canBeDeclined,
    this.price,
    this.sendDate = 0,
  });

  final SuggestedPostPrice? price;
  final int sendDate;
  final SuggestedPostState state;
  final bool canBeApproved;
  final bool canBeDeclined;
}

enum MessageSummaryKind { game, invoice, giveaway, paidMedia, suggestedPost }

class MessageSummaryCard {
  const MessageSummaryCard({
    required this.kind,
    required this.title,
    this.subtitle = '',
    this.detail = '',
    this.image,
    this.video,
  });

  final MessageSummaryKind kind;
  final String title;
  final String subtitle;
  final String detail;
  final TdFileRef? image;
  final TdFileRef? video;
}

class Contact {
  Contact({
    required this.id,
    required this.name,
    required this.username,
    this.usernames = const [],
    required this.statusText,
    this.photo,
    this.isOnline = false,
  });
  final int id;
  final String name;
  final String? username;
  final List<String> usernames;
  final String statusText;
  TdFileRef? photo;
  bool isOnline;
}

class CurrentUser {
  CurrentUser({
    required this.id,
    required this.name,
    required this.phoneNumber,
    this.username,
    this.photo,
    this.emojiStatusId = 0,
    this.isPremium = false,
  });
  int id;
  String name;
  String phoneNumber;
  String? username;
  TdFileRef? photo;
  int emojiStatusId; // custom_emoji_id of the Telegram emoji status, 0 = none
  bool isPremium; // Telegram Premium subscriber
}

class MediaAttachment {
  const MediaAttachment({
    this.image,
    this.width,
    this.height,
    this.document,
    this.music,
    this.animated,
    this.videoSticker,
    this.video,
    this.videoDuration,
    this.videoFileSize,
    this.stickerFileId,
    this.stickerSetId,
    this.isAnimatedEmoji = false,
  });
  final TdFileRef? image;
  final int? width;
  final int? height;
  final MessageDocument? document;
  final MessageMusic? music;
  final TdFileRef? animated; // .tgs Lottie sticker
  final TdFileRef? videoSticker; // .webm video sticker
  final TdFileRef? video; // playable video file (messageVideo)
  final int? videoDuration; // seconds
  final int? videoFileSize; // bytes, for the inline autoplay budget
  final int? stickerFileId; // any sticker's file id (for "add to favorites")
  final int? stickerSetId; // the sticker's set id (for 表情详情)
  final bool isAnimatedEmoji; // single-emoji message (messageAnimatedEmoji)
}
