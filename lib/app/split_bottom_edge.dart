import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'top_corner_cluster.dart';

/// Space a split-shell detail pane leaves under its bottom controls, or null
/// where the pane keeps the window's full bottom safe area.
///
/// Beside a corner status cluster (an opened iPhone Duo) the shell's tab bar
/// sits in the list column without the phone's home-bar gap. A row of 44pt
/// controls at the bottom of the detail pane then ends level with the tab
/// labels' bottom, so both columns end on one line. The labels' margin is
/// always above the home indicator's top, which keeps the indicator clear.
/// Regular iPhones, a closed Duo and iPads keep their safe area: none of them
/// has a [TopClusterPane] band.
double? splitPaneBottomEdgeOf(BuildContext context) {
  if (!TopClusterInsets.bandActiveOf(context)) return null;
  return splitTabBarLabelMargin(MediaQuery.textScalerOf(context));
}

/// Distance from the bottom of the shell's classic tab bar to its labels'
/// bottom when the bar keeps no inset: the icon block and label line are
/// centred in the bar, which grows with the label line.
double splitTabBarLabelMargin(TextScaler textScaler) {
  const labelSize = 11.0;
  const labelLineHeight = 1.3;
  final label = TextPainter(
    text: const TextSpan(
      text: 'Hg',
      style: TextStyle(fontSize: labelSize, fontWeight: FontWeight.w600),
    ),
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
    maxLines: 1,
  )..layout();
  final growth = math.max(
    0.0,
    (textScaler.scale(labelSize) - labelSize) * labelLineHeight,
  );
  final content = 28 + 2 + label.height;
  final margin = (62 + growth - content) / 2;
  label.dispose();
  return math.max(0.0, margin);
}
