import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../components/app_icons.dart';

/// A logical app tab, not a Flutter control painted over UIKit.
@immutable
class NativeTabBarItem {
  const NativeTabBarItem({
    required this.id,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    this.unread = 0,
    this.onMarkAllRead,
  });

  final int id;
  final String label;
  final AppIconData icon;
  final AppIconData selectedIcon;
  final int unread;
  final VoidCallback? onMarkAllRead;
}

/// Actual contained UITabBarController / UITabBar. UIKit owns touch, selection, captions, badges and material.
///
/// No content/UI scale or Flutter text scaler is applied to the native control.
/// Its live sizeThatFits result is returned over the per-view channel. The 1pt
/// bootstrap only mounts the measuring view; it is not a native height target.
/// Native badges have no public drag-clear API (see implementation plan).
class NativeTabBar extends StatefulWidget {
  const NativeTabBar({
    super.key,
    required this.items,
    required this.selectedId,
    required this.onSelect,
    required this.reserveBottomInset,
    required this.dark,
    required this.tint,
    required this.fallback,
    required this.markAllReadLabel,
    required this.actionScope,
  });

  final List<NativeTabBarItem> items;
  final int selectedId;
  final ValueChanged<int> onSelect;
  final bool reserveBottomInset;
  final bool dark;
  final Color tint;
  final Widget fallback;
  final String markAllReadLabel;
  final String actionScope;

  @override
  State<NativeTabBar> createState() => _NativeTabBarState();
}

class _NativeTabBarState extends State<NativeTabBar> {
  MethodChannel? _channel;
  double _height = 1;
  bool _supported = false;
  int _generation = 0;
  int _actionEpoch = 0;
  Map<String, Object>? _configuration;

  @override
  void initState() {
    super.initState();
    unawaited(_checkSupport());
  }

  Future<void> _checkSupport() async {
    bool supported;
    try {
      supported =
          await const MethodChannel(
            'mithka/native_tab_bar',
          ).invokeMethod<bool>('isSupported') ==
          true;
    } on MissingPluginException {
      supported = false;
    }
    if (!mounted || !supported) return;
    setState(() => _supported = true);
    _update();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _update();
  }

  @override
  void didUpdateWidget(NativeTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.actionScope != widget.actionScope ||
        oldWidget.selectedId != widget.selectedId ||
        !listEquals(
          oldWidget.items.map((item) => item.id).toList(),
          widget.items.map((item) => item.id).toList(),
        )) {
      ++_actionEpoch;
    }
    _update();
  }

  void _update() {
    if (!_supported) return;
    final generation = ++_generation;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final direction = Directionality.of(context);
    final items = widget.items;
    // Capture dependency values before asynchronous glyph generation. A newer
    // badge/theme/direction/tab update invalidates this entire snapshot.
    final configuration = <String, Object>{
      'selectedId': widget.selectedId,
      'markAllReadLabel': widget.markAllReadLabel,
      'actionEpoch': _actionEpoch,
      'dark': widget.dark,
      'tint': widget.tint.toARGB32(),
      'rtl': direction == TextDirection.rtl,
      'bottomInset': widget.reserveBottomInset
          ? MediaQuery.viewPaddingOf(context).bottom
          : 0.0,
    };
    unawaited(() async {
      final encoded = await Future.wait(
        items.map((item) async {
          final images = await Future.wait([
            NativeTabIconRasterizer.png(item.icon.data, dpr, direction),
            NativeTabIconRasterizer.png(item.selectedIcon.data, dpr, direction),
          ]);
          return <String, Object>{
            'id': item.id,
            'label': item.label,
            'unread': item.unread,
            'canMarkAllRead': item.onMarkAllRead != null,
            'image': images[0],
            'selectedImage': images[1],
            'imageScale': dpr,
          };
        }),
      );
      final readImage = await NativeTabIconRasterizer.png(
        HeroAppIcons.circleCheck.data,
        dpr,
        direction,
      );
      if (!mounted || generation != _generation) return;
      configuration['readActionImage'] = readImage;
      configuration['imageScale'] = dpr;
      configuration['items'] = encoded;
      _configuration = configuration;
      final channel = _channel;
      if (channel != null) {
        await channel.invokeMethod<void>('update', configuration);
      } else {
        setState(() {});
      }
    }());
  }

  Future<Object?> _onNativeCall(MethodCall call) async {
    if (!mounted) return null;
    if (call.method == 'select') {
      final id = (call.arguments as Map)['id'];
      if (id is int && widget.items.any((item) => item.id == id)) {
        // Deliberately forward current-tab taps: app reselect/pop-to-root.
        widget.onSelect(id);
      }
    } else if (call.method == 'markAllRead') {
      final arguments = call.arguments as Map;
      if (arguments['actionEpoch'] != _actionEpoch) return null;
      final id = arguments['id'];
      for (final item in widget.items) {
        if (item.id == id) {
          item.onMarkAllRead?.call();
          break;
        }
      }
    } else if (call.method == 'metrics') {
      final value = (call.arguments as Map)['height'];
      if (value is num && value.isFinite && value > 0 && value != _height) {
        setState(() => _height = value.toDouble());
      }
    }
    return null;
  }

  @override
  void dispose() {
    ++_generation;
    final channel = _channel;
    channel?.setMethodCallHandler(null);
    if (channel != null) unawaited(channel.invokeMethod<void>('dispose'));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => !_supported
      ? widget.fallback
      : SizedBox(
          key: const ValueKey('native-tab-bar'),
          height: _height,
          child: _configuration == null
              ? null
              : UiKitView(
                  viewType: 'mithka/native_tab_bar',
                  layoutDirection: Directionality.of(context),
                  creationParamsCodec: const StandardMessageCodec(),
                  creationParams: _configuration,
                  onPlatformViewCreated: (id) {
                    if (!mounted) return;
                    final channel = MethodChannel('mithka/native_tab_bar/$id');
                    _channel = channel;
                    channel.setMethodCallHandler(_onNativeCall);
                    // Explicit handshake: initial layout may precede Dart handler.
                    unawaited(
                      channel.invokeMethod<void>('update', _configuration),
                    );
                  },
                ),
        );
}

/// Owned font glyphs become template UIImage PNG data, never SF Symbols.
/// 25pt is the supplied tab artwork canvas, not a forced UIKit control metric.
/// Native captions, image placement, badge size and selection remain untouched.
@visibleForTesting
abstract final class NativeTabIconRasterizer {
  static const double artworkExtent = 25;
  static const int _cacheLimit = 96;
  static final _cache =
      <(IconData, double, TextDirection), Future<Uint8List>>{};

  static Future<Uint8List> png(
    IconData icon,
    double dpr,
    TextDirection direction,
  ) {
    final key = (icon, dpr, direction);
    final cached = _cache[key];
    if (cached != null) return cached;
    if (_cache.length >= _cacheLimit) _cache.remove(_cache.keys.first);
    final future = _rasterize(icon, dpr, direction);
    _cache[key] = future;
    // A failed render must not poison this glyph's cache permanently.
    unawaited(
      future.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {
          if (identical(_cache[key], future)) _cache.remove(key);
        },
      ),
    );
    return future;
  }

  static Future<Uint8List> _rasterize(
    IconData icon,
    double dpr,
    TextDirection direction,
  ) async {
    final pixels = (artworkExtent * dpr).ceil();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(dpr);
    if (icon.matchTextDirection && direction == TextDirection.rtl) {
      canvas.translate(artworkExtent, 0);
      canvas.scale(-1, 1);
    }
    final painter = TextPainter(
      textDirection: direction,
      textScaler: TextScaler.noScaling,
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          inherit: false,
          color: const Color(0xFFFFFFFF),
          fontSize: artworkExtent,
          height: 1,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
        ),
      ),
    )..layout();
    painter.paint(
      canvas,
      Offset(
        (artworkExtent - painter.width) / 2,
        (artworkExtent - painter.height) / 2,
      ),
    );
    painter.dispose();
    final picture = recorder.endRecording();
    final image = await picture.toImage(pixels, pixels);
    picture.dispose();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('Owned tab icon PNG encoding failed');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
    }
  }
}
