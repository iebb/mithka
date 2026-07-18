import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../components/toast.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import 'full_image_viewer.dart';
import 'message_bubble.dart';
import 'outgoing_attachment.dart';
import 'rich_text_composer_view.dart';
import 'rich_text_format.dart';

Map<String, dynamic> buildReplySheetTextRequest({
  required int chatId,
  required FormattedTextPayload formatted,
  Map<String, dynamic>? topicId,
  int? legacyMessageThreadId,
  int? replyToMessageId,
}) {
  return {
    '@type': 'sendMessage',
    'chat_id': chatId,
    'topic_id': ?topicId,
    'message_thread_id': ?legacyMessageThreadId,
    if (replyToMessageId != null)
      'reply_to': {
        '@type': 'inputMessageReplyToMessage',
        'message_id': replyToMessageId,
      },
    'input_message_content': {
      '@type': 'inputMessageText',
      'text': formatted.toTdJson(),
    },
  };
}

Future<void> showMessageRepliesSheet({
  required BuildContext context,
  required int chatId,
  required ChatMessage message,
  required String peerTitle,
  int? forumTopicId,
  VoidCallback? onSent,
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
      forumTopicId: forumTopicId,
      onSent: onSent,
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
    this.forumTopicId,
    this.onSent,
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
  final int? forumTopicId;
  final VoidCallback? onSent;
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
  final _replyController = TextEditingController();
  final _replyFocus = FocusNode();
  final _messages = <ChatMessage>[];
  final _senders = <int, _ReplySender>{};
  _ReplyThreadTarget? _replyTarget;
  ChatMessage? _replyTo;
  bool _loading = true;
  bool _unavailable = false;
  bool _canReply = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _replyController.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _unavailable = false;
    });
    try {
      Map<String, dynamic> properties = const {};
      try {
        properties = await TdClient.shared.query({
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

      final replyTarget = await _resolveReplyTarget();
      final chatCanSend = replyTarget == null
          ? false
          : await _targetChatCanSend(replyTarget.chatId);
      final linkedDiscussion =
          replyTarget != null && replyTarget.chatId != widget.chatId;
      final canReply =
          replyTarget != null &&
          chatCanSend != false &&
          (linkedDiscussion || properties.boolean('can_be_replied') != false);

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
              .where(
                (message) => message.id != replyTarget?.historyRootMessageId,
              )
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
      final byId = {for (final message in loaded) message.id: message};
      for (final message in loaded) {
        final quoted = byId[message.replyToMessageId];
        if (quoted == null) continue;
        message.replyToSender ??=
            quoted.senderName ?? quoted.senderTitle ?? widget.peerTitle;
        message.replyToPreview ??= quoted.text;
        message.replyToDate ??= quoted.date;
        message.replyToImage ??= quoted.image;
        message.replyToImageWidth ??= quoted.imageWidth;
        message.replyToImageHeight ??= quoted.imageHeight;
      }
      if (!mounted) return;
      setState(() {
        _replyTarget = replyTarget;
        _canReply = canReply;
        _messages
          ..clear()
          ..addAll(loaded);
        _loading = false;
      });
    } on _RepliesUnavailable {
      if (!mounted) return;
      setState(() {
        _replyTarget = null;
        _replyTo = null;
        _canReply = false;
        _loading = false;
        _unavailable = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _replyTarget = null;
        _replyTo = null;
        _canReply = false;
        _loading = false;
        _unavailable = true;
      });
    }
  }

  Future<_ReplyThreadTarget?> _resolveReplyTarget() async {
    final forumTopicId = widget.forumTopicId;
    if (forumTopicId != null && forumTopicId != 0) {
      return _ReplyThreadTarget(
        chatId: widget.chatId,
        topicId: {'@type': 'messageTopicForum', 'forum_topic_id': forumTopicId},
        legacyMessageThreadId: forumTopicId,
        rootReplyToMessageId: widget.message.id,
      );
    }
    try {
      final thread = await TdClient.shared.query({
        '@type': 'getMessageThread',
        'chat_id': widget.chatId,
        'message_id': widget.message.id,
      });
      final chatId = thread.int64('chat_id');
      final messageThreadId = thread.int64('message_thread_id');
      if (chatId != null && messageThreadId != null && messageThreadId != 0) {
        return _ReplyThreadTarget(
          chatId: chatId,
          topicId: {
            '@type': 'messageTopicThread',
            'message_thread_id': messageThreadId,
          },
          historyRootMessageId: messageThreadId,
        );
      }
    } catch (_) {}
    return _ReplyThreadTarget(
      chatId: widget.chatId,
      rootReplyToMessageId: widget.message.id,
    );
  }

  Future<bool?> _targetChatCanSend(int chatId) async {
    try {
      final chat = await TdClient.shared.query({
        '@type': 'getChat',
        'chat_id': chatId,
      });
      return chat.obj('permissions')?.boolean('can_send_basic_messages') ??
          true;
    } catch (_) {
      return null;
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

  void _beginReply(ChatMessage message) {
    if (!_canReply) return;
    setState(() => _replyTo = message);
    _replyFocus.requestFocus();
  }

  Future<void> _openRichReply() async {
    final result = await showRichTextComposerSheet(
      context,
      initialText: _replyController.text,
      submitText: AppStringKeys.composerSend,
      hintText: AppStringKeys.topicChatBeKindPrompt,
    );
    if (result == null || !mounted) return;
    await _sendReply(result.formattedText, attachments: result.attachments);
  }

  Future<void> _sendPlainReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty) return;
    await _sendReply(FormattedTextPayload(text, const []));
  }

  Future<void> _sendReply(
    FormattedTextPayload formatted, {
    List<OutgoingAttachment> attachments = const [],
  }) async {
    final target = _replyTarget;
    final text = formatted.text.trim();
    if (target == null ||
        !_canReply ||
        (text.isEmpty && attachments.isEmpty) ||
        _sending) {
      return;
    }
    setState(() => _sending = true);
    final replyToMessageId = _replyTo?.id ?? target.rootReplyToMessageId;
    final replyTo = replyToMessageId == null
        ? null
        : <String, dynamic>{
            '@type': 'inputMessageReplyToMessage',
            'message_id': replyToMessageId,
          };
    final requests = attachments.isEmpty
        ? <Map<String, dynamic>>[
            buildReplySheetTextRequest(
              chatId: target.chatId,
              formatted: formatted,
              topicId: target.topicId,
              legacyMessageThreadId: target.legacyMessageThreadId,
              replyToMessageId: replyToMessageId,
            ),
          ]
        : buildAttachmentSendRequests(
            chatId: target.chatId,
            attachments: attachments,
            caption: formatted.text,
            captionEntities: formatted.entities,
            replyTo: replyTo,
          );
    for (final request in requests) {
      if (attachments.isNotEmpty) {
        if (target.topicId != null) request['topic_id'] = target.topicId;
        if (target.legacyMessageThreadId != null) {
          request['message_thread_id'] = target.legacyMessageThreadId;
        }
      }
    }
    try {
      for (final request in requests) {
        await _sendRequestWithCompatibility(request);
      }
      _replyController.clear();
      if (!mounted) {
        widget.onSent?.call();
        return;
      }
      setState(() => _replyTo = null);
      widget.onSent?.call();
      await _load();
    } catch (error) {
      if (mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.momentsReplyFailed, {'value1': error}),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendRequestWithCompatibility(
    Map<String, dynamic> request,
  ) async {
    try {
      await TdClient.shared.query(request);
      return;
    } catch (_) {
      if (request.containsKey('message_thread_id')) {
        final withoutLegacyThread = Map<String, dynamic>.from(request)
          ..remove('message_thread_id');
        try {
          await TdClient.shared.query(withoutLegacyThread);
          return;
        } catch (_) {}
      }
      if (request.containsKey('topic_id') && request.containsKey('reply_to')) {
        final replyOnly = Map<String, dynamic>.from(request)
          ..remove('topic_id')
          ..remove('message_thread_id');
        await TdClient.shared.query(replyOnly);
        return;
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: FractionallySizedBox(
        heightFactor: 0.72,
        child: Container(
          decoration: BoxDecoration(
            color: c.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(top: BorderSide(color: c.divider, width: 0.5)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 54,
                height: 6,
                decoration: BoxDecoration(
                  color: c.divider,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    AppStrings.t(AppStringKeys.topicChatCommentCount, {
                      'value1': _displayCommentCount,
                    }),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
              Expanded(child: _body(context)),
              if (_canReply) _replyComposer(),
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
      padding: const EdgeInsets.fromLTRB(4, 7, 4, 12),
      itemCount: _messages.length,
      separatorBuilder: (_, _) => const SizedBox.shrink(),
      itemBuilder: (context, index) => _replyRow(_messages[index]),
    );
  }

  int get _displayCommentCount {
    final reported = widget.message.commentCount;
    return reported > _messages.length ? reported : _messages.length;
  }

  Widget _replyComposer() {
    final c = context.colors;
    final replyTo = _replyTo;
    return SafeArea(
      top: false,
      child: Container(
        key: const ValueKey('messageRepliesComposer'),
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
        decoration: BoxDecoration(
          color: c.navBar,
          border: Border(top: BorderSide(color: c.divider, width: 0.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (replyTo != null)
              Padding(
                key: const ValueKey('messageRepliesReplyTarget'),
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        AppStrings.t(AppStringKeys.momentsReplyToUser, {
                          'value1': _replySenderName(replyTo),
                        }),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: c.linkBlue),
                      ),
                    ),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _replyTo = null),
                      child: AppIcon(
                        HeroAppIcons.solidCircleXmark,
                        size: 18,
                        color: c.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('messageRepliesInput'),
                    controller: _replyController,
                    focusNode: _replyFocus,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendPlainReply(),
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(fontSize: 15, color: c.textPrimary),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: c.searchFill,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderSide: BorderSide.none,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      hintText: replyTo == null
                          ? AppStringKeys.topicChatBeKindPrompt.l10n(context)
                          : AppStrings.t(
                              AppStringKeys.momentsReplyToUserPlaceholder,
                              {'value1': _replySenderName(replyTo)},
                            ),
                      hintStyle: TextStyle(fontSize: 15, color: c.textTertiary),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                GestureDetector(
                  key: const ValueKey('messageRepliesMention'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _insertMention,
                  child: AppIcon(
                    HeroAppIcons.at,
                    size: 25,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(width: 14),
                GestureDetector(
                  key: const ValueKey('messageRepliesRichText'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _openRichReply,
                  child: AppIcon(
                    HeroAppIcons.penToSquare,
                    size: 25,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(width: 14),
                GestureDetector(
                  key: const ValueKey('messageRepliesSend'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _sending || _replyController.text.trim().isEmpty
                      ? null
                      : _sendPlainReply,
                  child: AppIcon(
                    HeroAppIcons.solidPaperPlane,
                    size: 25,
                    color: _replyController.text.trim().isEmpty
                        ? c.textTertiary
                        : AppTheme.brand,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _replySenderName(ChatMessage message) =>
      _senders[message.senderId]?.name ??
      message.senderName ??
      message.senderTitle ??
      widget.peerTitle;

  void _insertMention() {
    final selection = _replyController.selection;
    final offset = selection.isValid
        ? selection.baseOffset
        : _replyController.text.length;
    _replyController.text =
        '${_replyController.text.substring(0, offset)}@${_replyController.text.substring(offset)}';
    _replyController.selection = TextSelection.collapsed(offset: offset + 1);
    _replyFocus.requestFocus();
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
      onReply: _canReply ? _beginReply : null,
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
    this.onReply,
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
  final ValueChanged<ChatMessage>? onReply;
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
      onReply: onReply,
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

class _ReplyThreadTarget {
  const _ReplyThreadTarget({
    required this.chatId,
    this.topicId,
    this.legacyMessageThreadId,
    this.rootReplyToMessageId,
    this.historyRootMessageId,
  });

  final int chatId;
  final Map<String, dynamic>? topicId;
  final int? legacyMessageThreadId;
  final int? rootReplyToMessageId;
  final int? historyRootMessageId;
}

class _RepliesUnavailable implements Exception {
  const _RepliesUnavailable();
}
