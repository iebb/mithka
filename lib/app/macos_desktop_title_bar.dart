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
  static const double trailingPadding = 12;
  static const double dividerWidth = 0.5;

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
            SizedBox(
              key: const ValueKey('macos-traffic-light-clearance'),
              width: leadingClearance,
            ),
            KeyedSubtree(
              key: const ValueKey('macos-app-identity'),
              child: appIdentity,
            ),
            const SizedBox(width: identityGap),
            Expanded(
              child: desktopWindowDragArea(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: onDragAreaDoubleTap,
                  child: const SizedBox.expand(
                    key: ValueKey('macos-title-bar-drag-area'),
                  ),
                ),
              ),
            ),
            if (accountIdentity != null) ...[
              const SizedBox(width: identityGap),
              KeyedSubtree(
                key: const ValueKey('macos-account-identity'),
                child: accountIdentity,
              ),
            ],
            if (trailingActions != null) ...[
              const SizedBox(width: 4),
              KeyedSubtree(
                key: const ValueKey('desktop-title-bar-actions'),
                child: trailingActions,
              ),
              const SizedBox(width: 4),
            ],
            if (trailingControls != null)
              KeyedSubtree(
                key: const ValueKey('desktop-title-bar-window-controls'),
                child: trailingControls,
              ),
            const SizedBox(width: trailingPadding),
          ],
        ),
      ),
    );
  }
}
