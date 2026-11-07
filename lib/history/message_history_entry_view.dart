//
//  message_history_entry_view.dart
//
//  One kept message of the local mirror, rendered like a chat bubble: the
//  text (or media snapshot), the sender line, and the edit trail. Deleted
//  entries get the translucent ghost styling known from AyuGram. Long-press
//  copies the kept text. Part of the Telegram API Terms §1.4 mirror that
//  exists only in opted-in self-builds.
//

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/toast.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'message_history_models.dart';
import 'message_media_snapshot.dart';

/// Renders one [MessageHistoryEntry] as a standalone bubble-shaped card.
class MessageHistoryEntryView extends StatelessWidget {
  const MessageHistoryEntryView({
    super.key,
    required this.entry,
    required this.chatTitle,
    this.showChatTitle = true,
    this.senderName,
    this.mediaDir,
    this.trailing,
  });

  final MessageHistoryEntry entry;

  /// Chat display title (already resolved by the caller).
  final String chatTitle;

  /// Whether the chat header line is rendered (hidden inside a chat-scoped
  /// list where every row shares it).
  final bool showChatTitle;

  /// Resolved sender display name, when known.
  final String? senderName;

  /// Directory holding the media snapshots; null disables preview loading.
  final MessageMediaSnapshotter? mediaDir;

  /// Optional trailing widget in the header line (e.g. a delete button).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final entry = this.entry;
    final c = context.colors;
    final deleted =
        entry.state == MessageHistoryState.deleted || !entry.hasLiveChat;
    final senderLine = senderName ?? '';
    final kindLabel = entry.kindLabel();
    return AppInteractiveSurface(
      onLongPress: () => _copyEntry(context, entry),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.divider, width: 0.5),
        ),
        foregroundDecoration: deleted
            ? BoxDecoration(
                color: c.groupedBackground.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(14),
              )
            : null,
        child: Opacity(
          opacity: deleted ? 0.55 : 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (deleted) ...[
                    AppIcon(
                      HeroAppIcons.trash,
                      size: 13,
                      color: c.textTertiary,
                    ),
                    const SizedBox(width: 5),
                  ],
                  if (showChatTitle) ...[
                    Expanded(
                      child: Text(
                        chatTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.footnote(c.textSecondary),
                      ),
                    ),
                  ] else if (senderLine.isNotEmpty) ...[
                    Expanded(
                      child: Text(
                        senderLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.footnote(c.textPrimary),
                      ),
                    ),
                  ] else ...[
                    const Expanded(child: SizedBox.shrink()),
                  ],
                  const SizedBox(width: 8),
                  Text(
                    _formatDateTime(entry.date),
                    style: AppTextStyle.footnote(c.textTertiary),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    trailing!,
                  ],
                ],
              ),
              const SizedBox(height: 6),
              _content(context, entry, kindLabel),
              if (entry.events.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final event in entry.events)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      AppStrings.t(AppStringKeys.historyEditEvent, {
                        'value1': _formatDateTime(event.at),
                        'value2': event.newText.isEmpty
                            ? AppStrings.t(AppStringKeys.historyKindUnknown)
                            : event.newText,
                      }),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.footnote(c.textTertiary),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    MessageHistoryEntry entry,
    String kindLabel,
  ) {
    final c = context.colors;
    final text = entry.text.trim();
    if (text.isNotEmpty) {
      return Text(text, style: AppTextStyle.body(c.textPrimary));
    }
    return Text(kindLabel, style: AppTextStyle.body(c.textSecondary));
  }

  Future<void> _copyEntry(BuildContext context, MessageHistoryEntry entry) {
    final text = entry.text.trim();
    if (text.isEmpty) return Future<void>.value();
    return Clipboard.setData(ClipboardData(text: text)).then((_) {
      if (context.mounted) {
        showToast(context, AppStringKeys.topicPostContentCopied.l10n(context));
      }
    });
  }
}

String _formatDateTime(int unixSeconds) {
  final t = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000).toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}
