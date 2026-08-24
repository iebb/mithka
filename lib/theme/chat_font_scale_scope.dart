import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'theme_controller.dart';

/// Applies the user's chat font size (设置 › 外观 › 字体大小) to [child] only.
///
/// The font preference used to ride the root MediaQuery, which scaled every
/// label in the app while RichText-based message bubbles stayed put. Scoping
/// the factor to chat surfaces makes the setting do what it says: message
/// text, captions, and the composer scale; navigation, lists, and settings
/// keep their size. The factor composes with the ambient (system) scaler so
/// accessibility settings still apply inside chats.
class ChatFontScaleScope extends StatelessWidget {
  const ChatFontScaleScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final fontScale = context.watch<ThemeController>().fontScale;
    final media = MediaQuery.of(context);
    final composed = fontScale * media.textScaler.scale(1.0);
    return MediaQuery(
      data: media.copyWith(textScaler: TextScaler.linear(composed)),
      child: child,
    );
  }
}
