import '../chat/stickers/custom_emoji.dart';
import '../chat/stickers/sticker_item.dart';
import '../tdlib/json_helpers.dart';

/// Extracts the display sticker from each profile-visible received gift.
List<StickerItem> parseReceivedGiftStickers(Map<String, dynamic> response) {
  final stickers = <StickerItem>[];
  for (final received
      in response.objects('gifts') ?? const <Map<String, dynamic>>[]) {
    final sentGift = received.obj('gift');
    final gift = sentGift?.obj('gift');
    final sticker = switch (sentGift?.type) {
      'sentGiftRegular' => gift?.obj('sticker'),
      'sentGiftUpgraded' => gift?.obj('model')?.obj('sticker'),
      _ => null,
    };
    if (sticker == null) continue;
    final parsed = parseStickers([sticker]);
    if (parsed.isNotEmpty) stickers.add(parsed.first);
  }
  return stickers;
}
