import 'dart:ui' show DisplayFeature;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Reserves side-mounted system chrome for every route, sheet, and overlay.
/// Descendants receive the usable window size so adaptive panes and interface
/// scaling do not lay themselves out beneath a vertical status area.
class HorizontalSafeViewport extends StatefulWidget {
  const HorizontalSafeViewport({
    super.key,
    required this.child,
    this.sideNavigation = false,
  });

  final bool sideNavigation;

  final Widget child;

  @override
  State<HorizontalSafeViewport> createState() => _HorizontalSafeViewportState();
}

class _HorizontalSafeViewportState extends State<HorizontalSafeViewport> {
  late final _entry = OverlayEntry(builder: _buildViewport);
  static const _geometryChannel = MethodChannel('mithka/window_geometry');
  MediaQueryData? _queriedMedia;
  double? _sideTopFraction;

  void _refreshSideGeometry(MediaQueryData media) {
    if (!widget.sideNavigation ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.iOS ||
        (_queriedMedia?.size == media.size &&
            _queriedMedia?.padding == media.padding)) {
      return;
    }
    _queriedMedia = media;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      double? fraction;
      try {
        final geometry = await _geometryChannel
            .invokeMapMethod<String, dynamic>('sideNavigationGeometry');
        final value = geometry?['topFraction'];
        // Missing geometry retains the older-native fallback. Malformed geometry
        // must not manufacture usable space in an explicitly reserved edge.
        fraction = value == null ? null : (value is num ? value.toDouble() : 1);
        if (fraction != null &&
            (!fraction.isFinite || fraction < 0 || fraction > 1)) {
          fraction = 1;
        }
      } on MissingPluginException {
        // Older native builds and widget tests retain a conservative fallback.
      } on PlatformException {
        // Geometry will be refreshed on the next window change.
      }
      if (!mounted || !identical(_queriedMedia, media)) return;
      if (fraction != _sideTopFraction) {
        _sideTopFraction = fraction;
        _entry.markNeedsBuild();
      }
    });
  }

  @override
  void didUpdateWidget(HorizontalSafeViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sideNavigation) _entry.markNeedsBuild();
  }

  @override
  void dispose() {
    if (widget.sideNavigation) _entry.remove();
    _entry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.sideNavigation
      ? Overlay(initialEntries: [_entry])
      : _buildViewport(context);

  Widget _buildViewport(BuildContext context) {
    final media = MediaQuery.of(context);
    _refreshSideGeometry(media);
    final left = media.padding.left;
    final right = media.padding.right;
    final safeMedia = media.removePadding(removeLeft: true, removeRight: true);
    return Padding(
      padding: EdgeInsets.only(left: left, right: right),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final viewport = Offset.zero & size;
          return MediaQuery(
            data: safeMedia.copyWith(
              size: size,
              displayFeatures: [
                for (final feature in media.displayFeatures)
                  if (feature.bounds.right >= left &&
                      feature.bounds.left <= media.size.width - right)
                    DisplayFeature(
                      bounds: feature.bounds
                          .translate(-left, 0)
                          .intersect(viewport),
                      type: feature.type,
                      state: feature.state,
                    ),
              ],
            ),
            child: SideNavigationGeometry(
              window: media,
              enabled: widget.sideNavigation,
              sideTopFraction: _sideTopFraction,
              child: widget.child,
            ),
          );
        },
      ),
    );
  }
}

/// The outer window geometry remains available after horizontal safe padding.
class SideNavigationGeometry extends InheritedWidget {
  const SideNavigationGeometry({
    super.key,
    required this.window,
    required this.enabled,
    this.sideTopFraction,
    required super.child,
  });
  final MediaQueryData window;
  final bool enabled;
  final double? sideTopFraction;
  double get sideTop {
    final fraction = sideTopFraction ?? 0.5;
    return window.size.height *
        (fraction.isFinite && fraction >= 0 && fraction <= 1 ? fraction : 1);
  }

  /// Icon-only navigation retains generous targets at every text size.
  static const itemExtent = 56.0;

  static SideNavigationGeometry? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SideNavigationGeometry>();

  /// Ordinary landscape camera insets are too narrow for navigation controls.
  bool fits(int count, double itemHeight) =>
      enabled &&
      count > 0 &&
      itemHeight.isFinite &&
      itemHeight > 0 &&
      window.size.height.isFinite &&
      window.size.height >= 600 &&
      (window.padding.right >= 64 || window.padding.left >= 64) &&
      window.viewInsets.bottom == 0 &&
      count * itemHeight <=
          window.size.height - sideTop - window.padding.bottom;

  @override
  bool updateShouldNotify(SideNavigationGeometry oldWidget) =>
      window != oldWidget.window ||
      enabled != oldWidget.enabled ||
      sideTopFraction != oldWidget.sideTopFraction;
}

/// Paints and hit-tests controls in the side strip of the full window overlay.
/// This overlay belongs to the unlocked app, below calls and the lock screen.
class SideNavigationPortal extends StatefulWidget {
  const SideNavigationPortal({
    super.key,
    required this.child,
    required this.visible,
    this.fillSide = false,
  });
  final Widget child;
  final bool visible;
  final bool fillSide;
  @override
  State<SideNavigationPortal> createState() => _SideNavigationPortalState();
}

class _SideNavigationPortalState extends State<SideNavigationPortal> {
  final _controller = OverlayPortalController();
  @override
  void initState() {
    super.initState();
    _controller.show();
  }

  @override
  Widget build(BuildContext context) {
    final geometry = SideNavigationGeometry.of(context)!;
    final window = geometry.window;
    final right = window.padding.right >= 64;
    return OverlayPortal(
      controller: _controller,
      overlayLocation: OverlayChildLocation.rootOverlay,
      overlayChildBuilder: (_) =>
          !widget.visible ||
              geometry.sideTop >= window.size.height - window.padding.bottom
          ? const SizedBox.shrink()
          : Positioned(
              right: right ? 0 : null,
              left: right ? null : 0,
              top: widget.fillSide ? geometry.sideTop : null,
              bottom: window.padding.bottom,
              width: right ? window.padding.right : window.padding.left,
              child: widget.child,
            ),
      child: const SizedBox.shrink(),
    );
  }
}
