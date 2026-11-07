//
//  message_history_revision_sheet.dart
//
//  The per-message revision sheet opened from the chat message menu: the
//  kept edit trail of one message, newest revision on top, each earlier text
//  readable in full and copyable by long-press. Telegram API Terms §1.4
//  feature, rendered only in opted-in self-builds.
//

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/toast.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import 'message_history_models.dart';

/// Shows the edit trail of [entry] as a bottom sheet. Nothing is shown when
/// the entry has no events (the caller already checks, this is the guard for
/// programmatic opens).
Future<void> showMessageHistoryRevisionSheet(
  BuildContext context,
  MessageHistoryEntry entry,
) {
  return showAppModalSheet<void>(
    context: context,
    backgroundColor: context.colors.groupedBackground,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    isScrollControlled: true,
    builder: (context) => _RevisionSheet(entry: entry),
  );
}

class _RevisionSheet extends StatelessWidget {
  const _RevisionSheet({required this.entry});

  final MessageHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Newest first: the trail is stored oldest-first, so the current text
    // (entry.text) leads and every event's old text follows.
    final revisions = <({int at, String text})>[
      (
        at: entry.events.isEmpty ? entry.date : entry.events.last.at,
        text: entry.text,
      ),
      for (final event in entry.events.reversed)
        (at: event.at, text: event.oldText ?? ''),
    ];
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                AppStringKeys.historyRevisionsTitle.l10n(context),
                style: AppTextStyle.body(
                  c.textPrimary,
                  weight: FontWeight.w600,
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 16),
                children: [
                  for (final revision in revisions)
                    _RevisionRow(at: revision.at, text: revision.text),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RevisionRow extends StatelessWidget {
  const _RevisionRow({required this.at, required this.text});

  final int at;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final body = text.trim().isEmpty
        ? AppStringKeys.historyKindUnknown.l10n(context)
        : text;
    return AppInteractiveSurface(
      onLongPress: () {
        if (text.trim().isEmpty) return;
        Clipboard.setData(ClipboardData(text: text));
        showToast(context, AppStringKeys.topicPostContentCopied.l10n(context));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AppIcon(
                  HeroAppIcons.penToSquare,
                  size: 12,
                  color: c.textTertiary,
                ),
                const SizedBox(width: 6),
                Text(
                  _formatDateTime(at),
                  style: AppTextStyle.footnote(c.textTertiary),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(body, style: AppTextStyle.body(c.textPrimary)),
          ],
        ),
      ),
    );
  }
}

String _formatDateTime(int unixSeconds) {
  final t = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000).toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}
