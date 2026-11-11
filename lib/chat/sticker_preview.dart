//
//  sticker_preview.dart
//
//  Renders a StickerItem at preview size, animated by format: .tgs → Lottie,
//  .webm → VideoStickerView where supported or TDLib's thumbnail fallback,
//  .webp/other → its static thumbnail. Shared by the sticker picker grid, the
//  set-icon tabs, and the 表情详情 set-detail page.
//

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart' show FrameRate;

import '../components/app_icons.dart';
import '../components/photo_avatar.dart'; // TDImage
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import 'animated_sticker_view.dart';
import 'sticker_item.dart';
import 'video_sticker_view.dart';

class StickerPreview extends StatelessWidget {
  const StickerPreview({super.key, required this.item, this.cornerRadius = 6});
  final StickerItem item;
  final double cornerRadius;

  @override
  Widget build(BuildContext context) {
    final file = TdFileRef(id: item.id);
    if (item.isAnimated) {
      // Previews sit in grids of a dozen or more; at this size 30 fps looks
      // the same and halves the per-frame Lottie work for 60 fps stickers.
      return AnimatedStickerView(file: file, frameRate: const FrameRate(30));
    }
    if (item.isVideo) {
      final fallback = item.thumb?.id == item.id ? null : item.thumb;
      if (fallback != null) {
        return VideoStickerView(file: file, fallback: fallback);
      }
      return Center(
        child: Text(
          item.emoji.isEmpty ? '🎴' : item.emoji,
          style: const TextStyle(fontSize: 30),
        ),
      );
    }
    if (item.thumb != null) {
      return TDImage(
        photo: item.thumb,
        cornerRadius: cornerRadius,
        fit: BoxFit.contain,
      );
    }
    return Center(
      child: Text(
        item.emoji.isEmpty ? '🎴' : item.emoji,
        style: const TextStyle(fontSize: 30),
      ),
    );
  }
}

/// Stable, non-animated cover used by the narrow sticker-set tab strip.
/// Starting TGS/WebM decoders in 28px tab cells causes corrupt frames while
/// tabs are recycled, so only Telegram's static thumbnail is rendered here.
class StickerTabPreview extends StatelessWidget {
  const StickerTabPreview({super.key, required this.item});

  final StickerItem item;

  @override
  Widget build(BuildContext context) {
    final thumbnail = item.thumb;
    final canRenderThumbnail =
        thumbnail != null &&
        (!(item.isAnimated || item.isVideo) || thumbnail.id != item.id);
    if (canRenderThumbnail) {
      return TDImage(photo: thumbnail, cornerRadius: 4, fit: BoxFit.contain);
    }
    if (item.emoji.isNotEmpty) {
      return Text(item.emoji, style: const TextStyle(fontSize: 22));
    }
    return AppIcon(
      HeroAppIcons.solidFaceSmile,
      size: 20,
      color: context.colors.textSecondary,
    );
  }
}
