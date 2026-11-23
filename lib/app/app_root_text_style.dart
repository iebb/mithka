//
//  app_root_text_style.dart
//
//  The text style a window's navigator sits under. Mithka's screens bring no
//  text style of their own, and neither MaterialApp nor MaterialPageRoute
//  supplies one: without this, a Text that sets only its size and colour falls
//  through to Flutter's "unstyled" marker and draws at weight 900 with a yellow
//  double underline.
//

import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';

class AppRootTextStyle extends StatelessWidget {
  const AppRootTextStyle({super.key, required this.theme, required this.child});

  /// The window's own controller: its font choice and the system bold-text
  /// setting shape the default exactly as they shape the text theme.
  final ThemeController theme;
  final Widget? child;

  @override
  Widget build(BuildContext context) => DefaultTextStyle(
    // 15 px, weight 400, primary ink, no decoration.
    style: theme.applyAppTextStyle(
      AppTextStyle.body(context.colors.textPrimary),
      boldText: MediaQuery.boldTextOf(context),
    ),
    child: child ?? const SizedBox.shrink(),
  );
}
