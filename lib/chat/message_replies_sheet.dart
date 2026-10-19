import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../components/toast.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import 'emoji_catalog.dart';
import 'image_preview.dart';
import 'link_preview_fixer.dart';
import 'message_action_menu.dart';
import 'message_bubble.dart';
import 'outgoing_attachment.dart';
import 'rich_text_composer_view.dart';
import 'rich_text_format.dart';
import 'sticker_item.dart';
import 'sticker_preview.dart';
import 'sticker_store.dart';

Map<String, dynamic> buildReplySheetTextRequest({
  required int chatId,
  required FormattedTextPayload formatted,
  Map<String, dynamic>? topicId,
  int? legacyMessageThreadId,
  int? replyToMessageId,
}) {
  final text = formatted.toTdJson();
  final linkPreview = LinkPreviewFixer.shared.optionsForFormattedText(text);
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
      'text': text,
      'link_preview_options': ?linkPreview,
    },
  };
}

List<Map<String, dynamic>> replySheetSendCandidates(
  Map<String, dynamic> request,
) {
  final candidates = <Map<String, dynamic>>[Map<String, dynamic>.from(request)];
  if (request.containsKey('message_thread_id')) {
    candidates.add(
      Map<String, dynamic>.from(request)..remove('message_thread_id'),
    );
  }
  // A forum topic is an explicit destination, not optional metadata. If a
  // scoped request is rejected, fail closed instead of replying in the chat's
  // root conversation.
  if (request.obj('topic_id')?.type == 'messageTopicForum') {
    return candidates;
  }
  if (request.containsKey('topic_id') && request.containsKey('reply_to')) {
    candidates.add(
      Map<String, dynamic>.from(request)
        ..remove('topic_id')
        ..remove('message_thread_id'),
    );
  }
  return candidates;
}

class MessageRepliesViewTarget {
  const MessageRepliesViewTarget({
    required this.chatId,
    required this.messageId,
    required this.title,
  });

  final int chatId;
  final int messageId;
  final String title;
}

@visibleForTesting
MessageRepliesViewTarget resolveMessageRepliesViewTarget({
  required int sourceChatId,
  required int sourceMessageId,
  required String sourceTitle,
  int? threadChatId,
  int? threadRootMessageId,
  int? rootReplyToMessageId,
  String? threadTitle,
}) {
  final hasThreadRoot = threadRootMessageId != null;
  final resolvedChatId = hasThreadRoot
      ? threadChatId ?? sourceChatId
      : sourceChatId;
  final resolvedTitle = (threadTitle ?? '').trim();
  return MessageRepliesViewTarget(
    chatId: resolvedChatId,
    messageId: threadRootMessageId ?? rootReplyToMessageId ?? sourceMessageId,
    title: resolvedChatId == sourceChatId || resolvedTitle.isEmpty
        ? sourceTitle
        : resolvedTitle,
  );
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
  ValueChanged<MessageRepliesViewTarget>? onViewInChat,
}) {
  return showAppModalSheet<void>(
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
      onViewInChat: onViewInChat,
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
    this.onViewInChat,
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
  final ValueChanged<MessageRepliesViewTarget>? onViewInChat;

  @override
  State<_MessageRepliesSheet> createState() => _MessageRepliesSheetState();
}

/// How far one sweep step of the in-sheet jump moves, as a fraction of the
/// viewport. The step is applied only in the direction the materialized window
/// proves the target lies in, so the sweep always makes progress.
const double _sheetReplyScrollStepFraction = 0.8;

/// Frame budget of the in-sheet jump. The sweep steps toward the target by
/// less than a viewport at a time and each step is decided by the rows the
/// sliver actually built, so a whole 100-row thread is reachable well inside
/// this budget; exceeding it means the target cannot be reached at all.
const int _sheetReplyScrollMaxSteps = 240;

/// Precision below which two scroll offsets count as the same position.
const double _sheetReplyScrollTolerance = 0.5;

/// Test seam: makes the in-sheet reply jump report failure, so the verified
/// navigation fallback can be exercised without an unreachable row.
@visibleForTesting
bool debugForceSheetReplyScrollFailure = false;

/// Identity of a reply-sheet row: a channel post and a discussion comment can
/// carry the same numeric message id, so every row key, cache and lookup in
/// the sheet must be scoped by the chat owning the message.
typedef _SheetMessageKey = ({int chatId, int messageId});

class _MessageRepliesSheetState extends State<_MessageRepliesSheet> {
  final _replyController = TextEditingController();
  final _replyFocus = FocusNode();
  final _scrollController = ScrollController();
  final _messages = <ChatMessage>[];
  final _rowKeys = <_SheetMessageKey, GlobalKey>{};
  final _senders = <int, _ReplySender>{};
  final _chatTitles = <int, String>{};
  _ReplyThreadTarget? _replyTarget;
  String? _replyTargetTitle;
  ChatMessage? _replyTo;
  bool _loading = true;
  bool _unavailable = false;
  bool _canReply = false;
  bool _sending = false;
  bool _emojiVisible = false;
  bool _stickersVisible = false;
  int? _stickerPackId;

  @override
  void initState() {
    super.initState();
    // A writable chat can keep another composer listening behind this sheet.
    // Loading a cold shared store notifies synchronously, so wait until the
    // sheet's first build finishes before waking those existing listeners.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) StickerStore.shared.loadIfNeeded();
    });
    _load();
  }

  @override
  void dispose() {
    _replyController.dispose();
    _replyFocus.dispose();
    _scrollController.dispose();
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
      final targetChatInfo = replyTarget == null
          ? null
          : await _targetChatInfo(replyTarget.chatId);
      final chatCanSend = replyTarget == null ? false : targetChatInfo?.canSend;
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
              // The channel root and a discussion comment can share a numeric
              // message id; only the composite identity proves a row IS one of
              // the thread's roots, so a same-id comment of another chat is
              // kept instead of vanishing with the root.
              .where((message) => !_isSheetRootMessage(message, replyTarget))
              .toList()
            ..sort((a, b) => a.date.compareTo(b.date));
      await _hydrateMessageSender(widget.message);
      for (final message in loaded) {
        await _hydrateMessageSender(message);
      }
      final byChatAndId = <({int chatId, int messageId}), ChatMessage>{
        (chatId: widget.chatId, messageId: widget.message.id): widget.message,
        for (final message in loaded)
          (
            chatId: message.chatId ?? replyTarget?.chatId ?? widget.chatId,
            messageId: message.id,
          ): message,
      };
      final missingByChatId = <int, Set<int>>{};
      for (final message in loaded) {
        final rid = message.replyToMessageId;
        if (rid == null) continue;
        final rChatId =
            message.replyToChatId ??
            message.chatId ??
            replyTarget?.chatId ??
            widget.chatId;
        if (byChatAndId.containsKey((chatId: rChatId, messageId: rid))) {
          continue;
        }
        missingByChatId.putIfAbsent(rChatId, () => <int>{}).add(rid);
      }
      for (final entry in missingByChatId.entries) {
        try {
          final res = await TdClient.shared.query({
            '@type': 'getMessages',
            'chat_id': entry.key,
            'message_ids': entry.value.toList(),
          });
          for (final raw
              in res.objects('messages') ?? const <Map<String, dynamic>>[]) {
            final quoted = TDParse.message(raw);
            if (quoted == null) continue;
            await _hydrateMessageSender(quoted);
            final qChatId = quoted.chatId ?? entry.key;
            byChatAndId[(chatId: qChatId, messageId: quoted.id)] = quoted;
          }
        } catch (_) {}
      }
      final extraChatIds = <int>{
        for (final message in loaded)
          if (message.replyToChatId case final rChatId?
              when rChatId != widget.chatId && rChatId != replyTarget?.chatId)
            rChatId,
      };
      for (final chatId in extraChatIds) {
        if (_chatTitles.containsKey(chatId)) continue;
        final info = await _targetChatInfo(chatId);
        final title = info?.title?.trim();
        if (title != null && title.isNotEmpty) {
          _chatTitles[chatId] = title;
        }
      }
      for (final message in loaded) {
        final rid = message.replyToMessageId;
        if (rid == null) continue;
        final rChatId =
            message.replyToChatId ??
            message.chatId ??
            replyTarget?.chatId ??
            widget.chatId;
        final quoted = byChatAndId[(chatId: rChatId, messageId: rid)];
        if (quoted == null) continue;
        // The sender name is a trust boundary of the same quote: a
        // restriction-redacted parent must not lend its cached plaintext or
        // identity to the row quoting it.
        message.replyToSender ??= quoted.isContentRestricted
            ? widget.peerTitle
            : quoted.senderName ?? quoted.senderTitle ?? widget.peerTitle;
        if (quoted.isContentRestricted) continue;
        message.replyToPreview ??= quoted.text;
        message.replyToDate ??= quoted.date;
        message.replyToEntities = quoted.textEntities;
        message.replyToImage = quoted.hasSpoiler
            ? null
            : message.replyToImage ?? quoted.previewImage;
        message.replyToImageWidth ??= quoted.imageWidth;
        message.replyToImageHeight ??= quoted.imageHeight;
      }
      if (!mounted) return;
      setState(() {
        _replyTarget = replyTarget;
        _replyTargetTitle = targetChatInfo?.title;
        _canReply = canReply;
        _messages
          ..clear()
          ..addAll(loaded);
        final loadedKeys = <_SheetMessageKey>{
          for (final message in loaded) _sheetKeyFor(message),
        };
        _rowKeys.removeWhere((key, _) => !loadedKeys.contains(key));
        _loading = false;
      });
    } on _RepliesUnavailable {
      if (!mounted) return;
      setState(() {
        _replyTarget = null;
        _replyTargetTitle = null;
        _replyTo = null;
        _canReply = false;
        _loading = false;
        _unavailable = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _replyTarget = null;
        _replyTargetTitle = null;
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

  Future<_ReplyTargetChatInfo?> _targetChatInfo(int chatId) async {
    try {
      final chat = await TdClient.shared.query({
        '@type': 'getChat',
        'chat_id': chatId,
      });
      final title = chat.str('title');
      if (title != null && title.trim().isNotEmpty) {
        _chatTitles[chatId] = title.trim();
      }
      return _ReplyTargetChatInfo(
        canSend:
            chat.obj('permissions')?.boolean('can_send_basic_messages') ?? true,
        title: title,
      );
    } catch (_) {
      return null;
    }
  }

  MessageRepliesViewTarget _viewInChatTarget({int? targetMessageId}) {
    final target = _replyTarget;
    final viewTarget = resolveMessageRepliesViewTarget(
      sourceChatId: widget.chatId,
      sourceMessageId: widget.message.id,
      sourceTitle: widget.peerTitle,
      threadChatId: target?.chatId,
      threadRootMessageId: target?.historyRootMessageId,
      rootReplyToMessageId: target?.rootReplyToMessageId,
      threadTitle: _replyTargetTitle,
    );
    if (targetMessageId == null) return viewTarget;
    return MessageRepliesViewTarget(
      chatId: viewTarget.chatId,
      messageId: targetMessageId,
      title: viewTarget.title,
    );
  }

  Future<void> _hydrateMessageSender(ChatMessage message) async {
    final senderId = message.senderId;
    if (senderId == null) return;
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
      hintText: '',
    );
    if (result == null || !mounted) return;
    await _sendReply(result.formattedText, attachments: result.attachments);
  }

  Future<void> _sendPlainReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty) return;
    await _sendReply(FormattedTextPayload(text, const []));
  }

  Future<void> _sendSticker(StickerItem sticker) async {
    final target = _replyTarget;
    if (target == null || !_canReply || _sending) return;
    final remoteId = sticker.remoteId?.trim();
    final request = <String, dynamic>{
      '@type': 'sendMessage',
      'chat_id': target.chatId,
      'topic_id': ?target.topicId,
      'message_thread_id': ?target.legacyMessageThreadId,
      if ((_replyTo?.id ?? target.rootReplyToMessageId) case final int id)
        'reply_to': {'@type': 'inputMessageReplyToMessage', 'message_id': id},
      'input_message_content': {
        '@type': 'inputMessageSticker',
        'sticker': {
          '@type': 'inputSticker',
          'sticker': remoteId != null && remoteId.isNotEmpty
              ? {'@type': 'inputFileRemote', 'id': remoteId}
              : {'@type': 'inputFileId', 'id': sticker.id},
          'width': sticker.width,
          'height': sticker.height,
        },
        'emoji': sticker.emoji,
      },
    };
    setState(() => _sending = true);
    try {
      await _sendRequestWithCompatibility(request);
      if (!mounted) return;
      setState(() {
        _replyTo = null;
        _stickersVisible = false;
      });
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
    Object? lastError;
    StackTrace? lastStackTrace;
    for (final candidate in replySheetSendCandidates(request)) {
      try {
        await TdClient.shared.query(candidate);
        return;
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
      }
    }
    Error.throwWithStackTrace(lastError!, lastStackTrace!);
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
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
                child: Row(
                  children: [
                    Expanded(
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
                    if (widget.onViewInChat != null && _replyTarget != null)
                      GestureDetector(
                        key: const ValueKey('messageRepliesViewInChat'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          final target = _viewInChatTarget();
                          Navigator.of(context).pop();
                          widget.onViewInChat!(target);
                        },
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 6, 0, 6),
                          child: Text(
                            AppStringKeys.messageViewInChat.l10n(context),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: c.linkBlue,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(child: _body(context)),
              if (_canReply) _replyComposer(),
              if (_canReply && _emojiVisible) _emojiPanel(),
              if (_canReply && _stickersVisible) _stickerPanel(),
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
      controller: _scrollController,
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
                        borderRadius: BorderRadius.circular(AppRadius.control),
                      ),
                      hintText: replyTo == null
                          ? null
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
                  key: const ValueKey('messageRepliesEmoji'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    _replyFocus.unfocus();
                    setState(() {
                      _emojiVisible = !_emojiVisible;
                      _stickersVisible = false;
                    });
                  },
                  child: AppIcon(
                    HeroAppIcons.solidFaceSmile,
                    size: 25,
                    color: _emojiVisible ? AppTheme.brand : c.textPrimary,
                  ),
                ),
                const SizedBox(width: 14),
                GestureDetector(
                  key: const ValueKey('messageRepliesStickers'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    _replyFocus.unfocus();
                    setState(() {
                      _stickersVisible = !_stickersVisible;
                      _emojiVisible = false;
                    });
                  },
                  child: AppIcon(
                    HeroAppIcons.grip,
                    size: 25,
                    color: _stickersVisible ? AppTheme.brand : c.textPrimary,
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

  Widget _emojiPanel() {
    final emoji = EmojiCatalog.categories
        .expand((category) => category.emojis)
        .toList(growable: false);
    return SizedBox(
      key: const ValueKey('messageRepliesEmojiPanel'),
      height: 240,
      child: GridView.builder(
        padding: const EdgeInsets.all(10),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 8,
        ),
        itemCount: emoji.length,
        itemBuilder: (context, index) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            final value = emoji[index];
            final selection = _replyController.selection;
            final offset = selection.isValid
                ? selection.baseOffset
                : _replyController.text.length;
            _replyController.text = _replyController.text.replaceRange(
              offset,
              offset,
              value,
            );
            _replyController.selection = TextSelection.collapsed(
              offset: offset + value.length,
            );
            setState(() {});
          },
          child: Center(
            child: Text(emoji[index], style: const TextStyle(fontSize: 25)),
          ),
        ),
      ),
    );
  }

  Widget _stickerPanel() {
    return AnimatedBuilder(
      animation: StickerStore.shared,
      builder: (context, _) {
        final store = StickerStore.shared;
        final packs = store.packs;
        if (packs.isEmpty) {
          return SizedBox(
            height: 240,
            child: Center(
              child: store.loading
                  ? const CircularProgressIndicator.adaptive(strokeWidth: 2)
                  : Text(
                      AppStringKeys.composerNoEmoji.l10n(context),
                      style: TextStyle(color: context.colors.textSecondary),
                    ),
            ),
          );
        }
        _stickerPackId ??= packs.first.id;
        final pack = packs.firstWhere(
          (value) => value.id == _stickerPackId,
          orElse: () => packs.first,
        );
        if (!pack.loaded) unawaited(store.loadPack(pack.id));
        return SizedBox(
          key: const ValueKey('messageRepliesStickerPanel'),
          height: 280,
          child: Column(
            children: [
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    for (final candidate in packs)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          setState(() => _stickerPackId = candidate.id);
                          if (!candidate.loaded) {
                            unawaited(store.loadPack(candidate.id));
                          }
                        },
                        child: Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: candidate.id == pack.id
                                    ? AppTheme.brand
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                          ),
                          child: Text(
                            candidate.title,
                            style: TextStyle(
                              fontSize: 12,
                              color: candidate.id == pack.id
                                  ? AppTheme.brand
                                  : context.colors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: pack.loaded
                    ? GridView.builder(
                        padding: const EdgeInsets.all(10),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                            ),
                        itemCount: pack.stickers.length,
                        itemBuilder: (context, index) {
                          final sticker = pack.stickers[index];
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => unawaited(_sendSticker(sticker)),
                            child: StickerPreview(item: sticker),
                          );
                        },
                      )
                    : const Center(
                        child: CircularProgressIndicator.adaptive(
                          strokeWidth: 2,
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showMessageMenu(ChatMessage message) async {
    final action = await showAppModalSheet<_ReplySheetAction>(
      context: context,
      backgroundColor: context.colors.background,
      builder: (menuContext) => SafeArea(
        child: Wrap(
          children: [
            if (_canReply)
              _messageMenuRow(
                menuContext,
                icon: HeroAppIcons.quoteLeft,
                label: AppStringKeys.chatInputBarReply.l10n(menuContext),
                action: _ReplySheetAction.reply,
              ),
            if (message.text.trim().isNotEmpty)
              _messageMenuRow(
                menuContext,
                icon: HeroAppIcons.file,
                label: AppStringKeys.messageActionCopy.l10n(menuContext),
                action: _ReplySheetAction.copy,
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _ReplySheetAction.reply:
        _beginReply(message);
      case _ReplySheetAction.copy:
        await Clipboard.setData(ClipboardData(text: message.text));
    }
  }

  Widget _messageMenuRow(
    BuildContext menuContext, {
    required AppIconData icon,
    required String label,
    required _ReplySheetAction action,
  }) {
    final c = menuContext.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(menuContext).pop(action),
      child: SizedBox(
        height: 54,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              AppIcon(icon, size: 22, color: c.textPrimary),
              const SizedBox(width: 14),
              Text(label, style: TextStyle(fontSize: 16, color: c.textPrimary)),
            ],
          ),
        ),
      ),
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
    final rowKey = _rowKeys.putIfAbsent(_sheetKeyFor(message), GlobalKey.new);
    final replyTargetChatId =
        message.replyToChatId ??
        message.chatId ??
        _replyTarget?.chatId ??
        widget.chatId;
    final hasInSheetReplyTarget =
        message.replyToMessageId != null &&
        _messages.any(
          (candidate) =>
              candidate.id == message.replyToMessageId &&
              (candidate.chatId ?? _replyTarget?.chatId ?? widget.chatId) ==
                  replyTargetChatId,
        );
    // A row's reply target resolves inside the sheet when the sheet's own chat
    // owns a row with that message id.
    final canOpenReply =
        (message.replyToMessageId != null &&
            _sheetRowIndexOf(message.replyToMessageId!) >= 0) ||
        widget.onOpenReply != null ||
        widget.onViewInChat != null ||
        hasInSheetReplyTarget;
    return KeyedSubtree(
      key: rowKey,
      child: MessageReplySheetItem(
        message: message,
        peerTitle: widget.peerTitle,
        senderName: senderName,
        senderPhoto: sender?.photo ?? message.senderPhoto,
        onReply: _canReply ? _beginReply : null,
        onLongPress: (message, _, source) =>
            unawaited(_showMessageMenu(message)),
        onAvatarTap: widget.onAvatarTap,
        onOpenReply: canOpenReply
            ? (messageId) => unawaited(_openReplyTarget(message, messageId))
            : null,
        onOpenImage: _openImage,
        onOpenImageGallery: _openImageGallery,
        onOpenSticker: widget.onOpenSticker,
        onPlayVideo: widget.onPlayVideo,
        onPlayMusic: widget.onPlayMusic,
        onButtonTap: widget.onButtonTap,
        onBotCommandTap: widget.onBotCommandTap,
        onHashtagTap: widget.onHashtagTap,
      ),
    );
  }

  Future<void> _openReplyTarget(ChatMessage source, int targetMessageId) async {
    final targetChatId =
        source.replyToChatId ??
        source.chatId ??
        _replyTarget?.chatId ??
        widget.chatId;
    // The sheet lists one chat's rows, so an in-sheet target is identified by
    // (row chat == sheet chat, message id) — never by the id alone, which a
    // cross-chat reply can collide with.
    final targetIndex = targetChatId == _sheetChatId
        ? _sheetRowIndexOf(targetMessageId, chatId: targetChatId)
        : -1;
    if (targetIndex >= 0) {
      final reached = await _scrollToSheetReply(targetIndex, targetMessageId);
      if (reached) return;
      if (!mounted) return;
      // The in-sheet sweep could not prove the target visible. Do not swallow
      // the tap: fall through to the explicit navigation below, which opens
      // the same (chat, message) pair through a verified route.
    }
    if (!mounted) return;
    if (targetChatId != widget.chatId && widget.onViewInChat != null) {
      final resolvedTitle = targetChatId == _replyTarget?.chatId
          ? (_replyTargetTitle?.trim().isNotEmpty == true
                ? _replyTargetTitle!.trim()
                : widget.peerTitle)
          : (_chatTitles[targetChatId] ?? widget.peerTitle);
      final viewTarget = MessageRepliesViewTarget(
        chatId: targetChatId,
        messageId: targetMessageId,
        title: resolvedTitle,
      );
      Navigator.of(context).pop();
      widget.onViewInChat!(viewTarget);
      return;
    }
    if (widget.onOpenReply != null) {
      Navigator.of(context).pop();
      widget.onOpenReply!(targetMessageId);
      return;
    }
    if (widget.onViewInChat != null) {
      Navigator.of(context).pop();
      widget.onViewInChat!(
        MessageRepliesViewTarget(
          chatId: targetChatId,
          messageId: targetMessageId,
          title: widget.peerTitle,
        ),
      );
    }
  }

  /// The chat whose messages this sheet lists: the linked discussion group
  /// when the thread root resolves to another chat, else the source chat.
  int get _sheetChatId => _replyTarget?.chatId ?? widget.chatId;

  /// Identity of a sheet row. Messages parsed from this thread's history carry
  /// their own chat id; older/local fixtures leave it null and belong to the
  /// sheet's chat.
  ({int chatId, int messageId}) _sheetKeyFor(ChatMessage message) =>
      (chatId: message.chatId ?? _sheetChatId, messageId: message.id);

  /// Index of the in-sheet row with [messageId] owned by [chatId] (the sheet's
  /// own chat when the caller has none), or -1 when the sheet has no such row.
  int _sheetRowIndexOf(int messageId, {int? chatId}) {
    final expectedChatId = chatId ?? _sheetChatId;
    for (var index = 0; index < _messages.length; index++) {
      final candidate = _messages[index];
      if (candidate.id != messageId) continue;
      if ((candidate.chatId ?? _sheetChatId) == expectedChatId) return index;
    }
    return -1;
  }

  /// Whether [message], parsed out of this thread's history, IS one of the
  /// thread's roots. The comparison is (chatId, messageId): a discussion
  /// comment that reuses the channel post's numeric id is a real row and must
  /// not be dropped with the root.
  bool _isSheetRootMessage(ChatMessage message, _ReplyThreadTarget? target) {
    final sheetChatId = target?.chatId ?? widget.chatId;
    final key = (chatId: message.chatId ?? sheetChatId, messageId: message.id);
    if (key == (chatId: widget.chatId, messageId: widget.message.id)) {
      return true;
    }
    final historyRoot = target?.historyRootMessageId;
    return historyRoot != null &&
        key == (chatId: sheetChatId, messageId: historyRoot);
  }

  /// Scrolls the sheet until the row at [targetIndex] is on screen, and
  /// reports whether it actually got there.
  ///
  /// A row that has never been materialized has no render object, and with
  /// strongly non-uniform heights neither a proportional offset nor an
  /// estimate of the remaining extent can stand in for its position: ten
  /// hundred-line comments followed by ninety short ones make any pixel guess
  /// wrong by thousands of pixels. So nothing here is estimated. Every step is
  /// decided by the window the sliver has actually built:
  ///
  /// - the target is materialized: jump to its measured reveal offset and the
  ///   visibility check decides;
  /// - the target is above that window: step up by most of a viewport;
  /// - the target is below it: step down by most of a viewport.
  ///
  /// Scroll offset is monotone in item index, so each step moves strictly
  /// toward the target and the sweep terminates. Success is only reported when
  /// the target row is materialized AND intersects the viewport — never because
  /// some offset changed.
  Future<bool> _scrollToSheetReply(int targetIndex, int targetMessageId) async {
    if (debugForceSheetReplyScrollFailure) return false;
    if (!mounted || !_scrollController.hasClients) return false;
    if (targetIndex < 0 || targetIndex >= _messages.length) return false;

    for (var step = 0; step < _sheetReplyScrollMaxSteps; step++) {
      if (!mounted || !_scrollController.hasClients) return false;

      // Materialized: land on the row itself, by measurement.
      final reveal = _revealOffsetFor(targetIndex, targetMessageId);
      if (reveal != null) {
        final position = _scrollController.position;
        final target = reveal.clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
        if ((target - position.pixels).abs() >= _sheetReplyScrollTolerance) {
          _scrollController.jumpTo(target);
          await WidgetsBinding.instance.endOfFrame;
        }
        if (_sheetReplyVisible(targetIndex, targetMessageId)) return true;
        // The measured reveal did not bring it into view (the row can be
        // taller than the viewport): fall through to the sweep below, which
        // still only moves in a proven direction.
      }

      if (!mounted || !_scrollController.hasClients) return false;
      final position = _scrollController.position;
      final window = _sheetMaterializedRange();
      final viewportStep =
          position.viewportDimension * _sheetReplyScrollStepFraction;
      final double next;
      if (window == null || targetIndex < window.$1) {
        // Nothing built, or the target sits above what is built.
        next = position.pixels - viewportStep;
      } else if (targetIndex > window.$2) {
        next = position.pixels + viewportStep;
      } else {
        // Inside the built range yet not visible: the row's own reveal offset
        // was already tried, so step toward the side it was measured on.
        final measuredBelow = reveal == null || reveal > position.pixels;
        next = position.pixels + (measuredBelow ? viewportStep : -viewportStep);
      }
      final clamped = next.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if ((clamped - position.pixels).abs() < _sheetReplyScrollTolerance) {
        // The scroll range ends here and the target was not reached.
        return _sheetReplyVisible(targetIndex, targetMessageId);
      }
      _scrollController.jumpTo(clamped);
      await WidgetsBinding.instance.endOfFrame;
      if (_sheetReplyVisible(targetIndex, targetMessageId)) return true;
    }
    return _sheetReplyVisible(targetIndex, targetMessageId);
  }

  /// Inclusive index range of the rows the sliver currently has built, or null
  /// when none is measurable. Used to decide which way the jump must sweep;
  /// the heights themselves are never assumed.
  (int, int)? _sheetMaterializedRange() {
    int? first;
    int? last;
    for (var i = 0; i < _messages.length; i++) {
      final render = _rowRenderObject(i, _messages[i].id);
      if (render == null) continue;
      first ??= i;
      last = i;
    }
    return first == null || last == null ? null : (first, last);
  }

  double? _revealOffsetFor(int targetIndex, int targetMessageId) {
    final render = _rowRenderObject(targetIndex, targetMessageId);
    if (render == null) return null;
    final viewport = RenderAbstractViewport.maybeOf(render);
    if (viewport == null) return null;
    return viewport.getOffsetToReveal(render, 0.15).offset;
  }

  RenderBox? _rowRenderObject(int targetIndex, int targetMessageId) {
    final context = _rowContextFor(targetIndex, targetMessageId);
    if (context == null) return null;
    final render = context.findRenderObject();
    return render is RenderBox && render.hasSize && render.attached
        ? render
        : null;
  }

  /// Mounted element of the row at [targetIndex] when it is the row carrying
  /// [targetMessageId]. The key comes from the row's OWN composite identity, so
  /// a same-id row of another chat can never stand in for this target.
  BuildContext? _rowContextFor(int targetIndex, int targetMessageId) {
    if (targetIndex < 0 || targetIndex >= _messages.length) return null;
    final row = _messages[targetIndex];
    if (row.id != targetMessageId) return null;
    final context = _rowKeys[_sheetKeyFor(row)]?.currentContext;
    return context != null && context.mounted ? context : null;
  }

  bool _sheetReplyVisible(int targetIndex, int targetMessageId) {
    final context = _rowContextFor(targetIndex, targetMessageId);
    if (context == null) return false;
    final render = context.findRenderObject();
    if (render is! RenderBox || !render.hasSize || !render.attached) {
      return false;
    }
    final viewport = RenderAbstractViewport.maybeOf(render);
    if (viewport == null || !_scrollController.hasClients) return false;
    final reveal = viewport.getOffsetToReveal(render, 0.0);
    final position = _scrollController.position;
    final top = reveal.offset - position.pixels;
    final bottom = top + render.size.height;
    return bottom > 0 && top < position.viewportDimension;
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
    unawaited(
      openImagePreview(
        context,
        items: images,
        startIndex: start < 0 ? 0 : start,
      ),
    );
  }

  void _openImageGallery({
    required List<TdFileRef> items,
    required int startIndex,
  }) {
    unawaited(openImagePreview(context, items: items, startIndex: startIndex));
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
    this.onLongPress,
    this.onAvatarTap,
    this.onOpenReply,
    this.onOpenImage,
    this.onOpenImageGallery,
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
  final void Function(
    ChatMessage message,
    Rect? bounds,
    MessageActionSource source,
  )?
  onLongPress;
  final ValueChanged<ChatMessage>? onAvatarTap;
  final ValueChanged<int>? onOpenReply;
  final ValueChanged<ChatMessage>? onOpenImage;
  final ImageGalleryOpenCallback? onOpenImageGallery;
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
      onLongPress: onLongPress,
      onAvatarTap: onAvatarTap,
      onOpenReply: onOpenReply,
      onOpenImage: onOpenImage,
      onOpenImageGallery: onOpenImageGallery,
      onOpenSticker: onOpenSticker,
      onPlayVideo: onPlayVideo,
      onPlayMusic: onPlayMusic,
      onButtonTap: onButtonTap,
      onBotCommandTap: onBotCommandTap,
      onHashtagTap: onHashtagTap,
    );
  }
}

enum _ReplySheetAction { reply, copy }

class _ReplySender {
  const _ReplySender({required this.name, this.photo});

  final String name;
  final TdFileRef? photo;
}

class _ReplyTargetChatInfo {
  const _ReplyTargetChatInfo({required this.canSend, this.title});

  final bool canSend;
  final String? title;
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
