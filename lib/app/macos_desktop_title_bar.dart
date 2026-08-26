import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';
import 'desktop_window_drag_area.dart';

/// Flutter-owned chrome for the primary macOS window.
///
/// The native traffic-light controls remain visible in the leading clearance.
/// Only the intentionally blank middle region moves the window, keeping the
/// identity slots available for interactive controls.
class MacosDesktopTitleBar extends StatelessWidget {
  const MacosDesktopTitleBar({
    super.key,
    required this.appIdentity,
    this.accountIdentity,
    this.trailingActions,
    this.leadingClearance = trafficLightLeadingClearance,
    this.trailingControls,
    this.onDragAreaDoubleTap,
    this.backgroundColor,
  });

  static const double height = 40;
  static const double trafficLightLeadingClearance = 78;
  static const double identityGap = 12;

  /// Trailing inset for the action row. Dropped when this bar carries the
  /// window controls: a caption button has to reach the window corner.
  static const double trailingPadding = 12;
  static const double dividerWidth = 0.5;
  static const double _minimumIdentityWidth = 48;

  final Widget appIdentity;
  final Widget? accountIdentity;
  final Widget? trailingActions;
  final double leadingClearance;
  final Widget? trailingControls;
  final VoidCallback? onDragAreaDoubleTap;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accountIdentity = this.accountIdentity;
    final trailingActions = this.trailingActions;
    final trailingControls = this.trailingControls;

    return SizedBox(
      key: const ValueKey('macos-desktop-title-bar'),
      height: height,
      child: DecoratedBox(
        key: const ValueKey('macos-desktop-title-bar-decoration'),
        decoration: BoxDecoration(
          color: backgroundColor ?? colors.navBar,
          border: Border(
            bottom: BorderSide(color: colors.divider, width: dividerWidth),
          ),
        ),
        child: Row(
          children: [
            // Window controls own the trailing edge. Everything before them
            // is allowed to contract, so a wider search or narrower window
            // cannot push close beyond the top-right corner.
            Expanded(
              child: _content(
                appIdentity: appIdentity,
                accountIdentity: accountIdentity,
                trailingActions: trailingActions,
              ),
            ),
            // The caption buttons run flush into the top right corner, with
            // no inset of their own. That is the shape Windows and Linux draw,
            // and it is what puts close under the pointer when the window is
            // maximized and the corner swallows the cursor. macOS keeps the
            // inset because its controls are native and this slot is empty.
            if (trailingControls != null)
              KeyedSubtree(
                key: const ValueKey('desktop-title-bar-window-controls'),
                child: trailingControls,
              )
            else
              const SizedBox(width: trailingPadding),
          ],
        ),
      ),
    );
  }

  Widget _content({
    required Widget appIdentity,
    required Widget? accountIdentity,
    required Widget? trailingActions,
  }) {
    final identityAndDrag = LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final clearanceWidth = math.min(leadingClearance, availableWidth);
        final identityWidth = availableWidth - clearanceWidth - identityGap;

        // Below the avatar's useful width, keep the remaining strip draggable
        // instead of forcing the identity row to overflow under the actions.
        if (identityWidth < _minimumIdentityWidth) {
          return Row(
            children: [
              SizedBox(
                key: const ValueKey('macos-traffic-light-clearance'),
                width: clearanceWidth,
              ),
              Expanded(child: _dragArea()),
            ],
          );
        }

        return Row(
          children: [
            SizedBox(
              key: const ValueKey('macos-traffic-light-clearance'),
              width: clearanceWidth,
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: identityWidth),
              child: KeyedSubtree(
                key: const ValueKey('macos-app-identity'),
                child: appIdentity,
              ),
            ),
            const SizedBox(width: identityGap),
            Expanded(child: _dragArea()),
          ],
        );
      },
    );

    final withAccount = _appendTrailing(
      leading: identityAndDrag,
      trailing: accountIdentity == null
          ? null
          : KeyedSubtree(
              key: const ValueKey('macos-account-identity'),
              child: accountIdentity,
            ),
      leadingGap: identityGap,
    );
    return _appendTrailing(
      leading: withAccount,
      trailing: trailingActions == null
          ? null
          : KeyedSubtree(
              key: const ValueKey('desktop-title-bar-actions'),
              child: trailingActions,
            ),
      leadingGap: 4,
      trailingGap: 4,
    );
  }

  Widget _appendTrailing({
    required Widget leading,
    required Widget? trailing,
    required double leadingGap,
    double trailingGap = 0,
  }) {
    if (trailing == null) return leading;
    final totalGap = leadingGap + trailingGap;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= totalGap) {
          return Align(
            alignment: Alignment.centerRight,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth),
              child: trailing,
            ),
          );
        }
        return Row(
          children: [
            Expanded(child: leading),
            SizedBox(width: leadingGap),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: constraints.maxWidth - totalGap,
              ),
              child: trailing,
            ),
            SizedBox(width: trailingGap),
          ],
        );
      },
    );
  }

  Widget _dragArea() => desktopWindowDragArea(
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: onDragAreaDoubleTap,
      child: const SizedBox.expand(key: ValueKey('macos-title-bar-drag-area')),
    ),
  );
}
