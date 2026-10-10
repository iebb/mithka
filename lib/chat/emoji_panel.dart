//
//  emoji_panel.dart
//
//  The standard-emoji pane of the composer's emoji panel, modelled on Telegram
//  iOS: a "Recently used" section first, the catalog categories below it in an
//  adaptive grid, and a bottom strip of category icons that follows the scroll
//  position — scroll the grid and the highlighted category updates, tap a
//  category and the grid jumps to it. Long-pressing a cell raises an iOS-style
//  enlarged preview bubble and suppresses the insert.
//
//  The surrounding chrome (pack tab strip, search field, desktop popovers)
//  stays in chat_input_bar.dart; this file owns only the pane and its cells so
//  the composer's public behavior is unchanged.
//

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../components/app_icons.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import 'custom_emoji.dart';
import 'emoji_catalog.dart';
import 'emoji_panel_layout.dart';
import 'emoji_recents_store.dart';
import 'sticker_item.dart';

/// Vertical spacing each section header reserves, kept in one place so the
/// strip's tap-to-scroll target lines up with what the grid actually lays out.
const double _emojiSectionHeaderExtent = 30.0;

/// The standard pane: recents + category sections + a scroll-following strip.
class StandardEmojiPane extends StatefulWidget {
  const StandardEmojiPane({
    super.key,
    required this.insertText,
    required this.insertCustomEmoji,
  });

  /// Inserts a standard Unicode emoji into the composer.
  final ValueChanged<String> insertText;

  /// Inserts a Premium custom emoji (recents can contain them).
  final void Function(int customEmojiId, String fallback) insertCustomEmoji;

  @override
  State<StandardEmojiPane> createState() => StandardEmojiPaneState();
}

@visibleForTesting
class StandardEmojiPaneState extends State<StandardEmojiPane> {
  static const List<AppIconData> categoryIcons = [
    // Outline smiley (the composer toggle owns solidFaceSmile; reusing it would
    // make icon lookups ambiguous while the panel is open).
    HeroAppIcons.faceSmile,
    HeroAppIcons.user,
    HeroAppIcons.bug,
    HeroAppIcons.cake,
    HeroAppIcons.trophy,
    HeroAppIcons.locationPin,
    HeroAppIcons.lightbulb,
    HeroAppIcons.hashtag,
  ];

  final _controller = ScrollController();
  final _highlight = ValueNotifier<int>(0);

  List<double> _sectionOffsets = const [];

  bool get _hasRecents => EmojiRecentsStore.shared.renderableEntries.isNotEmpty;

  /// Analytic scroll offset of every section header, so a tap can jump to a
  /// section whose header is far off-screen and has no built box to measure.
  /// Headers have a fixed extent and grid cells are square, so this is exact —
  /// only the header label wraps, and it renders inside that fixed extent.
  void _computeSectionOffsets(double paneWidth, int columns) {
    final gridWidth = math.max(0, paneWidth - 20); // 10dp horizontal padding
    final cell = gridWidth / math.max(1, columns);
    final counts = <int>[
      if (_hasRecents) EmojiRecentsStore.shared.renderableEntries.length,
      for (final category in EmojiCatalog.categories) category.emojis.length,
    ];
    var offset = 8.0; // top spacer
    final offsets = <double>[];
    for (final count in counts) {
      offsets.add(offset);
      offset +=
          _emojiSectionHeaderExtent + (count / columns).ceilToDouble() * cell;
    }
    _sectionOffsets = offsets;
  }

  @override
  void initState() {
    super.initState();
    EmojiRecentsStore.shared.addListener(_onRecents);
    EmojiRecentsStore.shared.loadIfNeeded();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    EmojiRecentsStore.shared.removeListener(_onRecents);
    _controller
      ..removeListener(_onScroll)
      ..dispose();
    _highlight.dispose();
    super.dispose();
  }

  void _onRecents() {
    if (!mounted) return;
    setState(() {});
  }

  void _clampHighlight(int count) {
    if (count == 0) return;
    final clamped = _highlight.value.clamp(0, count - 1);
    if (_highlight.value != clamped) _highlight.value = clamped;
  }

  void _onScroll() {
    if (!mounted || _sectionOffsets.isEmpty) return;
    final pixels = _controller.hasClients ? _controller.position.pixels : 0.0;
    // The last header whose offset has scrolled to (or past) the top of the
    // viewport is the active section; a hair of slack keeps a header that is
    // still sliding in from winning one frame early.
    const slack = 2.0;
    var best = 0;
    for (var i = 0; i < _sectionOffsets.length; i++) {
      if (pixels + slack >= _sectionOffsets[i]) best = i;
    }
    if (_highlight.value != best) _highlight.value = best;
  }

  void _onStripTap(int section) {
    final position = _controller.hasClients ? _controller.position : null;
    if (position == null || section >= _sectionOffsets.length) return;
    _highlight.value = section;
    final target = _sectionOffsets[section].clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < 0.5) return;
    _controller.animateTo(
      target,
      duration: AppMotion.duration(context, AppMotion.routeReverse),
      curve: AppMotion.standard,
    );
  }

  void _insert(String emoji) {
    EmojiRecentsStore.shared.record(emoji);
    widget.insertText(emoji);
  }

  void _insertCustom(int customEmojiId, String fallback) {
    EmojiRecentsStore.shared.recordCustom(customEmojiId, fallback);
    widget.insertCustomEmoji(customEmojiId, fallback);
  }

  @override
  Widget build(BuildContext context) {
    final hasRecents = _hasRecents;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = emojiPanelColumnCount(constraints.maxWidth);
        _computeSectionOffsets(constraints.maxWidth, columns);
        _clampHighlight(_sectionOffsets.length);
        return Column(
          children: [
            Expanded(
              child: CustomScrollView(
                key: const ValueKey('emojiStandardGrid'),
                controller: _controller,
                slivers: [
                  const SliverToBoxAdapter(child: SizedBox(height: 8)),
                  if (hasRecents) ...[
                    _sectionHeader(
                      AppStringKeys.emojiRecentsSection.l10n(context),
                      section: 0,
                    ),
                    _recentsGrid(columns),
                  ],
                  for (var i = 0; i < EmojiCatalog.categories.length; i++) ...[
                    _sectionHeader(
                      EmojiCatalog.categories[i].name.l10n(context),
                      section: i + (hasRecents ? 1 : 0),
                    ),
                    _categoryGrid(EmojiCatalog.categories[i], columns),
                  ],
                  const SliverToBoxAdapter(child: SizedBox(height: 8)),
                ],
              ),
            ),
            _EmojiCategoryStrip(
              highlight: _highlight,
              hasRecents: hasRecents,
              recentLabel: AppStringKeys.emojiRecentsSection.l10n(context),
              categoryLabels: [
                for (final category in EmojiCatalog.categories)
                  category.name.l10n(context),
              ],
              categoryIcons: categoryIcons,
              onTap: _onStripTap,
            ),
          ],
        );
      },
    );
  }

  Widget _sectionHeader(String label, {required int section}) {
    return SliverToBoxAdapter(
      child: SizedBox(
        key: ValueKey('emojiSectionHeader-$section'),
        height: _emojiSectionHeaderExtent,
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 14, top: 6),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.colors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _recentsGrid(int columns) {
    final entries = EmojiRecentsStore.shared.renderableEntries;
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
        ),
        delegate: SliverChildBuilderDelegate((context, index) {
          final entry = entries[index];
          return entry.isCustom
              ? EmojiPanelCell(
                  key: ValueKey('emojiRecentCustom-${entry.customEmojiId}'),
                  customItem: StickerItem(
                    id: entry.customEmojiId,
                    width: 512,
                    height: 512,
                    emoji: entry.emoji,
                    customEmojiId: entry.customEmojiId,
                  ),
                  onTap: () => _insertCustom(entry.customEmojiId, entry.emoji),
                )
              : EmojiPanelCell(
                  key: ValueKey('emojiRecent-${entry.emoji}'),
                  emoji: entry.emoji,
                  onTap: () => _insert(entry.emoji),
                );
        }, childCount: entries.length),
      ),
    );
  }

  Widget _categoryGrid(EmojiCategory category, int columns) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
        ),
        delegate: SliverChildBuilderDelegate((context, index) {
          final emoji = category.emojis[index];
          return EmojiPanelCell(emoji: emoji, onTap: () => _insert(emoji));
        }, childCount: category.emojis.length),
      ),
    );
  }
}

/// Bottom strip of category icons that follows the grid's scroll position,
/// shaped like iOS: recents (clock) first, then one icon per catalog category.
class _EmojiCategoryStrip extends StatefulWidget {
  const _EmojiCategoryStrip({
    required this.highlight,
    required this.hasRecents,
    required this.recentLabel,
    required this.categoryLabels,
    required this.categoryIcons,
    required this.onTap,
  });

  final ValueListenable<int> highlight;
  final bool hasRecents;
  final String recentLabel;
  final List<String> categoryLabels;
  final List<AppIconData> categoryIcons;
  final ValueChanged<int> onTap;

  @override
  State<_EmojiCategoryStrip> createState() => _EmojiCategoryStripState();
}

class _EmojiCategoryStripState extends State<_EmojiCategoryStrip> {
  static const double _buttonExtent = 44.0;
  final _controller = ScrollController();
  int? _lastRevealed;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Keeps the selected icon centred, the way iOS nudges its category bar while
  /// the grid moves past a boundary. Runs once per highlight change (not every
  /// build) so the strip never keeps re-scheduling frames while it is idle.
  void _reveal(int selected, double stripWidth) {
    if (_lastRevealed == selected) return;
    _lastRevealed = selected;
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final centered =
        selected * _buttonExtent - (stripWidth - _buttonExtent) / 2;
    final target = centered.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < 0.5) return;
    _controller.animateTo(
      target,
      duration: AppMotion.duration(context, AppMotion.quick),
      curve: AppMotion.standard,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      key: const ValueKey('emojiCategoryStrip'),
      decoration: BoxDecoration(
        color: c.inputBarBackground,
        border: Border(top: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: SizedBox(
        height: 46,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return ValueListenableBuilder<int>(
              valueListenable: widget.highlight,
              builder: (context, highlighted, _) {
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _reveal(highlighted, constraints.maxWidth),
                );
                return ListView(
                  controller: _controller,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  children: [
                    if (widget.hasRecents)
                      _button(
                        section: 0,
                        icon: HeroAppIcons.clock,
                        label: widget.recentLabel,
                        selected: highlighted == 0,
                        selectedColor: AppTheme.brand,
                        unselectedColor: c.textSecondary,
                      ),
                    for (var i = 0; i < widget.categoryLabels.length; i++)
                      _button(
                        section: i + (widget.hasRecents ? 1 : 0),
                        icon: widget.categoryIcons[i],
                        label: widget.categoryLabels[i],
                        selected:
                            highlighted == i + (widget.hasRecents ? 1 : 0),
                        selectedColor: AppTheme.brand,
                        unselectedColor: c.textSecondary,
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _button({
    required int section,
    required AppIconData icon,
    required String label,
    required bool selected,
    required Color selectedColor,
    required Color unselectedColor,
  }) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        key: ValueKey('emojiCategoryStrip-$section'),
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onTap(section),
        child: SizedBox(
          width: _buttonExtent,
          height: 46,
          child: Center(
            child: AppIcon(
              icon,
              size: 22,
              color: selected ? selectedColor : unselectedColor,
            ),
          ),
        ),
      ),
    );
  }
}

/// One emoji cell shared by the standard pane, pack grids, and search results.
///
/// Tap inserts with a subtle iOS-style pop (skipped under reduce-motion) and a
/// selection haptic on touch platforms; long-press raises an enlarged preview
/// bubble and suppresses the insert, matching iOS. Mouse pointers skip the
/// preview so a desktop click never raises a bubble.
class EmojiPanelCell extends StatefulWidget {
  const EmojiPanelCell({
    super.key,
    required this.onTap,
    this.emoji,
    this.customItem,
    this.size = 34,
  });

  /// Standard Unicode emoji, or the fallback glyph for [customItem].
  final String? emoji;

  /// Premium custom emoji to render instead of [emoji].
  final StickerItem? customItem;

  final VoidCallback onTap;
  final double size;

  @override
  State<EmojiPanelCell> createState() => _EmojiPanelCellState();
}

class _EmojiPanelCellState extends State<EmojiPanelCell>
    with SingleTickerProviderStateMixin {
  static const double _previewWidth = 76.0;
  static const double _previewHeight = 88.0;

  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 150),
  );
  OverlayEntry? _previewEntry;
  bool _pointerIsMouse = false;

  @override
  void dispose() {
    _removePreviewEntry();
    _pop.dispose();
    super.dispose();
  }

  bool get _isCustom =>
      widget.customItem != null && widget.customItem!.customEmojiId != 0;

  String get _previewGlyph {
    final custom = widget.customItem;
    if (_isCustom && custom!.emoji.isNotEmpty) return custom.emoji;
    return widget.emoji ?? '';
  }

  void _handleTap() {
    _fireHaptic();
    widget.onTap();
    if (AppMotion.isReduced(context)) return;
    _pop
      ..value = 1
      ..reverse();
  }

  void _fireHaptic() {
    final platform = Theme.of(context).platform;
    if (platform == TargetPlatform.android || platform == TargetPlatform.iOS) {
      unawaited(HapticFeedback.selectionClick());
    }
  }

  void _showPreview(LongPressStartDetails details) {
    if (_previewEntry != null || !mounted || _pointerIsMouse) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final screen = MediaQuery.of(context).size;
    final cellBox = context.findRenderObject() as RenderBox?;
    final cellWidth = cellBox?.size.width ?? widget.size + 10;
    final left =
        (details.globalPosition.dx -
                cellWidth / 2 +
                (cellWidth - _previewWidth) / 2)
            .clamp(8.0, math.max(8.0, screen.width - _previewWidth - 8))
            .toDouble();
    final top = details.globalPosition.dy - 12 - _previewHeight;
    _fireHaptic();
    _previewEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: left,
        top: math.max(8.0, top),
        child: _EmojiPreviewCard(
          emoji: _previewGlyph,
          customItem: _isCustom ? widget.customItem : null,
          label: AppStringKeys.emojiPanelPreview.l10n(context),
          size: widget.size,
        ),
      ),
    );
    overlay.insert(_previewEntry!);
    if (AppMotion.isReduced(context)) return;
    _pop
      ..value = 1
      ..reverse();
  }

  void _dismissPreview() {
    final entry = _previewEntry;
    _previewEntry = null;
    if (entry == null) return;
    try {
      entry.remove();
    } catch (_) {
      // The overlay can already be gone when a panel closes mid-dismiss.
    }
  }

  /// Releasing a held emoji inserts it and closes the preview, matching iOS —
  /// the long-press consumes the gesture, so `onTap` never runs for it.
  void _onLongPressEnd() {
    if (_previewEntry == null) return;
    _dismissPreview();
    _fireHaptic();
    widget.onTap();
  }

  void _removePreviewEntry() => _dismissPreview();

  @override
  Widget build(BuildContext context) {
    final glyph = _isCustom
        ? CustomEmojiView(
            id: widget.customItem!.customEmojiId,
            size: widget.size,
            color: context.colors.textPrimary,
          )
        : Text(
            widget.emoji ?? '',
            maxLines: 1,
            textScaler: TextScaler.noScaling,
            style: const TextStyle(fontSize: 26),
          );
    return Listener(
      onPointerDown: (event) =>
          _pointerIsMouse = event.kind == PointerDeviceKind.mouse,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleTap,
        onLongPressStart: _showPreview,
        onLongPressEnd: (_) => _onLongPressEnd(),
        onLongPressCancel: _dismissPreview,
        child: Center(
          child: ScaleTransition(
            scale: Tween<double>(
              begin: 1,
              end: 1.16,
            ).animate(CurvedAnimation(parent: _pop, curve: Curves.easeOut)),
            child: SizedBox.square(
              dimension: widget.size + 10,
              child: Center(child: glyph),
            ),
          ),
        ),
      ),
    );
  }
}

/// The enlarged bubble iOS raises over a held emoji.
class _EmojiPreviewCard extends StatelessWidget {
  const _EmojiPreviewCard({
    required this.emoji,
    required this.customItem,
    required this.label,
    required this.size,
  });

  final String emoji;
  final StickerItem? customItem;
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: label,
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          key: const ValueKey('emojiLongPressPreview'),
          width: _EmojiPanelCellState._previewWidth,
          height: _EmojiPanelCellState._previewHeight,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: c.divider, width: 0.7),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: customItem != null
              ? CustomEmojiView(
                  id: customItem!.customEmojiId,
                  size: size * 1.9,
                  color: c.textPrimary,
                )
              : Text(
                  emoji,
                  maxLines: 1,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(fontSize: size * 1.9),
                ),
        ),
      ),
    );
  }
}
