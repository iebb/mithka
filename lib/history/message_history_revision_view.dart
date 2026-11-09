//
//  message_history_revision_view.dart
//
//  Full-screen edit history of one kept message (Telegram API Terms §1.4
//  feature, only in opted-in self-builds): every revision renders as a
//  chat-style bubble, newest first, with the media snapshot it had at that
//  time when one exists. Long-press copies the revision text. Opened from
//  the chat message menu and from the history viewer.
//

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../chat/file_opener.dart';
import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../config/build_flags.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'message_history_entry_view.dart'
    show MediaSnapshotView, localizedHistoryKindLabel;
import 'message_history_models.dart';
import 'message_media_snapshot.dart';

/// One revision as it was at a point in time.
class _Revision {
  const _Revision({
    required this.at,
    required this.text,
    required this.kindKey,
    required this.mediaPath,
  });

  final int at;
  final String text;
  final String kindKey;
  final String mediaPath;
}

/// Full-screen edit history of one mirrored message.
class MessageHistoryRevisionView extends StatefulWidget {
  const MessageHistoryRevisionView({super.key, required this.entry});

  final MessageHistoryEntry entry;

  @override
  State<MessageHistoryRevisionView> createState() =>
      _MessageHistoryRevisionViewState();
}

class _MessageHistoryRevisionViewState
    extends State<MessageHistoryRevisionView> {
  @override
  void initState() {
    super.initState();
    // The snapshot directory is resolved lazily on first snapshot; entering
    // this page straight from a long-press can be the first mirror surface
    // of the session, so resolve it before the first frame renders media
    // rows as bare kind labels. The page rebuilds once the directory lands
    // (the resolver is not a listenable).
    if (allowTelegramTosViolations) {
      unawaited(
        MessageMediaSnapshotter.shared.ensureDirResolved().then((_) {
          if (mounted) setState(() {});
        }),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPageScaffold(
      title: AppStringKeys.historyRevisionsTitle.l10n(context),
      onBack: () => Navigator.of(context).pop(),
      child: SettingsListView(
        children: [
          if (widget.entry.events.isEmpty)
            const SettingsNote(text: AppStringKeys.historyEmpty)
          else
            for (final revision in _revisions)
              _RevisionBubble(
                key: ValueKey('revision-${revision.at}'),
                revision: revision,
                mediaDir: MessageMediaSnapshotter.shared,
                onOpenMedia: (path) => openDownloadedFile(context, path),
              ),
        ],
      ),
    );
  }

  List<_Revision> get _revisions {
    // Newest first: the current text leads, then each event's previous state.
    final entry = widget.entry;
    final list = <_Revision>[
      _Revision(
        at: entry.events.isEmpty ? entry.date : entry.events.last.at,
        text: entry.text,
        kindKey: entry.kindKey,
        mediaPath: entry.mediaPath,
      ),
      for (final event in entry.events.reversed)
        _Revision(
          at: event.at,
          text: event.oldText ?? '',
          kindKey: event.oldKindKey,
          mediaPath: event.oldMediaPath,
        ),
    ];
    return list;
  }
}

class _RevisionBubble extends StatelessWidget {
  const _RevisionBubble({
    super.key,
    required this.revision,
    required this.mediaDir,
    required this.onOpenMedia,
  });

  final _Revision revision;
  final MessageMediaSnapshotter mediaDir;
  final void Function(String path) onOpenMedia;

  String? get _snapshotPath {
    if (revision.mediaPath.isEmpty) return null;
    final directory = mediaDir.dir?.path;
    if (directory == null) return null;
    if (!revision.mediaPath.startsWith('$directory/')) return null;
    return revision.mediaPath;
  }

  String _kindLabel(BuildContext context) =>
      localizedHistoryKindLabel(context, revision.kindKey);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = revision.text.trim();
    final media = _snapshotPath;
    final kindLabel = _kindLabel(context);
    return AppInteractiveSurface(
      onLongPress: () {
        if (text.isEmpty) return;
        Clipboard.setData(ClipboardData(text: text));
        showToast(context, AppStringKeys.topicPostContentCopied.l10n(context));
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.divider, width: 0.5),
        ),
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
                  _formatDateTime(revision.at),
                  style: AppTextStyle.footnote(c.textTertiary),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (text.isNotEmpty)
              Text(text, style: AppTextStyle.body(c.textPrimary)),
            if (media != null) ...[
              const SizedBox(height: 6),
              MediaSnapshotView(
                path: media,
                kindKey: revision.kindKey,
                kindLabel: kindLabel,
                onTap: () => onOpenMedia(media),
              ),
            ],
            if (text.isEmpty && media == null && kindLabel.isNotEmpty)
              Text(kindLabel, style: AppTextStyle.body(c.textSecondary)),
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
