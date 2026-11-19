//
//  sticker_item.dart
//
//  A pickable sticker or custom emoji (from the user's sets / favorites), passed
//  to ChatViewModel.sendSticker or inserted inline into the composer. Port of
//  the Swift `StickerItem`, extended with `customEmojiId` for premium emoji.
//

import '../../tdlib/td_models.dart';

class StickerItem {
  const StickerItem({
    required this.id,
    this.remoteId,
    required this.width,
    required this.height,
    required this.emoji,
    this.isAnimated = false,
    this.isVideo = false,
    this.thumb,
    this.customEmojiId = 0,
  });
  final int id;
  final String? remoteId;
  final int width;
  final int height;
  final String emoji; // associated standard emoji (custom-emoji fallback)
  final bool isAnimated; // .tgs (Lottie)
  final bool isVideo; // .webm (VP9 video sticker)
  final TdFileRef? thumb; // for display in the picker
  final int customEmojiId; // custom_emoji_id (premium emoji), or 0 if regular
}
