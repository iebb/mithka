//
//  td_models.dart
//
//  View-facing models parsed from TDLib JSON, plus content→text helpers.
//  The Flutter port of the Swift `TDModels` / `TDParse`.
//

import 'dart:convert';

import 'package:dlibphonenumber/dlibphonenumber.dart';
import 'package:flutter/foundation.dart';

import 'json_helpers.dart';

/// Reference to a downloadable TDLib file (profile photo, thumbnail, …).
class TdFileRef {
  TdFileRef({required this.id, this.miniThumb});
  final int id;
  Uint8List? miniThumb; // decoded JPEG for instant placeholder
}

// MARK: - Navigation values (route arguments)

class ChatRoute {
  const ChatRoute(this.id, this.title);
  final int id;
  final String title;
}

class ArchiveRoute {
  const ArchiveRoute();
}

class UserRoute {
  const UserRoute(this.id, this.name);
  final int id;
  final String name;
}

class ChatInfoRoute {
  const ChatInfoRoute(this.id, this.title);
  final int id;
  final String title;
}

class ChatSearchRoute {
  const ChatSearchRoute(this.chatId, this.title, this.isGroup);
  final int chatId;
  final String title;
  final bool isGroup;
}

class ChatMediaRoute {
  const ChatMediaRoute(this.chatId, this.title, this.category, this.isGroup);
  final int chatId;
  final String title;
  final ChatMediaCategory category;
  final bool isGroup;
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
    ChatMediaCategory.media => '图片/视频',
    ChatMediaCategory.file => '文件',
    ChatMediaCategory.audio => '音频',
    ChatMediaCategory.link => '链接',
    ChatMediaCategory.sticker => '表情',
    ChatMediaCategory.voice => '语音',
    ChatMediaCategory.member => '群成员',
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
    ChatMediaCategory.media => '当前没有图片/视频',
    ChatMediaCategory.file => '当前没有文件',
    ChatMediaCategory.audio => '当前没有音频',
    ChatMediaCategory.link => '当前没有链接',
    ChatMediaCategory.sticker => '当前没有表情',
    ChatMediaCategory.voice => '当前没有语音',
    ChatMediaCategory.member => '暂无成员',
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
enum MemberRole { owner, admin, member }

class ChatSummary {
  ChatSummary({
    required this.id,
    required this.title,
    required this.lastMessage,
    required this.lastMessageId,
    required this.date,
    required this.unreadCount,
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
    this.peerIsPremium = false,
    this.peerAccentColorId = -1,
    this.peerEmojiStatusId = 0,
    this.isForum = false,
  });

  final int id;
  String title;
  String lastMessage;
  int lastMessageId;
  int date;
  int unreadCount;
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
  bool peerIsPremium;
  int peerAccentColorId;
  int peerEmojiStatusId;
  bool isForum;

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
    this.senderName,
    this.isService = false,
    this.isCall = false,
    this.callIsVideo = false,
    this.callDiscardReason,
    this.callDuration = 0,
    this.contentType,
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
    this.stickerFileId,
    this.stickerSetId,
    this.isAnimatedEmoji = false,
    this.location,
    this.voice,
    this.replyToMessageId,
    this.serviceUserIds = const [],
    this.customEmoji = const [],
    this.textEntities = const [],
    this.linkPreview,
    this.translationText,
    this.translationEntities = const [],
    this.translationLanguageCode,
    this.isTranslating = false,
    this.buttonRows = const [],
    this.isEdited = false,
    this.hasCommentThread = false,
    this.commentCount = 0,
    this.lastCommentMessageId,
  });

  final int id;
  final bool isOutgoing;
  String text;
  final int date;
  String? senderName;
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
  int? stickerFileId; // any sticker's file id (for "add to favorites")
  int? stickerSetId; // the sticker's set id (for 表情详情)
  bool isAnimatedEmoji; // single-emoji message (messageAnimatedEmoji)
  MessageLocation? location;
  MessageVoice? voice;

  // 引用 / reply: the message this one replies to, resolved lazily for the quote.
  int? replyToMessageId;
  String? replyToSender; // resolved sender name of the quoted message
  String? replyToPreview; // one-line preview of the quoted message

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

  bool isEdited; // shows a "已编辑" tag
  bool hasCommentThread;
  int
  commentCount; // channel discussion replies/comments, when TDLib exposes it
  int? lastCommentMessageId;
  List<MessageReaction> reactions = const [];
  String? forwardOrigin; // name of the original author when forwarded
  int? forwardFromUserId; // origin user, resolved lazily to forwardOrigin
  int? forwardFromChatId; // origin chat/channel, resolved lazily

  /// A plain text message (messageText) — not an audio/poll/contact placeholder.
  bool get isPlainText => contentType == 'messageText';

  /// A real photo (messagePhoto) — not a sticker / GIF / video thumbnail, all
  /// of which also set [image].
  bool get isPhoto => contentType == 'messagePhoto';

  /// Visual media that Telegram may place in the same media album.
  ///
  /// Stickers, GIFs and video stickers also have thumbnails in [image], but
  /// they are not part of photo/video album merging.
  bool get isAlbumVisualMedia =>
      image != null &&
      (contentType == 'messagePhoto' || contentType == 'messageVideo');

  /// Whether the "+1" (复读) quick-repeat may apply to this kind at all: only
  /// plain text and photos. Audio, voice, location, stickers, polls, files,
  /// videos, contacts and call logs are excluded.
  bool get canRepeat => isPlainText || isPhoto;
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
    final last = chat.obj('last_message');
    if (last != null) {
      lastMessageId = last.int64('id') ?? 0;
      date = last.integer('date') ?? 0;
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

    final muted =
        (chat.obj('notification_settings')?.integer('mute_for') ?? 0) > 0;

    final type = chat.obj('type');
    return ChatSummary(
      id: id,
      title: title,
      lastMessage: lastText,
      lastMessageId: lastMessageId,
      date: date,
      unreadCount: unread,
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
    final outgoing = message.boolean('is_outgoing') ?? false;
    final date = message.integer('date') ?? 0;
    final content = message.obj('content');
    final service = isServiceContent(content?.type);
    final isCall = content?.type == 'messageCall';
    final callIsVideo = isCall && (content?.boolean('is_video') ?? false);
    final callDuration = isCall ? (content?.integer('duration') ?? 0) : 0;
    final callDiscardReason = isCall
        ? content?.obj('discard_reason')?.type
        : null;
    final text = service
        ? serviceText(content)
        : (content != null ? messageText(content) : '[消息]');

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
    final markdown = !service && parsedEntities.isEmpty
        ? _markdownText(text)
        : null;
    final displayText = markdown?.text ?? text;
    final displayEntities = markdown?.entities ?? parsedEntities;
    final replyInfo = message.obj('interaction_info')?.obj('reply_info');

    return ChatMessage(
        id: id,
        isOutgoing: outgoing,
        text: displayText,
        date: date,
        isService: service,
        isCall: isCall,
        callIsVideo: callIsVideo,
        callDiscardReason: callDiscardReason,
        callDuration: callDuration,
        contentType: content?.type,
        senderId: senderId,
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
        stickerFileId: media.stickerFileId,
        stickerSetId: media.stickerSetId,
        isAnimatedEmoji: media.isAnimatedEmoji,
        location: locationAttachment(content),
        voice: voiceAttachment(content),
        replyToMessageId: replyToMessageId,
        serviceUserIds: serviceUserIds(content, senderId),
        customEmoji: customEmojiEntitiesFrom(parsedEntities),
        textEntities: displayEntities,
        linkPreview: linkPreview(content?.obj('link_preview')),
        buttonRows: messageButtonRows(message.obj('reply_markup')),
        isEdited: (message.integer('edit_date') ?? 0) > 0,
        hasCommentThread: replyInfo != null,
        commentCount:
            replyInfo?.integer('reply_count') ??
            replyInfo?.integer('comment_count') ??
            0,
        lastCommentMessageId: replyInfo?.int64('last_message_id'),
      )
      ..reactions = reactionsFrom(message)
      ..forwardOrigin = fwdName
      ..forwardFromUserId = fwdUserId
      ..forwardFromChatId = fwdChatId;
  }

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
    final best = sizes.reduce(
      (a, b) => (a.integer('width') ?? 0) >= (b.integer('width') ?? 0) ? a : b,
    );
    return MediaAttachment(
      image: fileRef(best.obj('photo'), miniThumb: mini),
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
    switch (type) {
      case 'textEmpty':
      case 'richTextAnchor':
      case 'textAnchor':
        return;
      case 'richTextPlain':
      case 'textPlain':
        builder.write(value.str('text') ?? '');
        return;
      case 'richTexts':
      case 'textConcat':
        for (final item in value.objects('texts') ?? const []) {
          _appendRichText(builder, item);
        }
        return;
      case 'richTextCustomEmoji':
        final alt = value.str('alternative_text') ?? '';
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
      case 'textImage':
        builder.write('[图片]');
        return;
      case 'richTextMathematicalExpression':
        final expression = value.str('expression') ?? '';
        final start = builder.length;
        builder.write(expression);
        builder.entity(start, 'textEntityTypeCode');
        return;
    }

    final child = value['text'];
    final start = builder.length;
    if (child != null) {
      _appendRichText(builder, child);
    } else if (type == 'richTextEmailAddress') {
      builder.write(value.str('email_address') ?? '');
    } else if (type == 'richTextPhoneNumber') {
      builder.write(value.str('phone_number') ?? '');
    }
    final entityType = _richTextEntityType(type);
    if (entityType == null) return;
    builder.entity(
      start,
      entityType,
      url: _richTextEntityUrl(type, value),
      userId: value.int64('user_id'),
    );
  }

  static String? _richTextEntityType(String? type) {
    switch (type) {
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
      case 'richTextFixed':
      case 'textFixed':
        return 'textEntityTypeCode';
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
    switch (type) {
      case 'richTextUrl':
      case 'textUrl':
      case 'richTextReferenceLink':
      case 'richTextAnchorLink':
        return value.str('url');
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
        builder.write(block.str('expression') ?? '');
        builder.entity(start, 'textEntityTypeCode');
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
      case 'pageBlockMap':
        _appendCaption(builder, block.obj('caption'));
      case 'pageBlockCover':
        final cover = block.obj('cover');
        if (cover != null) _appendPageBlock(builder, cover);
      case 'pageBlockEmbeddedPost':
      case 'pageBlockCollage':
      case 'pageBlockSlideshow':
        _appendPageBlocks(builder, block.objects('blocks'));
        _appendCaption(builder, block.obj('caption'));
      case 'pageBlockTable':
        _appendRichText(builder, block.obj('caption'));
        _appendTable(builder, block['cells']);
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

  static void _appendTable(_RichTextBuilder builder, Object? rows) {
    if (rows is! List) return;
    for (final row in rows) {
      if (row is! List) continue;
      var first = true;
      for (final rawCell in row) {
        if (rawCell is! Map<String, dynamic>) continue;
        if (!first) builder.write('\t');
        _appendRichText(builder, rawCell.obj('text'));
        first = false;
      }
      builder.lineBreak();
    }
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
            final best = sizes.reduce(
              (a, b) => (a.integer('width') ?? 0) >= (b.integer('width') ?? 0)
                  ? a
                  : b,
            );
            return MediaAttachment(
              image: fileRef(best.obj('photo'), miniThumb: mini),
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
            image: (isTgs || isWebm)
                ? (thumb ?? stickerFile)
                : (stickerFile ?? thumb),
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
            image: (isTgs || isWebm)
                ? (thumb ?? stickerFile)
                : (stickerFile ?? thumb),
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
              title: title ?? fileName ?? '音乐',
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
          final name = doc.str('file_name') ?? '文件';
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
        return _richMessageText(content.obj('message'))?.text ?? '[消息]';
      case 'messagePhoto':
        final caption = content.obj('caption')?.str('text') ?? '';
        return caption.isEmpty ? '[图片]' : caption;
      case 'messageVideo':
        final caption = content.obj('caption')?.str('text') ?? '';
        return caption.isEmpty ? '[视频]' : caption;
      case 'messageVideoNote':
        return '[视频消息]';
      case 'messageVoiceNote':
        return '[语音]';
      case 'messageAudio':
        final caption = content.obj('caption')?.str('text') ?? '';
        return caption.isEmpty ? '[音乐]' : caption;
      case 'messageDocument':
        final caption = content.obj('caption')?.str('text') ?? '';
        if (caption.isNotEmpty) return caption;
        final name = content.obj('document')?.str('file_name');
        return name != null ? '[文件] $name' : '[文件]';
      case 'messageSticker':
        final emoji = content.obj('sticker')?.str('emoji') ?? '';
        return emoji.isEmpty ? '[表情]' : '[表情$emoji]';
      case 'messageAnimation':
        final caption = content.obj('caption')?.str('text') ?? '';
        return caption.isEmpty ? '[动画表情]' : caption;
      case 'messageAnimatedEmoji':
        return content.obj('animated_emoji')?.str('emoji') ?? '[动画表情]';
      case 'messageLocation':
        return '[位置]';
      case 'messageVenue':
        return '[位置]';
      case 'messageContact':
        return '[名片]';
      case 'messagePoll':
        return '[投票]';
      case 'messageChecklist':
        final title = content.obj('list')?.obj('title')?.str('text') ?? '';
        return title.isEmpty ? '[清单]' : title;
      case 'messageCall':
        return (content.boolean('is_video') ?? false) ? '[视频通话]' : '[语音通话]';
      case 'messageDice':
        return content.str('emoji') ?? '[骰子]';
      case 'messageGame':
        return '[游戏]';
      case 'messageInvoice':
        return '[商品]';
      case 'messageStory':
        return '[转发的故事]';
      case 'messageGiveaway':
      case 'messageGiveawayWinners':
      case 'messageGiveawayCompleted':
        return '[抽奖]';
      case 'messagePaidMedia':
        return '[付费内容]';
      case 'messagePaidMessagePriceChanged':
      case 'messageDirectMessagePriceChanged':
        return '[付费消息设置已更改]';
      case 'messageGift':
      case 'messagePremiumGiftCode':
      case 'messageGiftedPremium':
      case 'messageGiftedStars':
      case 'messageGiftedTon':
      case 'messageUpgradedGift':
      case 'messageRefundedUpgradedGift':
        return '[礼物]';
      case 'messageSuggestedPostInfo':
      case 'messageSuggestedPostApproved':
      case 'messageSuggestedPostApprovalFailed':
      case 'messageSuggestedPostDeclined':
      case 'messageSuggestedPostPaid':
      case 'messageSuggestedPostRefunded':
        return '[投稿]';
      case 'messageExpiredPhoto':
        return '[照片已过期]';
      case 'messageExpiredVideo':
        return '[视频已过期]';
      case 'messageUnsupported':
        return '[当前版本暂不支持的消息]';
      default:
        final fallback = _nestedFormattedText(content);
        if (fallback.isNotEmpty) return fallback;
        if (kDebugMode) {
          debugPrint('Unsupported TDLib message content: ${content.type}');
        }
        return '[消息]';
    }
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
    'messageChatSetTheme',
    'messageCustomServiceAction',
    'messageChatSetMessageAutoDeleteTime',
    'messageVideoChatStarted',
    'messageVideoChatEnded',
    'messageForumTopicCreated',
    'messageChatBoost',
  };

  static bool isServiceContent(String? type) =>
      type != null && _serviceTypes.contains(type);

  static String serviceText(Map<String, dynamic>? content) {
    switch (content?.type) {
      case 'messageContactRegistered':
        return '对方已加入 Telegram';
      case 'messageChatChangeTitle':
        return '群名称已修改为 ${content?.str('title') ?? ''}';
      case 'messageChatChangePhoto':
        return '群头像已更新';
      case 'messageChatDeletePhoto':
        return '群头像已删除';
      case 'messageChatAddMembers':
        return '新成员加入了群聊';
      case 'messageChatJoinByLink':
        return '通过链接加入了群聊';
      case 'messageChatJoinByRequest':
        return '加入了群聊';
      case 'messageChatDeleteMember':
        return '有成员离开了群聊';
      case 'messagePinMessage':
        return '置顶了一条消息';
      case 'messagePaidMessagePriceChanged':
      case 'messageDirectMessagePriceChanged':
        final stars =
            content?.integer('paid_message_star_count') ??
            content?.integer('star_count') ??
            content?.integer('price') ??
            0;
        return stars > 0 ? '发送消息价格已改为 $stars 星' : '已关闭付费消息';
      case 'messageChatSetMessageAutoDeleteTime':
        final seconds =
            content?.obj('message_auto_delete_time')?.integer('time') ??
            content?.integer('message_auto_delete_time') ??
            content?.integer('time') ??
            content?.integer('auto_delete_time') ??
            0;
        return seconds > 0
            ? '自动删除消息已设为${formatDuration(seconds)}'
            : '自动删除消息已关闭';
      case 'messageBasicGroupChatCreate':
      case 'messageSupergroupChatCreate':
        return '群聊已创建';
      case 'messageVideoChatStarted':
        return '群视频通话已开始';
      case 'messageVideoChatEnded':
        return '群视频通话已结束';
      case 'messageForumTopicCreated':
        return '创建了话题';
      case 'messageChatBoost':
        return '助力了本群';
      default:
        return '系统消息';
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
    if (seconds <= 0) return '关闭';
    if (seconds % 86400 == 0) {
      final days = seconds ~/ 86400;
      return days == 1 ? '1天' : '$days天';
    }
    if (seconds % 3600 == 0) {
      final hours = seconds ~/ 3600;
      return '$hours小时';
    }
    if (seconds % 60 == 0) {
      final minutes = seconds ~/ 60;
      return '$minutes分钟';
    }
    return '$seconds秒';
  }

  // MARK: Files

  static TdFileRef? smallPhoto(Map<String, dynamic>? photoInfo) {
    if (photoInfo == null) return null;
    final thumb = decodeMiniThumb(photoInfo.obj('minithumbnail'));
    final small = photoInfo.obj('small');
    final id = small?.integer('id');
    if (small == null || id == null) return null;
    return TdFileRef(id: id, miniThumb: thumb);
  }

  static TdFileRef? fileRef(
    Map<String, dynamic>? file, {
    Uint8List? miniThumb,
  }) {
    final id = file?.integer('id');
    if (file == null || id == null) return null;
    return TdFileRef(id: id, miniThumb: miniThumb);
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
    return '用户 ${user.int64('id') ?? 0}';
  }

  /// Formats a raw TDLib phone number (digits, no +) to international form via
  /// libphonenumber metadata (e.g. `+61 412 345 678`). Falls back to `+<digits>`.
  static String formatPhone(String? raw) {
    final d = (raw ?? '').replaceAll(RegExp(r'\D'), '');
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
        return '在线';
      case 'userStatusRecently':
        return '最近在线';
      case 'userStatusOffline':
        return _lastOnlineText(user.obj('status')?.integer('was_online') ?? 0);
      case 'userStatusLastWeek':
        return '一周内在线';
      case 'userStatusLastMonth':
        return '一个月内在线';
      default:
        return '';
    }
  }

  static bool isUserOnline(Map<String, dynamic> user) =>
      user.obj('status')?.type == 'userStatusOnline';

  static String _lastOnlineText(int unixSeconds) {
    if (unixSeconds <= 0) return '最后在线时间未知';
    final time = DateTime.fromMillisecondsSinceEpoch(
      unixSeconds * 1000,
    ).toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(time.year, time.month, time.day);
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    if (day == today) return '最后在线 今天 $hh:$mm';
    if (day == today.subtract(const Duration(days: 1))) {
      return '最后在线 昨天 $hh:$mm';
    }
    if (time.year == now.year) {
      return '最后在线 ${time.month}月${time.day}日';
    }
    return '最后在线 ${time.year}年${time.month}月${time.day}日';
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
