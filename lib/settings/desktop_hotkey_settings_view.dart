import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/desktop_content_constraint.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'desktop_hotkey_controller.dart';

class DesktopHotkeySettingsView extends StatefulWidget {
  const DesktopHotkeySettingsView({
    super.key,
    this.controller,
    this.showBackButton = true,
  });

  final DesktopHotkeyController? controller;
  final bool showBackButton;

  @override
  State<DesktopHotkeySettingsView> createState() =>
      _DesktopHotkeySettingsViewState();
}

class _DesktopHotkeySettingsViewState extends State<DesktopHotkeySettingsView> {
  DesktopHotkeyController? _controller;
  Future<DesktopHotkeyController>? _controllerFuture;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? DesktopHotkeyController.maybeShared;
    if (_controller == null) {
      _controllerFuture = SharedPreferences.getInstance().then(
        DesktopHotkeyController.initializeShared,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller != null) return _content(context, controller);
    return FutureBuilder<DesktopHotkeyController>(
      future: _controllerFuture,
      builder: (context, snapshot) {
        final loaded = snapshot.data;
        if (loaded != null) return _content(context, loaded);
        return Scaffold(
          backgroundColor: context.colors.groupedBackground,
          body: Column(
            children: [
              NavHeader(
                title: AppStringKeys.desktopHotkeysTitle,
                onBack: widget.showBackButton && Navigator.of(context).canPop()
                    ? () => Navigator.of(context).pop()
                    : null,
              ),
              const Expanded(child: Center(child: AppActivityIndicator())),
            ],
          ),
        );
      },
    );
  }

  Widget _content(BuildContext context, DesktopHotkeyController controller) {
    final c = context.colors;
    final desktopDense = !kIsWeb && controller.available;
    final theme = context.watch<ThemeController>();
    return Scaffold(
      key: const ValueKey('desktop-hotkey-settings'),
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStringKeys.desktopHotkeysTitle,
            onBack: widget.showBackButton && Navigator.of(context).canPop()
                ? () => Navigator.of(context).pop()
                : null,
          ),
          Expanded(
            child: DesktopContentConstraint(
              maxWidth: 860,
              child: AnimatedBuilder(
                animation: controller,
                builder: (context, _) => ListView(
                  padding: EdgeInsets.fromLTRB(
                    desktopDense ? 16 : 20,
                    desktopDense ? 12 : 18,
                    desktopDense ? 16 : 20,
                    desktopDense ? 20 : 32,
                  ),
                  children: [
                    Text(
                      AppStringKeys.desktopHotkeysDescription.l10n(context),
                      style: TextStyle(
                        color: c.textSecondary,
                        fontSize: desktopDense ? 13 : 15,
                        height: 1.35,
                      ),
                    ),
                    SizedBox(height: desktopDense ? 10 : 16),
                    SettingsCard(
                      children: [
                        for (final (index, action)
                            in DesktopHotkeyAction.values.indexed) ...[
                          if (index != 0) const InsetDivider(leadingInset: 48),
                          _hotkeyRow(
                            context,
                            controller,
                            action,
                            desktopDense: desktopDense,
                          ),
                        ],
                      ],
                    ),
                    SizedBox(height: desktopDense ? 10 : 16),
                    SettingsCard(
                      children: [
                        _resetRow(
                          context,
                          controller,
                          desktopDense: desktopDense,
                        ),
                      ],
                    ),
                    SizedBox(height: desktopDense ? 18 : 26),
                    _sectionLabel(
                      context,
                      AppStringKeys.desktopHotkeysSendSection,
                      desktopDense: desktopDense,
                    ),
                    SizedBox(height: desktopDense ? 6 : 9),
                    SettingsCard(
                      children: [
                        _enterToSendRow(
                          context,
                          theme,
                          desktopDense: desktopDense,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hotkeyRow(
    BuildContext context,
    DesktopHotkeyController controller,
    DesktopHotkeyAction action, {
    required bool desktopDense,
  }) {
    final c = context.colors;
    final gesture = controller.bindingFor(action);
    final titleKey = _actionTitleKey(action);
    return AppInteractiveSurface(
      key: ValueKey('desktop-hotkey-${action.name}'),
      semanticLabel:
          '${titleKey.l10n(context)}: ${gesture.label(platform: controller.platform)}',
      onTap: () => unawaited(_record(context, controller, action)),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: desktopDense ? 40 : 54),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: desktopDense ? 12 : 16,
            vertical: desktopDense ? 7 : 10,
          ),
          child: Row(
            children: [
              AppIcon(
                _actionIcon(action),
                size: desktopDense ? 17 : 21,
                color: c.textSecondary,
              ),
              SizedBox(width: desktopDense ? 10 : 14),
              Expanded(
                child: Text(
                  titleKey.l10n(context),
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: desktopDense ? 14 : 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              SizedBox(width: desktopDense ? 10 : 14),
              _shortcutPill(
                context,
                gesture.label(platform: controller.platform),
                desktopDense: desktopDense,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resetRow(
    BuildContext context,
    DesktopHotkeyController controller, {
    required bool desktopDense,
  }) {
    final c = context.colors;
    return AppInteractiveSurface(
      key: const ValueKey('desktop-hotkeys-reset'),
      semanticLabel: AppStringKeys.desktopHotkeysResetDefaults.l10n(context),
      onTap: controller.resetDefaults,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: desktopDense ? 40 : 54),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: desktopDense ? 12 : 16,
            vertical: desktopDense ? 7 : 10,
          ),
          child: Row(
            children: [
              AppIcon(
                HeroAppIcons.restore,
                size: desktopDense ? 17 : 21,
                color: c.linkBlue,
              ),
              SizedBox(width: desktopDense ? 10 : 14),
              Text(
                AppStringKeys.desktopHotkeysResetDefaults.l10n(context),
                style: TextStyle(
                  color: c.linkBlue,
                  fontSize: desktopDense ? 14 : 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _enterToSendRow(
    BuildContext context,
    ThemeController theme, {
    required bool desktopDense,
  }) {
    final c = context.colors;
    return AppInteractiveSurface(
      key: const ValueKey('desktop-hotkeys-enter-to-send'),
      toggled: theme.enterToSend,
      onTap: () => theme.enterToSend = !theme.enterToSend,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: desktopDense ? 48 : 64),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: desktopDense ? 12 : 16,
            vertical: desktopDense ? 7 : 10,
          ),
          child: Row(
            children: [
              AppIcon(
                HeroAppIcons.reply,
                size: desktopDense ? 17 : 21,
                color: c.textSecondary,
              ),
              SizedBox(width: desktopDense ? 10 : 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStringKeys.generalSendMessageWithEnter.l10n(context),
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: desktopDense ? 14 : 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      (theme.enterToSend
                              ? AppStringKeys.desktopHotkeysEnterSendDetail
                              : AppStringKeys.desktopHotkeysControlEnterDetail)
                          .l10n(context),
                      style: TextStyle(
                        color: c.textTertiary,
                        fontSize: desktopDense ? 12 : 13,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: desktopDense ? 10 : 14),
              ExcludeFocus(
                child: IgnorePointer(
                  child: AppSwitch(
                    value: theme.enterToSend,
                    onChanged: (value) => theme.enterToSend = value,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(
    BuildContext context,
    String key, {
    required bool desktopDense,
  }) => Padding(
    padding: const EdgeInsetsDirectional.only(start: 4),
    child: Text(
      key.l10n(context),
      style: TextStyle(
        color: context.colors.textSecondary,
        fontSize: desktopDense ? 13 : 14,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _shortcutPill(
    BuildContext context,
    String label, {
    required bool desktopDense,
  }) => Container(
    constraints: BoxConstraints(minHeight: desktopDense ? 25 : 30),
    padding: EdgeInsets.symmetric(
      horizontal: desktopDense ? 8 : 10,
      vertical: desktopDense ? 3 : 5,
    ),
    decoration: BoxDecoration(
      color: context.colors.searchFill,
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: context.colors.divider),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: context.colors.textSecondary,
        fontSize: desktopDense ? 12 : 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.15,
      ),
    ),
  );

  Future<void> _record(
    BuildContext context,
    DesktopHotkeyController controller,
    DesktopHotkeyAction action,
  ) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _DesktopHotkeyRecorderDialog(
      controller: controller,
      action: action,
      titleKey: _actionTitleKey(action),
    ),
  );

  String _actionTitleKey(DesktopHotkeyAction action) => switch (action) {
    DesktopHotkeyAction.openSettings => AppStringKeys.desktopHotkeyOpenSettings,
    DesktopHotkeyAction.newChat => AppStringKeys.desktopHotkeyNewChat,
    DesktopHotkeyAction.focusSearch => AppStringKeys.desktopHotkeyFocusSearch,
    DesktopHotkeyAction.screenshot => AppStringKeys.composerScreenshot,
  };

  AppIconData _actionIcon(DesktopHotkeyAction action) => switch (action) {
    DesktopHotkeyAction.openSettings => HeroAppIcons.gear,
    DesktopHotkeyAction.newChat => HeroAppIcons.penToSquare,
    DesktopHotkeyAction.focusSearch => HeroAppIcons.magnifyingGlass,
    DesktopHotkeyAction.screenshot => HeroAppIcons.crop,
  };
}

class _DesktopHotkeyRecorderDialog extends StatefulWidget {
  const _DesktopHotkeyRecorderDialog({
    required this.controller,
    required this.action,
    required this.titleKey,
  });

  final DesktopHotkeyController controller;
  final DesktopHotkeyAction action;
  final String titleKey;

  @override
  State<_DesktopHotkeyRecorderDialog> createState() =>
      _DesktopHotkeyRecorderDialogState();
}

class _DesktopHotkeyRecorderDialogState
    extends State<_DesktopHotkeyRecorderDialog> {
  final FocusNode _focusNode = FocusNode();
  DesktopHotkeyGesture? _candidate;
  String? _errorKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent || event is KeyRepeatEvent) return;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return;
    }
    if (isDesktopHotkeyModifier(event.logicalKey)) return;
    final keyboard = HardwareKeyboard.instance;
    final gesture = DesktopHotkeyGesture(
      key: event.logicalKey,
      control: keyboard.isControlPressed,
      alt: keyboard.isAltPressed,
      shift: keyboard.isShiftPressed,
      meta: keyboard.isMetaPressed,
    );
    setState(() {
      _candidate = gesture;
      _errorKey = switch (widget.controller.assign(widget.action, gesture)) {
        DesktopHotkeyAssignmentResult.assigned => null,
        DesktopHotkeyAssignmentResult.duplicate =>
          AppStringKeys.desktopHotkeysConflict,
        DesktopHotkeyAssignmentResult.invalid =>
          AppStringKeys.desktopHotkeysRequiresModifier,
      };
    });
    if (_errorKey == null) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final candidate = _candidate;
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Material(
            color: c.card,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    AppStringKeys.desktopHotkeysRecordPrompt.l10n(context),
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.titleKey.l10n(context),
                    style: TextStyle(color: c.textSecondary, fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    key: const ValueKey('desktop-hotkey-recorder'),
                    constraints: const BoxConstraints(minHeight: 72),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.searchFill,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _errorKey == null
                            ? c.divider
                            : const Color(0xFFFF3B30),
                      ),
                    ),
                    child: Text(
                      candidate?.label(platform: widget.controller.platform) ??
                          AppStringKeys.desktopHotkeysRecordHint.l10n(context),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: candidate == null
                            ? c.textTertiary
                            : c.textPrimary,
                        fontSize: candidate == null ? 14 : 18,
                        fontWeight: candidate == null
                            ? FontWeight.w400
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                  if (_errorKey != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _errorKey!.l10n(context),
                      style: const TextStyle(
                        color: Color(0xFFFF3B30),
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: AppInteractiveSurface(
                      key: const ValueKey('desktop-hotkey-cancel'),
                      semanticLabel: AppStringKeys.confirmCancel.l10n(context),
                      onTap: () => Navigator.of(context).pop(),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        child: Text(
                          AppStringKeys.confirmCancel.l10n(context),
                          style: TextStyle(
                            color: c.linkBlue,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
