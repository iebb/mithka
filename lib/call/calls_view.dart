import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../chat/chat_view.dart';
import '../components/app_icons.dart';
import '../components/photo_avatar.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/date_text.dart';
import 'call_manager.dart';

@visibleForTesting
Map<String, dynamic> callHistorySearchRequest({
  required String offset,
  int limit = 50,
  bool onlyMissed = false,
}) => {
  '@type': 'searchCallMessages',
  'offset': offset,
  'limit': limit,
  'only_missed': onlyMissed,
};

class CallsView extends StatefulWidget {
  const CallsView({super.key});

  @override
  State<CallsView> createState() => _CallsViewState();
}

class _CallsViewState extends State<CallsView> {
  final _scrollController = ScrollController();
  final _entries = <CallHistoryEntry>[];
  final _seenMessageIds = <int>{};
  final _chats = <int, ChatSummary>{};
  String _nextOffset = '';
  bool _loading = false;
  bool _hasMore = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    unawaited(_loadMore());
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 420) {
      unawaited(_loadMore());
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final response = await TdClient.shared.query(
        callHistorySearchRequest(offset: _nextOffset),
      );
      final messages = response.objects('messages') ?? const [];
      final parsed = messages
          .map(TDParse.message)
          .whereType<ChatMessage>()
          .where((message) => message.isCall)
          .toList();
      final chatIds = parsed
          .map((message) => message.chatId ?? 0)
          .where((id) => id != 0 && !_chats.containsKey(id))
          .toSet();
      await Future.wait(chatIds.map(_loadChat));
      for (final message in parsed) {
        if (!_seenMessageIds.add(message.id)) continue;
        final chatId = message.chatId ?? 0;
        final chat = _chats[chatId];
        _entries.add(
          CallHistoryEntry(
            message: message,
            chatId: chatId,
            title:
                chat?.title ??
                AppStrings.t(AppStringKeys.callsUnknownConversation),
            photo: chat?.photo,
            kind: chat?.kind ?? ChatKind.unknown,
            userId: chat?.peerUserId,
          ),
        );
      }
      final nextOffset = response.str('next_offset') ?? '';
      _hasMore = messages.isNotEmpty && nextOffset.isNotEmpty;
      _nextOffset = nextOffset;
    } catch (error) {
      debugPrint('Could not load call history: $error');
      _failed = true;
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _loadChat(int chatId) async {
    try {
      final raw = await TdClient.shared.query({
        '@type': 'getChat',
        'chat_id': chatId,
      });
      final chat = TDParse.chat(raw);
      if (chat != null) _chats[chatId] = chat;
    } catch (_) {}
  }

  void _openChat(CallHistoryEntry entry) {
    if (entry.chatId == 0) return;
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) =>
            ChatView(chatId: entry.chatId, title: entry.title),
      ),
    );
  }

  void _startCall(CallHistoryEntry entry, {required bool isVideo}) {
    final userId = entry.userId;
    if (userId == null || userId == 0) return;
    context.read<CallManager>().startCall(userId, isVideo);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ColoredBox(
      color: c.groupedBackground,
      child: Column(
        children: [
          NavHeader(
            title: AppStringKeys.callsTitle,
            onBack: () => Navigator.of(context).pop(),
            trailing: _refreshAction(),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_entries.isEmpty && _loading) {
      return const Center(child: AppActivityIndicator(size: 24));
    }
    if (_entries.isEmpty && _failed) {
      return _EmptyCalls(
        icon: HeroAppIcons.triangleExclamation,
        title: AppStringKeys.callsLoadFailed,
        action: AppStringKeys.callsRetry,
        onAction: _loadMore,
      );
    }
    if (_entries.isEmpty) {
      return const _EmptyCalls(
        icon: HeroAppIcons.phone,
        title: AppStringKeys.callsEmpty,
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _entries.length + ((_loading || _failed) ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _entries.length) {
          if (_failed) {
            return _LoadMoreFailure(onRetry: _loadMore);
          }
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(child: AppActivityIndicator(size: 22)),
          );
        }
        final entry = _entries[index];
        return _CallRow(
          entry: entry,
          onTap: () => _openChat(entry),
          onVoiceCall: entry.userId == null
              ? null
              : () => _startCall(entry, isVideo: false),
          onVideoCall: entry.userId == null
              ? null
              : () => _startCall(entry, isVideo: true),
        );
      },
    );
  }

  Future<void> _refreshCalls() async {
    setState(() {
      _entries.clear();
      _seenMessageIds.clear();
      _nextOffset = '';
      _hasMore = true;
      _failed = false;
    });
    await _loadMore();
  }

  Widget _refreshAction() => Semantics(
    button: true,
    label: 'Refresh calls',
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _loading ? null : () => unawaited(_refreshCalls()),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: AppIcon(
          HeroAppIcons.arrowsRotate,
          size: 19,
          color: _loading
              ? context.colors.textTertiary
              : context.colors.textPrimary,
        ),
      ),
    ),
  );
}

class CallHistoryEntry {
  const CallHistoryEntry({
    required this.message,
    required this.chatId,
    required this.title,
    required this.photo,
    required this.kind,
    required this.userId,
  });

  final ChatMessage message;
  final int chatId;
  final String title;
  final TdFileRef? photo;
  final ChatKind kind;
  final int? userId;
}

class _CallRow extends StatelessWidget {
  const _CallRow({
    required this.entry,
    required this.onTap,
    required this.onVoiceCall,
    required this.onVideoCall,
  });

  final CallHistoryEntry entry;
  final VoidCallback onTap;
  final VoidCallback? onVoiceCall;
  final VoidCallback? onVideoCall;

  String _duration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return '$minutes:${remainder.toString().padLeft(2, '0')}';
  }

  String _status() {
    final message = entry.message;
    if (message.callDuration > 0) {
      return AppStrings.t(AppStringKeys.messageBubbleCallDuration, {
        'value1': _duration(message.callDuration),
      });
    }
    return switch (message.callDiscardReason) {
      'callDiscardReasonDeclined' => AppStrings.t(
        message.isOutgoing
            ? AppStringKeys.messageBubbleCallDeclinedByOther
            : AppStringKeys.messageBubbleCallDeclined,
      ),
      'callDiscardReasonMissed' => AppStrings.t(
        message.isOutgoing
            ? AppStringKeys.messageBubbleCallNoAnswer
            : AppStringKeys.messageBubbleCallMissed,
      ),
      _ => AppStrings.t(AppStringKeys.messageBubbleCallCanceled),
    };
  }

  bool get _isMissed =>
      !entry.message.isOutgoing &&
      entry.message.callDuration == 0 &&
      (entry.message.callDiscardReason == 'callDiscardReasonMissed' ||
          entry.message.callDiscardReason == 'callDiscardReasonDeclined');

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final direction = entry.message.isOutgoing
        ? AppStringKeys.callsOutgoing
        : AppStringKeys.callsIncoming;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        color: c.card,
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(
          children: [
            PhotoAvatar(
              title: entry.title,
              photo: entry.photo,
              size: 48,
              square:
                  entry.kind == ChatKind.group ||
                  entry.kind == ChatKind.channel,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _isMissed
                          ? const Color(0xFFFF3B30)
                          : c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      AppIcon(
                        entry.message.isOutgoing
                            ? HeroAppIcons.arrowUp
                            : HeroAppIcons.arrowDown,
                        size: 13,
                        color: _isMissed
                            ? const Color(0xFFFF3B30)
                            : c.textTertiary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '${direction.l10n(context)} · ${_status()} · '
                          '${DateText.separatorLabel(entry.message.date)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: c.textTertiary),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (onVoiceCall != null)
              _CallButton(
                icon: HeroAppIcons.phone,
                onTap: onVoiceCall!,
                semanticLabel: AppStringKeys.composerVoiceCall,
              ),
            if (onVideoCall != null)
              _CallButton(
                icon: HeroAppIcons.video,
                onTap: onVideoCall!,
                semanticLabel: AppStringKeys.composerVideoCall,
              ),
          ],
        ),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton({
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
  });

  final AppIconData icon;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel.l10n(context),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 44,
          child: Center(child: AppIcon(icon, size: 19, color: AppTheme.brand)),
        ),
      ),
    );
  }
}

class _EmptyCalls extends StatelessWidget {
  const _EmptyCalls({
    required this.icon,
    required this.title,
    this.action,
    this.onAction,
  });

  final AppIconData icon;
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(icon, size: 38, color: c.textTertiary),
            const SizedBox(height: 12),
            Text(
              title.l10n(context),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: c.textSecondary),
            ),
            if (action != null && onAction != null) ...[
              const SizedBox(height: 16),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onAction,
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTheme.brand,
                    borderRadius: BorderRadius.circular(19),
                  ),
                  child: Text(
                    action!.l10n(context),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.onAccent,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LoadMoreFailure extends StatelessWidget {
  const _LoadMoreFailure({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onRetry,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Text(
          AppStringKeys.callsRetry.l10n(context),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: AppTheme.brand),
        ),
      ),
    );
  }
}
