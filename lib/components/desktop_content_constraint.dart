import 'package:flutter/widgets.dart';

import '../platform/adaptive_platform.dart';

/// Centers a readable content lane on native desktop targets.
///
/// On phones, tablets, and web this is an exact pass-through, so existing
/// touch layouts keep their current dimensions and navigation behavior.
class DesktopContentConstraint extends StatelessWidget {
  const DesktopContentConstraint({
    super.key,
    required this.child,
    this.maxWidth = 720,
  }) : assert(maxWidth > 0);

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    if (!isDesktopTargetPlatform()) return child;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth || constraints.maxWidth <= maxWidth) {
          return child;
        }
        final horizontalInset = (constraints.maxWidth - maxWidth) / 2;
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalInset),
          child: child,
        );
      },
    );
  }
}
