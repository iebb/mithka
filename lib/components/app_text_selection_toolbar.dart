// Portions adapted from Flutter text_selection_toolbar.dart.
// Copyright 2014 The Flutter Authors. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without modification,
// are permitted provided that the following conditions are met:
//
//     * Redistributions of source code must retain the above copyright
//       notice, this list of conditions and the following disclaimer.
//     * Redistributions in binary form must reproduce the above
//       copyright notice, this list of conditions and the following
//       disclaimer in the documentation and/or other materials provided
//       with the distribution.
//     * Neither the name of Google Inc. nor the names of its
//       contributors may be used to endorse or promote products derived
//       from this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
// ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
// ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
// LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
// ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
// SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'app_icons.dart';

const double _kToolbarHeight = 44.0;
const double _kToolbarContentDistance = 8.0;

/// A Material-style text selection toolbar whose overflow affordances use the
/// repository-owned icon vocabulary instead of the framework's bundled
/// MaterialIcons glyphs.
///
/// The framework's [TextSelectionToolbar] renders its overflow "more" and
/// "back" buttons with `Icons.more_vert` / `Icons.arrow_back`, which render as
/// tofu boxes when the MaterialIcons font is not bundled
/// (`uses-material-design: false`). This widget reproduces the framework
/// toolbar's anchoring, overflow pagination and trailing-edge alignment with
/// [HeroAppIcons.ellipsisVertical] and [HeroAppIcons.chevronLeft] instead, so
/// the app ships one icon vocabulary and no MaterialIcons font.
///
/// Use through [AppTextSelectionToolbar.fromButtonItems], which mirrors
/// [AdaptiveTextSelectionToolbar.buttonItems] for the mobile Material
/// platforms; desktop platforms keep the framework's desktop toolbars, which
/// have no overflow affordance.
class AppTextSelectionToolbar extends StatelessWidget {
  const AppTextSelectionToolbar({
    super.key,
    required this.anchorAbove,
    required this.anchorBelow,
    required this.children,
    this.buttonItems,
  });

  final Offset anchorAbove;
  final Offset anchorBelow;
  final List<Widget> children;

  /// The [ContextMenuButtonItem]s these [children] were built from, when the
  /// toolbar came from [AppTextSelectionToolbar.fromButtonItems]; tests and
  /// callers that need the semantic items read them from here.
  final List<ContextMenuButtonItem>? buttonItems;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }
    final anchorAbovePadded =
        anchorAbove - const Offset(0.0, _kToolbarContentDistance);
    const double screenPadding = 8.0;
    final paddingAbove = MediaQuery.paddingOf(context).top + screenPadding;
    final double availableHeight =
        anchorAbovePadded.dy - _kToolbarContentDistance - paddingAbove;
    final bool fitsAbove = _kToolbarHeight <= availableHeight;
    final localAdjustment = Offset(screenPadding, paddingAbove);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        screenPadding,
        paddingAbove,
        screenPadding,
        screenPadding,
      ),
      child: CustomSingleChildLayout(
        delegate: TextSelectionToolbarLayoutDelegate(
          anchorAbove: anchorAbovePadded - localAdjustment,
          anchorBelow: anchorBelow - localAdjustment,
          fitsAbove: fitsAbove,
        ),
        child: _AppToolbarOverflowable(isAbove: fitsAbove, children: children),
      ),
    );
  }

  /// Builds the toolbar from [ContextMenuButtonItem]s, mirroring
  /// [AdaptiveTextSelectionToolbar.buttonItems] but routing Android through
  /// this toolbar's owned overflow affordances. iOS/macOS keep the Cupertino
  /// toolbar (it pages with dots, not icons), and desktop keeps the framework
  /// desktop toolbar.
  static Widget fromButtonItems({
    required BuildContext context,
    required TextSelectionToolbarAnchors anchors,
    required List<ContextMenuButtonItem> items,
  }) {
    switch (Theme.of(context).platform) {
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
        return AppTextSelectionToolbar(
          anchorAbove: anchors.primaryAnchor,
          anchorBelow: anchors.secondaryAnchor ?? anchors.primaryAnchor,
          buttonItems: items,
          children: items
              .asMap()
              .entries
              .map(
                (entry) => TextSelectionToolbarTextButton(
                  padding: TextSelectionToolbarTextButton.getPadding(
                    entry.key,
                    items.length,
                  ),
                  onPressed: entry.value.onPressed,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    AdaptiveTextSelectionToolbar.getButtonLabel(
                      context,
                      entry.value,
                    ),
                  ),
                ),
              )
              .toList(),
        );
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: anchors,
          buttonItems: items,
        );
    }
  }
}

class _AppToolbarOverflowable extends StatefulWidget {
  const _AppToolbarOverflowable({required this.isAbove, required this.children})
    : assert(children.length > 0);

  final List<Widget> children;
  final bool isAbove;

  @override
  _AppToolbarOverflowableState createState() => _AppToolbarOverflowableState();
}

class _AppToolbarOverflowableState extends State<_AppToolbarOverflowable>
    with TickerProviderStateMixin {
  bool _overflowOpen = false;
  UniqueKey _containerKey = UniqueKey();

  void _reset() {
    _containerKey = UniqueKey();
    _overflowOpen = false;
  }

  @override
  void didUpdateWidget(_AppToolbarOverflowable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(widget.children, oldWidget.children)) {
      _reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    assert(debugCheckHasMaterialLocalizations(context));
    final MaterialLocalizations localizations = MaterialLocalizations.of(
      context,
    );
    final TextDirection textDirection = Directionality.of(context);
    final backIcon = textDirection == TextDirection.rtl
        ? HeroAppIcons.chevronRight
        : HeroAppIcons.chevronLeft;

    return _AppToolbarTrailingEdgeAlign(
      key: _containerKey,
      overflowOpen: _overflowOpen,
      textDirection: textDirection,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 140),
        child: Material(
          borderRadius: const BorderRadius.all(
            Radius.circular(_kToolbarHeight / 2),
          ),
          clipBehavior: Clip.antiAlias,
          color: _toolbarColor(Theme.of(context).colorScheme),
          elevation: 1.0,
          type: MaterialType.card,
          child: _AppToolbarItemsLayout(
            isAbove: widget.isAbove,
            overflowOpen: _overflowOpen,
            textDirection: textDirection,
            children: <Widget>[
              _AppToolbarOverflowButton(
                key: _overflowOpen
                    ? StandardComponentType.backButton.key
                    : StandardComponentType.moreButton.key,
                icon: Icon(
                  _overflowOpen
                      ? backIcon.data
                      : HeroAppIcons.ellipsisVertical.data,
                  size: 24,
                ),
                onPressed: () {
                  setState(() {
                    _overflowOpen = !_overflowOpen;
                  });
                },
                tooltip: _overflowOpen
                    ? localizations.backButtonTooltip
                    : localizations.moreButtonTooltip,
              ),
              ...widget.children,
            ],
          ),
        ),
      ),
    );
  }

  static Color _toolbarColor(ColorScheme colorScheme) {
    final bool isDefaultSurface = switch (colorScheme.brightness) {
      Brightness.light => identical(
        ThemeData().colorScheme.surface,
        colorScheme.surface,
      ),
      Brightness.dark => identical(
        ThemeData.dark().colorScheme.surface,
        colorScheme.surface,
      ),
    };
    if (!isDefaultSurface) {
      return colorScheme.surface;
    }
    return switch (colorScheme.brightness) {
      Brightness.light => const Color(0xffffffff),
      Brightness.dark => const Color(0xff424242),
    };
  }
}

class _AppToolbarOverflowButton extends StatelessWidget {
  const _AppToolbarOverflowButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
  });

  final Widget icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.card,
      color: const Color(0x00000000),
      child: IconButton(icon: icon, onPressed: onPressed, tooltip: tooltip),
    );
  }
}

// When the overflow menu is open, it tries to align its trailing edge to the
// trailing edge of the closed menu. Mirrors the framework's private
// _TextSelectionToolbarTrailingEdgeAlign.
class _AppToolbarTrailingEdgeAlign extends SingleChildRenderObjectWidget {
  const _AppToolbarTrailingEdgeAlign({
    super.key,
    required Widget super.child,
    required this.overflowOpen,
    required this.textDirection,
  });

  final bool overflowOpen;
  final TextDirection textDirection;

  @override
  _AppToolbarTrailingEdgeAlignRenderBox createRenderObject(
    BuildContext context,
  ) {
    return _AppToolbarTrailingEdgeAlignRenderBox(
      overflowOpen: overflowOpen,
      textDirection: textDirection,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _AppToolbarTrailingEdgeAlignRenderBox renderObject,
  ) {
    renderObject
      ..overflowOpen = overflowOpen
      ..textDirection = textDirection;
  }
}

class _AppToolbarTrailingEdgeAlignRenderBox extends RenderProxyBox {
  _AppToolbarTrailingEdgeAlignRenderBox({
    required this._overflowOpen,
    required this._textDirection,
  }) : super();

  double? _closedWidth;

  bool _overflowOpen;
  bool get overflowOpen => _overflowOpen;
  set overflowOpen(bool value) {
    if (value == overflowOpen) {
      return;
    }
    _overflowOpen = value;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  TextDirection get textDirection => _textDirection;
  set textDirection(TextDirection value) {
    if (value == textDirection) {
      return;
    }
    _textDirection = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    child!.layout(constraints.loosen(), parentUsesSize: true);

    if (!overflowOpen && _closedWidth == null) {
      _closedWidth = child!.size.width;
    }

    size = constraints.constrain(
      Size(
        _closedWidth == null || child!.size.width > _closedWidth!
            ? child!.size.width
            : _closedWidth!,
        child!.size.height,
      ),
    );

    final childParentData = child!.parentData! as ToolbarItemsParentData;
    childParentData.offset = Offset(
      textDirection == TextDirection.rtl ? 0.0 : size.width - child!.size.width,
      0.0,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final childParentData = child!.parentData! as ToolbarItemsParentData;
    context.paintChild(child!, childParentData.offset + offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final childParentData = child!.parentData! as ToolbarItemsParentData;
    return result.addWithPaintOffset(
      offset: childParentData.offset,
      position: position,
      hitTest: (BoxHitTestResult result, Offset transformed) {
        assert(transformed == position - childParentData.offset);
        return child!.hitTest(result, position: transformed);
      },
    );
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! ToolbarItemsParentData) {
      child.parentData = ToolbarItemsParentData();
    }
  }

  @override
  void applyPaintTransform(RenderObject child, Matrix4 transform) {
    final childParentData = child.parentData! as ToolbarItemsParentData;
    transform.translateByDouble(
      childParentData.offset.dx,
      childParentData.offset.dy,
      0,
      1,
    );
    super.applyPaintTransform(child, transform);
  }
}

// Renders the menu items in the correct positions in the menu and its overflow
// submenu, mirroring the framework's private items layout.
class _AppToolbarItemsLayout extends MultiChildRenderObjectWidget {
  const _AppToolbarItemsLayout({
    required this.isAbove,
    required this.overflowOpen,
    required this.textDirection,
    required super.children,
  });

  final bool isAbove;
  final bool overflowOpen;
  final TextDirection textDirection;

  @override
  _RenderAppToolbarItemsLayout createRenderObject(BuildContext context) {
    return _RenderAppToolbarItemsLayout(
      isAbove: isAbove,
      overflowOpen: overflowOpen,
      textDirection: textDirection,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderAppToolbarItemsLayout renderObject,
  ) {
    renderObject
      ..isAbove = isAbove
      ..textDirection = textDirection
      ..overflowOpen = overflowOpen;
  }

  @override
  _AppToolbarItemsLayoutElement createElement() =>
      _AppToolbarItemsLayoutElement(this);
}

class _AppToolbarItemsLayoutElement extends MultiChildRenderObjectElement {
  _AppToolbarItemsLayoutElement(super.widget);

  static bool _shouldPaint(Element child) {
    return (child.renderObject!.parentData! as ToolbarItemsParentData)
        .shouldPaint;
  }

  @override
  void debugVisitOnstageChildren(ElementVisitor visitor) {
    children.where(_shouldPaint).forEach(visitor);
  }
}

class _RenderAppToolbarItemsLayout extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, ToolbarItemsParentData> {
  _RenderAppToolbarItemsLayout({
    required this._isAbove,
    required this._overflowOpen,
    required this._textDirection,
  }) : super();

  int _lastIndexThatFits = -1;

  bool _isAbove;
  bool get isAbove => _isAbove;
  set isAbove(bool value) {
    if (value == isAbove) {
      return;
    }
    _isAbove = value;
    markNeedsLayout();
  }

  bool _overflowOpen;
  bool get overflowOpen => _overflowOpen;
  set overflowOpen(bool value) {
    if (value == overflowOpen) {
      return;
    }
    _overflowOpen = value;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  TextDirection get textDirection => _textDirection;
  set textDirection(TextDirection value) {
    if (value == textDirection) {
      return;
    }
    _textDirection = value;
    markNeedsLayout();
  }

  void _layoutChildren() {
    final BoxConstraints sizedConstraints = _overflowOpen
        ? constraints
        : BoxConstraints.loose(Size(constraints.maxWidth, _kToolbarHeight));

    var i = -1;
    var width = 0.0;
    visitChildren((RenderObject renderObjectChild) {
      i++;

      if (_lastIndexThatFits != -1 && !overflowOpen) {
        return;
      }

      final child = renderObjectChild as RenderBox;
      child.layout(sizedConstraints.loosen(), parentUsesSize: true);
      width += child.size.width;

      if (width > sizedConstraints.maxWidth && _lastIndexThatFits == -1) {
        _lastIndexThatFits = i - 1;
      }
    });

    final RenderBox navButton = firstChild!;
    if (_lastIndexThatFits != -1 &&
        _lastIndexThatFits == childCount - 2 &&
        width - navButton.size.width <= sizedConstraints.maxWidth) {
      _lastIndexThatFits = -1;
    }
  }

  bool _shouldPaintChild(RenderObject renderObjectChild, int index) {
    if (renderObjectChild == firstChild) {
      return _lastIndexThatFits != -1;
    }

    if (_lastIndexThatFits == -1) {
      return true;
    }

    return (index > _lastIndexThatFits) == overflowOpen;
  }

  Size _placeChildrenHorizontally() {
    final RenderBox navButton = firstChild!;
    final isRtl = textDirection == TextDirection.rtl;

    final contentItems = <RenderBox>[];

    var totalWidth = 0.0;
    var maxHeight = 0.0;

    var i = -1;
    visitChildren((RenderObject renderObjectChild) {
      final child = renderObjectChild as RenderBox;
      final childParentData = child.parentData! as ToolbarItemsParentData;
      i++;

      if (!_shouldPaintChild(child, i)) {
        childParentData.shouldPaint = false;
      } else {
        childParentData.shouldPaint = true;

        totalWidth += child.size.width;
        maxHeight = math.max(maxHeight, child.size.height);

        if (child != navButton) {
          contentItems.add(child);
        }
      }
    });

    var currentX = 0.0;
    final bool showNavButton = _lastIndexThatFits >= 0;

    if (isRtl) {
      if (showNavButton) {
        final navParentData = navButton.parentData! as ToolbarItemsParentData;
        navParentData.offset = Offset.zero;
        currentX += navButton.size.width;
      }

      var rightEdge = totalWidth;
      for (final item in contentItems) {
        rightEdge -= item.size.width;
        final itemParentData = item.parentData! as ToolbarItemsParentData;
        itemParentData.offset = Offset(rightEdge, 0.0);
      }
    } else {
      for (final item in contentItems) {
        final itemParentData = item.parentData! as ToolbarItemsParentData;
        itemParentData.offset = Offset(currentX, 0.0);
        currentX += item.size.width;
      }

      if (showNavButton) {
        final navParentData = navButton.parentData! as ToolbarItemsParentData;
        navParentData.offset = Offset(currentX, 0.0);
      }
    }

    return Size(totalWidth, maxHeight);
  }

  Size _placeChildrenVertically() {
    final RenderBox navButton = firstChild!;

    var currentY = 0.0;
    var maxWidth = 0.0;

    final navButtonParentData = navButton.parentData! as ToolbarItemsParentData;

    if (_shouldPaintChild(navButton, 0)) {
      navButtonParentData.shouldPaint = true;
      if (!isAbove) {
        navButtonParentData.offset = Offset.zero;
        currentY += navButton.size.height;
        maxWidth = math.max(maxWidth, navButton.size.width);
      }
    } else {
      navButtonParentData.shouldPaint = false;
    }

    var i = -1;
    visitChildren((RenderObject renderObjectChild) {
      final child = renderObjectChild as RenderBox;
      final childParentData = child.parentData! as ToolbarItemsParentData;

      i++;

      if (renderObjectChild == navButton) {
        return;
      }

      if (!_shouldPaintChild(child, i)) {
        childParentData.shouldPaint = false;
        return;
      }

      childParentData.shouldPaint = true;
      childParentData.offset = Offset(0.0, currentY);
      currentY += child.size.height;
      maxWidth = math.max(maxWidth, child.size.width);
    });

    if (isAbove && navButtonParentData.shouldPaint) {
      navButtonParentData.offset = Offset(0.0, currentY);
      currentY += navButton.size.height;
      maxWidth = math.max(maxWidth, navButton.size.width);
    }

    return Size(maxWidth, currentY);
  }

  void _placeChildren() {
    size = overflowOpen
        ? _placeChildrenVertically()
        : _placeChildrenHorizontally();
  }

  void _resizeChildrenWhenOverflow() {
    if (!overflowOpen) {
      return;
    }

    final RenderBox navButton = firstChild!;
    var i = -1;

    visitChildren((RenderObject renderObjectChild) {
      final child = renderObjectChild as RenderBox;
      final childParentData = child.parentData! as ToolbarItemsParentData;

      i++;

      if (renderObjectChild == navButton) {
        return;
      }

      if (!_shouldPaintChild(renderObjectChild, i)) {
        childParentData.shouldPaint = false;
        return;
      }

      child.layout(
        BoxConstraints.tightFor(width: size.width),
        parentUsesSize: true,
      );
    });
  }

  @override
  void performLayout() {
    _lastIndexThatFits = -1;
    if (firstChild == null) {
      size = constraints.smallest;
      return;
    }

    _layoutChildren();
    _placeChildren();
    _resizeChildrenWhenOverflow();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    visitChildren((RenderObject renderObjectChild) {
      final child = renderObjectChild as RenderBox;
      final childParentData = child.parentData! as ToolbarItemsParentData;
      if (!childParentData.shouldPaint) {
        return;
      }

      context.paintChild(child, childParentData.offset + offset);
    });
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! ToolbarItemsParentData) {
      child.parentData = ToolbarItemsParentData();
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    RenderBox? child = lastChild;
    while (child != null) {
      final childParentData = child.parentData! as ToolbarItemsParentData;

      if (!childParentData.shouldPaint) {
        child = childParentData.previousSibling;
        continue;
      }

      final bool isHit = result.addWithPaintOffset(
        offset: childParentData.offset,
        position: position,
        hitTest: (BoxHitTestResult result, Offset transformed) {
          assert(transformed == position - childParentData.offset);
          return child!.hitTest(result, position: transformed);
        },
      );
      if (isHit) {
        return true;
      }
      child = childParentData.previousSibling;
    }
    return false;
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    visitChildren((RenderObject renderObjectChild) {
      final child = renderObjectChild as RenderBox;
      final childParentData = child.parentData! as ToolbarItemsParentData;
      if (childParentData.shouldPaint) {
        visitor(renderObjectChild);
      }
    });
  }
}
