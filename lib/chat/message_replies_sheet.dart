import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import 'full_image_viewer.dart';
import 'message_bubble.dart';

Future<void> showMessageRepliesSheet({
  required BuildContext context,
  required int chatId,
  required ChatMessage message,
  required String peerTitle,
  ValueChanged<ChatMessage>? onAvatarTap,
  ValueChanged<int>? onOpenReply,
  ValueChanged<ChatMessage>? onOpenImage,
  ValueChanged<ChatMessage>? onOpenSticker,
  ValueChanged<ChatMessage>? onPlayVideo,
  ValueChanged<ChatMessage>? onPlayMusic,
  void Function(ChatMessage message, MessageButton button)? onButtonTap,
  ValueChanged<String>? onBotCommandTap,
  ValueChanged<String>? onHashtagTap,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _MessageRepliesSheet(
      chatId: chatId,
      message: message,
      peerTitle: peerTitle,
      onAvatarTap: onAvatarTap,
      onOpenReply: onOpenReply,
      onOpenImage: onOpenImage,
      onOpenSticker: onOpenSticker,
      onPlayVideo: onPlayVideo,
      onPlayMusic: onPlayMusic,
      onButtonTap: onButtonTap,
      onBotCommandTap: onBotCommandTap,
      onHashtagTap: onHashtagTap,
    ),
  );
}

class _MessageRepliesSheet extends StatefulWidget {
  const _MessageRepliesSheet({
    required this.chatId,
    required this.message,
    required this.peerTitle,
    this.onAvatarTap,
    this.onOpenReply,
    this.onOpenImage,
    this.onOpenSticker,
    this.onPlayVideo,
    this.onPlayMusic,
    this.onButtonTap,
    this.onBotCommandTap,
    this.onHashtagTap,
  });

  final int chatId;
  final ChatMessage message;
  final String peerTitle;
  final ValueChanged<ChatMessage>? onAvatarTap;
  final ValueChanged<int>? onOpenReply;
  final ValueChanged<ChatMessage>? onOpenImage;
  final ValueChanged<ChatMessage>? onOpenSticker;
  final ValueChanged<ChatMessage>? onPlayVideo;
  final ValueChanged<ChatMessage>? onPlayMusic;
  final void Function(ChatMessage message, MessageButton button)? onButtonTap;
  final ValueChanged<String>? onBotCommandTap;
  final ValueChanged<String>? onHashtagTap;

  @override
  State<_MessageRepliesSheet> createState() => _MessageRepliesSheetState();
}

class _MessageRepliesSheetState extends State<_MessageRepliesSheet> {
  final _messages = <ChatMessage>[];
  final _senders = <int, _ReplySender>{};
  bool _loading = true;
  bool _unavailable = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _unavailable = false;
    });
    try {
      try {
        final properties = await TdClient.shared.query({
          '@type': 'getMessageProperties',
          'chat_id': widget.chatId,
          'message_id': widget.message.id,
        });
        if (properties.boolean('can_get_message_thread') == false) {
          throw const _RepliesUnavailable();
        }
      } on _RepliesUnavailable {
        rethrow;
      } catch (_) {}

      final response = await TdClient.shared.query({
        '@type': 'getMessageThreadHistory',
        'chat_id': widget.chatId,
        'message_id': widget.message.id,
        'from_message_id': 0,
        'offset': 0,
        'limit': 100,
      });
      final loaded =
          (response.objects('messages') ?? const <Map<String, dynamic>>[])
              .map(TDParse.message)
              .whereType<ChatMessage>()
              .where((message) => !message.isService)
              .where((message) => message.id != widget.message.id)
              .toList()
            ..sort((a, b) => a.date.compareTo(b.date));
      for (final message in loaded) {
        final senderId = message.senderId;
        if (senderId == null) continue;
        var sender = _senders[senderId];
        if (sender == null) {
          sender = await _resolveSender(senderId);
          if (sender != null) _senders[senderId] = sender;
        }
        if (sender != null) {
          message.senderName ??= sender.name;
          message.senderPhoto ??= sender.photo;
        }
      }
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(loaded);
        _loading = false;
      });
    } on _RepliesUnavailable {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _unavailable = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _unavailable = true;
      });
    }
  }

  Future<_ReplySender?> _resolveSender(int senderId) async {
    try {
      if (senderId > 0) {
        final user = await TdClient.shared.query({
          '@type': 'getUser',
          'user_id': senderId,
        });
        return _ReplySender(
          name: TDParse.userName(user),
          photo: TDParse.smallPhoto(user.obj('profile_photo')),
        );
      }
      final chat = await TdClient.shared.query({
        '@type': 'getChat',
        'chat_id': senderId,
      });
      return _ReplySender(
        name: chat.str('title') ?? AppStringKeys.topicChatUsers,
        photo: TDParse.smallPhoto(chat.obj('photo')),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: FractionallySizedBox(
        heightFactor: 0.78,
        child: Container(
          decoration: BoxDecoration(
            color: c.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(top: BorderSide(color: c.divider, width: 0.5)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: c.textTertiary.withValues(alpha: 0.38),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 10, 12),
                child: Row(
                  children: [
                    AppIcon(HeroAppIcons.comments, size: 22, color: c.linkBlue),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        AppStringKeys.messageRepliesTitle.l10n(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: c.textPrimary,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(context).pop(),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: AppIcon(
                          HeroAppIcons.xmark,
                          size: 22,
                          color: c.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: c.divider),
              Expanded(child: _body(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final c = context.colors;
    if (_loading) {
      return Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator.adaptive(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(c.linkBlue),
          ),
        ),
      );
    }
    if (_unavailable) {
      return _emptyState(AppStringKeys.messageRepliesUnavailable);
    }
    if (_messages.isEmpty) {
      return _emptyState(AppStringKeys.messageRepliesEmpty);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(4, 7, 4, 24),
      itemCount: _messages.length,
      separatorBuilder: (_, _) => const SizedBox.shrink(),
      itemBuilder: (context, index) => _replyRow(_messages[index]),
    );
  }

  Widget _emptyState(String key) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Text(
          key.l10n(context),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            height: 1.4,
            color: c.textTertiary,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }

  Widget _replyRow(ChatMessage message) {
    final sender = message.senderId == null ? null : _senders[message.senderId];
    final senderName =
        sender?.name ??
        message.senderName ??
        message.senderTitle ??
        widget.peerTitle;
    message.senderName ??= senderName;
    message.senderPhoto ??= sender?.photo;
    return MessageReplySheetItem(
      message: message,
      peerTitle: widget.peerTitle,
      senderName: senderName,
      senderPhoto: sender?.photo ?? message.senderPhoto,
      onAvatarTap: widget.onAvatarTap,
      onOpenReply: widget.onOpenReply == null
          ? null
          : (messageId) {
              Navigator.of(context).pop();
              widget.onOpenReply!(messageId);
            },
      onOpenImage: _openImage,
      onOpenSticker: widget.onOpenSticker,
      onPlayVideo: widget.onPlayVideo,
      onPlayMusic: widget.onPlayMusic,
      onButtonTap: widget.onButtonTap,
      onBotCommandTap: widget.onBotCommandTap,
      onHashtagTap: widget.onHashtagTap,
    );
  }

  void _openImage(ChatMessage message) {
    final selected = message.image;
    if (selected == null) {
      widget.onOpenImage?.call(message);
      return;
    }
    final imageMessages = _messages
        .where((candidate) => candidate.isPhoto && candidate.image != null)
        .toList();
    if (!imageMessages.any((candidate) => candidate.image?.id == selected.id)) {
      imageMessages.add(message);
    }
    final images = imageMessages.map((candidate) => candidate.image!).toList();
    final start = images.indexWhere((image) => image.id == selected.id);
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            FullImageViewer(items: images, startIndex: start < 0 ? 0 : start),
      ),
    );
  }
}

/// A reply-sheet row that deliberately reuses the transcript renderer so
/// attachments, entities, link previews, and structured rich messages cannot
/// degrade to their list-preview labels on this surface.
class MessageReplySheetItem extends StatelessWidget {
  const MessageReplySheetItem({
    super.key,
    required this.message,
    required this.peerTitle,
    required this.senderName,
    this.senderPhoto,
    this.onAvatarTap,
    this.onOpenReply,
    this.onOpenImage,
    this.onOpenSticker,
    this.onPlayVideo,
    this.onPlayMusic,
    this.onButtonTap,
    this.onBotCommandTap,
    this.onHashtagTap,
  });

  final ChatMessage message;
  final String peerTitle;
  final String senderName;
  final TdFileRef? senderPhoto;
  final ValueChanged<ChatMessage>? onAvatarTap;
  final ValueChanged<int>? onOpenReply;
  final ValueChanged<ChatMessage>? onOpenImage;
  final ValueChanged<ChatMessage>? onOpenSticker;
  final ValueChanged<ChatMessage>? onPlayVideo;
  final ValueChanged<ChatMessage>? onPlayMusic;
  final void Function(ChatMessage message, MessageButton button)? onButtonTap;
  final ValueChanged<String>? onBotCommandTap;
  final ValueChanged<String>? onHashtagTap;

  @override
  Widget build(BuildContext context) {
    return MessageBubble(
      key: ValueKey('messageRepliesSheetMessage-${message.id}'),
      message: message,
      peerTitle: peerTitle,
      isGroup: true,
      meName: senderName,
      mePhoto: senderPhoto,
      forceShowTimestamp: true,
      onAvatarTap: onAvatarTap,
      onOpenReply: onOpenReply,
      onOpenImage: onOpenImage,
      onOpenSticker: onOpenSticker,
      onPlayVideo: onPlayVideo,
      onPlayMusic: onPlayMusic,
      onButtonTap: onButtonTap,
      onBotCommandTap: onBotCommandTap,
      onHashtagTap: onHashtagTap,
    );
  }
}

class _ReplySender {
  const _ReplySender({required this.name, this.photo});

  final String name;
  final TdFileRef? photo;
}

class _RepliesUnavailable implements Exception {
  const _RepliesUnavailable();
}
