import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/app_motion.dart';
import '../theme/app_theme.dart';

/// A native Liquid Glass surface behind app-owned tab content: the UIKit view
/// draws only the glass (public `UIGlassEffect` on iOS 26+, a system material
/// `UIBlurEffect` before), including the selected capsule nested in its native
/// content view. Flutter draws the controls and badges and owns every gesture.
/// One platform-view surface serves the
/// phone bottom bar and the tablet sidebar column alike — there are no system
/// slot metrics to fight.
///
/// The platform view is transparent to the widget tree: the child paints above
/// it and wins hit testing, while the view's own opaque hit region keeps the
/// scrollable underneath from receiving touches through the glass.
class NativeGlassSurface extends StatefulWidget {
  const NativeGlassSurface({
    super.key,
    required this.child,
    this.selection,
    this.itemCount = 0,
    this.selectionInset = 5,
  }) : assert(selectionInset >= 0),
       assert(selection == null || (selection >= 0 && selection < itemCount));

  /// Logical (start-to-end) selected slot, or null for a surface without tabs.
  final int? selection;
  final int itemCount;

  /// Must match the Flutter controls' padding; native geometry uses live bounds.
  final double selectionInset;

  /// The app-owned tab row drawn above the glass.
  final Widget child;

  @override
  State<NativeGlassSurface> createState() => _NativeGlassSurfaceState();
}

class _NativeGlassSurfaceState extends State<NativeGlassSurface> {
  MethodChannel? _channel;

  Map<String, Object> _configuration() {
    final colors = context.colors;
    final dark = colors.navBar.computeLuminance() < 0.5;
    return {
      'tint': colors.navBar.withValues(alpha: dark ? 0.12 : 0.36).toARGB32(),
      'dark': dark,
      'radius': AppRadius.pill,
      'rtl': Directionality.of(context) == TextDirection.rtl,
      'selection': widget.selection ?? -1,
      'itemCount': widget.itemCount,
      'selectionInset': widget.selectionInset,
      'selectionTint': colors.linkBlue
          .withValues(alpha: dark ? 0.19 : 0.10)
          .toARGB32(),
      'opaqueBackground': colors.navBar.withValues(alpha: 1).toARGB32(),
      'opaqueSelection': Color.alphaBlend(
        colors.linkBlue.withValues(alpha: 0.22),
        colors.navBar.withValues(alpha: 1),
      ).toARGB32(),
      'contrastBorder': colors.linkBlue.withValues(alpha: 1).toARGB32(),
      'highContrast': MediaQuery.highContrastOf(context),
      'durationMs': AppMotion.duration(
        context,
        AppMotion.deliberate,
      ).inMilliseconds,
    };
  }

  @override
  void didUpdateWidget(NativeGlassSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _update();
  }

  void _update() {
    final channel = _channel;
    if (channel != null) {
      unawaited(channel.invokeMethod<void>('update', _configuration()));
    }
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    key: const ValueKey('native-glass-surface'),
    textDirection: Directionality.of(context),
    children: [
      Positioned.fill(
        child: UiKitView(
          viewType: 'mithka/native_glass',
          creationParamsCodec: const StandardMessageCodec(),
          creationParams: _configuration(),
          onPlatformViewCreated: (id) {
            final channel = MethodChannel('mithka/native_glass/$id');
            _channel = channel;
            _update();
          },
        ),
      ),
      widget.child,
    ],
  );
}
