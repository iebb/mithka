import 'package:flutter/widgets.dart';

import '../platform/adaptive_platform.dart';

/// Width of the readable content lane on native desktop targets.
const double kDesktopContentMaxWidth = 720;

/// The inset that centres a [maxWidth] lane inside [availableWidth], or zero
/// where no lane applies (touch targets, or a pane already no wider than the
/// lane).
///
/// Prefer this over wrapping a scroll view in [DesktopContentConstraint]: the
/// wrapper narrows the scroll view itself, which drags its scrollbar in off
/// the pane edge to float beside the content. Folding the inset into the
/// scroll view's own padding lanes the content identically while leaving the
/// scrollbar where a scrollbar belongs.
double desktopContentLaneInset(
  double availableWidth, {
  double maxWidth = kDesktopContentMaxWidth,
}) {
  if (!isDesktopTargetPlatform()) return 0;
  if (!availableWidth.isFinite || availableWidth <= maxWidth) return 0;
  return (availableWidth - maxWidth) / 2;
}

/// Centers a readable content lane on native desktop targets.
///
/// On phones, tablets, and web this is an exact pass-through, so existing
/// touch layouts keep their current dimensions and navigation behavior.
class DesktopContentConstraint extends StatelessWidget {
  const DesktopContentConstraint({
    super.key,
    required this.child,
    this.maxWidth = kDesktopContentMaxWidth,
  }) : assert(maxWidth > 0);

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    if (!isDesktopTargetPlatform()) return child;

    return LayoutBuilder(
      builder: (context, constraints) {
        final inset = desktopContentLaneInset(
          constraints.hasBoundedWidth ? constraints.maxWidth : double.infinity,
          maxWidth: maxWidth,
        );
        if (inset == 0) return child;
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: inset),
          child: child,
        );
      },
    );
  }
}
