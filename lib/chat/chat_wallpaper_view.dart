import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../components/app_icons.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../media/app_asset_picker.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'chat_appearance_preview.dart';
import 'chat_wallpaper.dart';
import 'chat_wallpaper_color_view.dart';

class ChatWallpaperView extends StatefulWidget {
  const ChatWallpaperView({
    super.key,
    required this.chatId,
    required this.chatTitle,
    this.forDarkTheme = false,
  });

  const ChatWallpaperView.global({
    super.key,
    required this.chatTitle,
    required this.forDarkTheme,
  }) : chatId = null;

  final int? chatId;
  final String chatTitle;
  final bool forDarkTheme;

  bool get isGlobal => chatId == null;

  @override
  State<ChatWallpaperView> createState() => _ChatWallpaperViewState();
}

class _ChatWallpaperViewState extends State<ChatWallpaperView> {
  final _controller = ChatWallpaperController.shared;
  ChatWallpaper? _selection;
  ChatWallpaper? _initialRemote;
  List<ChatWallpaper> _catalogBackgrounds = const [];
  List<ChatWallpaper> _savedBackgrounds = const [];
  late bool _forDarkTheme = widget.forDarkTheme;
  bool _loaded = false;
  bool _saving = false;

  static const _solidPalettes = <int>[
    0xDCE9F4,
    0xE8E1D6,
    0xCDE8DF,
    0xD8D5ED,
    0xF1D6DC,
    0xD7E5C4,
    0x243348,
    0x252527,
  ];

  bool get _isDarkTheme => context.colors.background.computeLuminance() < 0.45;
  bool get _targetDark => widget.isGlobal ? _forDarkTheme : _isDarkTheme;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final selected = _selection;
    if (selected != null) {
      final resolved = _controller.resolvedWallpaper(selected);
      if (resolved != selected) {
        setState(() {
          _selection = resolved;
          if (resolved.kind == ChatWallpaperKind.telegram) {
            _initialRemote = resolved;
          }
        });
        return;
      }
    }
    if (widget.isGlobal) {
      setState(() {
        // Keep the user's pending choice while the controller resolves a
        // Telegram document. The saved default is loaded once in [_load].
      });
      return;
    }
    final current = _controller.wallpaperSelectionFor(widget.chatId!);
    if (_selection?.kind == ChatWallpaperKind.telegram &&
        current?.kind == ChatWallpaperKind.telegram &&
        _selection?.backgroundId == current?.backgroundId) {
      setState(() {
        _selection = current;
        _initialRemote = current;
      });
      return;
    }
    setState(() {});
  }

  Future<void> _load() async {
    final dark = _targetDark;
    if (widget.isGlobal) {
      await _controller.loadGlobalChatThemes();
      await _controller.loadDefaultWallpaper(dark: dark);
      try {
        _catalogBackgrounds = await _controller.installedBackgrounds(
          dark: dark,
        );
      } catch (_) {}
    } else {
      await _controller.load(widget.chatId!);
      try {
        _catalogBackgrounds = await _controller.installedBackgrounds(
          dark: dark,
        );
      } catch (_) {}
    }
    _savedBackgrounds = await _controller.loadSavedBackgrounds();
    if (!mounted) return;
    setState(() {
      _selection = widget.isGlobal
          ? _controller.defaultWallpaper(dark: dark)
          : _controller.wallpaperSelectionFor(widget.chatId!);
      if (_selection?.kind == ChatWallpaperKind.telegram) {
        _initialRemote = _selection;
      }
      _loaded = true;
    });
  }

  Future<void> _pickPhoto() async {
    if (!_allowCustomWallpaper()) return;
    try {
      final picked = await AppAssetPicker.pick(
        context,
        type: AppAssetPickerType.image,
        maxAssets: 1,
      );
      if (!mounted || picked.isEmpty) return;
      setState(() => _selection = ChatWallpaper.image(picked.first.path));
    } catch (_) {
      if (mounted) showToast(context, AppStringKeys.chatWallpaperPickFailed);
    }
  }

  Future<void> _pickColor() async {
    if (!_allowCustomWallpaper()) return;
    final previous = _selection;
    final selected = await Navigator.of(context).push<ChatWallpaper>(
      PageRouteBuilder<ChatWallpaper>(
        pageBuilder: (_, _, _) => ChatWallpaperColorView(
          controller: _controller,
          dark: _targetDark,
          initial: previous,
          colorOnly: true,
        ),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
    if (!mounted || selected == null) return;
    setState(() {
      _selection = previous?.remoteType == 'pattern'
          ? previous!
                .withColors(selected.colors)
                .withRotationAngle(selected.rotationAngle)
          : selected;
    });
  }

  bool _allowCustomWallpaper() {
    if (widget.isGlobal || !_controller.isBoostedChat(widget.chatId!)) {
      return true;
    }
    final access = _controller.accessFor(
      widget.chatId!,
      const ChatWallpaper.telegram(backgroundId: 0, remoteType: 'wallpaper'),
    );
    if (access.allowed) return true;
    showToast(
      context,
      context.l10n.t(AppStringKeys.chatWallpaperBoostRequired, {
        'value1': access.requiredLevel,
      }),
    );
    return false;
  }

  Future<void> _apply({required bool onlyForSelf}) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final value = _selection;
      if (widget.isGlobal) {
        await _controller.applyDefaultWallpaper(value, dark: _targetDark);
      } else {
        await _controller.applyWallpaper(
          widget.chatId!,
          value,
          onlyForSelf: onlyForSelf,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showToast(context, AppStringKeys.chatWallpaperSaveFailed);
    }
  }

  Future<void> _switchBrightness(bool dark) async {
    if (!widget.isGlobal || _forDarkTheme == dark || _saving) return;
    setState(() {
      _forDarkTheme = dark;
      _selection = null;
      _initialRemote = null;
      _catalogBackgrounds = const [];
      _loaded = false;
    });
    await _load();
  }

  Widget _brightnessPicker() {
    final c = context.colors;
    return Container(
      key: const ValueKey('global-wallpaper-brightness-picker'),
      height: 40,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: c.panelBackground,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _brightnessButton(
              dark: false,
              icon: HeroAppIcons.sun,
              label: AppStringKeys.globalThemeDay,
            ),
          ),
          Expanded(
            child: _brightnessButton(
              dark: true,
              icon: HeroAppIcons.moon,
              label: AppStringKeys.globalThemeNight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _brightnessButton({
    required bool dark,
    required AppIconData icon,
    required String label,
  }) {
    final c = context.colors;
    final selected = dark == _forDarkTheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _switchBrightness(dark),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: selected
              ? c.linkBlue.withValues(alpha: 0.15)
              : const Color(0x00000000),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppIcon(
              icon,
              size: 17,
              color: selected ? c.linkBlue : c.textTertiary,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label.l10n(context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? c.linkBlue : c.textSecondary,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ColoredBox(
      color: c.groupedBackground,
      child: Column(
        children: [
          NavHeader(
            title: AppStringKeys.chatWallpaperTitle,
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: _loaded
                ? SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.isGlobal) ...[
                          _brightnessPicker(),
                          const SizedBox(height: 12),
                        ],
                        _preview(),
                        const SizedBox(height: 12),
                        _senderNameReadabilityOption(),
                        const SizedBox(height: 18),
                        _customizeBlock(),
                        const SizedBox(height: 18),
                        Text(
                          AppStringKeys.chatWallpaperChoose.l10n(context),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: c.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _choices(),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          _applyBar(),
        ],
      ),
    );
  }

  Widget _preview() {
    final dark = _targetDark;
    final colors = _previewColors;
    final appearance = context.watch<ThemeController>();
    final targetColors =
        appearance
            .cloudThemeFor(dark ? Brightness.dark : Brightness.light)
            ?.uiColors ??
        (dark ? AppColors.dark : AppColors.light);
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: 270,
        child: ChatWallpaperBackground(
          wallpaper: _effectiveWallpaper,
          fallbackColor: targetColors.chatBackground,
          brightness: dark ? Brightness.dark : Brightness.light,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 24, 14, 18),
            child: Column(
              children: [
                ChatAppearancePreview(
                  incomingBubbleColor: colors.incomingBubble,
                  incomingTextColor: colors.incomingText,
                  outgoingBubbleColor: colors.outgoingBubble,
                  outgoingTextColor: colors.outgoingText,
                  incomingNameColor: colors.incomingName,
                  outgoingNameColor: colors.outgoingName,
                  incomingMessage: AppStringKeys.chatWallpaperPreviewIncoming
                      .l10n(context),
                  outgoingMessage: AppStringKeys.chatWallpaperPreviewOutgoing
                      .l10n(context),
                  showSenderNamePlate:
                      appearance.showSenderNameReadabilityPlate,
                ),
                const Spacer(),
                Text(
                  widget.chatTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xEFFFFFFF),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(color: Color(0x66000000), blurRadius: 6)],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  ({
    Color incomingBubble,
    Color incomingText,
    Color outgoingBubble,
    Color outgoingText,
    Color incomingName,
    Color outgoingName,
  })
  get _previewColors {
    final dark = _targetDark;
    final globalTheme = context.watch<ThemeController>().cloudThemeFor(
      dark ? Brightness.dark : Brightness.light,
    );
    final c =
        globalTheme?.uiColors ?? (dark ? AppColors.dark : AppColors.light);
    final activeTheme = widget.isGlobal
        ? null
        : _controller.themeSelectionFor(widget.chatId!);
    final themeStyle = widget.isGlobal
        ? globalTheme == null &&
                  _controller.hasExplicitGlobalThemeSelection(dark: dark)
              ? _controller.globalThemeStyleFor(dark: dark)
              : null
        : activeTheme == null
        ? null
        : _controller.styleForTheme(
            activeTheme.themeName ?? '',
            kind: activeTheme.themeKind,
            dark: dark,
          );
    final incomingBubble =
        themeStyle?.incomingColor ??
        globalTheme?.incomingColor ??
        c.bubbleIncoming;
    final outgoingBubble =
        themeStyle?.outgoingColor ?? globalTheme?.outgoingColor ?? c.linkBlue;
    return (
      incomingBubble: incomingBubble,
      incomingText:
          themeStyle?.incomingTextColor ??
          globalTheme?.incomingTextColor ??
          c.bubbleIncomingText,
      outgoingBubble: outgoingBubble,
      outgoingText:
          themeStyle?.outgoingTextColor ??
          globalTheme?.outgoingTextColor ??
          readableForeground(outgoingBubble),
      incomingName:
          themeStyle?.nameColor ?? globalTheme?.accentColor ?? c.linkBlue,
      outgoingName:
          themeStyle?.nameColor ?? globalTheme?.accentColor ?? c.linkBlue,
    );
  }

  Widget _senderNameReadabilityOption() {
    final c = context.colors;
    final appearance = context.watch<ThemeController>();
    final enabled = appearance.showSenderNameReadabilityPlate;
    void update(bool value) {
      appearance.showSenderNameReadabilityPlate = value;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => update(!enabled),
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            AppIcon(HeroAppIcons.idBadge, size: 19, color: c.linkBlue),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                AppStringKeys.appearanceSenderNameBackground.l10n(context),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: c.textPrimary),
              ),
            ),
            const SizedBox(width: 10),
            AppSwitch(value: enabled, onChanged: update),
          ],
        ),
      ),
    );
  }

  Widget _backgroundPaletteChoices() {
    final patterns = _patternCandidates;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _choiceSection(
          AppStringKeys.chatWallpaperColor,
          (width) => [
            for (final color in _solidPalettes) _solidChoice(width, color),
            _colorChoice(width),
          ],
        ),
        const SizedBox(height: 18),
        _choiceSection(
          AppStringKeys.chatWallpaperGradient,
          (width) => [
            for (final preset in chatWallpaperPresets)
              _gradientChoice(width, preset),
          ],
        ),
        const SizedBox(height: 18),
        _choiceSection(
          AppStringKeys.chatWallpaperPattern,
          (width) => [
            _noPatternChoice(width),
            for (final pattern in patterns)
              _patternSelectorChoice(width, pattern),
          ],
        ),
      ],
    );
  }

  Widget _customizeBlock() {
    final c = context.colors;
    final value = _effectiveWallpaper;
    final hasColorCustomization = wallpaperSupportsColorCustomization(value);
    final hasEffects =
        value?.supportsBlur == true ||
        value?.supportsMotion == true ||
        value?.supportsIntensity == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          AppStringKeys.chatWallpaperSectionCustomize.l10n(context),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: c.textTertiary,
          ),
        ),
        if (hasColorCustomization) ...[
          const SizedBox(height: 9),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _pickColor,
            child: Container(
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  AppIcon(HeroAppIcons.palette, size: 19, color: c.linkBlue),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      AppStringKeys.chatWallpaperColor.l10n(context),
                      style: TextStyle(fontSize: 14, color: c.textPrimary),
                    ),
                  ),
                  for (final color in _activePalette.take(4)) ...[
                    Container(
                      width: 18,
                      height: 18,
                      margin: const EdgeInsets.only(left: 4),
                      decoration: BoxDecoration(
                        color: Color(0xFF000000 | color),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0x33000000)),
                      ),
                    ),
                  ],
                  const SizedBox(width: 7),
                  AppIcon(
                    HeroAppIcons.chevronRight,
                    size: 15,
                    color: c.textTertiary,
                  ),
                ],
              ),
            ),
          ),
        ],
        if (hasEffects) ...[
          SizedBox(height: hasColorCustomization ? 8 : 9),
          _effects(),
        ],
      ],
    );
  }

  List<ChatWallpaper> get _patternCandidates {
    final values = <ChatWallpaper>[
      if (_initialRemote?.remoteType == 'pattern') _initialRemote!,
      for (final candidate in _officialThemeWallpaperCandidates)
        if (candidate.wallpaper.remoteType == 'pattern') candidate.wallpaper,
      for (final wallpaper in _catalogBackgrounds)
        if (wallpaper.remoteType == 'pattern') wallpaper,
    ];
    final seen = <String>{};
    return [
      for (final wallpaper in values)
        if (seen.add(
          '${wallpaper.backgroundId}:${wallpaper.fileId}:${wallpaper.imagePath}',
        ))
          wallpaper,
    ];
  }

  List<int> get _activePalette {
    final selection = _selection;
    if (selection?.kind == ChatWallpaperKind.preset) {
      final preset = chatWallpaperPreset(selection?.presetId ?? '');
      if (preset != null) {
        return preset.colors
            .map((color) => color.toARGB32() & 0x00FFFFFF)
            .toList(growable: false);
      }
    }
    if (selection?.colors.isNotEmpty == true) return selection!.colors;
    final effective = _effectiveWallpaper;
    if (effective?.colors.isNotEmpty == true) return effective!.colors;
    return [_targetDark ? 0x243348 : 0xDCE9F4];
  }

  int get _activeRotationAngle => _selection?.rotationAngle ?? 0;

  bool _paletteMatches(List<int> colors) => listEquals(_activePalette, colors);

  void _selectPalette(List<int> colors, {int rotationAngle = 0}) {
    if (!_allowCustomWallpaper()) return;
    final value = _selection;
    setState(() {
      _selection = value?.remoteType == 'pattern'
          ? value!.withColors(colors).withRotationAngle(rotationAngle)
          : ChatWallpaper.telegram(
              backgroundId: 0,
              remoteType: 'fill',
              colors: colors,
              rotationAngle: rotationAngle,
            );
    });
  }

  void _selectPattern(ChatWallpaper? pattern) {
    if (!_allowCustomWallpaper()) return;
    final palette = _activePalette;
    final rotation = _activeRotationAngle;
    setState(() {
      _selection = pattern == null
          ? ChatWallpaper.telegram(
              backgroundId: 0,
              remoteType: 'fill',
              colors: palette,
              rotationAngle: rotation,
            )
          : _controller
                .resolvedWallpaper(pattern)
                .withColors(palette)
                .withRotationAngle(rotation);
    });
  }

  Widget _solidChoice(double width, int color) {
    final foreground = readableForeground(Color(0xFF000000 | color));
    return _choiceFrame(
      width: width,
      selected: _paletteMatches([color]),
      onTap: () => _selectPalette([color]),
      access: _customWallpaperAccess(),
      child: ColoredBox(
        color: Color(0xFF000000 | color),
        child: Center(
          child: AppIcon(HeroAppIcons.circle, size: 18, color: foreground),
        ),
      ),
    );
  }

  Widget _gradientChoice(double width, ChatWallpaperPreset preset) {
    final colors = preset.colors
        .map((color) => color.toARGB32() & 0x00FFFFFF)
        .toList(growable: false);
    return _choiceFrame(
      width: width,
      selected: _paletteMatches(colors),
      onTap: () => _selectPalette(colors),
      access: _customWallpaperAccess(),
      child: ChatWallpaperBackground(
        wallpaper: ChatWallpaper.telegram(
          backgroundId: 0,
          remoteType: 'fill',
          colors: colors,
        ),
        fallbackColor: preset.colors.first,
        brightness: _targetDark ? Brightness.dark : Brightness.light,
      ),
    );
  }

  Widget _noPatternChoice(double width) {
    final colors = _activePalette;
    return _choiceFrame(
      width: width,
      selected: _selection?.remoteType != 'pattern',
      onTap: () => _selectPattern(null),
      access: _customWallpaperAccess(),
      child: ChatWallpaperBackground(
        wallpaper: ChatWallpaper.telegram(
          backgroundId: 0,
          remoteType: 'fill',
          colors: colors,
          rotationAngle: _activeRotationAngle,
        ),
        fallbackColor: context.colors.chatBackground,
        brightness: _targetDark ? Brightness.dark : Brightness.light,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                HeroAppIcons.circleXmark,
                size: 24,
                color: context.colors.textSecondary,
              ),
              const SizedBox(height: 6),
              Text(
                AppStringKeys.groupAppearanceNone.l10n(context),
                style: TextStyle(
                  fontSize: 11,
                  color: context.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _patternSelectorChoice(double width, ChatWallpaper pattern) {
    final resolved = _controller
        .resolvedWallpaper(pattern)
        .withColors(_activePalette)
        .withRotationAngle(_activeRotationAngle);
    return _choiceFrame(
      width: width,
      selected:
          _selection?.remoteType == 'pattern' &&
          _selection?.backgroundId == pattern.backgroundId,
      onTap: () => _selectPattern(pattern),
      access: _customWallpaperAccess(),
      child: ChatWallpaperBackground(
        wallpaper: resolved,
        fallbackColor: context.colors.chatBackground,
        brightness: _targetDark ? Brightness.dark : Brightness.light,
      ),
    );
  }

  Widget _choices() {
    final community = _communityWallpaperCandidates;
    final officialThemes = _officialThemeWallpaperCandidates;
    final officialThemeWallpapers = officialThemes
        .where((candidate) => candidate.wallpaper.remoteType != 'pattern')
        .toList(growable: false);
    // Telegram iOS shows the complete installed catalog rather than an
    // arbitrary first page. TDLib already provides the account's included
    // wallpapers and patterns in their server order.
    final catalog = _catalogBackgrounds;
    final catalogOfficial = catalog
        .where((wallpaper) => wallpaper.remoteType == 'wallpaper')
        .toList(growable: false);
    final currentOfficial = _initialRemote?.remoteType == 'wallpaper'
        ? _initialRemote
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_themeDefaultWallpaper != null) ...[
          _choiceSection(
            AppStringKeys.chatWallpaperCurrentTheme,
            (width) => [_defaultChoice(width)],
          ),
          const SizedBox(height: 20),
        ],
        if (_savedBackgrounds.isNotEmpty) ...[
          _choiceSection(
            AppStringKeys.chatWallpaperSectionSaved,
            (width) => [
              for (final wallpaper in _savedBackgrounds)
                _savedWallpaperChoice(width, wallpaper),
            ],
          ),
          const SizedBox(height: 20),
        ],
        _backgroundPaletteChoices(),
        if (community.isNotEmpty) ...[
          const SizedBox(height: 20),
          _choiceSection(
            AppStringKeys.chatWallpaperSectionCommunity,
            (width) => [
              for (final candidate in community)
                _themeWallpaperChoice(width, candidate),
            ],
          ),
        ],
        const SizedBox(height: 20),
        _choiceSection(
          AppStringKeys.chatWallpaperSectionOfficial,
          (width) => [
            _photoChoice(width),
            if (currentOfficial != null) _remoteChoice(width, currentOfficial),
            for (final candidate in officialThemeWallpapers)
              _themeWallpaperChoice(width, candidate),
            for (final wallpaper in catalogOfficial)
              _remoteCatalogChoice(width, wallpaper),
          ],
        ),
      ],
    );
  }

  Widget _choiceSection(
    String title,
    List<Widget> Function(double width) choices,
  ) {
    final c = context.colors;
    final items = choices(88);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title.l10n(context),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: c.textTertiary,
          ),
        ),
        const SizedBox(height: 9),
        SizedBox(
          height: 132,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) => items[index],
          ),
        ),
      ],
    );
  }

  Widget _defaultChoice(double width) {
    final c = context.colors;
    final selected = _selection == null;
    final wallpaper = _themeDefaultWallpaper;
    final compactWallpaper = wallpaper == null
        ? null
        : _controller.resolvedWallpaper(wallpaper);
    return _choiceFrame(
      width: width,
      selected: selected,
      onTap: () => setState(() => _selection = null),
      child: ChatWallpaperBackground(
        wallpaper: compactWallpaper,
        fallbackColor: c.chatBackground,
        brightness: _targetDark ? Brightness.dark : Brightness.light,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                HeroAppIcons.circleXmark,
                size: 25,
                color: c.textSecondary,
              ),
              const SizedBox(height: 6),
              Text(
                AppStringKeys.chatWallpaperDefault.l10n(context),
                style: TextStyle(fontSize: 12, color: c.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  ChatWallpaper? get _themeDefaultWallpaper {
    final dark = _targetDark;
    final customThemeWallpaper = context
        .watch<ThemeController>()
        .cloudThemeFor(dark ? Brightness.dark : Brightness.light)
        ?.wallpaper;
    return effectiveThemeWallpaperForPicker(
      controller: _controller,
      dark: dark,
      cloudThemeWallpaper: customThemeWallpaper,
    );
  }

  ChatWallpaper? get _effectiveWallpaper =>
      _selection ?? _themeDefaultWallpaper;

  List<_WallpaperCandidate> get _officialThemeWallpaperCandidates {
    if (!widget.isGlobal) return const [];
    final candidates = <_WallpaperCandidate>[];
    final seen = <String>{};
    for (final option in _controller.globalThemeOptions(
      dark: _targetDark,
      resolvePatterns: true,
    )) {
      final wallpaper = option.wallpaper;
      if (wallpaper == null) continue;
      final key = _wallpaperCandidateKey(wallpaper);
      if (seen.add(key)) {
        candidates.add(
          _WallpaperCandidate(
            title: option.label,
            wallpaper: wallpaper,
            emoji: option.emoji,
          ),
        );
      }
    }
    return candidates;
  }

  List<_WallpaperCandidate> get _communityWallpaperCandidates {
    final candidates = <_WallpaperCandidate>[];
    final seen = <String>{};
    for (final theme in context.watch<ThemeController>().installedCloudThemes) {
      final wallpaper = theme.wallpaper;
      if (wallpaper == null) continue;
      final resolved = _controller.resolvedWallpaper(wallpaper);
      final key = _wallpaperCandidateKey(resolved);
      if (seen.add(key)) {
        candidates.add(
          _WallpaperCandidate(title: theme.displayTitle, wallpaper: resolved),
        );
      }
    }
    return candidates;
  }

  String _wallpaperCandidateKey(ChatWallpaper wallpaper) =>
      '${wallpaper.kind.name}:${wallpaper.backgroundId}:'
      '${wallpaper.imagePath}:${wallpaper.colors.join(',')}:'
      '${wallpaper.rotationAngle}:${wallpaper.intensity}';

  Widget _themeWallpaperChoice(double width, _WallpaperCandidate candidate) {
    final wallpaper = candidate.wallpaper;
    final selected = _selection == wallpaper;
    final compactWallpaper = wallpaper.remoteType == 'pattern'
        ? _controller.resolvedWallpaper(wallpaper)
        : wallpaper;
    final emoji = candidate.emoji;
    return _choiceFrame(
      width: width,
      selected: selected,
      onTap: () => setState(() => _selection = wallpaper),
      child: ChatWallpaperBackground(
        // Telegram iOS fills each pattern tile with its actual document. File
        // preparation is cached by the controller, so rebuilds reuse it.
        wallpaper: compactWallpaper,
        fallbackColor: context.colors.chatBackground,
        brightness: _targetDark ? Brightness.dark : Brightness.light,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (emoji != null)
              Center(
                child: Text(
                  emoji,
                  style: const TextStyle(
                    fontSize: 27,
                    shadows: [Shadow(color: Color(0x66000000), blurRadius: 6)],
                  ),
                ),
              ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                color: const Color(0x66000000),
                child: Text(
                  candidate.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFFFFFFF),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photoChoice(double width) {
    final c = context.colors;
    final selected = _selection?.kind == ChatWallpaperKind.image;
    final path = selected ? _selection?.imagePath : null;
    return _choiceFrame(
      width: width,
      selected: selected,
      onTap: _pickPhoto,
      access: _customWallpaperAccess(),
      child: path != null && File(path).existsSync()
          ? Stack(
              fit: StackFit.expand,
              children: [
                Image.file(File(path), fit: BoxFit.cover),
                const ColoredBox(color: Color(0x28000000)),
                const Center(
                  child: AppIcon(
                    HeroAppIcons.image,
                    size: 27,
                    color: Color(0xFFFFFFFF),
                  ),
                ),
              ],
            )
          : ColoredBox(
              color: c.panelBackground,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIcon(HeroAppIcons.image, size: 25, color: c.linkBlue),
                    const SizedBox(height: 6),
                    Text(
                      AppStringKeys.chatWallpaperPhoto.l10n(context),
                      style: TextStyle(fontSize: 12, color: c.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _colorChoice(double width) {
    return _choiceFrame(
      width: width,
      selected: false,
      onTap: _pickColor,
      access: _customWallpaperAccess(),
      child: ChatWallpaperBackground(
        wallpaper: ChatWallpaper.telegram(
          backgroundId: 0,
          remoteType: 'fill',
          colors: _activePalette,
          rotationAngle: _activeRotationAngle,
        ),
        fallbackColor: context.colors.chatBackground,
        brightness: _targetDark ? Brightness.dark : Brightness.light,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppIcon(
                HeroAppIcons.palette,
                size: 25,
                color: Color(0xFFFFFFFF),
              ),
              const SizedBox(height: 6),
              Text(
                AppStringKeys.chatWallpaperColor.l10n(context),
                style: const TextStyle(fontSize: 12, color: Color(0xFFFFFFFF)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _remoteChoice(double width, ChatWallpaper wallpaper) {
    final selected = _selection == wallpaper;
    final compactWallpaper = wallpaper.remoteType == 'pattern'
        ? _controller.resolvedWallpaper(wallpaper)
        : wallpaper;
    return _choiceFrame(
      width: width,
      selected: selected,
      onTap: () => setState(() => _selection = wallpaper),
      child: ChatWallpaperBackground(
        wallpaper: compactWallpaper,
        fallbackColor: context.colors.chatBackground,
        brightness: _targetDark ? Brightness.dark : Brightness.light,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 5),
                color: const Color(0x66000000),
                child: Text(
                  AppStringKeys.chatWallpaperTelegramCurrent.l10n(context),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFFFFFFF),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _remoteCatalogChoice(double width, ChatWallpaper wallpaper) {
    final resolved = _selection?.backgroundId == wallpaper.backgroundId
        ? _selection ?? wallpaper
        : _controller.resolvedWallpaper(wallpaper);
    final compactWallpaper = wallpaper.remoteType == 'pattern'
        ? _controller.resolvedWallpaper(wallpaper)
        : resolved;
    return _choiceFrame(
      width: width,
      selected:
          _selection?.kind == ChatWallpaperKind.telegram &&
          _selection?.backgroundId == wallpaper.backgroundId,
      onTap: () =>
          setState(() => _selection = _controller.resolvedWallpaper(wallpaper)),
      access: _customWallpaperAccess(),
      child: ChatWallpaperBackground(
        wallpaper: compactWallpaper,
        fallbackColor: context.colors.chatBackground,
        brightness: _targetDark ? Brightness.dark : Brightness.light,
      ),
    );
  }

  Widget _savedWallpaperChoice(double width, ChatWallpaper wallpaper) {
    if (wallpaper.kind == ChatWallpaperKind.preset) {
      final preset = chatWallpaperPreset(wallpaper.presetId ?? '');
      return preset == null
          ? const SizedBox.shrink()
          : _presetChoice(width, preset);
    }
    if (wallpaper.kind == ChatWallpaperKind.telegram) {
      return _remoteCatalogChoice(width, wallpaper);
    }
    final selected = _selection == wallpaper;
    return _choiceFrame(
      width: width,
      selected: selected,
      onTap: () => setState(() => _selection = wallpaper),
      child: ChatWallpaperBackground(
        wallpaper: wallpaper,
        fallbackColor: context.colors.chatBackground,
        brightness: _targetDark ? Brightness.dark : Brightness.light,
      ),
    );
  }

  Widget _presetChoice(double width, ChatWallpaperPreset preset) {
    final selected =
        _selection?.kind == ChatWallpaperKind.preset &&
        _selection?.presetId == preset.id;
    return _choiceFrame(
      width: width,
      selected: selected,
      onTap: () => setState(() => _selection = ChatWallpaper.preset(preset.id)),
      access: _customWallpaperAccess(),
      child: ChatWallpaperBackground(
        wallpaper: ChatWallpaper.preset(preset.id),
        fallbackColor: preset.colors.first,
        brightness: _targetDark ? Brightness.dark : Brightness.light,
      ),
    );
  }

  Widget _choiceFrame({
    required double width,
    required bool selected,
    required VoidCallback onTap,
    required Widget child,
    ChatWallpaperBoostAccess? access,
  }) {
    final c = context.colors;
    final locked = access != null && !access.allowed;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: locked
          ? () => showToast(
              context,
              context.l10n.t(AppStringKeys.chatWallpaperBoostRequired, {
                'value1': access.requiredLevel,
              }),
            )
          : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: width,
        height: width * 1.5,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: c.card,
          border: Border.all(
            color: selected ? c.linkBlue : c.divider,
            width: selected ? 3 : 1,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Stack(
            fit: StackFit.expand,
            children: [
              child,
              if (locked)
                ColoredBox(
                  color: const Color(0x73000000),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xC57D4DE8),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const AppIcon(
                            HeroAppIcons.lock,
                            size: 12,
                            color: Color(0xFFFFFFFF),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            context.l10n.t(
                              AppStringKeys.chatWallpaperBoostLevel,
                              {'value1': access.requiredLevel},
                            ),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFFFFFFF),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  ChatWallpaperBoostAccess? _customWallpaperAccess() {
    if (widget.isGlobal || !_controller.isBoostedChat(widget.chatId!)) {
      return null;
    }
    return _controller.accessFor(
      widget.chatId!,
      const ChatWallpaper.telegram(backgroundId: 0, remoteType: 'wallpaper'),
    );
  }

  Widget _effects() {
    final value = _effectiveWallpaper;
    if (value == null) return const SizedBox.shrink();
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              if (value.supportsBlur)
                Expanded(
                  child: _effectButton(
                    AppStringKeys.chatWallpaperBlur,
                    HeroAppIcons.droplet,
                    value.isBlurred,
                    () => setState(
                      () => _selection = value.withBlurred(!value.isBlurred),
                    ),
                  ),
                ),
              if (value.supportsBlur && value.supportsMotion)
                const SizedBox(width: 8),
              if (value.supportsMotion)
                Expanded(
                  child: _effectButton(
                    AppStringKeys.chatWallpaperMotion,
                    HeroAppIcons.rotate,
                    value.isMoving,
                    () => setState(
                      () => _selection = value.withMoving(!value.isMoving),
                    ),
                  ),
                ),
            ],
          ),
          if (value.supportsIntensity) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  AppStringKeys.chatWallpaperIntensity.l10n(context),
                  style: TextStyle(fontSize: 13, color: c.textSecondary),
                ),
                const SizedBox(width: 12),
                Expanded(child: _intensitySlider(value)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 34,
                  child: Text(
                    '${value.intensity}%',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 12, color: c.textTertiary),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _effectButton(
    String key,
    AppIconData icon,
    bool active,
    VoidCallback onTap,
  ) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? c.linkBlue.withValues(alpha: 0.14) : c.searchFill,
          border: Border.all(color: active ? c.linkBlue : c.divider),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppIcon(
              icon,
              size: 17,
              color: active ? c.linkBlue : c.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              key.l10n(context),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: active ? c.linkBlue : c.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _intensitySlider(ChatWallpaper value) {
    final c = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        void update(Offset position) {
          final next = (position.dx / constraints.maxWidth).clamp(0.0, 1.0);
          setState(
            () => _selection = value.withIntensity((next * 100).round()),
          );
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => update(details.localPosition),
          onHorizontalDragUpdate: (details) => update(details.localPosition),
          child: SizedBox(
            height: 28,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 5,
                  decoration: BoxDecoration(
                    color: c.divider,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: value.intensity.clamp(0, 100) / 100,
                  child: Container(
                    height: 5,
                    decoration: BoxDecoration(
                      color: c.linkBlue,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                Positioned(
                  left:
                      (value.intensity.clamp(0, 100) / 100) *
                      (constraints.maxWidth - 20),
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFFFFF),
                      shape: BoxShape.circle,
                      boxShadow: [
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

  Widget _applyBar() {
    final c = context.colors;
    final canUsePersonal =
        !widget.isGlobal &&
        _selection != null &&
        _controller.canApplyOnlyForSelf(widget.chatId!);
    final access = widget.isGlobal
        ? null
        : _controller.accessFor(widget.chatId!, _selection);
    final enabled = !_saving && (access?.allowed ?? true);
    return ColoredBox(
      color: c.card,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          children: [
            if (canUsePersonal) ...[
              Expanded(
                child: _applyButton(
                  AppStringKeys.chatWallpaperApplyForMe,
                  onlyForSelf: true,
                  primary: false,
                  enabled: enabled,
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: _applyButton(
                canUsePersonal
                    ? AppStringKeys.chatWallpaperApplyForBoth
                    : access != null && !access.allowed
                    ? context.l10n.t(AppStringKeys.chatWallpaperBoostRequired, {
                        'value1': access.requiredLevel,
                      })
                    : AppStringKeys.chatWallpaperApply,
                onlyForSelf: false,
                primary: true,
                enabled: enabled,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _applyButton(
    String label, {
    required bool onlyForSelf,
    required bool primary,
    required bool enabled,
  }) {
    final c = context.colors;
    final background = primary ? c.linkBlue : const Color(0x00000000);
    final foreground = primary ? const Color(0xFFFFFFFF) : c.linkBlue;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? () => _apply(onlyForSelf: onlyForSelf) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? background : background.withValues(alpha: 0.45),
          border: primary ? null : Border.all(color: c.linkBlue),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          AppStrings.t(label),
          style: TextStyle(
            color: foreground,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

@visibleForTesting
ChatWallpaper? effectiveThemeWallpaperForPicker({
  required ChatWallpaperController controller,
  required bool dark,
  required ChatWallpaper? cloudThemeWallpaper,
}) {
  final global = controller.globalThemeWallpaperFor(dark: dark);
  // A selected Telegram cloud theme is the active app theme. Legacy emoji
  // preferences may still exist from older builds, but must not conceal a
  // cloud theme's declared defaultWallpaper / t.me/bg background.
  final value = cloudThemeWallpaper ?? global;
  return value == null ? null : controller.resolvedWallpaper(value);
}

@visibleForTesting
bool wallpaperSupportsColorCustomization(ChatWallpaper? value) {
  if (value == null) return true;
  if (value.kind == ChatWallpaperKind.image ||
      value.remoteType == 'wallpaper') {
    return false;
  }
  return value.kind == ChatWallpaperKind.preset ||
      value.remoteType == 'fill' ||
      value.remoteType == 'pattern' ||
      value.colors.isNotEmpty;
}

@immutable
class _WallpaperCandidate {
  const _WallpaperCandidate({
    required this.title,
    required this.wallpaper,
    this.emoji,
  });

  final String title;
  final ChatWallpaper wallpaper;
  final String? emoji;
}
