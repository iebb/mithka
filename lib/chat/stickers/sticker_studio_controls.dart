//
//  sticker_studio_controls.dart
//
//  Controls shared by every Sticker Studio surface (studio list, create flow,
//  manage screen, draft editor, mask placement): grouped cards, inline form
//  fields, choice rows, the switch, the value slider, the studio dialog, and
//  the draft preview tile. They are project-owned rather than Material widgets
//  so the editor keeps Mithka's own look on every platform.
//

import 'dart:io';

import 'package:flutter/material.dart';

import '../../components/app_icons.dart';
import '../../theme/app_theme.dart';
import 'sticker_set_management_service.dart';

/// A grouped card: one rounded surface holding rows, the shape iOS uses for
/// sticker-editor forms.
class StickerStudioSection extends StatelessWidget {
  const StickerStudioSection({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: context.colors.card,
      borderRadius: BorderRadius.circular(AppRadius.card),
    ),
    child: Column(children: children),
  );
}

/// A borderless text field inset to line up with studio rows.
Widget stickerStudioField(
  TextEditingController controller,
  String hint, {
  int? maxLength,
  TextInputType? keyboardType,
  ValueChanged<String>? onChanged,
}) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
  child: TextField(
    controller: controller,
    maxLength: maxLength,
    keyboardType: keyboardType,
    onChanged: onChanged,
    decoration: InputDecoration(
      border: InputBorder.none,
      hintText: hint,
      counterText: '',
    ),
  ),
);

/// A selectable row with a title, a supporting detail, and a radio mark.
class StickerStudioChoiceRow extends StatelessWidget {
  const StickerStudioChoiceRow({
    super.key,
    required this.label,
    required this.detail,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: 15, color: colors.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                  ),
                ],
              ),
            ),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? AppTheme.brand : Colors.transparent,
                border: Border.all(
                  color: selected ? AppTheme.brand : colors.textTertiary,
                  width: 1.5,
                ),
              ),
              child: selected
                  ? const Center(
                      child: AppIcon(
                        HeroAppIcons.check,
                        size: 14,
                        color: Colors.white,
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// The studio's own switch (iOS-like pill), never a Material [Switch].
class StickerStudioToggle extends StatelessWidget {
  const StickerStudioToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => onChanged(!value),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      width: 46,
      height: 28,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: value ? AppTheme.brand : context.colors.textTertiary,
        borderRadius: BorderRadius.circular(14),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
            color: Color(0xFFFFFFFF),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 3,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// A labelled value readout with the studio's drag-to-set value track.
class StickerStudioValueRow extends StatelessWidget {
  const StickerStudioValueRow({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: TextStyle(color: colors.textPrimary)),
              ),
              Text(
                value.toStringAsFixed(2),
                style: TextStyle(color: colors.textSecondary),
              ),
            ],
          ),
          StickerStudioValueTrack(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// The studio's value track: a tappable, draggable rail with a brand knob.
class StickerStudioValueTrack extends StatelessWidget {
  const StickerStudioValueTrack({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  void _update(double dx, double width) {
    final fraction = (dx / width).clamp(0.0, 1.0);
    onChanged(min + (max - min) * fraction);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, constraints) {
      final fraction = max == min
          ? 0.0
          : ((value - min) / (max - min)).clamp(0.0, 1.0);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) =>
            _update(details.localPosition.dx, constraints.maxWidth),
        onHorizontalDragUpdate: (details) =>
            _update(details.localPosition.dx, constraints.maxWidth),
        child: SizedBox(
          height: 38,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: 4,
                decoration: BoxDecoration(
                  color: context.colors.textTertiary.withValues(alpha: 0.32),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              FractionallySizedBox(
                widthFactor: fraction,
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.brand,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Positioned(
                left: (constraints.maxWidth - 22) * fraction,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: AppTheme.brand,
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(color: Color(0x33000000), blurRadius: 4),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// The studio's owned dialog surface (no Material [AlertDialog] chrome).
class StickerStudioDialog extends StatelessWidget {
  const StickerStudioDialog({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
  });

  final String title;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.colors.card,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: context.colors.divider, width: 0.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x44000000),
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: DefaultTextStyle(
            style: TextStyle(color: context.colors.textPrimary, fontSize: 15),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
                  child: content,
                ),
                Container(height: 0.5, color: context.colors.divider),
                SizedBox(height: 50, child: Row(children: actions)),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class StickerStudioDialogAction extends StatelessWidget {
  const StickerStudioDialogAction({
    super.key,
    required this.label,
    required this.onTap,
    this.color,
  });

  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: color ?? context.colors.textSecondary,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    ),
  );
}

/// The thumbnail tile for a not-yet-uploaded sticker source. Animated and
/// video sources cannot be decoded from disk here (TGS is gzipped Lottie, WEBM
/// needs a VP9 decoder), so they show their format badge instead.
class StickerDraftPreview extends StatelessWidget {
  const StickerDraftPreview({
    super.key,
    required this.draft,
    required this.size,
  });

  final NewStickerDraft draft;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: context.colors.searchFill,
      borderRadius: BorderRadius.circular(AppRadius.control),
    ),
    child: draft.format == StickerFileFormat.webp
        ? Image.file(
            File(draft.path),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => _fallback(context),
          )
        : _fallback(context),
  );

  Widget _fallback(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIcon(
          draft.format == StickerFileFormat.webm
              ? HeroAppIcons.video
              : HeroAppIcons.wandMagicSparkles,
          size: size * 0.32,
          color: context.colors.textSecondary,
        ),
        Text(
          draft.format.name.toUpperCase(),
          style: TextStyle(
            fontSize: size * 0.14,
            color: context.colors.textSecondary,
          ),
        ),
      ],
    ),
  );
}
