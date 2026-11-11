//
//  message_history_entry_view.dart
//
//  One kept message of the local mirror, rendered like a chat bubble: the
//  text (or media snapshot), the sender line, and the edit trail. Deleted
//  entries get the translucent ghost styling. Long-press
//  copies the kept text. Part of the Telegram API Terms §1.4 mirror that
//  exists only in opted-in self-builds.
//

import 'dart:io';

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
    this.onOpenMedia,
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

  /// Directory holding the media snapshots; supplied by the caller when
  /// previews should resolve snapshot paths (the viewer owns the snapshotter
  /// wiring). Null keeps media-only rows on their kind label.
  final MessageMediaSnapshotter? mediaDir;

  /// Opens the snapshot file in the system viewer (photos/videos/audio —
  /// whatever the OS can play); a kind label stays the fallback when the
  /// file is gone.
  final void Function(String path)? onOpenMedia;

  /// Optional trailing widget in the header line (e.g. a delete button).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final entry = this.entry;
    final c = context.colors;
    final deleted =
        entry.state == MessageHistoryState.deleted || !entry.hasLiveChat;
    final senderLine = senderName ?? '';
    final kindLabel = entry.kindKey.isEmpty
        ? ''
        : _localizedKindLabel(context, entry.kindKey);
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
    final media = _snapshotPath(entry);
    if (text.isNotEmpty && media == null) {
      return Text(text, style: AppTextStyle.body(c.textPrimary));
    }
    if (media != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: MediaSnapshotView(
          path: media,
          kindKey: entry.kindKey,
          kindLabel: kindLabel,
          onTap: onOpenMedia == null ? null : () => onOpenMedia!(media),
        ),
      );
    }
    return Text(kindLabel, style: AppTextStyle.body(c.textSecondary));
  }

  /// The snapshot path recorded on the entry, validated against the current
  /// snapshot directory so a stale path (file wiped, directory moved) renders
  /// the kind label instead of a broken preview.
  String? _snapshotPath(MessageHistoryEntry entry) {
    if (entry.mediaPath.isEmpty) return null;
    final directory = mediaDir?.dir?.path;
    if (directory == null) return null;
    if (!entry.mediaPath.startsWith('$directory/')) return null;
    return entry.mediaPath;
  }

  /// Localized kind name for a stored kind suffix; unknown kinds keep the
  /// generic label instead of leaking the raw key.
  static String _localizedKindLabel(BuildContext context, String suffix) =>
      localizedHistoryKindLabel(context, suffix);

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

/// Localized kind name for a stored kind suffix, shared by the entry view
/// and the revision view; unknown kinds keep the generic label instead of
/// leaking the raw key.
String localizedHistoryKindLabel(BuildContext context, String suffix) {
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
  return AppStrings.t(key).isEmpty ? suffix : key.l10n(context);
}

/// Renders a media snapshot: images inline (cached, aspect-preserved), other
/// kinds as a tappable file row with the kind's icon; both fall back to the
/// kind label when the file is missing. [onTap] opens the file externally.
class MediaSnapshotView extends StatefulWidget {
  const MediaSnapshotView({
    super.key,
    required this.path,
    required this.kindKey,
    required this.kindLabel,
    this.onTap,
  });

  final String path;
  final String kindKey;
  final String kindLabel;
  final VoidCallback? onTap;

  @override
  State<MediaSnapshotView> createState() => _MediaSnapshotViewState();
}

class _MediaSnapshotViewState extends State<MediaSnapshotView> {
  bool? _exists;

  @override
  void initState() {
    super.initState();
    // Plain test() bodies may await real IO; widget tests drive this widget
    // through runAsync-free pumps, so resolve asynchronously and rebuild.
    File(widget.path).exists().then((exists) {
      if (mounted) setState(() => _exists = exists);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (_exists == false) {
      return Text(widget.kindLabel, style: AppTextStyle.body(c.textSecondary));
    }
    final isImage = switch (widget.kindKey) {
      'historyKindPhoto' => true,
      _ => false,
    };
    final body = isImage
        ? ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(
              File(widget.path),
              key: ValueKey('history-media-${widget.path}'),
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => Text(
                widget.kindLabel,
                style: AppTextStyle.body(c.textSecondary),
              ),
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                _kindIcon(widget.kindKey),
                size: 15,
                color: c.textSecondary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  widget.kindLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.body(c.textSecondary),
                ),
              ),
            ],
          );
    final onTap = widget.onTap;
    if (onTap == null) return body;
    return GestureDetector(onTap: onTap, child: body);
  }

  static AppIconData _kindIcon(String kindKey) => switch (kindKey) {
    'historyKindVideo' ||
    'historyKindVideoNote' ||
    'historyKindAnimation' => HeroAppIcons.video,
    'historyKindVoice' => HeroAppIcons.microphone,
    'historyKindAudio' => HeroAppIcons.music,
    'historyKindDocument' => HeroAppIcons.file,
    _ => HeroAppIcons.image,
  };
}
