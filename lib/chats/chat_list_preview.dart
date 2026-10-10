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
      loadMessages: loadMessages,
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

/// TDLib chooses how many messages every `getChatHistory` page carries, so the
/// newest page can hold a single message even in a busy chat. Paging stops once
/// the slice is filled, the history is exhausted, or this many pages arrive.
const int _maxPreviewHistoryPages = 5;

/// The concrete TDLib client a preview load is pinned to.
///
/// Chat, message and user ids are account-scoped, so a load that outlives an
/// account switch must not quietly continue against the replacement account.
///
/// Pinning is deliberately weaker than [TdClient.retainAccountSlot]. A peek is
/// read-only and short: when its account goes away the load should die, and it
/// must never hold that account's client open or defer its local-data deletion.
abstract interface class ChatPreviewOwner {
  int get clientId;

  /// Query bound to [clientId]. It never resolves the foreground account.
  ChatListPreviewQuery get query;

  /// False once the user switched accounts, this slot's client was replaced or
  /// closed, or shutdown started. Whatever was collected after that point
  /// belongs to an account the preview no longer represents.
  bool get isCurrent;
}

/// Supplies the owner a preview load runs against.
abstract interface class ChatPreviewAccounts {
  /// Null when nothing can be pinned: nothing logged in, shutdown already
  /// running, or a client replaced between the reads.
  ChatPreviewOwner? pinActiveOwner();
}

final class _TdChatPreviewOwner implements ChatPreviewOwner {
  _TdChatPreviewOwner(this._client, this._slot, this._clientId);

  final TdClient _client;
  final int _slot;
  final int _clientId;

  @override
  int get clientId => _clientId;

  @override
  ChatListPreviewQuery get query =>
      (request) => _client.queryTo(request, _clientId);

  @override
  bool get isCurrent =>
      // Shutdown refuses queries before the slot and active-client mappings
      // necessarily disappear, so the latch belongs to "still this account".
      !_client.isShuttingDown &&
      _client.clientId(_slot) == _clientId &&
      _client.activeClientId == _clientId;
}

/// Production registry: pins the foreground account's concrete client the way
/// the switcher reads each account's identity, without retaining anything.
final class _TdChatPreviewAccounts implements ChatPreviewAccounts {
  const _TdChatPreviewAccounts();

  @override
  ChatPreviewOwner? pinActiveOwner() {
    final client = TdClient.shared;
    if (client.isShuttingDown) return null;
    final slot = client.activeSlot;
    final clientId = client.activeClientId;
    if (clientId == 0) return null;
    // A session swap or a QR reset can replace the slot's client between those
    // two reads; pinning that would page an account nobody peeked at.
    if (client.clientId(slot) != clientId) return null;
    return _TdChatPreviewOwner(client, slot, clientId);
  }
}

const ChatPreviewAccounts _tdChatPreviewAccounts = _TdChatPreviewAccounts();

/// The oldest message id in a `Messages` page, read from the raw payload so an
/// unparseable entry still moves the boundary instead of stalling the loop.
int _oldestRawMessageId(List<Map<String, dynamic>> rawMessages) {
  var oldest = 0;
  for (final raw in rawMessages) {
    final id = raw.int64('id') ?? 0;
    if (id <= 0) continue;
    if (oldest == 0 || id < oldest) oldest = id;
  }
  return oldest;
}

/// Fetches and parses a bounded recent-history slice for the preview.
///
/// Every history page and every sender lookup runs against the account that was
/// foreground when the peek started, and the result is dropped when that owner
/// expires mid-flight or [cancelled] flips, so a switched-away account's rows
/// never reach the preview.
///
/// The load owns no account resources. Dismissing the peek, logging out or
/// deleting that account while a page is in flight needs no release handshake:
/// the pinned client simply stops being current, and TDLib failing the stranded
/// request reads as expiry too.
///
/// This intentionally uses only read APIs. In particular, it never calls
/// `openChat`, `viewMessages`, or `closeChat`, so peeking does not clear unread
/// state or interfere with the active full-chat session.
Future<List<ChatMessage>> loadChatListPreviewMessages({
  required ChatSummary chat,
  int limit = 18,
  ChatPreviewAccounts accounts = _tdChatPreviewAccounts,
  bool Function()? cancelled,
}) async {
  final owner = accounts.pinActiveOwner();
  // No owner, nothing to page. The surface keeps its chat-list fallback.
  if (owner == null) return const [];
  return _loadOwnedPreviewMessages(
    chat: chat,
    wanted: limit.clamp(1, 24),
    owner: owner,
    expired: () => cancelled?.call() == true || !owner.isCurrent,
  );
}

Future<List<ChatMessage>> _loadOwnedPreviewMessages({
  required ChatSummary chat,
  required int wanted,
  required ChatPreviewOwner owner,
  required bool Function() expired,
}) async {
  final byId = <int, ChatMessage>{};
  // `Messages` carries total_count and messages only — no cursor. getChatHistory
  // pages backwards from an *inclusive* from_message_id at offset 0, so the
  // oldest id already seen is the only supported boundary; 0 starts at the
  // latest message.
  var fromMessageId = 0;

  for (
    var page = 0;
    page < _maxPreviewHistoryPages && byId.length < wanted;
    page++
  ) {
    if (expired()) return const [];
    final Map<String, dynamic> response;
    try {
      response = await owner.query({
        '@type': 'getChatHistory',
        'chat_id': chat.id,
        'from_message_id': fromMessageId,
        'offset': 0,
        'limit': wanted,
        'only_local': false,
      });
    } catch (_) {
      // A closed or replaced client, and shutdown, land here. Everything
      // fetched before that belongs to an owner the preview has lost.
      if (expired()) return const [];
      // Losing an older page only shortens the tail, so keep what arrived. A
      // first-page failure still belongs to the caller: the surface then flags
      // the chat-list fallback instead of passing it off as fetched history.
      if (byId.isEmpty) rethrow;
      break;
    }
    if (expired()) return const [];
    final rawMessages =
        response.objects('messages') ?? const <Map<String, dynamic>>[];
    if (rawMessages.isEmpty) break;
    for (final raw in rawMessages) {
      final message = TDParse.message(raw);
      if (message == null) continue;
      byId.putIfAbsent(message.id, () => message);
    }
    final oldest = _oldestRawMessageId(rawMessages);
    // An inclusive boundary repeats itself, so a page that reached nothing older
    // than the cursor has hit the first message of the chat; re-asking from the
    // same id would fetch the same page forever.
    if (oldest <= 0) break;
    if (fromMessageId != 0 && oldest >= fromMessageId) break;
    fromMessageId = oldest;
  }

  final ordered = byId.values.toList()..sort((a, b) => a.id.compareTo(b.id));
  final messages = ordered.length > wanted
      ? ordered.sublist(ordered.length - wanted)
      : ordered;

  for (final message in messages) {
    if (message.isOutgoing && !message.senderIsChat) {
      message.senderName = AppStrings.t(AppStringKeys.chatMeLabel);
    } else if (chat.kind != ChatKind.group && chat.kind != ChatKind.channel) {
      message.senderName = chat.title;
      message.senderPhoto = chat.photo;
    }
  }
  await _hydratePreviewSenders(messages, owner: owner, expired: expired);
  // Hydration is asynchronous too: an owner lost while names were in flight
  // invalidates the slice exactly like a late history page does.
  if (expired()) return const [];
  return messages;
}

Future<void> _hydratePreviewSenders(
  List<ChatMessage> messages, {
  required ChatPreviewOwner owner,
  required bool Function() expired,
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
      if (expired()) return;
      final (isChat, senderId) = entry.key;
      try {
        final raw = await owner.query(
          isChat
              ? {'@type': 'getChat', 'chat_id': senderId}
              : {'@type': 'getUser', 'user_id': senderId},
        );
        if (expired()) return;
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
    this.loadMessages,
    this.accounts,
    this.meName,
    this.mePhoto,
  });

  final ChatSummary chat;
  final List<ChatListPreviewAction> actions;

  /// Null loads through [loadChatListPreviewMessages], pinned to the account
  /// that is foreground when the peek starts and abandoned on dismissal.
  final ChatListPreviewLoader? loadMessages;
  final ChatPreviewAccounts? accounts;
  final String? meName;
  final TdFileRef? mePhoto;

  @override
  State<ChatListPreviewSurface> createState() => _ChatListPreviewSurfaceState();
}

final class _ChatListPreviewSurfaceState extends State<ChatListPreviewSurface> {
  final ScrollController _scrollController = ScrollController();
  late List<ChatMessage> _messages;
  bool _loading = true;
  bool _failed = false;
  bool _cancelled = false;

  late final ChatListPreviewLoader _loadMessages =
      widget.loadMessages ??
      () => loadChatListPreviewMessages(
        chat: widget.chat,
        accounts: widget.accounts ?? _tdChatPreviewAccounts,
        cancelled: () => _cancelled,
      );

  @override
  void initState() {
    super.initState();
    _messages = [?widget.chat.lastChatMessage];
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final loaded = await _loadMessages();
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
    // Dismissing the peek stops its paging. The load holds no account lease, so
    // the pinned account stays free to close or delete while its last request
    // is still outstanding.
    _cancelled = true;
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
        borderRadius: BorderRadius.circular(AppRadius.xl),
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
        borderRadius: BorderRadius.circular(AppRadius.xl),
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
        borderRadius: BorderRadius.circular(AppRadius.lg),
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
        borderRadius: BorderRadius.circular(AppRadius.lg),
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
