//
//  media_tile_action_sheet.dart
//
//  Long-press action sheet for sticker and GIF tiles in the composer media
//  panel, following NagramX's ContentPreviewViewer semantics: send, silent
//  send, schedule, favorites toggle, view sticker set, save, copy, and
//  delete-from-recent. The sheet is pure presentation — callers describe the
//  tile with [MediaTileDescriptor] and supply nullable callbacks in
//  [MediaTileActions]; a row renders only when its callback exists, and the
//  sheet itself performs no store or TDLib work. Panel wiring lives in the
//  composer.
//

import 'package:flutter/material.dart';

import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../platform/adaptive_platform.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import 'gif_item.dart';
import 'gif_preview.dart';
import 'sticker_item.dart';
import 'sticker_preview.dart';

/// Which kind of composer media tile a sheet describes.
enum MediaTileKind { sticker, gif }

/// The tile a [showMediaTileActionSheet] sheet is about, plus the state the
/// row labels depend on.
class MediaTileDescriptor {
  const MediaTileDescriptor.sticker(
    StickerItem item,
    this.inFavorites,
    this.isRecentTile,
  ) : kind = MediaTileKind.sticker,
      sticker = item,
      gif = null;

  const MediaTileDescriptor.gif(GifItem item, this.inFavorites)
    : kind = MediaTileKind.gif,
      sticker = null,
      gif = item,
      isRecentTile = false;

  final MediaTileKind kind;
  final StickerItem? sticker;
  final GifItem? gif;
  final bool inFavorites;

  /// Sticker-only: the tile sits in the recents pack, so the destructive
  /// "delete from recent" row applies.
  final bool isRecentTile;
}

/// Callbacks the sheet offers. A row renders only when its callback is
/// non-null; every action's semantics belong to the caller.
class MediaTileActions {
  const MediaTileActions({
    this.send,
    this.sendWithoutSound,
    this.schedule,
    this.toggleFavorite,
    this.viewSet,
    this.save,
    this.copy,
    this.removeFromRecent,
  });

  final VoidCallback? send;
  final VoidCallback? sendWithoutSound;
  final VoidCallback? schedule;
  final VoidCallback? toggleFavorite;
  final VoidCallback? viewSet;
  final VoidCallback? save;
  final VoidCallback? copy;
  final VoidCallback? removeFromRecent;
}

/// Destructive label color, matching MessageActionMenu's delete rows.
const Color _destructive = Color(0xFFFF6961);

/// Row lead-in for the dividers: 16px padding + 20px icon + 12px gap.
const double _rowDividerInset = 48;

/// Opens the long-press action sheet for a sticker or GIF tile.
Future<void> showMediaTileActionSheet(
  BuildContext context,
  MediaTileDescriptor descriptor,
  MediaTileActions actions,
) {
  final desktop = isDesktopTargetPlatform(Theme.of(context).platform);
  return showAppModalSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) {
      final c = context.colors;
      return SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Center(
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: descriptor.kind == MediaTileKind.sticker
                        ? StickerPreview(item: descriptor.sticker!)
                        : GifPreview(item: descriptor.gif!),
                  ),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: [
                    for (final row in _rowsFor(
                      descriptor,
                      actions,
                      desktop: desktop,
                    )) ...[
                      _MediaTileActionRow(row),
                      const InsetDivider(leadingInset: _rowDividerInset),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _MediaTileActionSpec {
  const _MediaTileActionSpec(
    this.key,
    this.icon,
    this.labelKey,
    this.onTap, {
    this.destructive = false,
  });

  final String key;
  final AppIconData icon;
  final String labelKey;
  final VoidCallback? onTap;
  final bool destructive;
}

List<_MediaTileActionSpec> _rowsFor(
  MediaTileDescriptor descriptor,
  MediaTileActions actions, {
  required bool desktop,
}) {
  final sticker = descriptor.sticker;
  // Copy Sticker is a desktop affordance for static WebP stickers only.
  final copyEligible =
      sticker != null && !sticker.isAnimated && !sticker.isVideo && desktop;
  return [
    if (actions.send != null)
      _MediaTileActionSpec(
        'send',
        HeroAppIcons.paperPlane,
        AppStringKeys.mediaTileSend,
        actions.send,
      ),
    if (actions.sendWithoutSound != null)
      _MediaTileActionSpec(
        'sendWithoutSound',
        HeroAppIcons.volumeXmark,
        AppStringKeys.mediaTileSendWithoutSound,
        actions.sendWithoutSound,
      ),
    if (actions.schedule != null)
      _MediaTileActionSpec(
        'schedule',
        HeroAppIcons.clock,
        AppStringKeys.mediaTileSchedule,
        actions.schedule,
      ),
    if (actions.toggleFavorite != null)
      _MediaTileActionSpec(
        'toggleFavorite',
        descriptor.inFavorites ? HeroAppIcons.star : HeroAppIcons.solidStar,
        descriptor.inFavorites
            ? AppStringKeys.mediaTileRemoveFromFavorites
            : AppStringKeys.mediaTileAddToFavorites,
        actions.toggleFavorite,
      ),
    if (actions.viewSet != null && descriptor.kind == MediaTileKind.sticker)
      _MediaTileActionSpec(
        'viewSet',
        HeroAppIcons.tableCells,
        AppStringKeys.mediaTileViewStickerSet,
        actions.viewSet,
      ),
    if (actions.save != null)
      _MediaTileActionSpec(
        'save',
        HeroAppIcons.download,
        desktop
            ? AppStringKeys.mediaTileSaveToFile
            : AppStringKeys.mediaTileSaveToGallery,
        actions.save,
      ),
    if (actions.copy != null && copyEligible)
      _MediaTileActionSpec(
        'copy',
        HeroAppIcons.documentDuplicate,
        AppStringKeys.mediaTileCopySticker,
        actions.copy,
      ),
    if (actions.removeFromRecent != null)
      _MediaTileActionSpec(
        'removeFromRecent',
        HeroAppIcons.trash,
        AppStringKeys.mediaTileDeleteFromRecent,
        actions.removeFromRecent,
        destructive: true,
      ),
  ];
}

class _MediaTileActionRow extends StatelessWidget {
  const _MediaTileActionRow(this.spec);

  final _MediaTileActionSpec spec;

  @override
  Widget build(BuildContext context) {
    final label = spec.labelKey.l10n(context);
    final color = spec.destructive ? _destructive : context.colors.textPrimary;
    return GestureDetector(
      key: ValueKey('mediaTileAction-${spec.key}'),
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Navigator.of(context).pop();
        spec.onTap?.call();
      },
      child: Semantics(
        button: true,
        label: label,
        child: SizedBox(
          height: 48,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                AppIcon(spec.icon, size: 20, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, color: color),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
