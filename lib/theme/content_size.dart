import 'package:flutter/widgets.dart';

import 'app_theme.dart';

/// Discrete content-size choices. Persisted custom sizes are not quantized.
const contentSizePresets = <double>[.9, 1, 1.1, 1.2, 1.35, 1.6];

@immutable
class ContentSizeData {
  const ContentSizeData({
    required this.appScale,
    required this.systemTextScaler,
  });

  final double appScale;
  final TextScaler systemTextScaler;
}

/// Captures the window OS scaler (already floored on touch) for all content.
class ContentSizeRoot extends StatelessWidget {
  const ContentSizeRoot({
    super.key,
    required this.appScale,
    required this.child,
  });

  final double appScale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final inherited = context
        .dependOnInheritedWidgetOfExactType<_ContentSize>();
    return _ContentSize(
      data: ContentSizeData(
        appScale: appScale,
        systemTextScaler:
            inherited?.data.systemTextScaler ??
            MediaQuery.textScalerOf(context),
      ),
      child: child,
    );
  }
}

/// Opts content into app sizing, then applies the OS's per-font-size scaling.
/// Nested scopes replace the app multiplier rather than multiplying it again.
class ContentSizeScope extends StatelessWidget {
  const ContentSizeScope({super.key, this.appScale, required this.child});

  final double? appScale;
  final Widget child;

  static ContentSizeData of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ContentSize>()?.data ??
      ContentSizeData(
        appScale: 1,
        systemTextScaler: MediaQuery.textScalerOf(context),
      );

  /// Shared by chat preview rendering and row-height measurement. Apply the
  /// role's app multiplier before the OS scaler, preserving nonlinear growth.
  static TextScaler chatListPreviewScalerOf(BuildContext context) {
    final data = of(context);
    return _ContentTextScaler(
      data.systemTextScaler,
      AppTextSize.chatListPreviewContentScale(data.appScale),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inherited = of(context);
    final data = ContentSizeData(
      appScale: appScale ?? inherited.appScale,
      systemTextScaler: inherited.systemTextScaler,
    );
    return _ContentSize(
      data: data,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: _ContentTextScaler(data.systemTextScaler, data.appScale),
        ),
        child: child,
      ),
    );
  }
}

class _ContentSize extends InheritedWidget {
  const _ContentSize({required this.data, required super.child});
  final ContentSizeData data;

  @override
  bool updateShouldNotify(_ContentSize oldWidget) =>
      data.appScale != oldWidget.data.appScale ||
      data.systemTextScaler != oldWidget.data.systemTextScaler;
}

class _ContentTextScaler extends TextScaler {
  const _ContentTextScaler(this.system, this.appScale);
  final TextScaler system;
  final double appScale;

  @override
  double scale(double fontSize) => system.scale(fontSize * appScale);

  @override
  double get textScaleFactor => scale(14) / 14;

  @override
  bool operator ==(Object other) =>
      other is _ContentTextScaler &&
      other.system == system &&
      other.appScale == appScale;

  @override
  int get hashCode => Object.hash(system, appScale);
}
