//
//  inline_video_autoplay.dart
//
//  Decides which chat videos play inside their bubble instead of waiting for a
//  tap that opens the dedicated player.
//

/// Telegram Desktop refuses to decode a frame larger than this inside the
/// transcript (`HistoryView::Gif::kMaxInlineArea`); the tapped player handles
/// those instead.
const int inlineVideoAutoplayMaxArea = 1920 * 1080;

/// The largest video this client fetches on sight for an inline preview.
///
/// Telegram Desktop allows up to its auto-play limit (50 MB by default) because
/// it streams the file while it plays. This client hands a completed local file
/// to the platform player, so an inline preview means downloading the whole
/// video: the budget is Telegram's default auto-download size instead
/// (`Data::AutoDownload::kDefaultMaxSize`), and anything larger keeps its
/// thumbnail until the user asks for it.
const int inlineVideoAutoplayMaxBytes = 8 * 1024 * 1024;

/// Whether a message's video plays inline, muted and looping, the way official
/// clients autoplay GIFs, video messages and short videos.
///
/// [contentType] is the TDLib message content type. Animations are Telegram's
/// GIFs: they are silent, small, and always play in place. Videos and video
/// messages join them while they stay inside the size and frame budgets.
bool shouldAutoplayVideoInline({
  required String? contentType,
  required int? fileSizeBytes,
  required int? width,
  required int? height,
}) {
  switch (contentType) {
    case 'messageAnimation':
      return true;
    case 'messageVideo':
    case 'messageVideoNote':
      final size = fileSizeBytes ?? 0;
      if (size <= 0 || size > inlineVideoAutoplayMaxBytes) return false;
      return _fitsInlineFrame(width, height);
    default:
      return false;
  }
}

/// Unknown dimensions are allowed: TDLib omits them for some forwarded videos,
/// and the bubble already lays those out from the thumbnail.
bool _fitsInlineFrame(int? width, int? height) {
  final frameWidth = width ?? 0;
  final frameHeight = height ?? 0;
  if (frameWidth <= 0 || frameHeight <= 0) return true;
  return frameWidth * frameHeight <= inlineVideoAutoplayMaxArea;
}
