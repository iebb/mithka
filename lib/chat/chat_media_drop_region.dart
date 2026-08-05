import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../components/app_icons.dart';
import '../theme/app_theme.dart';
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
  bool _draggingOver = false;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_handleNativeDropEvent);
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
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
        if (!widget.enabled) return;
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
        if (mounted && attachments.isNotEmpty) {
          await widget.onImagesDropped(attachments);
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
