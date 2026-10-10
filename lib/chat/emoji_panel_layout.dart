//
//  emoji_panel_layout.dart
//
//  Pure geometry for the composer's emoji panel grid: how many columns fit a
//  given width, so phones stay dense (8 columns) while popovers and tablets add
//  columns instead of stretching cells absurdly. Kept free of Flutter widgets
//  so the rule is testable without a harness.
//

/// Preferred cell extent for a standard emoji cell. iOS aims for roughly 44pt
/// cells; mithka's 360dp phone panel lands on 8 columns at that target.
const double emojiPanelTargetCellWidth = 44.0;

/// Never fewer columns than a comfortable phone row, never more than a wide
/// surface can hold before the tap targets shrink below iOS's guidance.
const int emojiPanelMinColumns = 6;
const int emojiPanelMaxColumns = 12;

/// Columns for a grid that spans [availableWidth] logical pixels.
int emojiPanelColumnCount(
  double availableWidth, {
  double targetCellWidth = emojiPanelTargetCellWidth,
}) {
  if (!availableWidth.isFinite || availableWidth <= 0) {
    return emojiPanelMinColumns;
  }
  final natural = (availableWidth / targetCellWidth).floor();
  return natural.clamp(emojiPanelMinColumns, emojiPanelMaxColumns);
}
