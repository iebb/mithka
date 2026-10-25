import 'dart:async';

import 'package:flutter/material.dart' show Scrollbar;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import '../theme/content_size.dart';
import '../theme/theme_controller.dart';
import 'content_size_preview.dart';

/// The preset names, in the same order as [contentSizePresets].
const _labelKeys = [
  AppStringKeys.contentSizeSmall,
  AppStringKeys.contentSizeStandard,
  AppStringKeys.contentSizeLarge,
  AppStringKeys.contentSizeExtraLarge,
  AppStringKeys.contentSizeVeryLarge,
  AppStringKeys.contentSizeLargest,
];

/// Preserve non-preset preferences until the user deliberately selects a stop.
int contentSizePresetIndex(double scale) => contentSizePresets.indexOf(scale);
double? adjacentContentSize(double scale, {required bool increase}) {
  final candidates = increase
      ? contentSizePresets
      : contentSizePresets.reversed;
  for (final value in candidates) {
    if (increase ? value > scale : value < scale) {
      return value;
    }
  }
  return null;
}

String contentSizePercent(double scale) =>
    (scale * 100).toStringAsFixed(6).replaceFirst(RegExp(r'\.?0+$'), '');
String contentSizeLabel(double scale) {
  final index = contentSizePresetIndex(scale);
  return AppStrings.t(
    index < 0 ? AppStringKeys.contentSizeCustom : _labelKeys[index],
  );
}

String contentSizeValue(double scale) => AppStrings.t(
  AppStringKeys.contentSizeValue,
  {'value1': contentSizeLabel(scale), 'value2': contentSizePercent(scale)},
);
String contentSizeSemanticValue(double scale) {
  final index = contentSizePresetIndex(scale);
  return AppStrings.t(
    index < 0
        ? AppStringKeys.contentSizeCustomSemantic
        : AppStringKeys.contentSizePresetSemantic,
    {
      'value1': contentSizeLabel(scale),
      'value2': contentSizePercent(scale),
      if (index >= 0) 'value3': index + 1,
    },
  );
}

/// Where [scale] sits along the six stops, 0 at Small and 1 at Largest.
/// Custom saved values sit between their neighbouring stops instead of being
/// snapped, and values beyond either end rest on that end.
double contentSizeStopFraction(double scale) {
  const presets = contentSizePresets;
  if (scale <= presets.first) return 0;
  if (scale >= presets.last) return 1;
  for (var i = 0; i < presets.length - 1; i++) {
    final low = presets[i];
    final high = presets[i + 1];
    if (scale <= high) {
      return (i + (scale - low) / (high - low)) / (presets.length - 1);
    }
  }
  return 1;
}

class ContentSizeSettingsView extends StatefulWidget {
  const ContentSizeSettingsView({super.key});
  @override
  State<ContentSizeSettingsView> createState() =>
      _ContentSizeSettingsViewState();
}

class _ContentSizeSettingsViewState extends State<ContentSizeSettingsView> {
  final _pages = PageController();
  final _pageScrolls = [ScrollController(), ScrollController()];
  final _panelScroll = ScrollController();
  final _now = DateTime.now();
  int _page = 0;
  int _selectionRevision = 0;
  @override
  void initState() {
    super.initState();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  void dispose() {
    _pages.dispose();
    for (final controller in _pageScrolls) {
      controller.dispose();
    }
    _panelScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    final colors = context.colors;
    final pageNames = [
      AppStrings.t(AppStringKeys.contentSizeConversation),
      AppStrings.t(AppStringKeys.contentSizeChatList),
    ];
    final pageBackgrounds = [colors.chatBackground, colors.background];
    return SettingsPageScaffold(
      title: AppStrings.t(AppStringKeys.contentSizeTitle),
      onBack: () => Navigator.of(context).pop(),
      // The preview is full-bleed at every width; the panel lanes itself.
      constrainContent: false,
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            Expanded(
              child: PageView(
                key: const ValueKey('content-size-preview-pages'),
                controller: _pages,
                // Reported at the halfway point of a swipe, so the dots follow
                // the finger rather than waiting for the page to settle.
                onPageChanged: (page) => setState(() => _page = page),
                children: [
                  for (var i = 0; i < pageNames.length; i++)
                    Semantics(
                      container: true,
                      label: pageNames[i],
                      child: ColoredBox(
                        key: ValueKey('content-size-preview-page-$i'),
                        color: pageBackgrounds[i],
                        child: Scrollbar(
                          controller: _pageScrolls[i],
                          child: SingleChildScrollView(
                            // Keeps each page's scroll position across swipes.
                            key: PageStorageKey('content-size-page-scroll-$i'),
                            controller: _pageScrolls[i],
                            child: ContentSizePreview(
                              appScale: theme.fontScale,
                              chatList: i == 1,
                              now: _now,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // The controls never take more than half the body: at very large
            // OS text sizes the panel scrolls and the preview keeps its half.
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: constraints.maxHeight / 2),
              child: _panel(context, theme.fontScale, pageNames),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panel(BuildContext context, double scale, List<String> pageNames) {
    final colors = context.colors;
    return DecoratedBox(
      key: const ValueKey('content-size-panel'),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border(top: BorderSide(color: colors.divider, width: 0.5)),
      ),
      child: Scrollbar(
        controller: _panelScroll,
        child: SingleChildScrollView(
          controller: _panelScroll,
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            16 + MediaQuery.paddingOf(context).bottom,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ContentSizePageDots(
                    names: pageNames,
                    page: _page,
                    onSelect: _showPage,
                  ),
                  const SizedBox(height: 4),
                  ContentSizeValueLabel(scale: scale),
                  const SizedBox(height: 12),
                  ContentSizeSlider(value: scale, onChanged: _selectSize),
                  const SizedBox(height: 12),
                  Text(
                    AppStrings.t(AppStringKeys.contentSizeExplanation),
                    key: const ValueKey('content-size-explanation'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: colors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showPage(int page) {
    if (!_pages.hasClients || page == _page) {
      return;
    }
    if (AppMotion.isReduced(context)) {
      _pages.jumpToPage(page);
    } else {
      _pages.animateToPage(
        page,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _selectSize(double value) async {
    final revision = ++_selectionRevision;
    final theme = context.read<ThemeController>();
    try {
      await theme.setFontScale(value);
    } catch (_) {
      // A late failure for an older choice must not overwrite the user's
      // latest feedback. The controller intentionally retains the live choice.
      if (!mounted ||
          revision != _selectionRevision ||
          theme.fontScale != value) {
        return;
      }
      showToast(context, AppStrings.t(AppStringKeys.contentSizeSaveFailed));
    }
  }
}

/// The current size's name with its percentage beside it, e.g.
/// "Standard  100%". Wraps between words at accessibility text sizes.
class ContentSizeValueLabel extends StatelessWidget {
  const ContentSizeValueLabel({super.key, required this.scale});
  final double scale;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: contentSizeLabel(scale),
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const WidgetSpan(child: SizedBox(width: 6)),
          TextSpan(
            text: AppStrings.t(AppStringKeys.contentSizePercent, {
              'value1': contentSizePercent(scale),
            }),
            style: TextStyle(
              fontSize: 15,
              color: colors.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
      key: const ValueKey('content-size-value'),
      textAlign: TextAlign.center,
    );
  }
}

/// iOS page-control dots for the preview carousel. Swiping the previews is the
/// primary interaction; tapping either half of the row shows that side's page,
/// and assistive technologies get one adjustable element named "Preview".
class ContentSizePageDots extends StatelessWidget {
  const ContentSizePageDots({
    super.key,
    required this.names,
    required this.page,
    required this.onSelect,
  });
  final List<String> names;
  final int page;
  final ValueChanged<int> onSelect;

  static const double _dot = 7;
  static const double _pitch = 16;

  String _value(int index) => AppStrings.t(AppStringKeys.contentSizePageValue, {
    'value1': names[index],
    'value2': index + 1,
    'value3': names.length,
  });

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final count = names.length;
    final colors = context.colors;
    return Semantics(
      container: true,
      label: AppStrings.t(AppStringKeys.contentSizePreview),
      value: _value(page),
      increasedValue: page < count - 1 ? _value(page + 1) : null,
      decreasedValue: page > 0 ? _value(page - 1) : null,
      onIncrease: page < count - 1 ? () => onSelect(page + 1) : null,
      onDecrease: page > 0 ? () => onSelect(page - 1) : null,
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) => GestureDetector(
            key: const ValueKey('content-size-page-dots'),
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) {
              final leftHalf =
                  details.localPosition.dx < constraints.maxWidth / 2;
              // The carousel mirrors in right-to-left layouts, so the first
              // page sits on the right there.
              onSelect(leftHalf != rtl ? 0 : count - 1);
            },
            child: SizedBox(
              height: 32,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < count; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: (_pitch - _dot) / 2,
                      ),
                      child: AnimatedContainer(
                        key: ValueKey('content-size-page-dot-$i'),
                        duration: AppMotion.duration(context, AppMotion.quick),
                        width: _dot,
                        height: _dot,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i == page
                              ? colors.textPrimary
                              : colors.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// An iOS-style stepped slider: small "A", a track with six tick marks and a
/// round thumb, large "A". Tapping either "A" moves one step; tapping the track
/// picks the nearest stop; dragging snaps from stop to stop.
class ContentSizeSlider extends StatefulWidget {
  const ContentSizeSlider({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final double value;
  final ValueChanged<double> onChanged;

  @override
  State<ContentSizeSlider> createState() => _ContentSizeSliderState();
}

class _ContentSizeSliderState extends State<ContentSizeSlider> {
  static const double _target = 44;
  static const double _inset = 14;
  static const double _thumb = 28;
  static const int _lastStop = 5;

  int? _lastDragIndex;

  /// Saves [index]'s preset. A tap always saves, so a deliberate tap retries a
  /// previously failed save of the same value; drags save only crossed stops.
  void _choose(int index, {bool dragging = false}) {
    // While dragging, the last crossed stop is the current one even before
    // the slider rebuilds with the new value.
    final current = dragging
        ? _lastDragIndex
        : contentSizePresetIndex(widget.value);
    if (dragging) {
      if (_lastDragIndex == index) {
        return;
      }
      _lastDragIndex = index;
    }
    if (current != index) {
      unawaited(HapticFeedback.selectionClick());
    }
    widget.onChanged(contentSizePresets[index]);
  }

  void _step(double? target) {
    if (target == null) return;
    _choose(contentSizePresets.indexOf(target));
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    final onChanged = widget.onChanged;
    final next = adjacentContentSize(value, increase: true);
    final previous = adjacentContentSize(value, increase: false);
    return Semantics(
      container: true,
      label: AppStrings.t(AppStringKeys.contentSizeTitle),
      value: contentSizeSemanticValue(value),
      increasedValue: next == null ? null : contentSizeSemanticValue(next),
      decreasedValue: previous == null
          ? null
          : contentSizeSemanticValue(previous),
      onIncrease: next == null ? null : () => onChanged(next),
      onDecrease: previous == null ? null : () => onChanged(previous),
      child: ExcludeSemantics(
        child: SizedBox(
          height: _target,
          child: Row(
            children: [
              _glyph(
                context,
                key: const ValueKey('content-size-step-down'),
                size: 15,
                onTap: () => _step(previous),
              ),
              Expanded(child: _lane(context, value)),
              _glyph(
                context,
                key: const ValueKey('content-size-step-up'),
                size: 25,
                onTap: () => _step(next),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A fixed-size "A": the control's ends must not grow with the setting
  /// they adjust, nor with the OS text size.
  Widget _glyph(
    BuildContext context, {
    required Key key,
    required double size,
    required VoidCallback onTap,
  }) => GestureDetector(
    key: key,
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: SizedBox.square(
      dimension: _target,
      child: Center(
        child: Text(
          'A',
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontSize: size,
            height: 1,
            color: context.colors.textSecondary,
          ),
        ),
      ),
    ),
  );

  Widget _lane(BuildContext context, double value) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final colors = context.colors;
    final reduced = AppMotion.isReduced(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final span = (width - _inset * 2).clamp(0.0, double.infinity);
        double x(double fraction) =>
            _inset + span * (rtl ? 1 - fraction : fraction);
        int nearest(Offset local) {
          final raw = span == 0 ? 0.0 : (local.dx - _inset) / span;
          final fraction = raw.clamp(0.0, 1.0);
          return ((rtl ? 1 - fraction : fraction) * _lastStop).round();
        }

        return GestureDetector(
          key: const ValueKey('content-size-slider-lane'),
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) => _choose(nearest(details.localPosition)),
          onHorizontalDragStart: (details) {
            _lastDragIndex = contentSizePresetIndex(widget.value);
            _choose(nearest(details.localPosition), dragging: true);
          },
          onHorizontalDragUpdate: (details) =>
              _choose(nearest(details.localPosition), dragging: true),
          onHorizontalDragEnd: (_) => _lastDragIndex = null,
          onHorizontalDragCancel: () => _lastDragIndex = null,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: contentSizeStopFraction(value)),
            duration: reduced
                ? Duration.zero
                : const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            builder: (context, fraction, _) {
              final thumbX = x(fraction);
              final start = x(0);
              final filledLeft = rtl ? thumbX : start;
              final filledRight = rtl ? start : thumbX;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: _inset,
                    width: span,
                    top: (_target - 4) / 2,
                    height: 4,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.textTertiary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Positioned(
                    key: const ValueKey('content-size-track-fill'),
                    left: filledLeft,
                    width: filledRight - filledLeft,
                    top: (_target - 4) / 2,
                    height: 4,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppTheme.brand,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  for (var i = 0; i <= _lastStop; i++)
                    Positioned(
                      left: x(i / _lastStop) - 1,
                      top: (_target - 10) / 2,
                      width: 2,
                      height: 10,
                      child: DecoratedBox(
                        key: ValueKey('content-size-stop-$i'),
                        decoration: BoxDecoration(
                          color: i / _lastStop <= fraction + 1e-6
                              ? AppTheme.brand
                              : colors.textTertiary,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                  Positioned(
                    left: thumbX - _thumb / 2,
                    top: (_target - _thumb) / 2,
                    width: _thumb,
                    height: _thumb,
                    child: DecoratedBox(
                      key: const ValueKey('content-size-thumb'),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFFFFFFF),
                        border: Border.all(
                          color: const Color(0x14000000),
                          width: 0.5,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x2E000000),
                            offset: Offset(0, 2),
                            blurRadius: 6,
                          ),
                          BoxShadow(color: Color(0x1F000000), blurRadius: 1),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
