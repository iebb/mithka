import 'package:flutter/widgets.dart';

import '../chat/stretchable_message_bubble_background.dart';
import '../theme/message_bubble_background.dart';

const _canvasColor = Color(0xFF222222);
const _purpleTextColor = Color(0xFFFFF09B);
const _creamTextColor = Color(0xFFD35722);

void main() {
  runApp(const MessageBubblePreviewApp());
}

/// Deterministic 2x iPhone SE fixture for pixel-comparing the two decorative
/// message-bubble presets with their source references.
class MessageBubblePreviewApp extends StatelessWidget {
  const MessageBubblePreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return WidgetsApp(
      color: _canvasColor,
      debugShowCheckedModeBanner: false,
      builder: (context, child) => const _PreviewGallery(),
    );
  }
}

class _PreviewGallery extends StatelessWidget {
  const _PreviewGallery();

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.noScaling, boldText: false),
      child: const ColoredBox(
        color: _canvasColor,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: 86.5,
              top: 96,
              width: 202,
              height: 61,
              child: _PurpleReferenceCanvas(),
            ),
            Positioned(
              left: 9.5,
              top: 224,
              width: 356,
              height: 67,
              child: _CreamReferenceCanvas(),
            ),
          ],
        ),
      ),
    );
  }
}

class _PurpleReferenceCanvas extends StatelessWidget {
  const _PurpleReferenceCanvas();

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 2,
          top: 10,
          width: 32,
          height: 32,
          child: Image.asset(
            'assets/message_bubbles/reference_purple_avatar.png',
            fit: BoxFit.fill,
            filterQuality: FilterQuality.high,
          ),
        ),
        const Positioned(
          left: 42.5,
          top: 8.5,
          width: 135,
          height: 40,
          child: StretchableMessageBubbleBackground(
            background: MessageBubbleBackgroundSpec.purpleFolded,
            fallbackColor: Color(0xFF4B2A86),
            fallbackBorderRadius: BorderRadius.zero,
            fallbackPadding: EdgeInsets.zero,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '躺一下 拖延症犯了',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                style: TextStyle(
                  color: _purpleTextColor,
                  fontSize: 14.1,
                  height: 1,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.15,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CreamReferenceCanvas extends StatelessWidget {
  const _CreamReferenceCanvas();

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 11,
          top: 12,
          width: 32,
          height: 32,
          child: Image.asset(
            'assets/message_bubbles/reference_cream_avatar.png',
            fit: BoxFit.fill,
            filterQuality: FilterQuality.high,
          ),
        ),
        const Positioned(
          left: 44.5,
          top: 8.5,
          width: 293,
          height: 48,
          child: StretchableMessageBubbleBackground(
            background: MessageBubbleBackgroundSpec.creamCharms,
            fallbackColor: Color(0xFFFFF2A4),
            fallbackBorderRadius: BorderRadius.zero,
            fallbackPadding: EdgeInsets.zero,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'https://casetify.com/auth/C5Q-HRD-6RP',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                style: TextStyle(
                  color: _creamTextColor,
                  fontSize: 13.6,
                  height: 1,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.16,
                  decoration: TextDecoration.underline,
                  decorationColor: _creamTextColor,
                  decorationThickness: 1.75,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
