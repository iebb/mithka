//
//  message_action_menu_presentation.dart
//
//  Enter/exit motion for the long-press action surfaces — the reaction bar and
//  the action menu. Both used to mount and unmount on the frame the target was
//  set or cleared, so the pair popped into and out of a still transcript. This
//  fades and scales them as one HUD growing out of the pressed message, and
//  keeps the closing surfaces mounted for the whole reverse so the exit is a
//  transition instead of a cut.
//
//  Timing comes from AppMotion so the overlay shares the app's motion language:
//  `emphasized` in (a floating surface arriving), `accelerate` out (content
//  leaving gets out of the way), and reduced motion collapses both phases to an
//  instant state change.
//

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../theme/app_motion.dart';

/// Fades and scales [child] in when [visible] turns true, and plays the same
/// motion in reverse when it turns false.
///
/// The host keeps this mounted across the exit and replays the closing child —
/// its own live state is already cleared by then — until [onExitComplete]
/// reports the reverse has landed. [anchor] is the point the surfaces grow
/// from, in the overlay's coordinate space; null scales about the center.
class MessageActionMenuPresentation extends StatefulWidget {
  const MessageActionMenuPresentation({
    super.key,
    required this.visible,
    required this.onExitComplete,
    required this.child,
    this.anchor,
  });

  @visibleForTesting
  static const rootKey = ValueKey('message-action-menu-presentation');

  /// Scale the surfaces arrive from and leave to. Matches the app's modal
  /// dialog (`AppMotion.dialogTransition`) so the HUD shares one motion
  /// language: a subtle grow out of the pressed message, not a modal takeover.
  @visibleForTesting
  static const surfaceScale = 0.94;

  static Duration enterDuration(BuildContext context) =>
      AppMotion.duration(context, AppMotion.deliberate);

  static Duration exitDuration(BuildContext context) =>
      AppMotion.duration(context, AppMotion.responsive);

  /// The alignment [anchor] maps to inside an overlay of [size]. Exposed so
  /// the growth point is testable without pixels.
  @visibleForTesting
  static Alignment alignmentForAnchor(Offset? anchor, Size size) {
    if (anchor == null || size.isEmpty) return Alignment.center;
    return Alignment(
      ((anchor.dx / size.width) * 2 - 1).clamp(-1.0, 1.0),
      ((anchor.dy / size.height) * 2 - 1).clamp(-1.0, 1.0),
    );
  }

  final bool visible;
  final VoidCallback onExitComplete;
  final Widget child;
  final Offset? anchor;

  @override
  State<MessageActionMenuPresentation> createState() =>
      _MessageActionMenuPresentationState();
}

class _MessageActionMenuPresentationState
    extends State<MessageActionMenuPresentation>
    with SingleTickerProviderStateMixin {
  // Built eagerly in initState: a lazily-constructed controller can first run
  // inside dispose() when a build path never touches it, and createTicker then
  // walks the ancestors of a deactivated element.
  late final AnimationController _controller;
  late final CurvedAnimation _entrance;
  late final Animation<double> _scale;
  bool _pendingInitialPlay = true;

  @override
  void initState() {
    super.initState();
    // Seeded with the default (non-reduced) durations: reading MediaQuery here
    // is illegal inside initState. didChangeDependencies runs before the first
    // frame, corrects them, and only then starts the initial play — so reduced
    // motion applies from frame one instead of being overwritten mid-forward.
    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.deliberate,
      reverseDuration: AppMotion.responsive,
    );
    _entrance = CurvedAnimation(
      parent: _controller,
      curve: AppMotion.emphasized,
      reverseCurve: AppMotion.accelerate,
    );
    _scale = Tween<double>(
      begin: MessageActionMenuPresentation.surfaceScale,
      end: 1,
    ).animate(_entrance);
    _controller.addStatusListener(_onStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The durations read MediaQuery's reduced-motion flag, so re-read them:
    // toggling the setting must reach the next transition rather than the one
    // this controller was constructed with.
    _applyDurations();
    if (!_pendingInitialPlay) return;
    _pendingInitialPlay = false;
    if (widget.visible) {
      _controller.forward();
    } else {
      // Mounted straight into an exit (the host still held a snapshot while
      // the chat switched to multi-select, which unmounts the overlay): there
      // is nothing to play, so release the snapshot immediately instead of
      // leaving a dismiss layer over the transcript forever.
      _reportExitComplete();
    }
  }

  @override
  void didUpdateWidget(MessageActionMenuPresentation oldWidget) {
    super.didUpdateWidget(oldWidget);
    _applyDurations();
    if (widget.visible == oldWidget.visible) return;
    if (widget.visible) {
      // A re-open mid-exit (another message long-pressed while the previous
      // menu was still collapsing) resumes from wherever the reverse got to.
      _controller.forward();
    } else if (_controller.value == 0) {
      // Nothing ever played — reduced motion, or a close before the first
      // frame. reverse() on a dismissed controller reports no status, so end
      // the exit here or the host would hold its snapshot forever.
      _reportExitComplete();
    } else {
      _controller.reverse();
    }
  }

  void _applyDurations() {
    _controller
      ..duration = MessageActionMenuPresentation.enterDuration(context)
      ..reverseDuration = MessageActionMenuPresentation.exitDuration(context);
  }

  void _onStatus(AnimationStatus status) {
    if (widget.visible) return;
    // Dismissed ends an ordinary exit. Completed only matters for a
    // zero-length enter that is already closing: no reverse will ever run.
    if (status == AnimationStatus.dismissed ||
        status == AnimationStatus.completed) {
      _reportExitComplete();
    }
  }

  /// Hands the exit back to the host, which drops its snapshot and unmounts
  /// the overlay. Status listeners normally fire from the ticker phase, where
  /// a setState is legal, but a zero-length transition reports from inside
  /// didUpdateWidget — mid-build — so that case defers to the next frame.
  void _reportExitComplete() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onExitComplete();
      });
      return;
    }
    widget.onExitComplete();
  }

  @override
  void dispose() {
    _controller
      ..removeStatusListener(_onStatus)
      ..dispose();
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      key: MessageActionMenuPresentation.rootKey,
      animation: _controller,
      // Captured once per frame and replayed verbatim while the exit runs, so
      // the closing overlay keeps the exact surfaces — menu grid or expanded
      // picker — it showed at the dismissal frame.
      child: widget.child,
      builder: (context, child) => LayoutBuilder(
        builder: (context, constraints) => IgnorePointer(
          // A collapsing menu is not a menu anymore: its actions target a
          // message the host has already released, so taps fall through to
          // the host's dismiss layer for the rest of the exit.
          ignoring: !widget.visible,
          child: Transform.scale(
            alignment: MessageActionMenuPresentation.alignmentForAnchor(
              widget.anchor,
              constraints.biggest,
            ),
            scale: _scale.value,
            child: FadeTransition(opacity: _entrance, child: child),
          ),
        ),
      ),
    );
  }
}
