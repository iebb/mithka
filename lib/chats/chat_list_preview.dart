import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../chat/group_remark_controller.dart';
import '../chat/message_bubble.dart';
import '../components/app_icons.dart';
import '../components/photo_avatar.dart';
import '../components/ui_components.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';

typedef ChatListPreviewQuery =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> request);
typedef ChatListPreviewLoader = Future<List<ChatMessage>> Function();

/// One action displayed alongside the read-only chat preview.
///
/// The overlay owns only presentation. The chat list supplies callbacks so the
/// preview never depends on the chat-list model or duplicates row-action state.
class ChatListPreviewAction {
  const ChatListPreviewAction({
    required this.label,
    required this.icon,
    required this.onSelected,
    this.destructive = false,
  });

  final String label;
  final AppIconData icon;
  final VoidCallback onSelected;
  final bool destructive;
}

/// Concrete geometry for the modal's phone/tablet/desktop arrangements.
@immutable
class ChatListPreviewGeometry {
  const ChatListPreviewGeometry({
    required this.horizontal,
    required this.previewWidth,
    required this.previewHeight,
    required this.actionWidth,
    required this.actionHeight,
  });

  final bool horizontal;
  final double previewWidth;
  final double previewHeight;
  final double actionWidth;
  final double actionHeight;
}

ChatListPreviewGeometry chatListPreviewGeometry(
  Size available, {
  required int actionCount,
}) {
  final separators = math.max(0, actionCount - 1) * 0.5;
  final naturalActionHeight = actionCount * 48.0 + separators;
  final horizontal =
      available.width >= 720 ||
      (available.width >= 620 && available.height < 640);
  if (horizontal) {
    final contentWidth = math.max(1.0, available.width - 32);
    final contentHeight = math.max(1.0, available.height - 32);
    final actionWidth = math.min(232.0, contentWidth * 0.28);
    final previewHeight = math.min(620.0, contentHeight);
    return ChatListPreviewGeometry(
      horizontal: true,
      previewWidth: math.min(480.0, contentWidth - actionWidth - 12),
      previewHeight: previewHeight,
      actionWidth: actionWidth,
      actionHeight: math.min(naturalActionHeight, previewHeight),
    );
  }

  final contentWidth = math.max(1.0, available.width - 32);
  final contentHeight = math.max(1.0, available.height - 32);
  final gap = actionCount == 0 ? 0.0 : 12.0;
  final actionHeight = math.min(
    naturalActionHeight,
    math.max(0.0, contentHeight - gap - 96),
  );
  return ChatListPreviewGeometry(
    horizontal: false,
    previewWidth: math.min(460.0, contentWidth),
    previewHeight: math.min(520.0, contentHeight - gap - actionHeight),
    actionWidth: math.min(460.0, contentWidth),
    actionHeight: actionHeight,
  );
}

/// Shows a Telegram-style, lifted conversation preview without opening the
/// chat or sending `viewMessages`. Selecting an action dismisses the preview
/// before handing control back to the chat list.
Future<void> showChatListPreview(
  BuildContext context, {
  required ChatSummary chat,
  required List<ChatListPreviewAction> actions,
  String? meName,
  TdFileRef? mePhoto,
  ChatListPreviewLoader? loadMessages,
}) async {
  unawaited(HapticFeedback.mediumImpact());
  final reduceMotion = AppMotion.isReduced(context);
  final route = RawDialogRoute<ChatListPreviewAction>(
    barrierLabel: AppStringKeys.countryPickerCancel.l10n(context),
    barrierColor: const Color(0xB8000000),
    transitionDuration: AppMotion.duration(context, AppMotion.deliberate),
    pageBuilder: (dialogContext, _, _) => ChatListPreviewSurface(
      chat: chat,
      actions: actions,
      meName: meName,
      mePhoto: mePhoto,
      loadMessages:
          loadMessages ?? () => loadChatListPreviewMessages(chat: chat),
    ),
    transitionBuilder: (dialogContext, animation, _, child) {
      if (reduceMotion) return child;
      final entrance = CurvedAnimation(
        parent: animation,
        curve: AppMotion.emphasized,
        reverseCurve: AppMotion.accelerate,
      );
      return FadeTransition(
        opacity: entrance,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.025),
            end: Offset.zero,
          ).animate(entrance),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(entrance),
            child: child,
          ),
        ),
      );
    },
  );
  final selected = await Navigator.of(context, rootNavigator: true).push(route);
  // Route.popped resolves when dismissal starts; completed resolves after the
  // reverse transition and overlay removal, so follow-up navigation cannot
  // collide with the preview route.
  await route.completed;
  if (!context.mounted || selected == null) return;
  selected.onSelected();
}

/// Fetches and parses a bounded recent-history slice for the preview.
///
/// This intentionally uses only read APIs. In particular, it never calls
/// `openChat`, `viewMessages`, or `closeChat`, so peeking does not clear unread
/// state or interfere with the active full-chat session.
Future<List<ChatMessage>> loadChatListPreviewMessages({
  required ChatSummary chat,
  ChatListPreviewQuery? query,
  int limit = 18,
}) async {
  final runQuery = query ?? TdClient.shared.query;
  final response = await runQuery({
    '@type': 'getChatHistory',
    'chat_id': chat.id,
    'from_message_id': 0,
    'offset': 0,
    'limit': limit.clamp(1, 24),
    'only_local': false,
  });
  final messages =
      (response.objects('messages') ?? const <Map<String, dynamic>>[])
          .map(TDParse.message)
          .whereType<ChatMessage>()
          .toList()
        ..sort((a, b) => a.id.compareTo(b.id));

  for (final message in messages) {
    if (message.isOutgoing && !message.senderIsChat) {
      message.senderName = AppStrings.t(AppStringKeys.chatMeLabel);
    } else if (chat.kind != ChatKind.group && chat.kind != ChatKind.channel) {
      message.senderName = chat.title;
      message.senderPhoto = chat.photo;
    }
  }
  await _hydratePreviewSenders(messages, query: runQuery);
  return messages;
}

Future<void> _hydratePreviewSenders(
  List<ChatMessage> messages, {
  required ChatListPreviewQuery query,
}) async {
  final bySender = <(bool, int), List<ChatMessage>>{};
  for (final message in messages) {
    final senderId = message.senderId;
    if (senderId == null || senderId == 0 || message.isOutgoing) continue;
    // TDLib chat identifiers can be negative. Only user identifiers are
    // required to be positive; rejecting all negative values drops channel
    // and anonymous-admin sender names/photos from the preview.
    if (!message.senderIsChat && senderId < 0) continue;
    bySender
        .putIfAbsent((message.senderIsChat, senderId), () => [])
        .add(message);
  }

  await Future.wait(
    bySender.entries.map((entry) async {
      final (isChat, senderId) = entry.key;
      try {
        final raw = await query(
          isChat
              ? {'@type': 'getChat', 'chat_id': senderId}
              : {'@type': 'getUser', 'user_id': senderId},
        );
        final name = isChat ? raw.str('title') ?? '' : TDParse.userName(raw);
        final photo = TDParse.smallPhoto(
          isChat ? raw.obj('photo') : raw.obj('profile_photo'),
        );
        for (final message in entry.value) {
          if (name.trim().isNotEmpty) message.senderName = name;
          message.senderPhoto = photo;
          if (!isChat) {
            message.senderIsPremium = raw.boolean('is_premium') ?? false;
            message.senderAccentColorId = raw.integer('accent_color_id') ?? -1;
            message.senderEmojiStatusId = TDParse.emojiStatusCustomEmojiId(
              raw.obj('emoji_status'),
            );
          }
        }
      } catch (_) {
        // A missing sender should not hide otherwise available history.
      }
    }),
  );
}

class ChatListPreviewSurface extends StatefulWidget {
  const ChatListPreviewSurface({
    super.key,
    required this.chat,
    required this.actions,
    required this.loadMessages,
    this.meName,
    this.mePhoto,
  });

  final ChatSummary chat;
  final List<ChatListPreviewAction> actions;
  final ChatListPreviewLoader loadMessages;
  final String? meName;
  final TdFileRef? mePhoto;

  @override
  State<ChatListPreviewSurface> createState() => _ChatListPreviewSurfaceState();
}

class _ChatListPreviewSurfaceState extends State<ChatListPreviewSurface> {
  final ScrollController _scrollController = ScrollController();
  late List<ChatMessage> _messages;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _messages = [?widget.chat.lastChatMessage];
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final loaded = await widget.loadMessages();
      if (!mounted) return;
      setState(() {
        if (loaded.isNotEmpty) _messages = loaded;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final geometry = chatListPreviewGeometry(
            Size(constraints.maxWidth, constraints.maxHeight),
            actionCount: widget.actions.length,
          );
          final preview = SizedBox(
            width: geometry.previewWidth,
            height: geometry.previewHeight,
            child: _previewCard(context),
          );
          final actions = SizedBox(
            width: geometry.actionWidth,
            height: geometry.actionHeight,
            child: _actionMenu(context),
          );
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: geometry.horizontal
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [preview, const SizedBox(width: 12), actions],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [preview, const SizedBox(height: 12), actions],
                    ),
            ),
          );
        },
      ),
    );
  }

  Widget _previewCard(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      key: const ValueKey('chat-list-preview-card'),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: c.divider.withValues(alpha: 0.82),
          width: 0.5,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x52000000),
            blurRadius: 34,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          children: [
            _previewHeader(context),
            ColoredBox(color: c.divider, child: const SizedBox(height: 0.5)),
            Expanded(child: _transcript(context)),
          ],
        ),
      ),
    );
  }

  Widget _previewHeader(BuildContext context) {
    final c = context.colors;
    final title = widget.chat.kind == ChatKind.group
        ? context.watch<GroupRemarkController?>()?.displayTitleFor(
                widget.chat.id,
                widget.chat.title,
              ) ??
              widget.chat.title
        : widget.chat.title;
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      color: c.navBar,
      child: Row(
        children: [
          PhotoAvatar(
            title: title,
            photo: widget.chat.photo,
            size: 40,
            square: widget.chat.usesSquareAvatar,
            allowAnimation: false,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: AppTextSize.bodyLarge,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          if (widget.chat.isMuted) ...[
            const SizedBox(width: 8),
            AppIcon(HeroAppIcons.bellSlash, size: 17, color: c.textTertiary),
          ],
          if (widget.chat.isPinned) ...[
            const SizedBox(width: 8),
            AppPinIcon(size: 15, color: c.textTertiary),
          ],
        ],
      ),
    );
  }

  Widget _transcript(BuildContext context) {
    final c = context.colors;
    final isGroup =
        widget.chat.kind == ChatKind.group ||
        widget.chat.kind == ChatKind.channel;
    return DecoratedBox(
      decoration: BoxDecoration(color: c.chatBackground),
      child: Stack(
        children: [
          if (_messages.isEmpty && _loading)
            const Center(child: AppActivityIndicator(size: 24))
          else if (_messages.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  AppStringKeys.chatSearchNoMessagesFound.l10n(context),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: AppTextSize.callout,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            )
          else
            ListView.builder(
              key: const ValueKey('chat-list-preview-transcript'),
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 14),
              itemCount: _messages.length,
              itemBuilder: (context, index) => IgnorePointer(
                child: MessageBubble(
                  key: ValueKey(
                    'chat-list-preview-message-${_messages[index].id}',
                  ),
                  message: _messages[index],
                  peerTitle: widget.chat.title,
                  peerPhoto: widget.chat.photo,
                  isGroup: isGroup,
                  meName:
                      widget.meName ?? AppStringKeys.chatMeLabel.l10n(context),
                  mePhoto: widget.mePhoto,
                ),
              ),
            ),
          if (_loading && _messages.isNotEmpty)
            Positioned(
              top: 10,
              right: 10,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.navBar.withValues(alpha: 0.88),
                  shape: BoxShape.circle,
                  boxShadow: const [
                    BoxShadow(color: Color(0x24000000), blurRadius: 6),
                  ],
                ),
                child: const SizedBox(
                  width: 30,
                  height: 30,
                  child: Center(child: AppActivityIndicator(size: 15)),
                ),
              ),
            ),
          if (_failed && _messages.isNotEmpty)
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.navBar.withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                ),
                child: AppIcon(
                  HeroAppIcons.triangleExclamation,
                  size: 16,
                  color: c.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _actionMenu(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      key: const ValueKey('chat-list-preview-actions'),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: c.divider.withValues(alpha: 0.82),
          width: 0.5,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x3D000000),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ListView.separated(
          padding: EdgeInsets.zero,
          itemCount: widget.actions.length,
          itemBuilder: (context, index) =>
              _ChatListPreviewActionRow(action: widget.actions[index]),
          separatorBuilder: (context, index) => ColoredBox(
            color: c.divider.withValues(alpha: 0.75),
            child: const SizedBox(height: 0.5),
          ),
        ),
      ),
    );
  }
}

class _ChatListPreviewActionRow extends StatefulWidget {
  const _ChatListPreviewActionRow({required this.action});

  final ChatListPreviewAction action;

  @override
  State<_ChatListPreviewActionRow> createState() =>
      _ChatListPreviewActionRowState();
}

class _ChatListPreviewActionRowState extends State<_ChatListPreviewActionRow> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final foreground = widget.action.destructive
        ? AppTheme.tagRed
        : c.textPrimary;
    final duration = AppMotion.duration(context, AppMotion.quick);
    return Semantics(
      button: true,
      label: widget.action.label.l10n(context),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        onTap: () => Navigator.of(context).pop(widget.action),
        child: AnimatedContainer(
          duration: duration,
          curve: AppMotion.standard,
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 15),
          color: _pressed
              ? c.textPrimary.withValues(alpha: 0.07)
              : Colors.transparent,
          child: Row(
            children: [
              AppIcon(widget.action.icon, size: 19, color: foreground),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.action.label.l10n(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: AppTextSize.body,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
