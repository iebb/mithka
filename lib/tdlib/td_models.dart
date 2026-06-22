//
//  td_models.dart
//
//  View-facing models parsed from TDLib JSON, plus content→text helpers.
//  The Flutter port of the Swift `TDModels` / `TDParse`.
//

import 'dart:convert';
import 'dart:typed_data';

import 'package:dlibphonenumber/dlibphonenumber.dart';

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
  link, // 链接
  sticker, // 表情
  voice, // 语音
  member; // 群成员

  String get title => switch (this) {
    ChatMediaCategory.media => '图片/视频',
    ChatMediaCategory.file => '文件',
    ChatMediaCategory.link => '链接',
    ChatMediaCategory.sticker => '表情',
    ChatMediaCategory.voice => '语音',
    ChatMediaCategory.member => '群成员',
  };

  /// The TDLib SearchMessagesFilter `@type`, or null for non-message categories.
  String? get tdFilter => switch (this) {
    ChatMediaCategory.media => 'searchMessagesFilterPhotoAndVideo',
    ChatMediaCategory.file => 'searchMessagesFilterDocument',
    ChatMediaCategory.link => 'searchMessagesFilterUrl',
    ChatMediaCategory.sticker => 'searchMessagesFilterAnimation',
    ChatMediaCategory.voice => 'searchMessagesFilterVoiceNote',
    ChatMediaCategory.member => null,
  };

  String get emptyText => switch (this) {
    ChatMediaCategory.media => '当前没有图片/视频',
    ChatMediaCategory.file => '当前没有文件',
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
  });

  final int id;
  String title;
  String lastMessage;
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

  /// Groups & channels use a rounded-square avatar; people use a circle.
  bool get usesSquareAvatar =>
      kind == ChatKind.group || kind == ChatKind.channel;
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
    this.senderId,
    this.senderPhoto,
    this.image,
    this.imageWidth,
    this.imageHeight,
    this.document,
    this.senderRole,
    this.senderTitle,
    this.animatedSticker,
    this.videoSticker,
    this.stickerFileId,
    this.location,
    this.voice,
    this.replyToMessageId,
    this.customEmoji = const [],
    this.isEdited = false,
  });

  final int id;
  final bool isOutgoing;
  String text;
  final int date;
  String? senderName;
  bool isService;
  bool isCall; // messageCall — a call log; not reactable
  int? senderId;
  TdFileRef? senderPhoto;
  TdFileRef? image; // photo / sticker / video-thumb / gif
  int? imageWidth;
  int? imageHeight;
  MessageDocument? document;
  MemberRole? senderRole;
  String? senderTitle;
  TdFileRef? animatedSticker; // .tgs (Lottie) sticker file
  TdFileRef? videoSticker; // .webm video sticker file
  int? stickerFileId; // any sticker's file id (for "add to favorites")
  MessageLocation? location;
  MessageVoice? voice;

  // 引用 / reply: the message this one replies to, resolved lazily for the quote.
  int? replyToMessageId;
  String? replyToSender; // resolved sender name of the quoted message
  String? replyToPreview; // one-line preview of the quoted message

  // Inline custom (premium) emoji spans within `text`.
  List<CustomEmojiEntity> customEmoji;

  bool isEdited; // shows a "已编辑" tag
  List<MessageReaction> reactions = const [];
  String? forwardOrigin; // name of the original author when forwarded
  int? forwardFromUserId; // origin user, resolved lazily to forwardOrigin
  int? forwardFromChatId; // origin chat/channel, resolved lazily
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
  bool isPremium; // Telegram Premium subscriber → shown as a QQ-style VIP badge
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
    var date = 0;
    final last = chat.obj('last_message');
    if (last != null) {
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

    return ChatSummary(
      id: id,
      title: title,
      lastMessage: lastText,
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

    // Inline custom emoji come from the formattedText that produced `text`.
    final ft = content?.type == 'messageText'
        ? content?.obj('text')
        : (content?.type == 'messagePhoto' || content?.type == 'messageVideo')
        ? content?.obj('caption')
        : null;

    return ChatMessage(
        id: id,
        isOutgoing: outgoing,
        text: text,
        date: date,
        isService: service,
        isCall: isCall,
        senderId: senderId,
        image: media.image,
        imageWidth: media.width,
        imageHeight: media.height,
        document: media.document,
        animatedSticker: media.animated,
        videoSticker: media.videoSticker,
        stickerFileId: media.stickerFileId,
        location: locationAttachment(content),
        voice: voiceAttachment(content),
        replyToMessageId: replyToMessageId,
        customEmoji: customEmojiEntities(ft),
        isEdited: (message.integer('edit_date') ?? 0) > 0,
      )
      ..reactions = reactionsFrom(message)
      ..forwardOrigin = fwdName
      ..forwardFromUserId = fwdUserId
      ..forwardFromChatId = fwdChatId;
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

  /// Extracts textEntityTypeCustomEmoji spans from a formattedText object.
  static List<CustomEmojiEntity> customEmojiEntities(Map<String, dynamic>? ft) {
    final entities = ft?.objects('entities');
    if (entities == null) return const [];
    final out = <CustomEmojiEntity>[];
    for (final e in entities) {
      final type = e.obj('type');
      if (type?.type != 'textEntityTypeCustomEmoji') continue;
      final id = type?.int64('custom_emoji_id');
      final offset = e.integer('offset');
      final length = e.integer('length');
      if (id != null && offset != null && length != null) {
        out.add(CustomEmojiEntity(offset, length, id));
      }
    }
    return out;
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
          return MediaAttachment(
            image: thumb ?? stickerFile,
            width: w,
            height: h,
            animated: fmt == 'stickerFormatTgs' ? stickerFile : null,
            videoSticker: fmt == 'stickerFormatWebm' ? stickerFile : null,
            stickerFileId: stickerFile?.id,
          );
        }
      case 'messageAnimation':
        final anim = content.obj('animation');
        if (anim != null) {
          final mini = decodeMiniThumb(anim.obj('minithumbnail'));
          final ref =
              fileRef(anim.obj('thumbnail')?.obj('file'), miniThumb: mini) ??
              fileRef(anim.obj('animation'), miniThumb: mini);
          return MediaAttachment(
            image: ref,
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
            width: video.integer('width'),
            height: video.integer('height'),
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
    switch (content.type) {
      case 'messageText':
        return content.obj('text')?.str('text') ?? '';
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
        return '[音乐]';
      case 'messageDocument':
        final name = content.obj('document')?.str('file_name');
        return name != null ? '[文件] $name' : '[文件]';
      case 'messageSticker':
        final emoji = content.obj('sticker')?.str('emoji') ?? '';
        return emoji.isEmpty ? '[表情]' : '[表情$emoji]';
      case 'messageAnimation':
        return '[动画表情]';
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
      case 'messageGift':
      case 'messagePremiumGiftCode':
      case 'messageGiftedPremium':
        return '[礼物]';
      case 'messageExpiredPhoto':
        return '[照片已过期]';
      case 'messageExpiredVideo':
        return '[视频已过期]';
      case 'messageUnsupported':
        return '[当前版本暂不支持的消息]';
      default:
        return '[消息]';
    }
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
        return '离线';
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
}

/// Tuple-equivalent for [TDParse.mediaAttachment].
class MediaAttachment {
  const MediaAttachment({
    this.image,
    this.width,
    this.height,
    this.document,
    this.animated,
    this.videoSticker,
    this.stickerFileId,
  });
  final TdFileRef? image;
  final int? width;
  final int? height;
  final MessageDocument? document;
  final TdFileRef? animated; // .tgs Lottie sticker
  final TdFileRef? videoSticker; // .webm video sticker
  final int? stickerFileId; // any sticker's file id (for "add to favorites")
}
