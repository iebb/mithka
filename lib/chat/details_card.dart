//
//  details_card.dart
//
//  The shared pieces of the read-only detail sheets (gift, Gram transfer):
//  the grouped label / value card, rows on `card` with inset dividers, each
//  a 96pt label column beside its right-aligned value, or the label above
//  the value at large text or when the value needs more than one line; and
//  the pin that holds a sheet's close button still while its content
//  scrolls.
//

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../components/photo_avatar.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';

/// The card around [rows], with a divider between each two. Callers leave a
/// row out when its data is missing and the card out when no row is left.
class DetailsCard extends StatelessWidget {
  const DetailsCard({super.key, required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < rows.length; index++) ...[
            if (index > 0)
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.xxl),
                child: Divider(height: 1, color: c.divider),
              ),
            rows[index],
          ],
        ],
      ),
    );
  }
}

/// One label / value row. The value sits at the row's end beside a 96pt
/// label column while it fits on one line there. When it needs more lines
/// (a long note, a name that would wrap), when the label would not fit in
/// its column, or when text is scaled to 130 % or more, the label moves
/// above the value, which then starts at the row's start and has the full
/// width.
///
/// With [onTap] the whole row is one button; [trailing] then usually shows
/// what the tap does, at the row's end.
class DetailsRow extends StatelessWidget {
  const DetailsRow({
    super.key,
    required this.label,
    required this.value,
    required this.semanticValue,
    this.trailing,
    this.onTap,
  });

  final String label;

  /// Laid out at its natural width, so any text in it should start-align:
  /// on one line the row places it at the end itself.
  final Widget value;
  final String semanticValue;
  final Widget? trailing;
  final VoidCallback? onTap;

  static const double avatarSize = 22;
  static const double _labelWidth = 96;
  static const double _labelGap = 10;
  static const double _verticalPadding = 13;
  static const double _stackedTextScale = 1.3;

  /// A plain text value.
  static Widget textValue(String text, {TextStyle? style}) => Builder(
    builder: (context) => Text(
      text,
      style: style ?? AppTextStyle.body(context.colors.textPrimary),
    ),
  );

  /// A person or chat: their avatar, then [name]. [avatarTitle] picks the
  /// avatar's initials and colour when it differs from [name].
  static Widget partyValue(
    String name,
    TdFileRef? photo, {
    String? avatarTitle,
  }) => Builder(
    builder: (context) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IgnoreBaseline(
          child: PhotoAvatar(
            title: avatarTitle ?? name,
            photo: photo,
            size: avatarSize,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Flexible(
          child: Text(
            name,
            style: AppTextStyle.body(context.colors.textPrimary),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final scaler = MediaQuery.textScalerOf(context);
    final labelStyle = AppTextStyle.body(c.textSecondary);
    final painter = TextPainter(
      text: TextSpan(text: label, style: labelStyle),
      textDirection: Directionality.of(context),
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final alwaysStacked =
        painter.width > _labelWidth || scaler.scale(1) >= _stackedTextScale;
    painter.dispose();
    final padded = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxl,
        vertical: _verticalPadding,
      ),
      child: _DetailsRowLayout(
        alwaysStacked: alwaysStacked,
        textDirection: Directionality.of(context),
        inlineLabel: Text(label, style: labelStyle),
        stackedLabel: Text(
          label,
          style: AppTextStyle.footnote(c.textSecondary),
        ),
        value: value,
        trailing: trailing,
      ),
    );
    final onTap = this.onTap;
    return Semantics(
      container: true,
      button: onTap != null ? true : null,
      label: '$label, $semanticValue',
      onTap: onTap,
      excludeSemantics: true,
      child: onTap == null
          ? padded
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: padded,
            ),
    );
  }
}

enum _DetailsRowSlot { inlineLabel, stackedLabel, value, trailing }

/// Lays a row out beside its label when the value fits on one line there,
/// and stacked otherwise. Both label styles are children; only the one the
/// layout uses is painted.
class _DetailsRowLayout
    extends SlottedMultiChildRenderObjectWidget<_DetailsRowSlot, RenderBox> {
  const _DetailsRowLayout({
    required this.alwaysStacked,
    required this.textDirection,
    required this.inlineLabel,
    required this.stackedLabel,
    required this.value,
    this.trailing,
  });

  final bool alwaysStacked;
  final TextDirection textDirection;
  final Widget inlineLabel;
  final Widget stackedLabel;
  final Widget value;
  final Widget? trailing;

  @override
  Iterable<_DetailsRowSlot> get slots => _DetailsRowSlot.values;

  @override
  Widget? childForSlot(_DetailsRowSlot slot) => switch (slot) {
    _DetailsRowSlot.inlineLabel => inlineLabel,
    _DetailsRowSlot.stackedLabel => stackedLabel,
    _DetailsRowSlot.value => value,
    _DetailsRowSlot.trailing => trailing,
  };

  @override
  _RenderDetailsRow createRenderObject(BuildContext context) =>
      _RenderDetailsRow(
        alwaysStacked: alwaysStacked,
        textDirection: textDirection,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderDetailsRow renderObject,
  ) {
    renderObject
      ..alwaysStacked = alwaysStacked
      ..textDirection = textDirection;
  }
}

/// Where a layout pass put each child, in start-to-end coordinates.
class _DetailsRowArrangement {
  const _DetailsRowArrangement({
    required this.size,
    required this.stacked,
    required this.label,
    required this.value,
    required this.trailing,
  });

  final Size size;
  final bool stacked;
  final Offset label;
  final Offset value;
  final Offset trailing;
}

class _RenderDetailsRow extends RenderBox
    with SlottedContainerRenderObjectMixin<_DetailsRowSlot, RenderBox> {
  _RenderDetailsRow({
    required this._alwaysStacked,
    required this._textDirection,
  });

  bool get alwaysStacked => _alwaysStacked;
  bool _alwaysStacked;
  set alwaysStacked(bool value) {
    if (_alwaysStacked == value) return;
    _alwaysStacked = value;
    markNeedsLayout();
  }

  TextDirection get textDirection => _textDirection;
  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    markNeedsLayout();
  }

  /// Whether the last layout stacked the label above the value.
  bool _stacked = false;

  RenderBox get _inlineLabel => childForSlot(_DetailsRowSlot.inlineLabel)!;
  RenderBox get _stackedLabel => childForSlot(_DetailsRowSlot.stackedLabel)!;
  RenderBox get _value => childForSlot(_DetailsRowSlot.value)!;
  RenderBox? get _trailing => childForSlot(_DetailsRowSlot.trailing);
  RenderBox get _label => _stacked ? _stackedLabel : _inlineLabel;

  /// A baseline sits well below the middle of its line, so a single line is
  /// never twice as tall as its first baseline and two lines always are.
  /// That holds for an avatar beside a one-line name too: the avatar is
  /// barely taller than the line it is centred on.
  static bool _fitsOneLine(Size size, double? baseline) =>
      baseline == null || size.height <= baseline * 2;

  _DetailsRowArrangement _arrange(
    BoxConstraints constraints,
    ChildLayouter layoutChild,
    ChildBaselineGetter baselineOf,
  ) {
    final bounded = constraints.hasBoundedWidth;
    final trailing = _trailing;
    final trailingSize = trailing == null
        ? Size.zero
        : layoutChild(trailing, BoxConstraints(maxWidth: constraints.maxWidth));
    final trailingExtent = trailing == null
        ? 0.0
        : trailingSize.width + AppSpacing.md;
    final inlineLabelSize = layoutChild(
      _inlineLabel,
      const BoxConstraints(maxWidth: DetailsRow._labelWidth),
    );
    final stackedLabelSize = layoutChild(
      _stackedLabel,
      BoxConstraints(maxWidth: constraints.maxWidth),
    );

    if (!alwaysStacked) {
      final valueConstraints = BoxConstraints(
        maxWidth: math.max(
          0,
          constraints.maxWidth -
              DetailsRow._labelWidth -
              DetailsRow._labelGap -
              trailingExtent,
        ),
      );
      final valueSize = layoutChild(_value, valueConstraints);
      final baseline = baselineOf(
        _value,
        valueConstraints,
        TextBaseline.alphabetic,
      );
      if (_fitsOneLine(valueSize, baseline)) {
        final line = math.max(valueSize.height, trailingSize.height);
        final valueTop = (line - valueSize.height) / 2;
        // The label sits on the value's first baseline, which an emoji or an
        // avatar can push below the line's middle; whatever lies above the
        // row's top shifts the whole row down.
        final labelBaseline = baselineOf(
          _inlineLabel,
          const BoxConstraints(maxWidth: DetailsRow._labelWidth),
          TextBaseline.alphabetic,
        );
        final labelTop = baseline == null || labelBaseline == null
            ? 0.0
            : valueTop + baseline - labelBaseline;
        final shift = math.max(0.0, -labelTop);
        final size = constraints.constrain(
          Size(
            bounded
                ? constraints.maxWidth
                : DetailsRow._labelWidth +
                      DetailsRow._labelGap +
                      valueSize.width +
                      trailingExtent,
            math.max(labelTop + inlineLabelSize.height, line) + shift,
          ),
        );
        return _DetailsRowArrangement(
          size: size,
          stacked: false,
          label: Offset(0, labelTop + shift),
          value: Offset(
            size.width - trailingExtent - valueSize.width,
            valueTop + shift,
          ),
          trailing: Offset(
            size.width - trailingSize.width,
            (line - trailingSize.height) / 2 + shift,
          ),
        );
      }
    }

    final valueSize = layoutChild(
      _value,
      BoxConstraints(
        maxWidth: math.max(0, constraints.maxWidth - trailingExtent),
      ),
    );
    final line = math.max(valueSize.height, trailingSize.height);
    final top = stackedLabelSize.height + AppSpacing.xxs;
    final size = constraints.constrain(
      Size(
        bounded
            ? constraints.maxWidth
            : math.max(
                stackedLabelSize.width,
                valueSize.width + trailingExtent,
              ),
        top + line,
      ),
    );
    return _DetailsRowArrangement(
      size: size,
      stacked: true,
      label: Offset.zero,
      value: Offset(0, top + (line - valueSize.height) / 2),
      trailing: Offset(
        size.width - trailingSize.width,
        top + (line - trailingSize.height) / 2,
      ),
    );
  }

  /// [start] measured from the row's start edge, as a left offset.
  Offset _place(Offset start, RenderBox child, double width) =>
      textDirection == TextDirection.ltr
      ? start
      : Offset(width - start.dx - child.size.width, start.dy);

  @override
  void performLayout() {
    final arrangement = _arrange(
      constraints,
      ChildLayoutHelper.layoutChild,
      ChildLayoutHelper.getBaseline,
    );
    size = arrangement.size;
    _stacked = arrangement.stacked;
    void position(RenderBox child, Offset start) {
      (child.parentData! as BoxParentData).offset = _place(
        start,
        child,
        size.width,
      );
    }

    position(_inlineLabel, arrangement.label);
    position(_stackedLabel, arrangement.label);
    position(_value, arrangement.value);
    final trailing = _trailing;
    if (trailing != null) position(trailing, arrangement.trailing);
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) => _arrange(
    constraints,
    ChildLayoutHelper.dryLayoutChild,
    ChildLayoutHelper.getDryBaseline,
  ).size;

  double get _trailingMaxWidth {
    final trailing = _trailing;
    return trailing == null
        ? 0
        : trailing.getMaxIntrinsicWidth(double.infinity) + AppSpacing.md;
  }

  @override
  double computeMinIntrinsicWidth(double height) => math.max(
    _stackedLabel.getMinIntrinsicWidth(double.infinity),
    _value.getMinIntrinsicWidth(double.infinity) + _trailingMaxWidth,
  );

  @override
  double computeMaxIntrinsicWidth(double height) {
    final value = _value.getMaxIntrinsicWidth(double.infinity);
    return alwaysStacked
        ? math.max(
            _stackedLabel.getMaxIntrinsicWidth(double.infinity),
            value + _trailingMaxWidth,
          )
        : DetailsRow._labelWidth +
              DetailsRow._labelGap +
              value +
              _trailingMaxWidth;
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      computeDryLayout(BoxConstraints(maxWidth: width)).height;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      computeMinIntrinsicHeight(width);

  Iterable<RenderBox> get _shown sync* {
    yield _label;
    yield _value;
    final trailing = _trailing;
    if (trailing != null) yield trailing;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    for (final child in _shown) {
      final parentData = child.parentData! as BoxParentData;
      context.paintChild(child, offset + parentData.offset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final child in _shown) {
      final parentData = child.parentData! as BoxParentData;
      final hit = result.addWithPaintOffset(
        offset: parentData.offset,
        position: position,
        hitTest: (result, transformed) =>
            child.hitTest(result, position: transformed),
      );
      if (hit) return true;
    }
    return false;
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    _shown.forEach(visitor);
  }
}

/// Holds [child] still on screen while the vertical scroll view it is laid
/// out in scrolls, so the content passes under it.
///
/// The child stays part of the scrolled content, and so of its semantics: a
/// sort key can still put a sheet's close button right after the title,
/// which a button stacked over the scroll view could not follow.
class ScrollPinned extends StatelessWidget {
  const ScrollPinned({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final position = Scrollable.maybeOf(context)?.position;
    if (position == null) return child;
    return ListenableBuilder(
      listenable: position,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, position.hasPixels ? position.pixels : 0),
        child: child,
      ),
      child: child,
    );
  }
}
