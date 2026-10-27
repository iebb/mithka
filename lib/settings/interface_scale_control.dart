import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../components/app_interactive_surface.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// UI choices only. The controller's older API/storage range is unchanged.
abstract final class InterfaceScaleSteps {
  static const double min = .5;
  static const double max = 2.2;
  static const int divisions = 17;
  static const double reset = 1;

  static List<double> get values => [
    for (var percent = 50; percent <= 220; percent += 10) percent / 100,
  ];

  static double atFraction(double fraction) =>
      (50 + (fraction.clamp(0.0, 1.0) * divisions).round() * 10) / 100;

  // Tolerance removes only sqrt/square round-trip noise at a grid boundary.
  static double? next(double value) {
    for (final step in values) {
      if (step > value + 1e-10) return step;
    }
    return null;
  }

  static double? previous(double value) {
    for (final step in values.reversed) {
      if (step < value - 1e-10) return step;
    }
    return null;
  }

  /// Show custom preferences, not the nearest offered stop. Strip only double
  /// round-trip noise (e.g. sqrt(1.1)^2), retaining fractional percentages.
  static String percent(double value) {
    final digits = (value * 100).toStringAsFixed(8);
    return '${digits.replaceFirst(RegExp(r'\.?0+$'), '')}%';
  }

  /// Logical screen points AFTER the root's render transform, not device
  /// pixels and not 44 virtual points at a reduced interface size.
  static double targetExtent(double renderedScale) =>
      math.max(44, 44 / renderedScale);
}

/// Project-owned discrete slider. A custom in-range value has its real thumb
/// position; an out-of-range legacy value has no misleading endpoint thumb.
/// Building this widget never normalizes or writes its supplied value.
class InterfaceScaleControl extends StatefulWidget {
  const InterfaceScaleControl({
    super.key,
    required this.value,
    required this.renderedScale,
    required this.onChanged,
  });

  final double value;
  final double renderedScale;
  final ValueChanged<double> onChanged;

  @override
  State<InterfaceScaleControl> createState() => _InterfaceScaleControlState();
}

class _InterfaceScaleControlState extends State<InterfaceScaleControl> {
  bool _focused = false;
  double get value => widget.value;
  double get renderedScale => widget.renderedScale;
  ValueChanged<double> get onChanged => widget.onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final title = AppStrings.t(AppStringKeys.appearanceInterfaceSize);
    final resetLabel = AppStrings.t(AppStringKeys.resetInterfaceScale);
    final previous = InterfaceScaleSteps.previous(value);
    final next = InterfaceScaleSteps.next(value);
    final extent = InterfaceScaleSteps.targetExtent(renderedScale);
    final percent = InterfaceScaleSteps.percent(value);
    final rtl = Directionality.of(context) == TextDirection.rtl;

    Widget button(
      String key,
      String label,
      String text,
      VoidCallback? action,
    ) => AppInteractiveSurface(
      key: ValueKey(key),
      semanticLabel: label,
      enabled: action != null,
      onTap: action,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: extent, minHeight: extent),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Text(
              text,
              textAlign: TextAlign.center,
              softWrap: true,
              style: AppTextStyle.body(
                action == null ? colors.textTertiary : colors.linkBlue,
              ),
            ),
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: [
              Text(title, style: AppTextStyle.bodyLarge(colors.textPrimary)),
              Text(
                percent,
                key: const ValueKey('interface-scale-value'),
                style: AppTextStyle.body(colors.textSecondary),
              ),
            ],
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              const thumb = 22.0;
              final trackWidth = math.max(1.0, width - thumb);
              final fraction =
                  (value - InterfaceScaleSteps.min) /
                  (InterfaceScaleSteps.max - InterfaceScaleSteps.min);
              final showThumb = fraction >= -1e-10 && fraction <= 1 + 1e-10;
              final displayFraction = fraction.clamp(0.0, 1.0);
              void update(Offset position) => onChanged(
                InterfaceScaleSteps.atFraction(
                  rtl
                      ? 1 - (position.dx - thumb / 2) / trackWidth
                      : (position.dx - thumb / 2) / trackWidth,
                ),
              );
              void updateGlobal(BuildContext context, Offset globalPosition) {
                // Gesture events retain their pointer-down transform. Resolve
                // against the live render box as dragging changes root scale.
                final box = context.findRenderObject()! as RenderBox;
                update(box.globalToLocal(globalPosition));
              }

              void increase() {
                if (next != null) onChanged(next);
              }

              void decrease() {
                if (previous != null) onChanged(previous);
              }

              return CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.arrowRight): rtl
                      ? decrease
                      : increase,
                  const SingleActivator(LogicalKeyboardKey.arrowUp): increase,
                  const SingleActivator(LogicalKeyboardKey.arrowLeft): rtl
                      ? increase
                      : decrease,
                  const SingleActivator(LogicalKeyboardKey.arrowDown): decrease,
                  const SingleActivator(LogicalKeyboardKey.home): () =>
                      onChanged(InterfaceScaleSteps.min),
                  const SingleActivator(LogicalKeyboardKey.end): () =>
                      onChanged(InterfaceScaleSteps.max),
                },
                child: Focus(
                  onFocusChange: (focused) =>
                      setState(() => _focused = focused),
                  child: Builder(
                    builder: (context) => Semantics(
                      key: const ValueKey('interface-scale-slider'),
                      slider: true,
                      label: title,
                      value: percent,
                      increasedValue: next == null
                          ? null
                          : InterfaceScaleSteps.percent(next),
                      decreasedValue: previous == null
                          ? null
                          : InterfaceScaleSteps.percent(previous),
                      onIncrease: next == null ? null : increase,
                      onDecrease: previous == null ? null : decrease,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (details) {
                          Focus.of(context).requestFocus();
                          updateGlobal(context, details.globalPosition);
                        },
                        onHorizontalDragStart: (details) {
                          Focus.of(context).requestFocus();
                          updateGlobal(context, details.globalPosition);
                        },
                        onHorizontalDragUpdate: (details) =>
                            updateGlobal(context, details.globalPosition),
                        child: DecoratedBox(
                          key: const ValueKey('interface-scale-focus-ring'),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                              AppRadius.control,
                            ),
                            border: _focused
                                ? Border.all(color: colors.linkBlue, width: 2)
                                : null,
                          ),
                          child: SizedBox(
                            height: extent,
                            child: Stack(
                              alignment: Alignment.centerLeft,
                              children: [
                                Positioned(
                                  left: thumb / 2,
                                  right: thumb / 2,
                                  child: Container(
                                    height: 4,
                                    color: colors.divider,
                                  ),
                                ),
                                for (
                                  var index = 0;
                                  index <= InterfaceScaleSteps.divisions;
                                  index++
                                )
                                  Positioned(
                                    left:
                                        thumb / 2 +
                                        trackWidth *
                                            index /
                                            InterfaceScaleSteps.divisions -
                                        1,
                                    child: Container(
                                      width: 2,
                                      height: 8,
                                      color: colors.textTertiary,
                                    ),
                                  ),
                                if (showThumb)
                                  Positioned(
                                    left:
                                        (rtl
                                            ? 1 - displayFraction
                                            : displayFraction) *
                                        trackWidth,
                                    child: Container(
                                      key: const ValueKey(
                                        'interface-scale-thumb',
                                      ),
                                      width: thumb,
                                      height: thumb,
                                      decoration: BoxDecoration(
                                        color: colors.card,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: colors.linkBlue,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              button(
                'interface-scale-decrease',
                previous == null
                    ? '$title: −'
                    : '$title: ${InterfaceScaleSteps.percent(previous)}',
                '−',
                previous == null ? null : () => onChanged(previous),
              ),
              button(
                'interface-scale-reset',
                resetLabel,
                resetLabel,
                () => onChanged(InterfaceScaleSteps.reset),
              ),
              button(
                'interface-scale-increase',
                next == null
                    ? '$title: +'
                    : '$title: ${InterfaceScaleSteps.percent(next)}',
                '+',
                next == null ? null : () => onChanged(next),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                Text('50%', style: AppTextStyle.footnote(colors.textSecondary)),
                Text(
                  '220%',
                  style: AppTextStyle.footnote(colors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
