import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../components/app_icons.dart';
import '../../theme/app_theme.dart';
import 'outgoing_attachment.dart';

class ChatMediaDropRegion extends StatefulWidget {
  const ChatMediaDropRegion({
    super.key,
    required this.child,
    required this.enabled,
    required this.onImagesDropped,
  });

  final Widget child;
  final bool enabled;
  final Future<void> Function(List<OutgoingAttachment>) onImagesDropped;

  @override
  State<ChatMediaDropRegion> createState() => _ChatMediaDropRegionState();
}

class _ChatMediaDropRegionState extends State<ChatMediaDropRegion> {
  static const _channel = MethodChannel('mithka/media_drop');
  static final _regions = <_ChatMediaDropRegionState>[];
  static final _pendingDrops = <String, (_ChatMediaDropRegionState, Object)>{};
  bool _draggingOver = false;

  @override
  void initState() {
    super.initState();
    _regions.add(this);
    _channel.setMethodCallHandler(_dispatchNativeDropEvent);
  }

  @override
  void dispose() {
    _regions.remove(this);
    _pendingDrops.removeWhere((_, target) => identical(target.$1, this));
    if (_regions.isEmpty) _channel.setMethodCallHandler(null);
    super.dispose();
  }

  bool get _canReceive =>
      mounted && widget.enabled && (ModalRoute.of(context)?.isCurrent ?? true);

  bool _contains(Offset point) {
    if (!_canReceive) return false;
    final box = context.findRenderObject();
    if (box is! RenderBox ||
        !box.attached ||
        !box.paintBounds.contains(box.globalToLocal(point))) {
      return false;
    }
    final hit = HitTestResult();
    WidgetsBinding.instance.hitTestInView(hit, point, View.of(context).viewId);
    return hit.path.any((entry) => identical(entry.target, box));
  }

  static Future<void> _dispatchNativeDropEvent(MethodCall call) async {
    final args = call.arguments;
    if (call.method == 'dropImagesAt') {
      if (args is! Map || args['id'] is! String) return;
      final pending = _pendingDrops.remove(args['id']);
      if (pending != null &&
          identical(pending.$1.widget.onImagesDropped, pending.$2)) {
        await pending.$1._handleNativeDropEvent(
          MethodCall('dropImages', args['paths']),
        );
      }
      return;
    }
    final positioned =
        call.method == 'dragEnteredAt' || call.method == 'dropStartedAt';
    Offset? point;
    if (positioned) {
      if (args is! Map || args['x'] is! num || args['y'] is! num) return;
      point = Offset(
        (args['x'] as num).toDouble(),
        (args['y'] as num).toDouble(),
      );
    }
    final target = _regions.reversed
        .where(
          (region) =>
              point == null ? region._canReceive : region._contains(point),
        )
        .firstOrNull;
    for (final region in List.of(_regions)) {
      final hovering =
          identical(region, target) &&
          (call.method == 'dragEntered' || call.method == 'dragEnteredAt');
      if (region.mounted && region._draggingOver != hovering) {
        region.setState(() => region._draggingOver = hovering);
      }
    }
    if (call.method == 'dropStartedAt') {
      final id = (args as Map)['id'];
      if (target != null && id is String) {
        // Keep the original recipient while AppKit copies into our temporary
        // directory. Changing chats during that work must not retarget a drop.
        _pendingDrops[id] = (target, target.widget.onImagesDropped);
      }
    } else if (call.method == 'dropImages') {
      await target?._handleNativeDropEvent(call);
    }
  }

  Future<void> _handleNativeDropEvent(MethodCall call) async {
    switch (call.method) {
      case 'dragEntered':
        if (widget.enabled && !_draggingOver && mounted) {
          setState(() => _draggingOver = true);
        }
      case 'dragExited':
        if (_draggingOver && mounted) setState(() => _draggingOver = false);
      case 'dropImages':
        if (_draggingOver && mounted) setState(() => _draggingOver = false);
        if (!_canReceive) return;
        final receiver = widget.onImagesDropped;
        final paths = (call.arguments as List<Object?>? ?? const [])
            .whereType<String>()
            .where((path) => path.isNotEmpty && File(path).existsSync())
            .take(10);
        final attachments = await resolveAttachmentListDimensions(
          paths.map(
            (path) => OutgoingAttachment(
              path: path,
              kind: _isGif(path)
                  ? OutgoingAttachmentKind.animation
                  : OutgoingAttachmentKind.photo,
            ),
          ),
        );
        if (_canReceive &&
            identical(widget.onImagesDropped, receiver) &&
            attachments.isNotEmpty) {
          await receiver(attachments);
        }
    }
  }

  bool _isGif(String path) => path.toLowerCase().endsWith('.gif');

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        if (_draggingOver)
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(
                color: AppTheme.brand.withValues(alpha: 0.12),
                child: Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: context.colors.card,
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      border: Border.all(color: AppTheme.brand, width: 2),
                    ),
                    child: AppIcon(
                      HeroAppIcons.image,
                      size: 32,
                      color: AppTheme.brand,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
