//
//  emoji_panel_layout.dart
//
//  Pure geometry for the composer's emoji panel grid: how many columns fit a
//  given width, so phones stay dense (8 columns) while popovers and tablets add
//  columns instead of stretching cells absurdly. Kept free of Flutter widgets
//  so the rule is testable without a harness.
//

/// Fixed extent of a standard emoji cell, used for both axes: the grid rows are
/// laid out at exactly this height and the column count is chosen so a cell is
/// never much narrower. A 360dp phone panel lands on 8 columns, and the cell's
/// glyph box is already 44dp (34dp glyph + 5dp padding each side), so this is
/// the natural cell size rather than an arbitrary target.
const double emojiPanelCellExtent = 44.0;

/// Never fewer columns than a comfortable phone row. There is no upper bound:
/// columns are the width divided by [emojiPanelCellExtent], so every cell stays
/// at least that wide however wide the surface gets — a ceiling would only
/// reintroduce the stretched, sparse rows this rule exists to prevent.
const int emojiPanelMinColumns = 6;

/// Columns for a grid that spans [availableWidth] logical pixels.
int emojiPanelColumnCount(
  double availableWidth, {
  double cellExtent = emojiPanelCellExtent,
}) {
  if (!availableWidth.isFinite || availableWidth <= 0) {
    return emojiPanelMinColumns;
  }
  final natural = (availableWidth / cellExtent).floor();
  return natural < emojiPanelMinColumns ? emojiPanelMinColumns : natural;
}
