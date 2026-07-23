//
//  toast.dart
//
//  messenger-style transient toast — a dark rounded pill near the bottom that
//  fades in, holds, fades out, and removes itself. Replaces Material SnackBars
//  app-wide (no Material chrome). Capture the overlay synchronously so it still
//  works when called after an `await` (the originating widget may have unmounted).
//

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

void showToast(
  BuildContext context,
  String message, {
  Duration visibleFor = const Duration(milliseconds: 1400),
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  showToastOverlay(overlay, message.l10n(context), visibleFor: visibleFor);
}

void showToastOverlay(
  OverlayState overlay,
  String message, {
  Duration visibleFor = const Duration(milliseconds: 1400),
}) {
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _Toast(
      message: message,
      visibleFor: visibleFor,
      onClose: () {
        if (entry.mounted) entry.remove();
      },
    ),
  );
  overlay.insert(entry);
}

class _Toast extends StatefulWidget {
  const _Toast({
    required this.message,
    required this.visibleFor,
    required this.onClose,
  });
  final String message;
  final Duration visibleFor;
  final VoidCallback onClose;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    await _c.forward();
    await Future.delayed(widget.visibleFor);
    if (!mounted) return;
    await _c.reverse();
    widget.onClose();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Positioned(
      left: 40,
      right: 40,
      bottom: media.padding.bottom + 96,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _c,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                widget.message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
