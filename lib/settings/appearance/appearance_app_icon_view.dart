part of 'appearance_view.dart';

class AppIconSettingsView extends StatefulWidget {
  const AppIconSettingsView({super.key});

  @override
  State<AppIconSettingsView> createState() => _AppIconSettingsViewState();
}

class _AppIconSettingsViewState extends State<AppIconSettingsView>
    with WidgetsBindingObserver {
  bool _selecting = false;
  bool _changeFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    // A suspended day timer may be late, and the time zone may have changed:
    // recheck today's penguin and reformat the next-change time.
    context.read<AppIconController>().refreshDailyPenguin();
    setState(() {});
  }

  Future<void> _select(AppIconVariant icon) async {
    if (_selecting) return;
    final controller = context.read<AppIconController>();
    if (!controller.supported || controller.loading) return;
    // Retaining the actual applied icon is never a purchase or native change,
    // including an expired paid choice. Other paid choices still use the
    // controller's unchanged entitlement-first verification below.
    if (controller.isCurrent(icon)) return;
    // Today's penguin applies directly. If the UTC day rolls over before it
    // is applied, the old icon stays and the change fails visibly instead of
    // turning into a purchase prompt.
    final freeToday = controller.dailyPenguin == icon;
    setState(() {
      _selecting = true;
      _changeFailed = false;
    });
    try {
      var applied = await controller.setVariant(icon);
      if (!mounted) return;
      if (!applied &&
          !freeToday &&
          icon.requiresSupporter &&
          !controller.activeSupporter) {
        final unlocked = await Navigator.of(context).push<bool>(
          AppPageRoute<bool>(
            pageBuilder: (_, _, _) => MithkaProView(
              service: controller.proService,
              returnOnEntitlement: true,
            ),
          ),
        );
        if (!mounted || unlocked != true) return;
        // The route result is not authority: recheck native state at selection.
        applied = await controller.setVariant(icon);
      }
      if (!applied && mounted) {
        setState(() => _changeFailed = true);
        showToast(context, AppStringKeys.appIconChangeFailed);
      }
    } finally {
      if (mounted) setState(() => _selecting = false);
    }
  }

  // Next 00:00 UTC in the device's time zone, with a localized date and a
  // time that honours the 12/24-hour preference.
  String _nextPenguinText(DateTime next) {
    final local = next.toLocal();
    final use24 = MediaQuery.alwaysUse24HourFormatOf(context);
    String value;
    try {
      final date = DateFormat.MMMd(
        Localizations.maybeLocaleOf(context)?.toLanguageTag(),
      );
      value = (use24 ? date.add_Hm() : date.add_jm()).format(local);
    } catch (_) {
      // An unknown locale must not cost the card its date and time.
      final material = MaterialLocalizations.of(context);
      final time = material.formatTimeOfDay(
        TimeOfDay.fromDateTime(local),
        alwaysUse24HourFormat: use24,
      );
      value = '${material.formatShortMonthDay(local)} $time';
    }
    return AppStrings.t(AppStringKeys.appIconNextPenguin, {'value1': value});
  }

  Widget _heading(String key, String textKey) => Text(
    AppStrings.t(textKey),
    key: ValueKey(key),
    style: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: context.colors.textPrimary,
    ),
  );

  Widget _caption(String key, String textKey) => Text(
    AppStrings.t(textKey),
    key: ValueKey(key),
    style: TextStyle(
      fontSize: 13,
      height: 18 / 13,
      color: context.colors.textSecondary,
    ),
  );

  // Rows hug their tallest actual label; no nested scrollable, implicit
  // MediaQuery padding, fixed two-line reservation, or catalogue-size math.
  Widget _choices(
    AppIconController controller,
    List<AppIconVariant> icons,
    int columns,
    AppIconVariant? freeToday,
  ) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var start = 0; start < icons.length; start += columns) ...[
        if (start != 0) const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var column = 0; column < columns; column++) ...[
              if (column != 0) const SizedBox(width: 12),
              Expanded(
                child: start + column >= icons.length
                    ? const SizedBox.shrink()
                    : _AppIconVariantTile(
                        key: ValueKey(icons[start + column].key),
                        variant: icons[start + column],
                        selected: controller.isCurrent(icons[start + column]),
                        locked: controller.isLocked(icons[start + column]),
                        freeToday: icons[start + column] == freeToday,
                        enabled:
                            controller.supported &&
                            !controller.loading &&
                            !_selecting,
                        horizontal: columns == 1,
                        onTap: () => unawaited(_select(icons[start + column])),
                      ),
              ),
            ],
          ],
        ),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppIconController>();
    final icons = controller.availableVariants;
    final retained = controller.unlistedCurrent;
    // Null for active Supporters and where the 48 are not offered.
    final freeToday = controller.dailyPenguin;
    final c = context.colors;
    final textScale = MediaQuery.textScalerOf(context).scale(13) / 13;
    return SettingsPageScaffold(
      title: AppStrings.t(AppStringKeys.appIconTitle),
      onBack: () => Navigator.of(context).pop(),
      // NavHeader owns the top inset. This is the body's only safe-area owner.
      child: SafeArea(
        top: false,
        child: Stack(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = textScale >= 2.4 || constraints.maxWidth < 220
                    ? 1
                    : constraints.maxWidth < 360 || textScale >= 1.6
                    ? 2
                    : 3;
                final enabled =
                    controller.supported && !controller.loading && !_selecting;
                return ListView(
                  key: const ValueKey('app-icon-scroll'),
                  primary: false,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    if (!controller.supported)
                      SettingsNote(
                        text: AppStrings.t(AppStringKeys.appIconUnsupported),
                      ),
                    // Unknown current IDs use approved generic retention copy
                    // only: no invented name, foreground, or unsupported claim.
                    if (retained != null ||
                        controller.currentVariant == null) ...[
                      _RetainedAppIconStatus(
                        key: ValueKey(
                          'app-icon-current-${controller.currentKey}',
                        ),
                        variant: retained,
                      ),
                      const SizedBox(height: 8),
                    ],
                    _heading(
                      'app-icon-standard-heading',
                      AppStringKeys.appIconFreeHeading,
                    ),
                    const SizedBox(height: 4),
                    _caption(
                      'app-icon-standard-caption',
                      AppStringKeys.appIconFreeCaption,
                    ),
                    const SizedBox(height: 12),
                    _choices(
                      controller,
                      icons.where((icon) => !icon.requiresSupporter).toList(),
                      columns,
                      null,
                    ),
                    if (controller.supported &&
                        controller.supporterAvailable &&
                        icons.any((icon) => icon.requiresSupporter)) ...[
                      const SizedBox(height: 20),
                      _heading(
                        'app-icon-penguin-heading',
                        AppStringKeys.appIconPenguinHeading,
                      ),
                      const SizedBox(height: 4),
                      _caption(
                        'app-icon-penguin-caption',
                        controller.activeSupporter
                            ? AppStringKeys.appIconPenguinSupporterCaption
                            : AppStringKeys.appIconPenguinCaption,
                      ),
                      const SizedBox(height: 12),
                      if (freeToday != null) ...[
                        _FreeTodayCard(
                          key: ValueKey('app-icon-free-today-${freeToday.key}'),
                          variant: freeToday,
                          selected: controller.isCurrent(freeToday),
                          enabled: enabled,
                          nextChange: _nextPenguinText(
                            controller.nextDailyPenguinChange,
                          ),
                          onTap: () => unawaited(_select(freeToday)),
                        ),
                        const SizedBox(height: 16),
                      ],
                      _choices(
                        controller,
                        icons.where((icon) => icon.requiresSupporter).toList(),
                        columns,
                        freeToday,
                      ),
                      SettingsNote(
                        text: AppStrings.t(AppStringKeys.supporterIconAccess),
                      ),
                    ],
                  ],
                );
              },
            ),
            // Keep the established toast and expose the same localized failure
            // as a visible live region with a real semantic rect. Overlaying it
            // changes no list extent, choice geometry, or retained scroll offset.
            if (_changeFailed)
              PositionedDirectional(
                start: 16,
                end: 16,
                bottom: 24,
                child: IgnorePointer(
                  key: const ValueKey('app-icon-failure-pointer-pass-through'),
                  child: Semantics(
                    key: const ValueKey('app-icon-change-failure'),
                    container: true,
                    excludeSemantics: true,
                    liveRegion: true,
                    label: AppStrings.t(AppStringKeys.appIconChangeFailed),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: c.groupedBackground,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        AppStrings.t(AppStringKeys.appIconChangeFailed),
                        style: TextStyle(
                          fontSize: 13,
                          height: 18 / 13,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// A retained identity is status, not an extra choice or an entitlement action.
// The single semantic node preserves heading → actual localized name → note.
class _RetainedAppIconStatus extends StatelessWidget {
  const _RetainedAppIconStatus({super.key, required this.variant});

  final AppIconVariant? variant;

  @override
  Widget build(BuildContext context) {
    final icon = variant;
    final c = context.colors;
    final heading = AppStrings.t(AppStringKeys.appIconCurrentHeading);
    final name = icon == null ? null : AppStrings.t(icon.labelKey);
    final note = AppStrings.t(AppStringKeys.appIconCurrentNote);
    return Semantics(
      key: const ValueKey('app-icon-current-status'),
      container: true,
      excludeSemantics: true,
      label: name == null ? '$heading\n$note' : '$heading\n$name\n$note',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Row(
          children: [
            if (icon != null) ...[
              Image.asset(
                icon.pickerAsset,
                key: const ValueKey('app-icon-current-art'),
                width: 56,
                height: 56,
                cacheWidth: (56 * MediaQuery.devicePixelRatioOf(context))
                    .ceil(),
                fit: BoxFit.contain,
                excludeFromSemantics: true,
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    heading,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                    ),
                  ),
                  if (name != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 13,
                        height: 17 / 13,
                        color: c.textPrimary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    note,
                    style: TextStyle(
                      fontSize: 13,
                      height: 18 / 13,
                      color: c.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// One focusable, pressable app-icon choice: a single semantics node with the
// shared 0.72 press opacity, keyboard activation and focus underline.
class _AppIconChoice extends StatefulWidget {
  const _AppIconChoice({
    required this.semanticsKey,
    required this.pressKey,
    required this.label,
    required this.hint,
    required this.selected,
    required this.enabled,
    required this.onTap,
    required this.builder,
  });

  final Key semanticsKey;
  final Key pressKey;
  final String label;
  final String? hint;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final Widget Function(bool focusHighlight) builder;

  @override
  State<_AppIconChoice> createState() => _AppIconChoiceState();
}

class _AppIconChoiceState extends State<_AppIconChoice> {
  bool _pressed = false;
  bool _focused = false;
  bool _focusHighlight = false;

  void _press(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  void didUpdateWidget(covariant _AppIconChoice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _pressed = false;
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    final target = InterfaceScaleSteps.targetExtent(
      context.watch<ThemeController>().renderedInterfaceScale,
    );
    return Semantics(
      key: widget.semanticsKey,
      container: true,
      excludeSemantics: true,
      button: true,
      enabled: enabled,
      focusable: enabled,
      focused: _focused,
      selected: widget.selected,
      label: widget.label,
      hint: widget.hint,
      onTap: enabled ? widget.onTap : null,
      child: FocusableActionDetector(
        enabled: enabled,
        includeFocusSemantics: false,
        mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onFocusChange: (value) => setState(() => _focused = value),
        onShowFocusHighlight: (value) =>
            setState(() => _focusHighlight = value),
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter, includeRepeats: false):
              ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space, includeRepeats: false):
              ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              if (enabled) widget.onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: enabled ? widget.onTap : null,
          onTapDown: enabled ? (_) => _press(true) : null,
          onTapUp: enabled ? (_) => _press(false) : null,
          onTapCancel: enabled ? () => _press(false) : null,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: target, minHeight: target),
            child: AnimatedOpacity(
              key: widget.pressKey,
              duration: const Duration(milliseconds: 120),
              opacity: _pressed && enabled ? 0.72 : 1,
              child: widget.builder(_focusHighlight),
            ),
          ),
        ),
      ),
    );
  }
}

// A standard icon's opaque Home Screen image, clipped to the icon shape with
// a faint inner edge so Neutral stays visible on a page of its own colour.
class _StandardAppIconImage extends StatelessWidget {
  const _StandardAppIconImage({
    super.key,
    required this.variant,
    required this.size,
  });

  final AppIconVariant variant;
  final double size;

  @override
  Widget build(BuildContext context) {
    // 18pt at the picker's 80pt; the same proportion at any other size.
    final radius = BorderRadius.circular(size * 18 / 80);
    return SizedBox.square(
      dimension: size,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: radius,
              child: Image.asset(
                variant.standardPickerAsset(Theme.of(context).brightness),
                width: size,
                height: size,
                fit: BoxFit.cover,
                filterQuality:
                    variant.freeMotif == AppIconFreeMotif.pixelPenguin
                    ? FilterQuality.none
                    : FilterQuality.medium,
                cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                    .ceil(),
                excludeFromSemantics: true,
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(
                  color: context.colors.textPrimary.withValues(alpha: 0.12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// The 88pt art shared by grid tiles and the Free today card. Standard icons
// draw their real background at 80pt, inset so the selected ring (radius 22)
// keeps a 2pt gap of page colour; penguins keep their background-free art.
class _AppIconArt extends StatelessWidget {
  const _AppIconArt({
    required this.variant,
    required this.selected,
    required this.locked,
    this.badgeBorder,
    this.keyPrefix = 'icon',
  });

  final AppIconVariant variant;
  final bool selected;
  final bool locked;
  final Color? badgeBorder;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final standard = variant.isStandard;
    return SizedBox(
      key: ValueKey('$keyPrefix-art-${variant.key}'),
      width: 88,
      height: 88,
      child: Stack(
        children: [
          if (standard)
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: _StandardAppIconImage(variant: variant, size: 80),
              ),
            )
          else
            Image.asset(
              variant.pickerAsset,
              width: 88,
              height: 88,
              fit: BoxFit.contain,
              // Pixel art stays crisp, as in the other previews.
              filterQuality: variant.freeMotif == AppIconFreeMotif.pixelPenguin
                  ? FilterQuality.none
                  : FilterQuality.medium,
              cacheWidth: (88 * MediaQuery.devicePixelRatioOf(context)).ceil(),
              excludeFromSemantics: true,
            ),
          // Overlay the outline so it never pads, clips, or shrinks the art.
          Positioned.fill(
            child: DecoratedBox(
              key: ValueKey('$keyPrefix-outline-${variant.key}'),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(standard ? 22 : 16),
                border: selected
                    ? Border.all(color: AppTheme.brand, width: 2)
                    : null,
              ),
            ),
          ),
          if (selected || locked)
            PositionedDirectional(
              end: 0,
              bottom: 0,
              child: Container(
                key: ValueKey(
                  selected
                      ? '$keyPrefix-selected-${variant.key}'
                      : '$keyPrefix-locked-${variant.key}',
                ),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: selected
                      ? AppTheme.brand
                      : dark
                      ? const Color(0xFFEDEDED)
                      : const Color(0xFF1A1A1A),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: badgeBorder ?? c.groupedBackground,
                    width: 2,
                  ),
                ),
                alignment: Alignment.center,
                child: AppIcon(
                  selected ? HeroAppIcons.check : HeroAppIcons.lock,
                  size: 13,
                  color: selected || !dark
                      ? Colors.white
                      : const Color(0xFF1A1A1A),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// Marks today's free penguin for non-Supporters. Brand tint, never brand text.
class _FreeTodayPill extends StatelessWidget {
  const _FreeTodayPill({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      constraints: const BoxConstraints(minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.brand.withValues(alpha: dark ? 0.28 : 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        AppStrings.t(AppStringKeys.appIconFreeToday),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          height: 16 / 12,
          fontWeight: FontWeight.w600,
          color: context.colors.textPrimary,
        ),
      ),
    );
  }
}

// Today's free penguin for non-Supporters: one tap target on the same
// selection path as its grid tile. It is never locked.
class _FreeTodayCard extends StatelessWidget {
  const _FreeTodayCard({
    super.key,
    required this.variant,
    required this.selected,
    required this.enabled,
    required this.nextChange,
    required this.onTap,
  });

  final AppIconVariant variant;
  final bool selected;
  final bool enabled;
  final String nextChange;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final name = AppStrings.t(variant.labelKey);
    final description = AppStrings.t(AppStringKeys.supporterIconAccessibility, {
      'value1': AppStrings.t(variant.fullSemanticNameKey),
      'value2': AppStrings.t(
        selected
            ? AppStringKeys.appIconSelectedFreeToday
            : AppStringKeys.appIconFreeToday,
      ),
    });
    return _AppIconChoice(
      semanticsKey: const ValueKey('app-icon-free-today-card'),
      pressKey: const ValueKey('free-today-press'),
      label: '$description\n$nextChange',
      hint: selected ? null : AppStrings.t(AppStringKeys.appIconUseHint),
      selected: selected,
      enabled: enabled,
      onTap: onTap,
      builder: (focusHighlight) => SettingsPanel(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            _AppIconArt(
              variant: variant,
              selected: selected,
              locked: false,
              badgeBorder: c.card,
              keyPrefix: 'free-today',
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _FreeTodayPill(key: ValueKey('free-today-pill')),
                  const SizedBox(height: 6),
                  Text(
                    name,
                    key: const ValueKey('free-today-name'),
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 17,
                      height: 22 / 17,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                      decoration: focusHighlight
                          ? TextDecoration.underline
                          : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    nextChange,
                    key: const ValueKey('free-today-next-change'),
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 13,
                      height: 18 / 13,
                      color: c.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (selected)
                    ConstrainedBox(
                      key: const ValueKey('free-today-selected'),
                      constraints: const BoxConstraints(minHeight: 32),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppIcon(
                            HeroAppIcons.check,
                            size: 16,
                            color: AppTheme.brand,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              AppStrings.t(AppStringKeys.supporterIconSelected),
                              style: TextStyle(
                                fontSize: 15,
                                height: 20 / 15,
                                fontWeight: FontWeight.w600,
                                color: c.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    // The button's shape only: the whole card is the target.
                    DecoratedBox(
                      key: const ValueKey('free-today-use'),
                      decoration: BoxDecoration(
                        color: c.accentButton,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        child: Text(
                          AppStrings.t(AppStringKeys.appIconUse),
                          style: TextStyle(
                            fontSize: 15,
                            height: 20 / 15,
                            fontWeight: FontWeight.w600,
                            color: c.accentButtonText,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppIconVariantTile extends StatelessWidget {
  const _AppIconVariantTile({
    super.key,
    required this.variant,
    required this.selected,
    required this.locked,
    required this.freeToday,
    required this.enabled,
    required this.horizontal,
    required this.onTap,
  });

  final AppIconVariant variant;
  final bool selected;
  final bool locked;
  // Today's penguin for a non-Supporter: never locked, marked Free today.
  final bool freeToday;
  final bool enabled;
  final bool horizontal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final stateKey = selected
        ? freeToday
              ? AppStringKeys.appIconSelectedFreeToday
              : AppStringKeys.supporterIconSelected
        : locked
        ? AppStringKeys.supporterIconRequired
        : freeToday
        ? AppStringKeys.appIconFreeToday
        : AppStringKeys.supporterIconAvailable;
    final art = _AppIconArt(
      variant: variant,
      selected: selected,
      locked: locked,
    );
    // Final copy 699 / design 712: background label at every adaptive width,
    // full motif + background name in semantics; natural wrapping, never ellipsis.
    final semanticNameKey = variant.fullSemanticNameKey;
    final visibleNameKey = variant.pickerLabelKey ?? variant.labelKey;
    final pill = freeToday
        ? _FreeTodayPill(key: ValueKey('icon-free-today-${variant.key}'))
        : null;
    return _AppIconChoice(
      semanticsKey: ValueKey('app-icon-${variant.key}'),
      pressKey: ValueKey('icon-press-${variant.key}'),
      label: AppStrings.t(AppStringKeys.supporterIconAccessibility, {
        'value1': AppStrings.t(semanticNameKey),
        'value2': AppStrings.t(stateKey),
      }),
      hint: locked
          ? AppStrings.t(AppStringKeys.supporterIconLockedHint)
          : freeToday && !selected
          ? AppStrings.t(AppStringKeys.appIconUseHint)
          : null,
      selected: selected,
      enabled: enabled,
      onTap: onTap,
      builder: (focusHighlight) {
        final label = Text(
          AppStrings.t(visibleNameKey),
          key: ValueKey('icon-label-${variant.key}'),
          textAlign: horizontal ? TextAlign.start : TextAlign.center,
          softWrap: true,
          style: TextStyle(
            fontSize: 13,
            height: 17 / 13,
            fontWeight: FontWeight.w400,
            color: c.textPrimary,
            decoration: focusHighlight ? TextDecoration.underline : null,
          ),
        );
        return horizontal
            ? Row(
                children: [
                  art,
                  const SizedBox(width: 12),
                  Expanded(
                    child: pill == null
                        ? label
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [label, const SizedBox(height: 4), pill],
                          ),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  art,
                  const SizedBox(height: 4),
                  label,
                  if (pill != null) ...[const SizedBox(height: 4), pill],
                ],
              );
      },
    );
  }
}
