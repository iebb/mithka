//
//  message_history_view.dart
//
//  The local message-history viewer: every kept copy of what this account
//  received, including messages the counterpart deleted or edited
//  afterwards. Entries are grouped per chat; opening a chat shows its kept
//  messages newest-first with edit trails and media snapshots. Deleted
//  entries render translucent (the AyuGram ghost style). Opened from
//  Advanced settings behind the compile-time [allowTelegramTosViolations]
//  gate.
//

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../components/app_confirm_dialog.dart';
import '../components/app_icons.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../config/build_flags.dart';
import '../l10n/app_localizations.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import 'message_history_entry_view.dart';
import 'message_history_store.dart';

class MessageHistoryView extends StatefulWidget {
  const MessageHistoryView({super.key, this.chatId, this.store});

  /// Pre-filters the list to this chat; the viewer can still switch.
  final int? chatId;

  /// Injectable for tests; defaults to the shared store.
  final MessageHistoryStore? store;

  @override
  State<MessageHistoryView> createState() => _MessageHistoryViewState();
}

class _MessageHistoryViewState extends State<MessageHistoryView> {
  late MessageHistoryStore _store;
  late int? _chatId;
  Map<int, String> _chatTitles = const {};
  bool _resolvingTitles = false;
  int? _titleAccountUserId;
  int _titleResolutionGeneration = 0;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? MessageHistoryStore.shared;
    _chatId = widget.chatId;
    if (!allowTelegramTosViolations) return;
    _titleAccountUserId = _store.activeAccountUserId;
    _store.addListener(_onStore);
    unawaited(_store.ensureLoaded());
    _maybeResolveChatTitles();
  }

  @override
  void dispose() {
    _store.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() {
    if (_titleAccountUserId != _store.activeAccountUserId) {
      _titleAccountUserId = _store.activeAccountUserId;
      _titleResolutionGeneration++;
      _resolvingTitles = false;
      _chatTitles = const {};
      _chatId = null;
    }
    if (mounted) setState(() {});
    _maybeResolveChatTitles();
  }

  /// Resolves display titles for every chat that has kept copies, once the
  /// set of chats is not fully covered yet. Failures keep the localized
  /// "Chat {id}" fallback.
  void _maybeResolveChatTitles() {
    if (_resolvingTitles) return;
    final wanted = {for (final entry in _store.entries) entry.chatId};
    if (_chatTitles.keys.toSet().containsAll(wanted)) return;
    _resolvingTitles = true;
    unawaited(_resolveChatTitles(wanted, ++_titleResolutionGeneration));
  }

  Future<void> _resolveChatTitles(Set<int> chatIds, int generation) async {
    final clientId = TdClient.shared.activeClientId;
    final resolved = <int, String>{};
    for (final chatId in chatIds) {
      if (!mounted || generation != _titleResolutionGeneration) return;
      try {
        final chat = await TdClient.shared.queryTo({
          '@type': 'getChat',
          'chat_id': chatId,
        }, clientId);
        final title = chat.str('title');
        if (title != null && title.isNotEmpty) resolved[chatId] = title;
      } catch (_) {
        // Fall through to the localized "Chat {id}" label.
      }
    }
    if (!mounted || generation != _titleResolutionGeneration) return;
    if (resolved.isNotEmpty) {
      setState(() => _chatTitles = {..._chatTitles, ...resolved});
    }
    _resolvingTitles = false;
  }

  String _chatLabel(int chatId) =>
      _chatTitles[chatId] ??
      AppStrings.t(AppStringKeys.historyChatLabel, {'value1': '$chatId'});

  Future<void> _confirmClearAll() async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: AppStringKeys.historyClearAllConfirmTitle.l10n(context),
      confirmText: AppStringKeys.historyClearAction.l10n(context),
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    _store.clearAll();
    if (!mounted) return;
    setState(() => _chatId = null);
    showToast(context, AppStringKeys.historyClearedToast.l10n(context));
  }

  Future<void> _confirmClearChat(int chatId) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: AppStrings.t(AppStringKeys.historyClearChatConfirmTitle, {
        'value1': _chatLabel(chatId),
      }),
      confirmText: AppStringKeys.historyClearAction.l10n(context),
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    _store.clearChat(chatId);
    if (!mounted) return;
    if (_chatId == chatId) {
      setState(() => _chatId = null);
    } else {
      setState(() {});
    }
    showToast(context, AppStringKeys.historyClearedToast.l10n(context));
  }

  @override
  Widget build(BuildContext context) {
    if (!allowTelegramTosViolations) return const SizedBox.shrink();
    final chatId = _chatId;
    return SettingsPageScaffold(
      title: chatId == null
          ? AppStringKeys.historyTitle.l10n(context)
          : _chatLabel(chatId),
      onBack: () => Navigator.of(context).pop(),
      trailingIcon: HeroAppIcons.trash,
      // Unfiltered: the header clears everything. Filtered: it clears the
      // chat in view, which is the narrower clear the user is looking at.
      onTrailing: _store.entries.isEmpty
          ? null
          : chatId == null
          ? _confirmClearAll
          : () => unawaited(_confirmClearChat(chatId)),
      child: chatId == null
          ? _buildChatList(context)
          : _buildChatEntries(context, chatId),
    );
  }

  /// The chat list: one row per chat with kept copies, plus the exclusion
  /// entry point.
  Widget _buildChatList(BuildContext context) {
    final entries = _store.entries;
    // Newest kept copy per chat drives the row order and the preview line.
    final latestByChat = <int, MessageHistoryEntry>{};
    final counts = <int, int>{};
    for (final entry in entries) {
      final latest = latestByChat[entry.chatId];
      if (latest == null || entry.date > latest.date) {
        latestByChat[entry.chatId] = entry;
      }
      counts[entry.chatId] = (counts[entry.chatId] ?? 0) + 1;
    }
    final chats = latestByChat.keys.toList()
      ..sort((a, b) => latestByChat[b]!.date.compareTo(latestByChat[a]!.date));
    return SettingsListView(
      children: [
        SettingsCard.rows(
          rows: [
            // Excluded chats stay recorded nowhere, so the filter needs a
            // manual re-entry point for them.
            SettingsRow(
              title: AppStringKeys.historyExcludedTitle.l10n(context),
              value: '${_store.excludedChats.length}',
              leading: const SettingsLeadingIcon(icon: HeroAppIcons.eyeSlash),
              onTap: _openExcludedChats,
            ),
          ],
        ),
        if (chats.isEmpty)
          const SettingsNote(
            key: ValueKey('history-view-empty'),
            text: AppStringKeys.historyEmpty,
          )
        else
          SettingsCard.rows(
            rows: [
              for (final chatId in chats)
                SettingsRow(
                  key: ValueKey('history-chat-$chatId'),
                  title: _chatLabel(chatId),
                  subtitle: _chatRowPreview(latestByChat[chatId]!),
                  value: '${counts[chatId]}',
                  leading: _ChatLeading(
                    label: _chatLabel(chatId),
                    dead: latestByChat[chatId]!.hasLiveChat
                        ? false
                        : latestByChat.entries.any(
                            (e) => e.key == chatId && !e.value.hasLiveChat,
                          ),
                  ),
                  onTap: () => setState(() => _chatId = chatId),
                ),
            ],
          ),
      ],
    );
  }

  String _chatRowPreview(MessageHistoryEntry entry) {
    final parts = <String>[
      if (entry.state == MessageHistoryState.deleted)
        AppStringKeys.historyDeletedLabel.l10n(context),
      if (entry.isEdited) AppStringKeys.historyEditedLabel.l10n(context),
    ];
    final body = entry.text.trim().isNotEmpty
        ? entry.text.trim()
        : _kindLabel(context, entry.kindKey);
    return parts.isEmpty ? body : '${parts.join(' · ')} · $body';
  }

  /// The kept messages of one chat, newest first, with edit trails. Each row
  /// can be deleted individually.
  Widget _buildChatEntries(BuildContext context, int chatId) {
    final entries = _store.entriesFor(chatId).reversed.toList();
    return SettingsListView(
      children: [
        if (entries.isEmpty)
          const SettingsNote(text: AppStringKeys.historyEmpty)
        else ...[
          for (final entry in entries)
            MessageHistoryEntryView(
              key: ValueKey('history-${entry.key}'),
              entry: entry,
              chatTitle: _chatLabel(chatId),
              showChatTitle: false,
              trailing: _EntryDeleteButton(
                onDelete: () => _store.deleteEntry(entry),
              ),
            ),
          const SettingsNote(text: AppStringKeys.historyFilteredNote),
        ],
      ],
    );
  }

  String _kindLabel(BuildContext context, String kindKey) =>
      kindKey.isEmpty ? '' : _kindKeyToLabel(context, kindKey);

  String _kindKeyToLabel(BuildContext context, String suffix) {
    final key = switch (suffix) {
      'historyKindPhoto' => AppStringKeys.historyKindPhoto,
      'historyKindVideo' => AppStringKeys.historyKindVideo,
      'historyKindVideoNote' => AppStringKeys.historyKindVideoNote,
      'historyKindVoice' => AppStringKeys.historyKindVoice,
      'historyKindAnimation' => AppStringKeys.historyKindAnimation,
      'historyKindSticker' => AppStringKeys.historyKindSticker,
      'historyKindDocument' => AppStringKeys.historyKindDocument,
      'historyKindAudio' => AppStringKeys.historyKindAudio,
      'historyKindPoll' => AppStringKeys.historyKindPoll,
      'historyKindLocation' => AppStringKeys.historyKindLocation,
      'historyKindContact' => AppStringKeys.historyKindContact,
      'historyKindDice' => AppStringKeys.historyKindDice,
      _ => AppStringKeys.historyKindUnknown,
    };
    return key.l10n(context);
  }

  void _openExcludedChats() {
    Navigator.of(context).push(
      AppPageRoute<void>(
        pageBuilder: (_, _, _) => MessageHistoryExcludedChatsView(
          store: _store,
          chatLabel: _chatLabel,
        ),
      ),
    );
  }
}

/// Small circular chat avatar stand-in with the initial, tinted down for
/// chats whose counterpart is gone.
class _ChatLeading extends StatelessWidget {
  const _ChatLeading({required this.label, required this.dead});

  final String label;
  final bool dead;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final initial = label.trim().isEmpty ? '·' : _firstGlyph(label.trim());
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: dead ? c.groupedBackground : c.card,
        border: Border.all(color: c.divider, width: 0.5),
      ),
      child: Text(
        initial,
        maxLines: 1,
        style: AppTextStyle.footnote(
          dead ? c.textTertiary : c.textSecondary,
        ).copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _EntryDeleteButton extends StatelessWidget {
  const _EntryDeleteButton({required this.onDelete});

  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onDelete,
      child: SizedBox(
        width: 30,
        height: 30,
        child: Center(
          child: AppIcon(HeroAppIcons.trash, size: 15, color: c.textTertiary),
        ),
      ),
    );
  }
}

/// Chats the mirror must not record, with re-include actions.
class MessageHistoryExcludedChatsView extends StatelessWidget {
  const MessageHistoryExcludedChatsView({
    super.key,
    required this.store,
    required this.chatLabel,
  });

  final MessageHistoryStore store;
  final String Function(int chatId) chatLabel;

  @override
  Widget build(BuildContext context) {
    if (!allowTelegramTosViolations) return const SizedBox.shrink();
    return SettingsPageScaffold(
      title: AppStringKeys.historyExcludedTitle.l10n(context),
      onBack: () => Navigator.of(context).pop(),
      child: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final chats = store.excludedChats.toList()..sort();
          return SettingsListView(
            children: [
              if (chats.isEmpty)
                const SettingsNote(text: AppStringKeys.historyNoExcludedChats)
              else
                SettingsCard.rows(
                  rows: [
                    for (final chatId in chats)
                      SettingsRow(
                        key: ValueKey('history-excluded-$chatId'),
                        title: chatLabel(chatId),
                        value: AppStringKeys.historyReincludeAction.l10n(
                          context,
                        ),
                        onTap: () => store.includeChat(chatId),
                      ),
                  ],
                ),
              const SettingsNote(text: AppStringKeys.historyExcludedNote),
            ],
          );
        },
      ),
    );
  }
}

String _firstGlyph(String text) {
  final runes = text.runes;
  if (runes.isEmpty) return '·';
  return String.fromCharCode(runes.first);
}
