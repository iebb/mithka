import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../components/app_icons.dart';
import '../theme/app_theme.dart';

Future<String?> showStoryTextEntry(
  BuildContext context, {
  required String title,
  String hint = '',
  String initial = '',
  TextInputType? keyboardType,
}) async {
  final controller = TextEditingController(text: initial);
  final value = await showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.black.withValues(alpha: 0.52),
    transitionDuration: const Duration(milliseconds: 180),
    transitionBuilder: (context, animation, secondaryAnimation, child) =>
        FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween(begin: 0.96, end: 1.0).animate(animation),
            child: child,
          ),
        ),
    pageBuilder: (dialogContext, _, _) {
      final c = dialogContext.colors;
      return SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Material(
              color: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                  decoration: BoxDecoration(
                    color: c.background,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: c.divider),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x38000000),
                        blurRadius: 24,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        constraints: const BoxConstraints(minHeight: 48),
                        padding: const EdgeInsets.symmetric(horizontal: 13),
                        decoration: BoxDecoration(
                          color: c.searchFill,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: c.divider),
                        ),
                        child: TextField(
                          controller: controller,
                          autofocus: true,
                          keyboardType: keyboardType,
                          style: TextStyle(color: c.textPrimary, fontSize: 16),
                          decoration: InputDecoration(
                            hintText: hint,
                            hintStyle: TextStyle(color: c.textTertiary),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          StoryDialogAction(
                            label: 'Cancel',
                            onTap: () => Navigator.of(dialogContext).pop(),
                          ),
                          const SizedBox(width: 10),
                          StoryDialogAction(
                            label: 'Done',
                            primary: true,
                            onTap: () => Navigator.of(
                              dialogContext,
                            ).pop(controller.text.trim()),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
  controller.dispose();
  return value;
}

class StoryDialogAction extends StatelessWidget {
  const StoryDialogAction({
    super.key,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.destructive = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fill = destructive
        ? AppTheme.tagRed
        : primary
        ? AppTheme.brand
        : c.searchFill;
    final foreground = primary || destructive ? Colors.white : c.textPrimary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 40,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(11),
          border: primary || destructive ? null : Border.all(color: c.divider),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: foreground,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class StoryActivityIndicator extends StatefulWidget {
  const StoryActivityIndicator({super.key, this.size = 30, this.color});

  final double size;
  final Color? color;

  @override
  State<StoryActivityIndicator> createState() => _StoryActivityIndicatorState();
}

class _StoryActivityIndicatorState extends State<StoryActivityIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading',
    child: AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Transform.rotate(
        angle: _controller.value * math.pi * 2,
        child: child,
      ),
      child: AppIcon(
        HeroAppIcons.arrowsRotate,
        size: widget.size,
        color: widget.color ?? AppTheme.brand,
      ),
    ),
  );
}

class StoryProgressBar extends StatefulWidget {
  const StoryProgressBar({super.key});

  @override
  State<StoryProgressBar> createState() => _StoryProgressBarState();
}

class _StoryProgressBarState extends State<StoryProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Working',
    child: ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 4,
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(
                  color: AppTheme.brand.withValues(alpha: 0.16),
                ),
              ),
              AnimatedBuilder(
                animation: _controller,
                builder: (context, child) => Positioned(
                  left: (constraints.maxWidth + 70) * _controller.value - 70,
                  top: 0,
                  bottom: 0,
                  width: 70,
                  child: child!,
                ),
                child: ColoredBox(color: AppTheme.brand),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
