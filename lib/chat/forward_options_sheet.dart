//
//  forward_options_sheet.dart
//
//  The forward-preview options panel (转发选项), opened by tapping the
//  composer's pending-forward banner. Mirrors the reference client's forward
//  preview menu: hide-sender / remove-caption toggles (independent, with the
//  caption→copy forcing rule), render-markdown, change recipient, apply,
//  cancel.
//
//  The toggles are action-labeled rows (the reference client ToggleButton): the label
//  names the action tapping performs — “Hide sender” while the sender is
//  shown, “Show sender” once hidden — and every tap re-renders both rows
//  immediately, so the coupled caption→sender rule is visible the moment it
//  fires.
//

import 'package:flutter/material.dart';

import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import 'forward_handoff.dart';

/// The result of a session with [ForwardOptionsSheet].
sealed class ForwardOptionsResult {
  const ForwardOptionsResult();
}

/// Keep the forward with its current options.
class ForwardOptionsApply extends ForwardOptionsResult {
  const ForwardOptionsApply();
}

/// Drop the pending forward (banner close equivalent).
class ForwardOptionsCancel extends ForwardOptionsResult {
  const ForwardOptionsCancel();
}

/// Pick a different recipient for the forward.
class ForwardOptionsChangeRecipient extends ForwardOptionsResult {
  const ForwardOptionsChangeRecipient();
}

class ForwardOptionsSheet extends StatefulWidget {
  const ForwardOptionsSheet({super.key, required this.forward});

  final PendingForward forward;

  @override
  State<ForwardOptionsSheet> createState() => _ForwardOptionsSheetState();
}

class _ForwardOptionsSheetState extends State<ForwardOptionsSheet> {
  void _toggle(VoidCallback toggle) {
    setState(toggle);
    // The composer banner below reads the same PendingForward; sync the
    // host so the banner (and later send options) match the sheet.
    ForwardOptionsHost.maybeOf(context)?.onForwardOptionsChanged();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final forward = widget.forward;
    // On desktop/wide-tablet layouts the sheet presents centered with all
    // corners rounded (AppMotion swaps the surface); only the phone
    // bottom-sheet form rounds the top edge.
    final centered = appModalUsesCenteredPresentation(
      MediaQuery.sizeOf(context),
    );
    return Material(
      key: const ValueKey('composerForwardOptionsSheet'),
      color: colors.panelBackground,
      borderRadius: centered
          ? const BorderRadius.all(Radius.circular(AppRadius.xl))
          : const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStringKeys.chatForwardOptionsTitle.l10n(context),
                    style: AppTextStyle.title(
                      colors.textPrimary,
                      weight: AppTextWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            if (forward.canToggleSender)
              _ForwardOptionToggleRow(
                key: const ValueKey('composerForwardOptionSender'),
                icon: forward.removeSender
                    ? HeroAppIcons.user
                    : HeroAppIcons.eyeSlash,
                label:
                    (forward.removeSender
                            ? AppStringKeys.chatForwardShowSender
                            : AppStringKeys.chatForwardRemoveSender)
                        .l10n(context),
                value: forward.removeSender,
                onTap: () => _toggle(forward.toggleSender),
              ),
            if (forward.canToggleCaption && forward.hasCaption)
              _ForwardOptionToggleRow(
                key: const ValueKey('composerForwardOptionCaption'),
                icon: forward.removeCaption
                    ? HeroAppIcons.image
                    : HeroAppIcons.font,
                label:
                    (forward.removeCaption
                            ? AppStringKeys.chatForwardShowCaption
                            : AppStringKeys.chatForwardRemoveCaption)
                        .l10n(context),
                value: forward.removeCaption,
                onTap: () => _toggle(forward.toggleCaption),
              ),
            if (forward.markdownOffer.available)
              _ForwardOptionToggleRow(
                key: const ValueKey('composerForwardOptionMarkdown'),
                icon: HeroAppIcons.code,
                label: AppStringKeys.chatForwardRenderMarkdown.l10n(context),
                value: forward.renderMarkdown,
                onTap: () => _toggle(forward.toggleRenderMarkdown),
              ),
            const SizedBox(height: 6),
            _ForwardOptionMenuRow(
              key: const ValueKey('composerForwardOptionRecipient'),
              icon: HeroAppIcons.forward,
              label: AppStringKeys.chatForwardChangeRecipient.l10n(context),
              onTap: () => Navigator.of(
                context,
              ).pop(const ForwardOptionsChangeRecipient()),
            ),
            const SizedBox(height: 6),
            _ForwardOptionMenuRow(
              key: const ValueKey('composerForwardOptionApply'),
              icon: HeroAppIcons.check,
              label: AppStringKeys.composerReplyOptionApply.l10n(context),
              onTap: () =>
                  Navigator.of(context).pop(const ForwardOptionsApply()),
            ),
            _ForwardOptionMenuRow(
              key: const ValueKey('composerForwardOptionCancel'),
              icon: HeroAppIcons.trash,
              label: AppStringKeys.composerReplyOptionCancel.l10n(context),
              color: AppTheme.tagRed,
              onTap: () =>
                  Navigator.of(context).pop(const ForwardOptionsCancel()),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Center(
                child: Text(
                  AppStringKeys.composerReplyOptionsHint.l10n(context),
                  style: AppTextStyle.body(colors.textTertiary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Notifies the sheet's host (the composer) that toggle state changed, so the
/// banner preview below stays in sync while the sheet is open.
class ForwardOptionsHost extends InheritedWidget {
  const ForwardOptionsHost({
    super.key,
    required this.onForwardOptionsChanged,
    required super.child,
  });

  final VoidCallback onForwardOptionsChanged;

  static ForwardOptionsHost? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ForwardOptionsHost>();

  @override
  bool updateShouldNotify(ForwardOptionsHost oldWidget) =>
      onForwardOptionsChanged != oldWidget.onForwardOptionsChanged;
}

class _ForwardOptionToggleRow extends StatelessWidget {
  const _ForwardOptionToggleRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    super.key,
  });

  final AppIconData icon;
  final String label;
  final bool value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return _ForwardOptionMenuRow(
      icon: icon,
      label: label,
      trailing: AnimatedContainer(
        key: const ValueKey('composerForwardOptionToggleBox'),
        duration: const Duration(milliseconds: 150),
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: value ? colors.linkBlue : colors.searchFill,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: value ? colors.linkBlue : colors.divider,
            width: value ? 0 : 1,
          ),
        ),
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 120),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: animation, child: child),
            ),
            child: value
                ? const AppIcon(
                    HeroAppIcons.check,
                    key: ValueKey('on'),
                    size: 14,
                    color: Colors.white,
                  )
                : const SizedBox.shrink(key: ValueKey('off')),
          ),
        ),
      ),
      onTap: onTap,
    );
  }
}

/// One full-width 48dp menu row: icon, label, optional trailing control.
class _ForwardOptionMenuRow extends StatelessWidget {
  const _ForwardOptionMenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
    this.color,
    super.key,
  });

  final AppIconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppInteractiveSurface(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: SizedBox(
        height: 48,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              AppIcon(icon, size: 19, color: color ?? colors.textSecondary),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyle.bodyLarge(
                    color ?? colors.textPrimary,
                    weight: AppTextWeight.medium,
                  ),
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 10), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}
