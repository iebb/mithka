import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// A native Liquid Glass surface behind app-owned tab content: the UIKit view
/// draws only the glass (public `UIGlassEffect` on iOS 26+, a system material
/// `UIBlurEffect` before), while Flutter draws the tabs, the selection pill,
/// and the badges on top and owns every gesture, so one surface serves the
/// phone bottom bar and the tablet sidebar column alike — there are no system
/// slot metrics to fight.
///
/// The platform view is transparent to the widget tree: the child paints above
/// it and wins hit testing, while the view's own opaque hit region keeps the
/// scrollable underneath from receiving touches through the glass.
class NativeGlassSurface extends StatefulWidget {
  const NativeGlassSurface({super.key, required this.child});

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
