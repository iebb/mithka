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
import 'package:mithka/l10n/telegram_language_controller.dart';
import 'package:mithka/notifications/scope_notification_settings.dart';

import 'json_helpers.dart';

/// Reference to a downloadable TDLib file (profile photo, thumbnail, …).
class TdFileRef {
  TdFileRef({
    required this.id,
    this.localPath,
    this.miniThumb,
    this.thumbnail,
    this.hasAnimation = false,
    this.photoId,
  });
  final int id;
  final String? localPath;
  final bool hasAnimation;
  final int? photoId;
  Uint8List? miniThumb; // decoded JPEG for instant placeholder
  TdFileRef? thumbnail; // downloadable thumbnail with the real aspect ratio

  TdFileRef inheritLocalPathFrom(TdFileRef? previous) {
    return TdFileRef(
      id: id,
      localPath: _usablePath(localPath) ?? _usablePath(previous?.localPath),
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
    ChatMediaCategory.media => telegramText(AppStringKeys.tdMessagePhotoVideo),
    ChatMediaCategory.file => telegramText(AppStringKeys.topicPostContentFile),
    ChatMediaCategory.audio => telegramText(AppStringKeys.composerAudio),
    ChatMediaCategory.link => telegramText(AppStringKeys.sharedMediaLinks),
    ChatMediaCategory.sticker => telegramText(AppStringKeys.tdMessageSticker),
    ChatMediaCategory.voice => telegramText(AppStringKeys.sharedMediaVoice),
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
    ChatMediaCategory.media => telegramText(
      AppStringKeys.tdMessageNoPhotoVideo,
    ),
    ChatMediaCategory.file => telegramText(AppStringKeys.tdMessageNoFiles),
    ChatMediaCategory.audio => telegramText(AppStringKeys.tdMessageNoAudio),
    ChatMediaCategory.link => telegramText(AppStringKeys.tdMessageNoLinks),
    ChatMediaCategory.sticker => telegramText(
      AppStringKeys.tdMessageNoStickers,
    ),
    ChatMediaCategory.voice => telegramText(AppStringKeys.tdMessageNoVoice),
    ChatMediaCategory.member => telegramText(AppStringKeys.tdMessageNoMembers),
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
  });

  final int offset;
  final int length;
  final String type;
  final String? url;
  final int? userId;
  final int? customEmojiId;
  final String? language;

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
    final entityType = <String, dynamic>{'@type': type};
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
  list,
  blockQuote,
  pullQuote,
  animation,
  audio,
  photo,
  video,
  voiceNote,
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

  bool get isTable => kind == RichMessageBlockKind.table;
  bool get isMath => kind == RichMessageBlockKind.math;
  bool get isMap => kind == RichMessageBlockKind.map;
}

class _ParsedMarkdownText {
  const _ParsedMarkdownText(this.text, this.entities);

  final String text;
  final List<MessageTextEntity> entities;
}

class _MarkdownMarker {
  const _MarkdownMarker(this.marker, this.type);

  final String marker;
  final String type;
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
    this.unreadMentionCount = 0,
    required this.order,
    required this.isMuted,
    this.kind = ChatKind.unknown,
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
    this.lastChatMessage,
    this.isSavedMessages = false,
  });

  final int id;
  String title;
  String lastMessage;
  int lastMessageId;
  int date;
  int unreadCount;
  int unreadMentionCount;
  int order;
  bool isMuted;
  ChatKind kind;
  TdFileRef? photo;
  String? lastSender; // group preview prefix, e.g. "restart:"
  bool isPinned;
  bool isVerified;
  int archiveOrder; // > 0 when the chat is in the Archive list
  bool isMarkedUnread; // "标为未读" with no unread count
  String draftText; // unsent draft; shown as "[草稿]" prefix when non-empty
  int? peerUserId; // private/secret chat peer, used for chat-list Premium UI
  bool peerIsContact;
  String? peerPhoneNumber;
  bool peerIsPremium;
  int peerAccentColorId;
  int peerEmojiStatusId;
  bool isForum;
  ChatMessage? lastChatMessage;
  bool
  isSavedMessages; // true when this is the Saved Messages chat (private chat with yourself)

  /// Groups & channels use a rounded-square avatar unless UI preferences
  /// override them; people use a circle.
  bool get usesSquareAvatar =>
      kind == ChatKind.group || kind == ChatKind.channel;

  bool get showsRedUnreadIndicator =>
      (unreadCount > 0 && !isMuted) || isMarkedUnread;
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.isOutgoing,
    required this.text,
    required this.date,
    this.chatId,
    this.senderName,
    this.senderIsChat = false,
    this.isService = false,
    this.isCall = false,
    this.callIsVideo = false,
    this.callDiscardReason,
    this.callDuration = 0,
    this.contentType,
    this.restrictionReason,
    this.restrictionReasonCode,
    this.restrictedContentText,
    this.restrictedContentTextEntities = const [],
    this.containsUnreadMention = false,
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
    this.senderAccentColorId = -1,
    this.senderEmojiStatusId = 0,
    this.mediaAlbumId = 0,
    this.animatedSticker,
    this.videoSticker,
    this.video,
    this.videoDuration,
    this.diceEmoji,
    this.diceValue,
    this.stickerFileId,
    this.stickerSetId,
    this.isAnimatedEmoji = false,
    this.location,
    this.voice,
    this.replyToMessageId,
    this.replyToDate,
    this.replyToImage,
    this.replyToImageWidth,
    this.replyToImageHeight,
    this.serviceUserIds = const [],
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
    this.hasCommentThread = false,
    this.commentCount = 0,
    this.lastCommentMessageId,
    this.blockedByUser = false,
  });

  final int id;
  final bool isOutgoing;
  String text;
  final int date;
  int? chatId;
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

  /// TDLib's message-level restriction reason. When present, the original
  /// content must be replaced by this server-provided explanation.
  String? restrictionReason;
  String? restrictionReasonCode;
  String? restrictedContentText;
  List<MessageTextEntity> restrictedContentTextEntities;
  bool containsUnreadMention;
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
  int senderAccentColorId;
  int senderEmojiStatusId;
  int mediaAlbumId;
  TdFileRef? animatedSticker; // .tgs (Lottie) sticker file
  TdFileRef? videoSticker; // .webm video sticker file
  TdFileRef? video; // playable video file (messageVideo)
  int? videoDuration; // seconds, for the duration badge
  String? diceEmoji; // messageDice emoji, e.g. 🎲 / 🎯 / 🏀
  int? diceValue; // messageDice value reported by TDLib
  int? stickerFileId; // any sticker's file id (for "add to favorites")
  int? stickerSetId; // the sticker's set id (for 表情详情)
  bool isAnimatedEmoji; // single-emoji message (messageAnimatedEmoji)
  MessageLocation? location;
  MessageVoice? voice;

  // 引用 / reply: the message this one replies to, resolved lazily for the quote.
  int? replyToMessageId;
  int? replyToDate; // unix timestamp of the quoted message
  String? replyToSender; // resolved sender name of the quoted message
  String? replyToPreview; // one-line preview of the quoted message
  TdFileRef? replyToImage; // thumbnail/photo shown inside the quote block
  int? replyToImageWidth;
  int? replyToImageHeight;

  // Service messages such as member joins may carry affected user ids, resolved
  // by the chat view model once TDLib can provide display names.
  List<int> serviceUserIds;

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
  bool hasCommentThread;
  int
  commentCount; // channel discussion replies/comments, when TDLib exposes it
  int? lastCommentMessageId;

  /// When true, this message is from a Telegram-blocked user and the
  /// "hide blocked user messages" feature is on.
  bool blockedByUser;
  List<MessageReaction> reactions = const [];
  String? forwardOrigin; // name of the original author when forwarded
  int? forwardFromUserId; // origin user, resolved lazily to forwardOrigin
  int? forwardFromChatId; // origin chat/channel, resolved lazily

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
      );
    }
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
    this.isReplyKeyboard = false,
  });

  final String text;
  final String type;
  final String? url;
  final String? data;
  final int? userId;
  final String? copyText;
  final String? switchInlineQuery;
  final bool isReplyKeyboard;

  bool get isCallback =>
      type == 'inlineKeyboardButtonTypeCallback' ||
      type == 'inlineKeyboardButtonTypeCallbackWithPassword' ||
      type == 'inlineKeyboardButtonTypeCallbackGame' ||
      type == 'inlineKeyboardButtonTypeBuy';

  bool get isWebApp =>
      type == 'inlineKeyboardButtonTypeWebApp' ||
      type == 'keyboardButtonTypeWebApp';
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
  MessageVoice({required this.file, required this.duration});
  final TdFileRef? file;
  final int duration;
}

class Contact {
  Contact({
    required this.id,
    required this.name,
    required this.username,
    required this.statusText,
    this.photo,
    this.isOnline = false,
  });
  final int id;
  final String name;
  final String? username;
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

// MARK: - Parsing

abstract final class TDParse {
  static ChatKind chatKind(Map<String, dynamic> chat) {
    final t = chat.obj('type');
    switch (t?.type) {
      case 'chatTypePrivate':
        return ChatKind.privateChat;
      case 'chatTypeSecret':
        return ChatKind.secret;
      case 'chatTypeBasicGroup':
        return ChatKind.group;
      case 'chatTypeSupergroup':
        return (t?.boolean('is_channel') ?? false)
            ? ChatKind.channel
            : ChatKind.group;
      default:
        return ChatKind.unknown;
    }
  }

  static ChatSummary? chat(Map<String, dynamic> chat) {
    final id = chat.int64('id');
    if (id == null) return null;
    final title = chat.str('title') ?? '—';
    final unread = chat.integer('unread_count') ?? 0;

    var lastText = '';
    var lastMessageId = 0;
    var date = 0;
    ChatMessage? lastChatMessage;
    final last = chat.obj('last_message');
    if (last != null) {
      lastMessageId = last.int64('id') ?? 0;
      date = last.integer('date') ?? 0;
      lastChatMessage = message(last);
      final content = last.obj('content');
      if (content != null) lastText = messageText(content);
    }

    int order = 0, archiveOrder = 0;
    bool pinned = false;
    final positions = chat.objects('positions');
    if (positions != null) {
      for (final pos in positions) {
        switch (pos.obj('list')?.type) {
          case 'chatListMain':
            order = pos.int64('order') ?? 0;
            pinned = pos.boolean('is_pinned') ?? false;
          case 'chatListArchive':
            archiveOrder = pos.int64('order') ?? 0;
        }
      }
    }

    final muted = ScopeNotificationSettings.shared.isMuted(chat);

    final type = chat.obj('type');
    return ChatSummary(
      id: id,
      title: title,
      lastMessage: lastText,
      lastMessageId: lastMessageId,
      date: date,
      unreadCount: unread,
      unreadMentionCount: chat.integer('unread_mention_count') ?? 0,
      order: order,
      isMuted: muted,
      kind: chatKind(chat),
      photo: smallPhoto(chat.obj('photo')),
      isPinned: pinned,
      archiveOrder: archiveOrder,
      isMarkedUnread: chat.boolean('is_marked_as_unread') ?? false,
      draftText: draftText(chat.obj('draft_message')),
      peerUserId: switch (type?.type) {
        'chatTypePrivate' || 'chatTypeSecret' => type?.int64('user_id'),
        _ => null,
      },
      isForum: chat.boolean('view_as_topics') ?? false,
      lastChatMessage: lastChatMessage,
    );
  }

  /// Text of a chat's unsent draft, or '' if none.
  static String draftText(Map<String, dynamic>? draft) {
    if (draft == null) return '';
    final content = draft.obj('input_message_text');
    if (content?.type != 'inputMessageText') return '';
    return content?.obj('text')?.str('text') ?? '';
  }

  static ChatMessage? message(Map<String, dynamic> message) {
    final id = message.int64('id');
    if (id == null) return null;
    final chatId = message.int64('chat_id');
    final outgoing = message.boolean('is_outgoing') ?? false;
    final date = message.integer('date') ?? 0;
    final content = message.obj('content');
    final restrictionReason = restrictionReasonFor(message);
    final restrictionReasonCode = restrictionReasonCodeFor(message);
    final isContentRestricted = restrictionReason != null;
    final rawService = isServiceContent(content?.type);
    final service = !isContentRestricted && rawService;
    final isCall = !isContentRestricted && content?.type == 'messageCall';
    final callIsVideo = isCall && (content?.boolean('is_video') ?? false);
    final callDuration = isCall ? (content?.integer('duration') ?? 0) : 0;
    final callDiscardReason = isCall
        ? content?.obj('discard_reason')?.type
        : null;
    final contentText = rawService
        ? serviceText(content)
        : (content != null
              ? messageText(content)
              : telegramText(AppStringKeys.chatSearchMessageResultLabel));
    final text = restrictionReason ?? contentText;

    int? senderId;
    final sender = message.obj('sender_id');
    switch (sender?.type) {
      case 'messageSenderUser':
        senderId = sender?.int64('user_id');
      case 'messageSenderChat':
        senderId = sender?.int64('chat_id');
    }

    final media = mediaAttachment(content);

    // 转发: forward_info.origin identifies the original author.
    final origin = message.obj('forward_info')?.obj('origin');
    String? fwdName;
    int? fwdUserId, fwdChatId;
    switch (origin?.type) {
      case 'messageOriginUser':
        fwdUserId = origin?.int64('sender_user_id');
      case 'messageOriginChat':
        fwdChatId = origin?.int64('sender_chat_id');
        fwdName = origin?.str('author_signature');
      case 'messageOriginChannel':
        fwdChatId = origin?.int64('chat_id');
        fwdName = origin?.str('author_signature');
      case 'messageOriginHiddenUser':
        fwdName = origin?.str('sender_name');
    }

    // 引用: reply_to is messageReplyToMessage { chat_id, message_id, … }.
    final replyTo = message.obj('reply_to');
    final replyToMessageId = replyTo?.type == 'messageReplyToMessage'
        ? replyTo?.int64('message_id')
        : null;

    final parsedEntities = messageTextEntities(content);
    final contentMarkdown = !rawService && parsedEntities.isEmpty
        ? _markdownText(contentText)
        : null;
    final replyInfo = message.obj('interaction_info')?.obj('reply_info');
    var contentDisplayText = contentMarkdown?.text ?? contentText;
    var contentDisplayEntities = contentMarkdown?.entities ?? parsedEntities;
    final contentRichBlocks = <RichMessageBlock>[...richMessageBlocks(content)];
    if (content?.type == 'messageRichMessage' && contentRichBlocks.isNotEmpty) {
      contentDisplayText = '';
      contentDisplayEntities = const [];
    }
    if (content?.type != 'messageRichMessage') {
      final extracted = _extractMarkdownTables(
        contentDisplayText,
        contentDisplayEntities,
      );
      contentDisplayText = extracted.text;
      contentDisplayEntities = extracted.entities;
      contentRichBlocks.addAll(extracted.blocks);
    }
    final displayText = isContentRestricted ? text : contentDisplayText;
    final displayEntities = isContentRestricted
        ? const <MessageTextEntity>[]
        : contentDisplayEntities;
    final richBlocks = contentRichBlocks;

    return ChatMessage(
        id: id,
        isOutgoing: outgoing,
        text: displayText,
        date: date,
        chatId: chatId,
        isService: service,
        isCall: isCall,
        callIsVideo: callIsVideo,
        callDiscardReason: callDiscardReason,
        callDuration: callDuration,
        contentType: isContentRestricted ? 'messageText' : content?.type,
        restrictionReason: restrictionReason,
        restrictionReasonCode: restrictionReasonCode,
        restrictedContentText: isContentRestricted ? contentDisplayText : null,
        restrictedContentTextEntities: isContentRestricted
            ? contentDisplayEntities
            : const [],
        containsUnreadMention:
            message.boolean('contains_unread_mention') ?? false,
        senderId: senderId,
        senderIsChat: sender?.type == 'messageSenderChat',
        senderTitle:
            _cleanString(message.str('sender_tag')) ??
            _cleanString(message.str('author_signature')),
        mediaAlbumId: message.int64('media_album_id') ?? 0,
        image: media.image,
        imageWidth: media.width,
        imageHeight: media.height,
        document: media.document,
        music: media.music,
        animatedSticker: media.animated,
        videoSticker: media.videoSticker,
        video: media.video,
        videoDuration: media.videoDuration,
        diceEmoji: content?.type == 'messageDice'
            ? content?.str('emoji')
            : null,
        diceValue: content?.type == 'messageDice'
            ? content?.integer('value')
            : null,
        stickerFileId: media.stickerFileId,
        stickerSetId: media.stickerSetId,
        isAnimatedEmoji: media.isAnimatedEmoji,
        location: locationAttachment(content),
        voice: voiceAttachment(content),
        replyToMessageId: isContentRestricted ? null : replyToMessageId,
        serviceUserIds: isContentRestricted
            ? const []
            : serviceUserIds(content, senderId),
        customEmoji: isContentRestricted
            ? const []
            : customEmojiEntitiesFrom(parsedEntities),
        textEntities: displayEntities,
        linkPreview: linkPreview(content?.obj('link_preview')),
        buttonRows: isContentRestricted
            ? const []
            : messageButtonRows(message.obj('reply_markup')),
        richBlocks: richBlocks,
        richMessageIsFull:
            isContentRestricted ||
            content?.type != 'messageRichMessage' ||
            (content?.obj('message')?.boolean('is_full') ?? false),
        isEdited: (message.integer('edit_date') ?? 0) > 0,
        isSending: message.obj('sending_state') != null,
        hasCommentThread: !isContentRestricted && replyInfo != null,
        commentCount: isContentRestricted
            ? 0
            : (replyInfo?.integer('reply_count') ??
                  replyInfo?.integer('comment_count') ??
                  0),
        lastCommentMessageId: isContentRestricted
            ? null
            : replyInfo?.int64('last_message_id'),
      )
      ..reactions = reactionsFrom(message)
      ..forwardOrigin = isContentRestricted ? null : fwdName
      ..forwardFromUserId = isContentRestricted ? null : fwdUserId
      ..forwardFromChatId = isContentRestricted ? null : fwdChatId;
  }

  /// Returns the server-provided reason that makes a chat or message
  /// unavailable on this client platform.
  static String? restrictionReasonFor(Map<String, dynamic>? object) =>
      _cleanString(
        object?.obj('restriction_info')?.str('restriction_reason'),
      ) ??
      _cleanString(object?.obj('restriction_info')?.str('text'));

  /// Returns the machine-readable restriction reason such as `porno` or
  /// `terms` when TDLib includes it.
  static String? restrictionReasonCodeFor(Map<String, dynamic>? object) {
    final restrictionInfo = object?.obj('restriction_info');
    return _cleanString(
      restrictionInfo?.str('reason') ??
          restrictionInfo?.str('restriction_reason_code'),
    )?.toLowerCase();
  }

  static bool hasSensitiveRestriction(Map<String, dynamic>? object) =>
      object?.obj('restriction_info')?.boolean('has_sensitive_content') ??
      false;

  static bool isBlockingRestriction(Map<String, dynamic>? object) =>
      restrictionReasonFor(object) != null;

  static bool isPornographicRestriction(Map<String, dynamic>? object) {
    final code = restrictionReasonCodeFor(object);
    final text = restrictionReasonFor(object);
    return isPornographicRestrictionText(code) ||
        isPornographicRestrictionText(text);
  }

  static bool isTermsRestriction(Map<String, dynamic>? object) {
    final code = restrictionReasonCodeFor(object);
    final text = restrictionReasonFor(object);
    if (hasSensitiveRestriction(object) ||
        isPornographicRestrictionText(code) ||
        isPornographicRestrictionText(text)) {
      return false;
    }
    return code == 'terms' || isTelegramTermsRestrictionText(text);
  }

  static bool isPornographicRestrictionText(String? value) {
    final normalized = _normalizedRestrictionText(value);
    return normalized.contains('porn') ||
        normalized.contains('pornographic material');
  }

  static bool isTelegramTermsRestrictionText(String? value) {
    final normalized = _normalizedRestrictionText(value);
    final cannotDisplay =
        normalized.contains("can't be displayed") ||
        normalized.contains("couldn't be displayed") ||
        normalized.contains('cannot be displayed') ||
        normalized.contains('could not be displayed');
    final telegramTerms =
        normalized.contains('terms of service') ||
        normalized.contains('violated telegram');
    return cannotDisplay && telegramTerms;
  }

  static String _normalizedRestrictionText(String? value) =>
      (value ?? '').toLowerCase().replaceAll('’', "'");

  static String? _cleanString(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  static MessageLinkPreview? linkPreview(Map<String, dynamic>? preview) {
    if (preview == null) return null;
    final type = preview.obj('type');
    final media = linkPreviewMedia(type);
    final description = preview.obj('description');
    final link = MessageLinkPreview(
      url: preview.str('url') ?? '',
      displayUrl: preview.str('display_url') ?? '',
      siteName: preview.str('site_name') ?? '',
      title: preview.str('title') ?? '',
      description: description?.str('text') ?? '',
      descriptionEntities: textEntities(description),
      image: media.image,
      imageWidth: media.width,
      imageHeight: media.height,
      video: media.video,
      videoDuration: media.videoDuration,
      showLargeMedia: preview.boolean('show_large_media') ?? false,
      showMediaAboveDescription:
          preview.boolean('show_media_above_description') ?? false,
      showAboveText: preview.boolean('show_above_text') ?? false,
      type: type?.type ?? '',
    );
    return link.hasText || link.hasMedia ? link : null;
  }

  static MediaAttachment linkPreviewMedia(Map<String, dynamic>? type) {
    if (type == null) return const MediaAttachment();
    switch (type.type) {
      case 'linkPreviewTypeArticle':
      case 'linkPreviewTypePhoto':
      case 'linkPreviewTypeBackground':
      case 'linkPreviewTypeTheme':
        return photoAttachment(type.obj('photo'));
      case 'linkPreviewTypeVideo':
      case 'linkPreviewTypeEmbeddedVideoPlayer':
      case 'linkPreviewTypeExternalVideo':
        return videoAttachment(type.obj('video'), type);
      case 'linkPreviewTypeAnimation':
      case 'linkPreviewTypeEmbeddedAnimationPlayer':
        return animationAttachment(type.obj('animation'), type);
      case 'linkPreviewTypeAlbum':
        final media = type['media'];
        if (media is List) {
          for (final item in media.whereType<Map<String, dynamic>>()) {
            final attachment = switch (item.type) {
              'linkPreviewAlbumMediaPhoto' => photoAttachment(
                item.obj('photo'),
              ),
              'linkPreviewAlbumMediaVideo' => videoAttachment(
                item.obj('video'),
                item,
              ),
              _ => const MediaAttachment(),
            };
            if (attachment.image != null || attachment.video != null) {
              return attachment;
            }
          }
        }
      case 'linkPreviewTypeDocument':
        final document = type.obj('document');
        return MediaAttachment(
          image: fileRef(document?.obj('thumbnail')?.obj('file')),
        );
      case 'linkPreviewTypeAudio':
      case 'linkPreviewTypeEmbeddedAudioPlayer':
      case 'linkPreviewTypeExternalAudio':
        final audio = type.obj('audio');
        return MediaAttachment(
          image: fileRef(audio?.obj('album_cover_thumbnail')?.obj('file')),
        );
    }
    return const MediaAttachment();
  }

  static MediaAttachment photoAttachment(Map<String, dynamic>? photo) {
    if (photo == null) return const MediaAttachment();
    final mini = decodeMiniThumb(photo.obj('minithumbnail'));
    final sizes = photo.objects('sizes');
    if (sizes == null || sizes.isEmpty) return const MediaAttachment();
    final best = bestPhotoSize(sizes);
    final thumbnail = photoThumbnailSize(sizes, best);
    return MediaAttachment(
      image: fileRef(
        best.obj('photo'),
        miniThumb: mini,
        thumbnail: fileRef(thumbnail?.obj('photo'), miniThumb: mini),
      ),
      width: best.integer('width'),
      height: best.integer('height'),
    );
  }

  static MediaAttachment videoAttachment(
    Map<String, dynamic>? video, [
    Map<String, dynamic>? fallback,
  ]) {
    if (video == null) {
      return MediaAttachment(
        width: fallback?.integer('width'),
        height: fallback?.integer('height'),
        videoDuration: fallback?.integer('duration'),
      );
    }
    final mini = decodeMiniThumb(video.obj('minithumbnail'));
    return MediaAttachment(
      image: fileRef(video.obj('thumbnail')?.obj('file'), miniThumb: mini),
      video: fileRef(video.obj('video')),
      videoDuration: video.integer('duration') ?? fallback?.integer('duration'),
      width: video.integer('width') ?? fallback?.integer('width'),
      height: video.integer('height') ?? fallback?.integer('height'),
    );
  }

  static MediaAttachment animationAttachment(
    Map<String, dynamic>? animation, [
    Map<String, dynamic>? fallback,
  ]) {
    if (animation == null) {
      return MediaAttachment(
        width: fallback?.integer('width'),
        height: fallback?.integer('height'),
        videoDuration: fallback?.integer('duration'),
      );
    }
    final mini = decodeMiniThumb(animation.obj('minithumbnail'));
    final thumb =
        fileRef(animation.obj('thumbnail')?.obj('file'), miniThumb: mini) ??
        fileRef(animation.obj('animation'), miniThumb: mini);
    return MediaAttachment(
      image: thumb,
      video: fileRef(animation.obj('animation'), miniThumb: mini),
      videoDuration:
          animation.integer('duration') ?? fallback?.integer('duration'),
      width: animation.integer('width') ?? fallback?.integer('width'),
      height: animation.integer('height') ?? fallback?.integer('height'),
    );
  }

  /// Parses message.interaction_info.reactions into reaction buckets.
  static List<MessageReaction> reactionsFrom(Map<String, dynamic> message) {
    final list = message
        .obj('interaction_info')
        ?.obj('reactions')
        ?.objects('reactions');
    if (list == null) return const [];
    return list.map((r) {
      final type = r.obj('type');
      return MessageReaction(
        emoji: type?.type == 'reactionTypeEmoji' ? type?.str('emoji') : null,
        customEmojiId: type?.type == 'reactionTypeCustomEmoji'
            ? (type?.int64('custom_emoji_id') ?? 0)
            : 0,
        count: r.integer('total_count') ?? 0,
        chosen: r.boolean('is_chosen') ?? false,
      );
    }).toList();
  }

  static List<List<MessageButton>> messageButtonRows(
    Map<String, dynamic>? replyMarkup,
  ) {
    if (replyMarkup == null) return const [];
    final type = replyMarkup.type;
    if (type != 'replyMarkupInlineKeyboard' &&
        type != 'replyMarkupShowKeyboard') {
      return const [];
    }
    final rows = replyMarkup['rows'];
    if (rows is! List) return const [];
    final out = <List<MessageButton>>[];
    for (final row in rows) {
      if (row is! List) continue;
      final buttons = row
          .whereType<Map<String, dynamic>>()
          .map(
            (button) => _messageButton(
              button,
              isReplyKeyboard: type == 'replyMarkupShowKeyboard',
            ),
          )
          .whereType<MessageButton>()
          .toList();
      if (buttons.isNotEmpty) out.add(buttons);
    }
    return out;
  }

  static MessageButton? _messageButton(
    Map<String, dynamic> button, {
    required bool isReplyKeyboard,
  }) {
    final text = (button.str('text') ?? '').trim();
    if (text.isEmpty) return null;
    final type = button.obj('type');
    final typeName = type?.type ?? '';
    final loginUrl = type?.obj('url');
    final webApp = type?.obj('web_app');
    final copyText = type?.obj('copy_text')?.str('text');
    return MessageButton(
      text: text,
      type: typeName,
      url: type?.str('url') ?? loginUrl?.str('url') ?? webApp?.str('url'),
      data: type?.str('data'),
      userId: type?.int64('user_id'),
      copyText: type?.str('text') ?? copyText,
      switchInlineQuery: type?.str('query'),
      isReplyKeyboard: isReplyKeyboard,
    );
  }

  /// Extracts textEntityTypeCustomEmoji spans from a formattedText object.
  static List<CustomEmojiEntity> customEmojiEntities(Map<String, dynamic>? ft) {
    return customEmojiEntitiesFrom(textEntities(ft));
  }

  static List<CustomEmojiEntity> customEmojiEntitiesFrom(
    List<MessageTextEntity> entities,
  ) {
    return entities
        .where((e) => e.customEmojiId != null)
        .map((e) => CustomEmojiEntity(e.offset, e.length, e.customEmojiId!))
        .toList();
  }

  static List<CustomEmojiEntity> customEmojiEntitiesForContent(
    Map<String, dynamic>? content,
  ) {
    return customEmojiEntitiesFrom(messageTextEntities(content));
  }

  static Map<String, dynamic>? formattedTextForContent(
    Map<String, dynamic>? content,
  ) {
    switch (content?.type) {
      case 'messageText':
        return content?.obj('text');
      case 'messageAnimation':
      case 'messageAudio':
      case 'messageDocument':
      case 'messagePaidMedia':
      case 'messagePhoto':
      case 'messageVideo':
      case 'messageVoiceNote':
        return content?.obj('caption');
      default:
        return null;
    }
  }

  static List<MessageTextEntity> messageTextEntities(
    Map<String, dynamic>? content,
  ) {
    if (content == null) return const [];
    if (content.type == 'messageRichMessage') {
      return _richMessageText(content.obj('message'))?.entities ?? const [];
    }
    return textEntities(formattedTextForContent(content));
  }

  static List<MessageTextEntity> textEntities(Map<String, dynamic>? ft) {
    final raw = ft?.objects('entities');
    if (raw == null) return const [];
    final out = <MessageTextEntity>[];
    for (final e in raw) {
      final type = e.obj('type');
      final typeName = type?.type;
      final offset = e.integer('offset');
      final length = e.integer('length');
      if (typeName == null || offset == null || length == null || length <= 0) {
        continue;
      }
      out.add(
        MessageTextEntity(
          offset: offset,
          length: length,
          type: typeName,
          url: type?.str('url'),
          userId: type?.int64('user_id'),
          customEmojiId: type?.int64('custom_emoji_id'),
          language: type?.str('language'),
        ),
      );
    }
    return out;
  }

  static String richTextText(Map<String, dynamic>? value) {
    return _richText(value).text;
  }

  static List<MessageTextEntity> richTextEntities(Map<String, dynamic>? value) {
    return _richText(value).entities;
  }

  static List<RichMessageBlock> richMessageBlocks(
    Map<String, dynamic>? content,
  ) {
    if (content?.type != 'messageRichMessage') return const [];
    final blocks = content?.obj('message')?.objects('blocks');
    if (blocks == null || blocks.isEmpty) return const [];
    final out = <RichMessageBlock>[];
    for (final block in blocks) {
      _appendRichBlocks(out, block);
    }
    return out;
  }

  static void _appendRichBlocks(
    List<RichMessageBlock> out,
    Map<String, dynamic> block,
  ) {
    final parsed = _parseRichBlock(block);
    if (parsed != null) out.add(parsed);
  }

  static RichMessageBlock? _parseRichBlock(Map<String, dynamic> block) {
    switch (block.type) {
      case 'pageBlockParagraph':
      case 'RichBlockParagraph':
        final text = _richBlockText(block.obj('text'));
        return RichMessageBlock.text(
          kind: RichMessageBlockKind.paragraph,
          text: text.text,
          entities: text.entities,
        );
      case 'pageBlockSectionHeading':
      case 'RichBlockSectionHeading':
        final text = _richBlockText(block.obj('text'));
        return RichMessageBlock.text(
          kind: RichMessageBlockKind.heading,
          text: text.text,
          entities: text.entities,
          size: (block.integer('size') ?? 1).clamp(1, 6),
        );
      case 'pageBlockPreformatted':
      case 'RichBlockPreformatted':
        final text = _richBlockText(block.obj('text'));
        return RichMessageBlock.text(
          kind: RichMessageBlockKind.preformatted,
          text: text.text,
          entities: text.entities,
          language: block.str('language') ?? '',
        );
      case 'pageBlockFooter':
      case 'RichBlockFooter':
        final text = _richBlockText(block.obj('footer') ?? block.obj('text'));
        return RichMessageBlock.text(
          kind: RichMessageBlockKind.footer,
          text: text.text,
          entities: text.entities,
        );
      case 'pageBlockThinking':
      case 'RichBlockThinking':
        final text = _richBlockText(block.obj('text'));
        return RichMessageBlock.text(
          kind: RichMessageBlockKind.thinking,
          text: text.text,
          entities: text.entities,
        );
      case 'pageBlockDivider':
      case 'RichBlockDivider':
        return const RichMessageBlock.container(
          kind: RichMessageBlockKind.divider,
        );
      case 'pageBlockAnchor':
      case 'RichBlockAnchor':
        return RichMessageBlock.container(
          kind: RichMessageBlockKind.anchor,
          name: block.str('name') ?? '',
        );
      case 'pageBlockList':
      case 'RichBlockList':
        final items = <RichMessageListItem>[];
        for (final item
            in block.objects('items') ?? const <Map<String, dynamic>>[]) {
          items.add(
            RichMessageListItem(
              blocks: _parseRichChildren(item.objects('blocks')),
              label: item.str('label') ?? '',
              hasCheckbox: item.boolean('has_checkbox') ?? false,
              isChecked: item.boolean('is_checked') ?? false,
              value: item.integer('value') ?? 0,
              numberingType: item.str('type') ?? '',
            ),
          );
        }
        return RichMessageBlock.container(
          kind: RichMessageBlockKind.list,
          listItems: items,
        );
      case 'pageBlockBlockQuote':
      case 'RichBlockBlockQuotation':
        final credit = _richBlockText(block.obj('credit'));
        return RichMessageBlock.container(
          kind: RichMessageBlockKind.blockQuote,
          children: _parseRichChildren(block.objects('blocks')),
          caption: credit.text,
          captionEntities: credit.entities,
        );
      case 'pageBlockPullQuote':
      case 'RichBlockPullQuotation':
        final text = _richBlockText(block.obj('text'));
        final credit = _richBlockText(block.obj('credit'));
        return RichMessageBlock.container(
          kind: RichMessageBlockKind.pullQuote,
          text: text.text,
          textEntities: text.entities,
          caption: credit.text,
          captionEntities: credit.entities,
        );
      case 'pageBlockTable':
      case 'RichBlockTable':
        final rows = _richTableRows(block['cells'] ?? block['rows']);
        if (rows.isEmpty) return null;
        final caption = _richBlockCaption(block.obj('caption'));
        return RichMessageBlock.captionedTable(
          tableRows: rows,
          caption: caption.text,
          captionEntities: caption.entities,
          isBordered:
              block.boolean('is_bordered') ??
              block.boolean('isBordered') ??
              block.boolean('bordered') ??
              false,
          isStriped:
              block.boolean('is_striped') ??
              block.boolean('isStriped') ??
              block.boolean('striped') ??
              false,
        );
      case 'pageBlockMathematicalExpression':
      case 'RichBlockMathematicalExpression':
        final expression =
            block.str('expression') ??
            block.str('formula') ??
            block.str('source') ??
            '';
        return expression.trim().isEmpty
            ? null
            : RichMessageBlock.math(expression);
      case 'pageBlockPhoto':
      case 'RichBlockPhoto':
        return _richMediaBlock(block, RichMessageBlockKind.photo, {
          '@type': 'messagePhoto',
          'photo': block['photo'],
        });
      case 'pageBlockVideo':
      case 'RichBlockVideo':
        return _richMediaBlock(block, RichMessageBlockKind.video, {
          '@type': 'messageVideo',
          'video': block['video'],
        });
      case 'pageBlockAnimation':
      case 'RichBlockAnimation':
        return _richMediaBlock(block, RichMessageBlockKind.animation, {
          '@type': 'messageAnimation',
          'animation': block['animation'],
        });
      case 'pageBlockAudio':
      case 'RichBlockAudio':
        return _richMediaBlock(block, RichMessageBlockKind.audio, {
          '@type': 'messageAudio',
          'audio': block['audio'],
        });
      case 'pageBlockVoiceNote':
      case 'RichBlockVoiceNote':
        final caption = _richBlockCaption(block.obj('caption'));
        final voice = voiceAttachment({
          '@type': 'messageVoiceNote',
          'voice_note': block['voice_note'] ?? block['voice'],
        });
        return RichMessageBlock.media(
          kind: RichMessageBlockKind.voiceNote,
          voice: voice,
          caption: caption.text,
          captionEntities: caption.entities,
        );
      case 'pageBlockMap':
      case 'richBlockMap':
      case 'RichBlockMap':
      case 'map':
        final location = block.obj('location');
        final latitude =
            location?.dbl('latitude') ??
            location?.dbl('lat') ??
            block.dbl('latitude') ??
            block.dbl('lat');
        final longitude =
            location?.dbl('longitude') ??
            location?.dbl('long') ??
            location?.dbl('lon') ??
            block.dbl('longitude') ??
            block.dbl('long') ??
            block.dbl('lon');
        if (latitude == null || longitude == null) return null;
        final caption = _richBlockCaption(block.obj('caption'));
        return RichMessageBlock.map(
          mapLocation: MessageLocation(
            latitude: latitude,
            longitude: longitude,
            title: caption.text.isEmpty ? null : caption.text,
          ),
          mapZoom: (block.integer('zoom') ?? 16).clamp(0, 24),
          mapWidth: (block.integer('width') ?? 220).clamp(1, 10000),
          mapHeight: (block.integer('height') ?? 120).clamp(1, 10000),
          caption: caption.text,
          captionEntities: caption.entities,
        );
      case 'pageBlockCollage':
      case 'RichBlockCollage':
        final caption = _richBlockCaption(block.obj('caption'));
        return RichMessageBlock.container(
          kind: RichMessageBlockKind.collage,
          children: _parseRichChildren(block.objects('blocks')),
          caption: caption.text,
          captionEntities: caption.entities,
        );
      case 'pageBlockSlideshow':
      case 'RichBlockSlideshow':
        final caption = _richBlockCaption(block.obj('caption'));
        return RichMessageBlock.container(
          kind: RichMessageBlockKind.slideshow,
          children: _parseRichChildren(block.objects('blocks')),
          caption: caption.text,
          captionEntities: caption.entities,
        );
      case 'pageBlockDetails':
      case 'RichBlockDetails':
        final header = _richBlockText(block.obj('header'));
        return RichMessageBlock.container(
          kind: RichMessageBlockKind.details,
          text: header.text,
          textEntities: header.entities,
          children: _parseRichChildren(block.objects('blocks')),
          isOpen: block.boolean('is_open') ?? block.boolean('isOpen') ?? false,
        );
      case 'pageBlockCover':
      case 'RichBlockCover':
        final cover = block.obj('cover');
        return cover == null ? null : _parseRichBlock(cover);
    }
    return null;
  }

  static List<RichMessageBlock> _parseRichChildren(
    List<Map<String, dynamic>>? blocks,
  ) {
    if (blocks == null) return const [];
    return blocks.map(_parseRichBlock).whereType<RichMessageBlock>().toList();
  }

  static _ParsedMarkdownText _richBlockText(Map<String, dynamic>? value) {
    if (value == null) return const _ParsedMarkdownText('', []);
    return _ParsedMarkdownText(richTextText(value), richTextEntities(value));
  }

  static RichMessageBlock _richMediaBlock(
    Map<String, dynamic> block,
    RichMessageBlockKind kind,
    Map<String, dynamic> content,
  ) {
    final media = mediaAttachment(content);
    final caption = _richBlockCaption(block.obj('caption'));
    return RichMessageBlock.media(
      kind: kind,
      image: media.image,
      imageWidth: media.width,
      imageHeight: media.height,
      video: media.video,
      videoDuration: media.videoDuration ?? 0,
      music: media.music,
      hasSpoiler: block.boolean('has_spoiler') ?? false,
      caption: caption.text,
      captionEntities: caption.entities,
    );
  }

  static _ParsedMarkdownText _richBlockCaption(Map<String, dynamic>? caption) {
    if (caption == null) return const _ParsedMarkdownText('', []);
    final builder = _RichTextBuilder();
    _appendRichText(builder, caption.obj('text') ?? caption);
    _appendCredit(builder, caption.obj('credit'));
    return _ParsedMarkdownText(builder.buffer.toString(), builder.entities);
  }

  static List<List<RichMessageTableCell>> _richTableRows(Object? rows) {
    if (rows is! List) return const [];
    final out = <List<RichMessageTableCell>>[];
    for (final rawRow in rows) {
      final rawCells = rawRow is Map<String, dynamic>
          ? (rawRow['cells'] as Object?)
          : rawRow;
      if (rawCells is! List) continue;
      final row = <RichMessageTableCell>[];
      for (final rawCell in rawCells) {
        if (rawCell is! Map<String, dynamic>) continue;
        final parsed = _richText(rawCell.obj('text') ?? rawCell['content']);
        row.add(
          RichMessageTableCell(
            text: parsed.text,
            entities: parsed.entities,
            isHeader:
                rawCell.boolean('is_header') ??
                rawCell.boolean('isHeader') ??
                false,
            horizontalAlignment: _richTableHorizontalAlignment(rawCell),
            verticalAlignment: _richTableVerticalAlignment(rawCell),
          ),
        );
      }
      if (row.isNotEmpty) out.add(row);
    }
    return out;
  }

  static String _richTableHorizontalAlignment(Map<String, dynamic> cell) {
    final raw = cell['align'];
    if (raw is String && const {'left', 'center', 'right'}.contains(raw)) {
      return raw;
    }
    final type = raw is Map<String, dynamic> ? (raw.type ?? '') : '';
    if (type.toLowerCase().contains('center')) return 'center';
    if (type.toLowerCase().contains('right')) return 'right';
    return 'left';
  }

  static String _richTableVerticalAlignment(Map<String, dynamic> cell) {
    final raw = cell['valign'];
    if (raw is String && const {'top', 'middle', 'bottom'}.contains(raw)) {
      return raw;
    }
    final type = raw is Map<String, dynamic> ? (raw.type ?? '') : '';
    if (type.toLowerCase().contains('middle')) return 'middle';
    if (type.toLowerCase().contains('bottom')) return 'bottom';
    return 'top';
  }

  static ({
    String text,
    List<MessageTextEntity> entities,
    List<RichMessageBlock> blocks,
  })
  _extractMarkdownTables(String text, List<MessageTextEntity> entities) {
    final lines = text.split('\n');
    final starts = <int>[];
    var offset = 0;
    for (final line in lines) {
      starts.add(offset);
      offset += line.length + 1;
    }
    final removals = <({int start, int end})>[];
    final blocks = <RichMessageBlock>[];
    var i = 0;
    while (i < lines.length - 1) {
      if (!_looksLikeMarkdownTableRow(lines[i]) ||
          !_looksLikeMarkdownSeparatorRow(lines[i + 1])) {
        i++;
        continue;
      }
      final rows = <List<RichMessageTableCell>>[
        _markdownTableCells(lines[i], isHeader: true),
      ];
      var endLine = i + 2;
      while (endLine < lines.length &&
          _looksLikeMarkdownTableRow(lines[endLine])) {
        rows.add(_markdownTableCells(lines[endLine]));
        endLine++;
      }
      if (rows.length > 1) {
        blocks.add(RichMessageBlock.table(rows));
        if (endLine < lines.length && lines[endLine].trim().isEmpty) {
          endLine++;
        }
        final start = starts[i];
        final end = endLine >= lines.length ? text.length : starts[endLine];
        removals.add((start: start, end: end));
        i = endLine;
      } else {
        i++;
      }
    }
    if (removals.isEmpty) {
      return (text: text, entities: entities, blocks: const []);
    }
    final buffer = StringBuffer();
    var cursor = 0;
    for (final removal in removals) {
      buffer.write(text.substring(cursor, removal.start));
      cursor = removal.end;
    }
    buffer.write(text.substring(cursor));
    final stripped = buffer.toString().trimRight();
    final adjusted = <MessageTextEntity>[];
    for (final entity in entities) {
      var removedBefore = 0;
      var overlaps = false;
      for (final removal in removals) {
        if (entity.end <= removal.start) continue;
        if (entity.offset >= removal.end) {
          removedBefore += removal.end - removal.start;
          continue;
        }
        overlaps = true;
        break;
      }
      if (overlaps) continue;
      adjusted.add(
        MessageTextEntity(
          offset: entity.offset - removedBefore,
          length: entity.length,
          type: entity.type,
          url: entity.url,
          userId: entity.userId,
          customEmojiId: entity.customEmojiId,
          language: entity.language,
        ),
      );
    }
    return (text: stripped, entities: adjusted, blocks: blocks);
  }

  static bool _looksLikeMarkdownTableRow(String line) {
    final trimmed = line.trim();
    return trimmed.startsWith('|') &&
        trimmed.endsWith('|') &&
        _splitMarkdownTableRow(trimmed).length >= 2;
  }

  static bool _looksLikeMarkdownSeparatorRow(String line) {
    final cells = _splitMarkdownTableRow(line);
    if (cells.length < 2) return false;
    return cells.every((cell) => RegExp(r'^:?-{3,}:?$').hasMatch(cell.trim()));
  }

  static List<RichMessageTableCell> _markdownTableCells(
    String line, {
    bool isHeader = false,
  }) {
    return _splitMarkdownTableRow(line)
        .map(
          (cell) => RichMessageTableCell(
            text: cell.replaceAll(r'\|', '|').trim(),
            isHeader: isHeader,
          ),
        )
        .toList();
  }

  static List<String> _splitMarkdownTableRow(String line) {
    final trimmed = line.trim();
    final start = trimmed.startsWith('|') ? 1 : 0;
    final end = trimmed.endsWith('|') ? trimmed.length - 1 : trimmed.length;
    if (end <= start) return const [];
    final content = trimmed.substring(start, end);
    final cells = <String>[];
    final buffer = StringBuffer();
    var escaped = false;
    for (final codeUnit in content.codeUnits) {
      final char = String.fromCharCode(codeUnit);
      if (escaped) {
        buffer.write(char);
        escaped = false;
      } else if (char == '\\') {
        buffer.write(char);
        escaped = true;
      } else if (char == '|') {
        cells.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    cells.add(buffer.toString());
    return cells;
  }

  static _ParsedMarkdownText _richText(Object? value) {
    final builder = _RichTextBuilder();
    _appendRichText(builder, value);
    return _ParsedMarkdownText(builder.buffer.toString(), builder.entities);
  }

  static void _appendRichText(_RichTextBuilder builder, Object? value) {
    if (value == null) return;
    if (value is String) {
      builder.write(value);
      return;
    }
    if (value is List) {
      for (final item in value) {
        _appendRichText(builder, item);
      }
      return;
    }
    if (value is! Map<String, dynamic>) return;

    final type = value.type;
    final normalizedType = _normalizedRichTextType(type);
    switch (type) {
      case 'textEmpty':
      case 'richTextAnchor':
      case 'RichTextAnchor':
      case 'textAnchor':
        return;
      case 'richTextPlain':
      case 'RichTextPlain':
      case 'textPlain':
        builder.write(value.str('text') ?? '');
        return;
      case 'richTexts':
      case 'RichTexts':
      case 'RichText':
      case 'textConcat':
        for (final item
            in value.objects('texts') ?? const <Map<String, dynamic>>[]) {
          _appendRichText(builder, item);
        }
        return;
      case 'richTextCustomEmoji':
      case 'RichTextCustomEmoji':
        final alt =
            value.str('alternative_text') ??
            value.str('text') ??
            value.str('emoji') ??
            '';
        if (alt.isEmpty) return;
        final start = builder.length;
        builder.write(alt);
        builder.entity(
          start,
          'textEntityTypeCustomEmoji',
          customEmojiId: value.int64('custom_emoji_id'),
        );
        return;
      case 'richTextIcon':
      case 'RichTextIcon':
      case 'textImage':
        builder.write(telegramText(AppStringKeys.composerImagePreview));
        return;
      case 'richTextMathematicalExpression':
      case 'RichTextMathematicalExpression':
        final expression =
            value.str('expression') ??
            value.str('formula') ??
            value.str('source') ??
            '';
        final start = builder.length;
        builder.write(expression);
        builder.entity(start, 'textEntityTypeMathematicalExpression');
        return;
    }

    final child = value['text'];
    final start = builder.length;
    if (child != null) {
      _appendRichText(builder, child);
    } else {
      builder.write(_richTextFallbackText(normalizedType, value));
    }
    final entityType = _richTextEntityType(type);
    if (entityType == null) return;
    builder.entity(
      start,
      entityType,
      url: _richTextEntityUrl(type, value),
      userId: _richTextUserId(value),
    );
  }

  static String _normalizedRichTextType(String? type) {
    if (type == null || type.isEmpty) return '';
    if (type.startsWith('RichText')) {
      return 'richText${type.substring('RichText'.length)}';
    }
    return type;
  }

  static String _richTextFallbackText(
    String normalizedType,
    Map<String, dynamic> value,
  ) {
    final direct = value.str('text') ?? value.str('alternative_text');
    if (direct != null) return direct;
    switch (normalizedType) {
      case 'richTextDateTime':
        return value.str('time_text') ??
            value.str('datetime') ??
            value.str('format') ??
            '';
      case 'richTextEmailAddress':
        return value.str('email_address') ?? '';
      case 'richTextPhoneNumber':
        return value.str('phone_number') ?? '';
      case 'richTextBankCardNumber':
        return value.str('bank_card_number') ?? value.str('number') ?? '';
      case 'richTextMention':
        final username = value.str('username');
        return username == null || username.isEmpty ? '' : '@$username';
      case 'richTextHashtag':
        final hashtag = value.str('hashtag');
        return hashtag == null || hashtag.isEmpty ? '' : '#$hashtag';
      case 'richTextCashtag':
        final cashtag = value.str('cashtag');
        return cashtag == null || cashtag.isEmpty ? '' : '\$$cashtag';
      case 'richTextBotCommand':
        final command = value.str('bot_command') ?? value.str('command');
        return command == null || command.isEmpty ? '' : '/$command';
      case 'richTextAnchorLink':
      case 'richTextReferenceLink':
        return value.str('name') ?? value.str('url') ?? '';
      case 'richTextReference':
        return value.str('name') ?? '';
      default:
        return '';
    }
  }

  static int? _richTextUserId(Map<String, dynamic> value) {
    return value.int64('user_id') ??
        value.obj('user')?.int64('id') ??
        value.obj('text_mention')?.int64('user_id') ??
        value.obj('text_mention')?.obj('user')?.int64('id');
  }

  static String? _richTextEntityType(String? type) {
    switch (_normalizedRichTextType(type)) {
      case 'richTextBold':
      case 'textBold':
        return 'textEntityTypeBold';
      case 'richTextItalic':
      case 'textItalic':
        return 'textEntityTypeItalic';
      case 'richTextUnderline':
      case 'textUnderline':
        return 'textEntityTypeUnderline';
      case 'richTextStrikethrough':
      case 'textStrike':
        return 'textEntityTypeStrikethrough';
      case 'richTextSpoiler':
        return 'textEntityTypeSpoiler';
      case 'richTextCode':
      case 'richTextFixed':
      case 'textFixed':
        return 'textEntityTypeCode';
      case 'richTextTextMention':
      case 'richTextMentionName':
        return 'textEntityTypeMentionName';
      case 'richTextUrl':
      case 'textUrl':
      case 'richTextReferenceLink':
      case 'richTextAnchorLink':
        return 'textEntityTypeTextUrl';
      case 'richTextMention':
        return 'textEntityTypeTextUrl';
      case 'richTextEmailAddress':
      case 'textEmail':
        return 'textEntityTypeEmailAddress';
      case 'richTextPhoneNumber':
      case 'textPhone':
        return 'textEntityTypePhoneNumber';
      case 'richTextHashtag':
        return 'textEntityTypeHashtag';
      case 'richTextCashtag':
        return 'textEntityTypeCashtag';
      case 'richTextBotCommand':
        return 'textEntityTypeBotCommand';
      case 'richTextBankCardNumber':
        return 'textEntityTypeBankCardNumber';
      case 'richTextMarked':
      case 'textMarked':
        return 'textEntityTypeMarked';
      case 'richTextSubscript':
      case 'textSubscript':
        return 'textEntityTypeSubscript';
      case 'richTextSuperscript':
      case 'textSuperscript':
        return 'textEntityTypeSuperscript';
      case 'richTextDateTime':
        return 'textEntityTypeDateTime';
      default:
        return null;
    }
  }

  static String? _richTextEntityUrl(String? type, Map<String, dynamic> value) {
    switch (_normalizedRichTextType(type)) {
      case 'richTextUrl':
      case 'textUrl':
      case 'richTextReferenceLink':
      case 'richTextAnchorLink':
        final url = value.str('url') ?? value.str('href');
        if (url != null && url.isNotEmpty) return url;
        final name =
            value.str('anchor_name') ??
            value.str('reference_name') ??
            value.str('name');
        return name == null || name.isEmpty ? null : '#$name';
      case 'richTextMention':
        final username = value.str('username');
        return username == null || username.isEmpty
            ? null
            : 'https://t.me/$username';
      default:
        return null;
    }
  }

  static _ParsedMarkdownText? _richMessageText(Map<String, dynamic>? message) {
    final blocks = message?.objects('blocks');
    if (blocks == null || blocks.isEmpty) return null;
    final builder = _RichTextBuilder();
    for (final block in blocks) {
      final before = builder.length;
      _appendPageBlock(builder, block);
      if (builder.length > before) builder.blankLine();
    }
    final text = builder.buffer.toString().trimRight();
    if (text.isEmpty) return null;
    final entities = builder.entities
        .where((entity) => entity.offset < text.length)
        .map(
          (entity) => MessageTextEntity(
            offset: entity.offset,
            length:
                entity.end.clamp(entity.offset, text.length) - entity.offset,
            type: entity.type,
            url: entity.url,
            userId: entity.userId,
            customEmojiId: entity.customEmojiId,
            language: entity.language,
          ),
        )
        .where((entity) => entity.length > 0)
        .toList();
    return _ParsedMarkdownText(text, entities);
  }

  static void _appendPageBlock(
    _RichTextBuilder builder,
    Map<String, dynamic> block,
  ) {
    final start = builder.length;
    switch (block.type) {
      case 'pageBlockTitle':
        _appendRichText(builder, block.obj('title'));
      case 'pageBlockSubtitle':
        _appendRichText(builder, block.obj('subtitle'));
      case 'pageBlockAuthorDate':
        _appendRichText(builder, block.obj('author'));
      case 'pageBlockHeader':
        _appendRichText(builder, block.obj('header'));
      case 'pageBlockSubheader':
        _appendRichText(builder, block.obj('subheader'));
      case 'pageBlockSectionHeading':
      case 'pageBlockParagraph':
      case 'pageBlockThinking':
        _appendRichText(builder, block.obj('text'));
      case 'pageBlockKicker':
        _appendRichText(builder, block.obj('kicker'));
      case 'pageBlockFooter':
        _appendRichText(builder, block.obj('footer'));
      case 'pageBlockPreformatted':
        _appendRichText(builder, block.obj('text'));
        builder.entity(
          start,
          'textEntityTypePreCode',
          language: block.str('language'),
        );
      case 'pageBlockMathematicalExpression':
        return;
      case 'pageBlockList':
        _appendPageBlockList(builder, block.objects('items'));
      case 'pageBlockBlockQuote':
        _appendPageBlocks(builder, block.objects('blocks'));
        _appendCredit(builder, block.obj('credit'));
        builder.entity(start, 'textEntityTypeBlockQuote');
      case 'pageBlockPullQuote':
        _appendRichText(builder, block.obj('text'));
        _appendCredit(builder, block.obj('credit'));
        builder.entity(start, 'textEntityTypeBlockQuote');
      case 'pageBlockAnimation':
      case 'pageBlockAudio':
      case 'pageBlockPhoto':
      case 'pageBlockVideo':
      case 'pageBlockVoiceNote':
      case 'pageBlockEmbedded':
        _appendCaption(builder, block.obj('caption'));
      case 'pageBlockMap':
      case 'richBlockMap':
      case 'RichBlockMap':
      case 'map':
        return;
      case 'pageBlockCover':
        final cover = block.obj('cover');
        if (cover != null) _appendPageBlock(builder, cover);
      case 'pageBlockEmbeddedPost':
      case 'pageBlockCollage':
      case 'pageBlockSlideshow':
        _appendPageBlocks(builder, block.objects('blocks'));
        _appendCaption(builder, block.obj('caption'));
      case 'pageBlockTable':
        return;
      case 'pageBlockDetails':
        _appendRichText(builder, block.obj('header'));
        builder.lineBreak();
        _appendPageBlocks(builder, block.objects('blocks'));
      case 'pageBlockRelatedArticles':
        _appendRichText(builder, block.obj('header'));
        _appendRelatedArticles(builder, block.objects('articles'));
      case 'pageBlockChatLink':
        builder.write(block.str('title') ?? '');
      case 'pageBlockDivider':
      case 'pageBlockAnchor':
        return;
    }
  }

  static void _appendPageBlocks(
    _RichTextBuilder builder,
    List<Map<String, dynamic>>? blocks,
  ) {
    if (blocks == null) return;
    for (final block in blocks) {
      final before = builder.length;
      _appendPageBlock(builder, block);
      if (builder.length > before) builder.lineBreak();
    }
  }

  static void _appendPageBlockList(
    _RichTextBuilder builder,
    List<Map<String, dynamic>>? items,
  ) {
    if (items == null) return;
    for (final item in items) {
      final label = item.str('label');
      final checked = item.boolean('is_checked') ?? false;
      if (item.boolean('has_checkbox') ?? false) {
        builder.write(checked ? '[x] ' : '[ ] ');
      } else if (label != null && label.isNotEmpty) {
        builder.write('$label ');
      } else {
        builder.write('- ');
      }
      _appendPageBlocks(builder, item.objects('blocks'));
    }
  }

  static void _appendCaption(
    _RichTextBuilder builder,
    Map<String, dynamic>? caption,
  ) {
    if (caption == null) return;
    _appendRichText(builder, caption.obj('text'));
    _appendCredit(builder, caption.obj('credit'));
  }

  static void _appendCredit(
    _RichTextBuilder builder,
    Map<String, dynamic>? credit,
  ) {
    if (credit == null) return;
    if (richTextText(credit).trim().isEmpty) return;
    builder.lineBreak();
    _appendRichText(builder, credit);
  }

  static void _appendRelatedArticles(
    _RichTextBuilder builder,
    List<Map<String, dynamic>>? articles,
  ) {
    if (articles == null) return;
    for (final article in articles) {
      builder.lineBreak();
      final title = article.str('title') ?? article.str('url') ?? '';
      if (title.isNotEmpty) builder.write('- $title');
    }
  }

  static _ParsedMarkdownText? _markdownText(String text) {
    if (!text.contains('*') &&
        !text.contains('_') &&
        !text.contains('~') &&
        !text.contains('`')) {
      return null;
    }
    const markers = [
      _MarkdownMarker('```', 'textEntityTypePre'),
      _MarkdownMarker('~~', 'textEntityTypeStrikethrough'),
      _MarkdownMarker('**', 'textEntityTypeBold'),
      _MarkdownMarker('__', 'textEntityTypeUnderline'),
      _MarkdownMarker('`', 'textEntityTypeCode'),
      _MarkdownMarker('*', 'textEntityTypeItalic'),
      _MarkdownMarker('_', 'textEntityTypeItalic'),
    ];
    final buffer = StringBuffer();
    final entities = <MessageTextEntity>[];
    var i = 0;
    var changed = false;
    while (i < text.length) {
      _MarkdownMarker? matched;
      for (final marker in markers) {
        if (text.startsWith(marker.marker, i)) {
          matched = marker;
          break;
        }
      }
      if (matched == null) {
        buffer.write(text[i]);
        i += 1;
        continue;
      }

      final contentStart = i + matched.marker.length;
      final contentEnd = text.indexOf(matched.marker, contentStart);
      if (contentEnd <= contentStart) {
        buffer.write(text[i]);
        i += 1;
        continue;
      }

      final inner = text.substring(contentStart, contentEnd);
      if (inner.trim().isEmpty) {
        buffer.write(text[i]);
        i += 1;
        continue;
      }

      final offset = buffer.length;
      buffer.write(inner);
      entities.add(
        MessageTextEntity(
          offset: offset,
          length: inner.length,
          type: matched.type,
        ),
      );
      i = contentEnd + matched.marker.length;
      changed = true;
    }

    if (!changed || entities.isEmpty) return null;
    return _ParsedMarkdownText(buffer.toString(), entities);
  }

  static MessageLocation? locationAttachment(Map<String, dynamic>? content) {
    if (content == null) return null;
    switch (content.type) {
      case 'messageLocation':
        final l = content.obj('location');
        final lat = l?.dbl('latitude'), lon = l?.dbl('longitude');
        if (lat != null && lon != null) {
          return MessageLocation(latitude: lat, longitude: lon);
        }
      case 'messageVenue':
        final v = content.obj('venue');
        final l = v?.obj('location');
        final lat = l?.dbl('latitude'), lon = l?.dbl('longitude');
        if (lat != null && lon != null) {
          return MessageLocation(
            latitude: lat,
            longitude: lon,
            title: v?.str('title'),
            address: v?.str('address'),
          );
        }
    }
    return null;
  }

  static MessageVoice? voiceAttachment(Map<String, dynamic>? content) {
    if (content == null || content.type != 'messageVoiceNote') return null;
    final note = content.obj('voice_note');
    if (note == null) return null;
    return MessageVoice(
      file: fileRef(note.obj('voice')),
      duration: note.integer('duration') ?? 0,
    );
  }

  static MediaAttachment mediaAttachment(Map<String, dynamic>? content) {
    if (content == null) return const MediaAttachment();
    switch (content.type) {
      case 'messagePhoto':
        final photo = content.obj('photo');
        if (photo != null) {
          final mini = decodeMiniThumb(photo.obj('minithumbnail'));
          final sizes = photo.objects('sizes');
          if (sizes != null && sizes.isNotEmpty) {
            final best = bestPhotoSize(sizes);
            final thumbnail = photoThumbnailSize(sizes, best);
            return MediaAttachment(
              image: fileRef(
                best.obj('photo'),
                miniThumb: mini,
                thumbnail: fileRef(thumbnail?.obj('photo'), miniThumb: mini),
              ),
              width: best.integer('width'),
              height: best.integer('height'),
            );
          }
        }
      case 'messageSticker':
        final sticker = content.obj('sticker');
        if (sticker != null) {
          final thumb = fileRef(sticker.obj('thumbnail')?.obj('file'));
          final stickerFile = fileRef(sticker.obj('sticker'));
          final w = sticker.integer('width'), h = sticker.integer('height');
          final fmt = sticker.obj('format')?.type;
          final isTgs = fmt == 'stickerFormatTgs';
          final isWebm = fmt == 'stickerFormatWebm';
          return MediaAttachment(
            // Static (.webp) stickers are shown directly via `image`, so point at
            // the full sticker file — the thumbnail is low-res and looks blurry
            // scaled up. Animated (.tgs) / video (.webm) keep the thumb only as a
            // placeholder behind the rendered animation.
            image: (isTgs || isWebm) ? thumb : (stickerFile ?? thumb),
            width: w,
            height: h,
            animated: isTgs ? stickerFile : null,
            videoSticker: isWebm ? stickerFile : null,
            stickerFileId: stickerFile?.id,
            stickerSetId: sticker.int64('set_id'),
          );
        }
      case 'messageAnimatedEmoji':
        // A lone emoji → TDLib sends its animated sticker (usually .tgs); render
        // it like a sticker so single emoji animate instead of "[动画表情]" text.
        final sticker = content.obj('animated_emoji')?.obj('sticker');
        if (sticker != null) {
          final thumb = fileRef(sticker.obj('thumbnail')?.obj('file'));
          final stickerFile = fileRef(sticker.obj('sticker'));
          final w = sticker.integer('width'), h = sticker.integer('height');
          final fmt = sticker.obj('format')?.type;
          final isTgs = fmt == 'stickerFormatTgs';
          final isWebm = fmt == 'stickerFormatWebm';
          return MediaAttachment(
            image: (isTgs || isWebm) ? thumb : (stickerFile ?? thumb),
            width: w,
            height: h,
            animated: isTgs ? stickerFile : null,
            videoSticker: isWebm ? stickerFile : null,
            stickerFileId: stickerFile?.id,
            stickerSetId: sticker.int64('set_id'),
            isAnimatedEmoji: true,
          );
        }
      case 'messageAnimation':
        final anim = content.obj('animation');
        if (anim != null) {
          final mini = decodeMiniThumb(anim.obj('minithumbnail'));
          final thumb =
              fileRef(anim.obj('thumbnail')?.obj('file'), miniThumb: mini) ??
              fileRef(anim.obj('animation'), miniThumb: mini);
          final animation = fileRef(anim.obj('animation'), miniThumb: mini);
          return MediaAttachment(
            image: thumb,
            video: animation,
            videoDuration: anim.integer('duration'),
            width: anim.integer('width'),
            height: anim.integer('height'),
          );
        }
      case 'messageVideo':
        final video = content.obj('video');
        if (video != null) {
          final mini = decodeMiniThumb(video.obj('minithumbnail'));
          return MediaAttachment(
            image: fileRef(
              video.obj('thumbnail')?.obj('file'),
              miniThumb: mini,
            ),
            video: fileRef(video.obj('video')),
            videoDuration: video.integer('duration'),
            width: video.integer('width'),
            height: video.integer('height'),
          );
        }
      case 'messageAudio':
        final audio = content.obj('audio');
        if (audio != null) {
          final mini = decodeMiniThumb(audio.obj('album_cover_minithumbnail'));
          final title = _cleanString(audio.str('title'));
          final fileName = _cleanString(audio.str('file_name'));
          final performer = _cleanString(audio.str('performer'));
          return MediaAttachment(
            music: MessageMusic(
              title:
                  title ??
                  fileName ??
                  AppStrings.t(AppStringKeys.profileDetailMusic),
              performer: performer,
              cover: fileRef(
                audio.obj('album_cover_thumbnail')?.obj('file'),
                miniThumb: mini,
              ),
              file: fileRef(audio.obj('audio')),
              duration: audio.integer('duration') ?? 0,
            ),
          );
        }
      case 'messageDocument':
        final doc = content.obj('document');
        if (doc != null) {
          final f = doc.obj('document');
          final name =
              doc.str('file_name') ??
              telegramText(AppStringKeys.topicPostContentFile);
          final dot = name.lastIndexOf('.');
          final ext = dot >= 0 ? name.substring(dot + 1).toUpperCase() : '';
          return MediaAttachment(
            document: MessageDocument(
              fileName: name,
              size: f?.int64('size') ?? 0,
              ext: ext,
              file: fileRef(f),
            ),
          );
        }
    }
    return const MediaAttachment();
  }

  static String messageText(Map<String, dynamic> content) {
    if (isServiceContent(content.type)) return serviceText(content);
    switch (content.type) {
      case 'messageText':
        return content.obj('text')?.str('text') ?? '';
      case 'messageRichMessage':
        return _richMessageText(content.obj('message'))?.text ??
            telegramText(AppStringKeys.chatSearchMessageResultLabel);
      case 'messagePhoto':
        final caption = content.obj('caption')?.str('text') ?? '';
        return caption.isEmpty
            ? telegramText(AppStringKeys.composerImagePreview)
            : caption;
      case 'messageVideo':
        final caption = content.obj('caption')?.str('text') ?? '';
        return caption.isEmpty
            ? telegramText(AppStringKeys.chatVideoPlaceholder)
            : caption;
      case 'messageVideoNote':
        return telegramText(AppStringKeys.tdMessageVideoMessage);
      case 'messageVoiceNote':
        return telegramText(AppStringKeys.composerVoicePreview);
      case 'messageAudio':
        final caption = content.obj('caption')?.str('text') ?? '';
        return caption.isEmpty
            ? telegramText(AppStringKeys.tdMessageMusic)
            : caption;
      case 'messageDocument':
        final caption = content.obj('caption')?.str('text') ?? '';
        if (caption.isNotEmpty) return caption;
        final name = content.obj('document')?.str('file_name');
        return name != null
            ? telegramText(AppStringKeys.tdMessageFileWithName, {
                'value1': name,
              })
            : telegramText(AppStringKeys.channelsFileAttachment);
      case 'messageSticker':
        final emoji = content.obj('sticker')?.str('emoji') ?? '';
        return emoji.isEmpty
            ? telegramText(AppStringKeys.tdMessageStickerPreview)
            : telegramText(AppStringKeys.tdMessageStickerWithEmoji, {
                'value1': emoji,
              });
      case 'messageAnimation':
        final caption = content.obj('caption')?.str('text') ?? '';
        return caption.isEmpty
            ? telegramText(AppStringKeys.composerAnimatedEmojiPreview)
            : caption;
      case 'messageAnimatedEmoji':
        return content.obj('animated_emoji')?.str('emoji') ??
            telegramText(AppStringKeys.composerAnimatedEmojiPreview);
      case 'messageLocation':
        return telegramText(AppStringKeys.composerLocationPreview);
      case 'messageVenue':
        return telegramText(AppStringKeys.composerLocationPreview);
      case 'messageContact':
        return telegramText(AppStringKeys.tdMessageContactCard);
      case 'messagePoll':
        return telegramText(AppStringKeys.tdMessagePoll);
      case 'messageChecklist':
        final title = content.obj('list')?.obj('title')?.str('text') ?? '';
        return title.isEmpty
            ? telegramText(AppStringKeys.tdMessageChecklist)
            : title;
      case 'messageCall':
        return (content.boolean('is_video') ?? false)
            ? telegramText(AppStringKeys.tdMessageVideoCall)
            : telegramText(AppStringKeys.tdMessageVoiceCall);
      case 'messageDice':
        return content.str('emoji') ??
            telegramText(AppStringKeys.tdMessageDice);
      case 'messageGame':
        return telegramText(AppStringKeys.tdMessageGame);
      case 'messageInvoice':
        return telegramText(AppStringKeys.tdMessageProduct);
      case 'messageStory':
        return telegramText(AppStringKeys.tdMessageForwardedStory);
      case 'messageGiveaway':
      case 'messageGiveawayWinners':
      case 'messageGiveawayCompleted':
        return telegramText(AppStringKeys.tdMessageGiveaway);
      case 'messagePaidMedia':
        return telegramText(AppStringKeys.tdMessagePaidContent);
      case 'messagePaidMessagePriceChanged':
      case 'messageDirectMessagePriceChanged':
        return telegramText(AppStringKeys.tdMessagePaidMessageSettingsChanged);
      case 'messageGift':
      case 'messagePremiumGiftCode':
      case 'messageGiftedPremium':
      case 'messageGiftedStars':
      case 'messageGiftedTon':
      case 'messageUpgradedGift':
      case 'messageRefundedUpgradedGift':
        return telegramText(AppStringKeys.tdMessageGift);
      case 'messageSuggestedPostInfo':
      case 'messageSuggestedPostApproved':
      case 'messageSuggestedPostApprovalFailed':
      case 'messageSuggestedPostDeclined':
      case 'messageSuggestedPostPaid':
      case 'messageSuggestedPostRefunded':
        return telegramText(AppStringKeys.tdMessageSubmission);
      case 'messageExpiredPhoto':
        return telegramText(AppStringKeys.tdMessageExpiredPhoto);
      case 'messageExpiredVideo':
        return telegramText(AppStringKeys.tdMessageExpiredVideo);
      case 'messageUnsupported':
        return telegramText(AppStringKeys.tdMessageUnsupportedCurrentVersion);
      default:
        final fallback = _nestedFormattedText(content);
        if (fallback.isNotEmpty) return fallback;
        if (kDebugMode) {
          debugPrint('Unsupported TDLib message content: ${content.type}');
        }
        return telegramText(AppStringKeys.chatSearchMessageResultLabel);
    }
  }

  static String richMessageDisplayText(Map<String, dynamic> content) {
    final text = messageText(content);
    if (content.type == 'messageRichMessage' &&
        richMessageBlocks(content).isNotEmpty &&
        text == telegramText(AppStringKeys.chatSearchMessageResultLabel)) {
      return '';
    }
    return text;
  }

  static String _nestedFormattedText(Object? value) {
    if (value is Map<String, dynamic>) {
      if (value.type == 'formattedText') {
        final text = value.str('text')?.trim() ?? '';
        if (text.isNotEmpty) return text;
      }
      if (_isRichTextType(value.type)) {
        final text = richTextText(value).trim();
        if (text.isNotEmpty) return text;
      }
      if (value.type == 'richMessage') {
        final text = _richMessageText(value)?.text.trim() ?? '';
        if (text.isNotEmpty) return text;
      }
      for (final key in const ['text', 'caption', 'title', 'description']) {
        final obj = value.obj(key);
        final nested = _nestedFormattedText(obj ?? value[key]);
        if (nested.isNotEmpty) return nested;
      }
      for (final entry in value.entries) {
        if (entry.key == '@type') continue;
        final nested = _nestedFormattedText(entry.value);
        if (nested.isNotEmpty) return nested;
      }
    } else if (value is List) {
      for (final item in value) {
        final nested = _nestedFormattedText(item);
        if (nested.isNotEmpty) return nested;
      }
    } else if (value is String) {
      final text = value.trim();
      if (text.isNotEmpty && !text.startsWith('message')) return text;
    }
    return '';
  }

  static bool _isRichTextType(String? type) {
    return type == 'textEmpty' ||
        type == 'textPlain' ||
        type == 'textBold' ||
        type == 'textItalic' ||
        type == 'textUnderline' ||
        type == 'textStrike' ||
        type == 'textFixed' ||
        type == 'textUrl' ||
        type == 'textEmail' ||
        type == 'textConcat' ||
        type == 'textSubscript' ||
        type == 'textSuperscript' ||
        type == 'textMarked' ||
        type == 'textPhone' ||
        type == 'textImage' ||
        type == 'textAnchor' ||
        (type?.startsWith('richText') ?? false) ||
        type == 'richTexts';
  }

  static const _serviceTypes = {
    'messageBasicGroupChatCreate',
    'messageSupergroupChatCreate',
    'messageChatChangeTitle',
    'messageChatChangePhoto',
    'messageChatDeletePhoto',
    'messageChatAddMembers',
    'messageChatJoinByLink',
    'messageChatJoinByRequest',
    'messageChatDeleteMember',
    'messageChatUpgradeTo',
    'messageChatUpgradeFrom',
    'messagePinMessage',
    'messagePaidMessagePriceChanged',
    'messageDirectMessagePriceChanged',
    'messageContactRegistered',
    'messageChatSetBackground',
    'messageChatSetTheme',
    'messageChatHasProtectedContentToggled',
    'messageCustomServiceAction',
    'messageChatSetMessageAutoDeleteTime',
    'messageVideoChatStarted',
    'messageVideoChatEnded',
    'messageForumTopicCreated',
    'messageChatBoost',
    'messageChatAddedToCommunity',
    'messageChatRemovedFromCommunity',
  };

  static bool isServiceContent(String? type) =>
      type != null && _serviceTypes.contains(type);

  static String serviceText(Map<String, dynamic>? content) {
    switch (content?.type) {
      case 'messageContactRegistered':
        return telegramText(AppStringKeys.tdMessageUserJoinedTelegram);
      case 'messageChatChangeTitle':
        return telegramText(AppStringKeys.tdMessageGroupNameChanged, {
          'value1': content?.str('title') ?? '',
        });
      case 'messageChatChangePhoto':
        return telegramText(AppStringKeys.tdMessageGroupPhotoUpdated);
      case 'messageChatDeletePhoto':
        return telegramText(AppStringKeys.tdMessageGroupPhotoDeleted);
      case 'messageChatAddMembers':
        return telegramText(AppStringKeys.tdMessageNewMemberJoinedGroup);
      case 'messageChatJoinByLink':
        return telegramText(AppStringKeys.tdMessageJoinedGroupByLink);
      case 'messageChatJoinByRequest':
        return AppStrings.t(AppStringKeys.groupManagementLogJoinedGroup);
      case 'messageChatDeleteMember':
        return telegramText(AppStringKeys.tdMessageMemberLeftGroup);
      case 'messagePinMessage':
        return telegramText(AppStringKeys.tdMessageMessagePinned);
      case 'messageCustomServiceAction':
        return _cleanString(content?.str('text')) ??
            telegramText(AppStringKeys.tdMessageSystemMessage);
      case 'messagePaidMessagePriceChanged':
      case 'messageDirectMessagePriceChanged':
        final stars =
            content?.integer('paid_message_star_count') ??
            content?.integer('star_count') ??
            content?.integer('price') ??
            0;
        return stars > 0
            ? telegramText(AppStringKeys.tdMessagePaidMessagePriceChanged, {
                'value1': stars,
              })
            : telegramText(AppStringKeys.tdMessagePaidMessagesDisabled);
      case 'messageChatSetMessageAutoDeleteTime':
        final seconds =
            content?.obj('message_auto_delete_time')?.integer('time') ??
            content?.integer('message_auto_delete_time') ??
            content?.integer('time') ??
            content?.integer('auto_delete_time') ??
            0;
        return seconds > 0
            ? telegramText(AppStringKeys.tdMessageAutoDeleteTimerChanged, {
                'value1': formatDuration(seconds),
              })
            : telegramText(AppStringKeys.tdMessageAutoDeleteTimerDisabled);
      case 'messageBasicGroupChatCreate':
      case 'messageSupergroupChatCreate':
        return telegramText(AppStringKeys.tdMessageGroupCreated);
      case 'messageVideoChatStarted':
        return telegramText(AppStringKeys.tdMessageGroupVideoChatStarted);
      case 'messageVideoChatEnded':
        return telegramText(AppStringKeys.tdMessageGroupVideoChatEnded);
      case 'messageForumTopicCreated':
        return AppStrings.t(AppStringKeys.groupManagementLogCreatedTopic);
      case 'messageChatBoost':
        return telegramText(AppStringKeys.tdMessageBoostedGroup);
      case 'messageChatAddedToCommunity':
        return AppStrings.t(AppStringKeys.communityChatAddedService);
      case 'messageChatRemovedFromCommunity':
        return AppStrings.t(AppStringKeys.communityChatRemovedService);
      case 'messageChatSetBackground':
        return AppStrings.t(AppStringKeys.chatWallpaperChanged);
      case 'messageChatSetTheme':
        return AppStrings.t(AppStringKeys.chatThemeChanged);
      default:
        return telegramText(AppStringKeys.tdMessageSystemMessage);
    }
  }

  static List<int> serviceUserIds(
    Map<String, dynamic>? content,
    int? senderId,
  ) {
    switch (content?.type) {
      case 'messageChatAddMembers':
        return content?.int64Array('member_user_ids') ??
            content?.int64Array('user_ids') ??
            const <int>[];
      case 'messageChatJoinByLink':
      case 'messageChatJoinByRequest':
        return senderId != null && senderId > 0 ? [senderId] : const <int>[];
      case 'messageChatDeleteMember':
        final userId = content?.int64('user_id');
        return userId != null && userId > 0 ? [userId] : const <int>[];
      default:
        return const <int>[];
    }
  }

  static String formatDuration(int seconds) {
    if (seconds <= 0) {
      return AppStrings.t(AppStringKeys.chatInfoAutoDeleteOff);
    }
    if (seconds % 86400 == 0) {
      final days = seconds ~/ 86400;
      return days == 1
          ? AppStrings.t(AppStringKeys.chatInfoAutoDeleteOneDay)
          : telegramText(AppStringKeys.tdMessageDaysDuration, {'value1': days});
    }
    if (seconds % 3600 == 0) {
      final hours = seconds ~/ 3600;
      return telegramText(AppStringKeys.tdMessageHoursDuration, {
        'value1': hours,
      });
    }
    if (seconds % 60 == 0) {
      final minutes = seconds ~/ 60;
      return telegramText(AppStringKeys.tdMessageMinutesDuration, {
        'value1': minutes,
      });
    }
    return telegramText(AppStringKeys.tdMessageSecondsDuration, {
      'value1': seconds,
    });
  }

  // MARK: Files

  static TdFileRef? smallPhoto(Map<String, dynamic>? photoInfo) {
    if (photoInfo == null) return null;
    final thumb = decodeMiniThumb(photoInfo.obj('minithumbnail'));
    final small = photoInfo.obj('small');
    final id = small?.integer('id');
    if (small == null || id == null) return null;
    final ref = fileRef(small, miniThumb: thumb);
    if (ref == null) return null;
    return TdFileRef(
      id: ref.id,
      localPath: ref.localPath,
      miniThumb: ref.miniThumb,
      thumbnail: ref.thumbnail,
      hasAnimation: photoInfo.boolean('has_animation') ?? false,
      photoId: photoInfo.int64('id'),
    );
  }

  static TdFileRef? fileRef(
    Map<String, dynamic>? file, {
    Uint8List? miniThumb,
    TdFileRef? thumbnail,
  }) {
    final id = file?.integer('id');
    if (file == null || id == null) return null;
    final normalizedThumbnail = thumbnail?.id == id ? null : thumbnail;
    return TdFileRef(
      id: id,
      localPath: file.obj('local')?.str('path'),
      miniThumb: miniThumb,
      thumbnail: normalizedThumbnail,
    );
  }

  static Map<String, dynamic> bestPhotoSize(List<Map<String, dynamic>> sizes) {
    return sizes.reduce((a, b) => _photoArea(a) >= _photoArea(b) ? a : b);
  }

  static Map<String, dynamic>? photoThumbnailSize(
    List<Map<String, dynamic>> sizes,
    Map<String, dynamic> best,
  ) {
    final candidates =
        sizes
            .where((size) => size.obj('photo')?.integer('id') != null)
            .where(
              (size) =>
                  size.obj('photo')?.integer('id') !=
                  best.obj('photo')?.integer('id'),
            )
            .toList()
          ..sort((a, b) => _photoArea(a).compareTo(_photoArea(b)));
    if (candidates.isEmpty) return null;

    Map<String, dynamic>? preferred;
    for (final candidate in candidates) {
      final longestSide = [
        candidate.integer('width') ?? 0,
        candidate.integer('height') ?? 0,
      ].reduce((a, b) => a > b ? a : b);
      if (longestSide <= 640) preferred = candidate;
    }
    return preferred ?? candidates.first;
  }

  static int _photoArea(Map<String, dynamic> size) {
    final width = size.integer('width') ?? 0;
    final height = size.integer('height') ?? 0;
    return width * height;
  }

  static Uint8List? decodeMiniThumb(Map<String, dynamic>? mini) {
    final b64 = mini?.str('data');
    if (b64 == null) return null;
    try {
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  // MARK: Users

  static String userName(Map<String, dynamic> user) {
    final first = user.str('first_name') ?? '';
    final last = user.str('last_name') ?? '';
    final full = [first, last].where((s) => s.isNotEmpty).join(' ');
    if (full.isNotEmpty) return full;
    final username = user.obj('usernames')?.str('editable_username');
    if (username != null && username.isNotEmpty) return '@$username';
    return AppStrings.t(AppStringKeys.chatUserFallbackName, {
      'value1': user.int64('id') ?? 0,
    });
  }

  /// The custom emoji that represents a TDLib `emojiStatus` in compact UI.
  ///
  /// Regular statuses expose `custom_emoji_id`, while upgraded gifts expose
  /// their display model through `model_custom_emoji_id`.
  static int emojiStatusCustomEmojiId(Map<String, dynamic>? emojiStatus) {
    final type = emojiStatus?.obj('type');
    return type?.int64('custom_emoji_id') ??
        type?.int64('model_custom_emoji_id') ??
        emojiStatus?.int64('custom_emoji_id') ??
        emojiStatus?.int64('model_custom_emoji_id') ??
        0;
  }

  static final _nonDigitsRegExp = RegExp(r'\D');

  /// Formats a raw TDLib phone number (digits, no +) to international form via
  /// libphonenumber metadata (e.g. `+61 412 345 678`). Falls back to `+<digits>`.
  static String formatPhone(String? raw) {
    final d = (raw ?? '').replaceAll(_nonDigitsRegExp, '');
    if (d.isEmpty) return '';
    try {
      final util = PhoneNumberUtil.instance;
      final number = util.parse('+$d', null);
      return util.format(number, PhoneNumberFormat.international);
    } catch (_) {
      return '+$d';
    }
  }

  static String userStatus(Map<String, dynamic> user) {
    switch (user.obj('status')?.type) {
      case 'userStatusOnline':
        return telegramPresenceText(TelegramPresenceLabel.online);
      case 'userStatusRecently':
        return telegramPresenceText(TelegramPresenceLabel.recently);
      case 'userStatusOffline':
        return _lastOnlineText(user.obj('status')?.integer('was_online') ?? 0);
      case 'userStatusLastWeek':
        return telegramPresenceText(TelegramPresenceLabel.withinWeek);
      case 'userStatusLastMonth':
        return telegramPresenceText(TelegramPresenceLabel.withinMonth);
      default:
        return '';
    }
  }

  static bool isUserOnline(Map<String, dynamic> user) =>
      user.obj('status')?.type == 'userStatusOnline';

  static String _lastOnlineText(int unixSeconds) {
    if (unixSeconds <= 0) {
      return telegramText(AppStringKeys.tdMessageLastSeenUnknown);
    }
    final time = DateTime.fromMillisecondsSinceEpoch(
      unixSeconds * 1000,
    ).toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(time.year, time.month, time.day);
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    if (day == today) {
      return telegramText(AppStringKeys.tdMessageLastSeenTodayTime, {
        'value1': hh,
        'value2': mm,
      });
    }
    if (day == today.subtract(const Duration(days: 1))) {
      return telegramText(AppStringKeys.tdMessageLastSeenYesterdayTime, {
        'value1': hh,
        'value2': mm,
      });
    }
    if (time.year == now.year) {
      return telegramText(AppStringKeys.tdMessageLastSeenMonthDay, {
        'value1': time.month,
        'value2': time.day,
      });
    }
    return telegramText(AppStringKeys.tdMessageLastSeenYearMonthDay, {
      'value1': time.year,
      'value2': time.month,
      'value3': time.day,
    });
  }
}

/// Tuple-equivalent for [TDParse.mediaAttachment].
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
  final int? stickerFileId; // any sticker's file id (for "add to favorites")
  final int? stickerSetId; // the sticker's set id (for 表情详情)
  final bool isAnimatedEmoji; // single-emoji message (messageAnimatedEmoji)
}
