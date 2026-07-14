import 'dart:io';

import 'package:flutter/widgets.dart';

import '../components/app_icons.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../media/app_asset_picker.dart';
import '../theme/app_theme.dart';
import 'chat_wallpaper.dart';
import 'chat_wallpaper_color_view.dart';
import 'chat_wallpaper_search_view.dart';

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
  ChatWallpaper? _themeSelection;
  ChatWallpaper? _initialRemote;
  List<ChatWallpaper> _catalogBackgrounds = const [];
  bool _loaded = false;
  bool _saving = false;

  bool get _isDarkTheme => context.colors.background.computeLuminance() < 0.45;

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
    if (widget.isGlobal) {
      setState(() {
        _selection = _controller.defaultWallpaper(dark: widget.forDarkTheme);
      });
      return;
    }
    final current = _controller.selectionFor(widget.chatId!);
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
    final dark = widget.isGlobal ? widget.forDarkTheme : _isDarkTheme;
    if (widget.isGlobal) {
      await _controller.loadDefaultWallpaper(dark: widget.forDarkTheme);
      try {
        _catalogBackgrounds = await _controller.installedBackgrounds(
          dark: widget.forDarkTheme,
        );
      } catch (_) {}
    } else {
      await _controller.load(widget.chatId!);
      if (_controller.canApplyGiftTheme(widget.chatId!)) {
        await _controller.loadGiftThemes();
      }
      try {
        _catalogBackgrounds = await _controller.installedBackgrounds(
          dark: dark,
        );
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      final boostedChat =
          !widget.isGlobal && _controller.isBoostedChat(widget.chatId!);
      _selection = widget.isGlobal
          ? _controller.defaultWallpaper(dark: widget.forDarkTheme)
          : boostedChat
          ? _controller.selectionFor(widget.chatId!)
          : _controller.wallpaperSelectionFor(widget.chatId!);
      _themeSelection = widget.isGlobal || boostedChat
          ? null
          : _controller.themeSelectionFor(widget.chatId!);
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

  Future<void> _searchBackgrounds() async {
    if (!_allowCustomWallpaper()) return;
    final selected = await Navigator.of(context).push<ChatWallpaper>(
      PageRouteBuilder<ChatWallpaper>(
        pageBuilder: (_, _, _) =>
            ChatWallpaperSearchView(controller: _controller),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
    if (!mounted || selected == null) return;
    setState(() => _selection = selected);
  }

  Future<void> _pickColor() async {
    if (!_allowCustomWallpaper()) return;
    final selected = await Navigator.of(context).push<ChatWallpaper>(
      PageRouteBuilder<ChatWallpaper>(
        pageBuilder: (_, _, _) => ChatWallpaperColorView(
          controller: _controller,
          dark: widget.isGlobal ? widget.forDarkTheme : _isDarkTheme,
          initial: _selection,
        ),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
    if (!mounted || selected == null) return;
    setState(() => _selection = selected);
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
        await _controller.applyDefaultWallpaper(
          value,
          dark: widget.forDarkTheme,
        );
      } else if (_controller.isBoostedChat(widget.chatId!)) {
        await _controller.applyWallpaper(
          widget.chatId!,
          value,
          onlyForSelf: false,
        );
      } else {
        await _controller.applyTheme(
          widget.chatId!,
          _themeSelection?.themeName,
          kind: _themeSelection?.themeKind ?? ChatThemeKind.emoji,
        );
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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ColoredBox(
      color: c.groupedBackground,
      child: Column(
        children: [
          NavHeader(
            title: widget.isGlobal
                ? AppStringKeys.chatWallpaperGlobalTitle
                : AppStringKeys.chatWallpaperTitle,
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: _loaded
                ? SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _preview(),
                        if (_selection?.supportsBlur == true ||
                            _selection?.supportsMotion == true ||
                            _selection?.supportsIntensity == true) ...[
                          const SizedBox(height: 12),
                          _effects(),
                        ],
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
                        if (!widget.isGlobal &&
                            _controller.canApplyTheme(widget.chatId!) &&
                            _controller
                                .availableThemes(
                                  dark: _isDarkTheme,
                                  chatId: widget.chatId!,
                                  resolvePatterns: false,
                                )
                                .isNotEmpty) ...[
                          const SizedBox(height: 20),
                          Text(
                            AppStringKeys.chatWallpaperTelegramThemes.l10n(
                              context,
                            ),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: c.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            (_controller.isBoostedChat(widget.chatId!)
                                    ? AppStringKeys
                                          .chatWallpaperThemesSharedWithChat
                                    : AppStringKeys.chatWallpaperThemesShared)
                                .l10n(context),
                            style: TextStyle(
                              fontSize: 12,
                              color: c.textTertiary,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _themeChoices(),
                        ],
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
    final c = context.colors;
    final dark = _isDarkTheme;
    final activeTheme = _controller.isBoostedChat(widget.chatId ?? 0)
        ? (_selection?.kind == ChatWallpaperKind.theme ? _selection : null)
        : _themeSelection;
    final previewWallpaper =
        _selection?.kind == ChatWallpaperKind.theme ||
            (_selection == null && activeTheme != null)
        ? _controller.themeWallpaper(
            activeTheme?.themeName ?? '',
            kind: activeTheme?.themeKind ?? ChatThemeKind.emoji,
            dark: dark,
          )
        : _selection;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: 270,
        child: ChatWallpaperBackground(
          wallpaper: previewWallpaper,
          fallbackColor: c.chatBackground,
          brightness: dark ? Brightness.dark : Brightness.light,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 24, 14, 18),
            child: Column(
              children: [
                _previewBubble(
                  AppStringKeys.chatWallpaperPreviewIncoming.l10n(context),
                  outgoing: false,
                ),
                const SizedBox(height: 10),
                _previewBubble(
                  AppStringKeys.chatWallpaperPreviewOutgoing.l10n(context),
                  outgoing: true,
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

  Widget _previewBubble(String text, {required bool outgoing}) {
    final c = context.colors;
    final dark = _isDarkTheme;
    final activeTheme = _selection?.kind == ChatWallpaperKind.theme
        ? _selection
        : _themeSelection;
    final themeStyle = activeTheme == null
        ? widget.isGlobal
              ? null
              : _controller.themeStyleFor(widget.chatId!, dark: dark)
        : _controller.styleForTheme(
            activeTheme.themeName ?? '',
            kind: activeTheme.themeKind,
            dark: dark,
          );
    final background = outgoing
        ? themeStyle?.outgoingColor ?? const Color(0xFF4B8DEE)
        : themeStyle?.incomingColor ?? c.bubbleIncoming;
    final foreground = outgoing
        ? themeStyle?.outgoingTextColor ?? const Color(0xFFFFFFFF)
        : themeStyle?.incomingTextColor ?? c.bubbleIncomingText;
    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 250),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(15),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 5,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Text(text, style: TextStyle(fontSize: 14, color: foreground)),
      ),
    );
  }

  Widget _choices() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 10.0;
        final width = (constraints.maxWidth - spacing * 2) / 3;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            _defaultChoice(width),
            _photoChoice(width),
            _searchChoice(width),
            _colorChoice(width),
            if (_initialRemote != null) _remoteChoice(width, _initialRemote!),
            for (final preset in chatWallpaperPresets)
              _presetChoice(width, preset),
            for (final wallpaper in _catalogBackgrounds.take(12))
              if (wallpaper.remoteType == 'wallpaper' ||
                  wallpaper.remoteType == 'pattern')
                _remoteCatalogChoice(width, wallpaper),
          ],
        );
      },
    );
  }

  Widget _defaultChoice(double width) {
    final c = context.colors;
    final selected = _selection == null;
    return _choiceFrame(
      width: width,
      selected: selected,
      onTap: () => setState(() => _selection = null),
      child: ColoredBox(
        color: c.chatBackground,
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

  Widget _searchChoice(double width) {
    final c = context.colors;
    return _choiceFrame(
      width: width,
      selected: false,
      onTap: _searchBackgrounds,
      access: _customWallpaperAccess(),
      child: ColoredBox(
        color: c.panelBackground,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                HeroAppIcons.magnifyingGlass,
                size: 25,
                color: c.linkBlue,
              ),
              const SizedBox(height: 6),
              Text(
                AppStringKeys.chatWallpaperSearch.l10n(context),
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
      selected:
          _selection?.kind == ChatWallpaperKind.telegram &&
          (_selection?.remoteType == 'fill' ||
              _selection?.remoteType == 'pattern') &&
          _selection?.backgroundId == 0,
      onTap: _pickColor,
      access: _customWallpaperAccess(),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF2828F), Color(0xFF8B75E8), Color(0xFF5BC5D8)],
          ),
        ),
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
    return _choiceFrame(
      width: width,
      selected: selected,
      onTap: () => setState(() => _selection = wallpaper),
      child: ChatWallpaperBackground(
        wallpaper: wallpaper,
        fallbackColor: context.colors.chatBackground,
        brightness: _isDarkTheme ? Brightness.dark : Brightness.light,
        child: Align(
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
      ),
    );
  }

  Widget _remoteCatalogChoice(double width, ChatWallpaper wallpaper) {
    final resolved = _selection?.backgroundId == wallpaper.backgroundId
        ? _selection ?? wallpaper
        : wallpaper.withoutPatternDocument();
    return _choiceFrame(
      width: width,
      selected:
          _selection?.kind == ChatWallpaperKind.telegram &&
          _selection?.backgroundId == wallpaper.backgroundId,
      onTap: () =>
          setState(() => _selection = _controller.resolvedWallpaper(wallpaper)),
      access: _customWallpaperAccess(),
      child: ChatWallpaperBackground(
        wallpaper: resolved,
        fallbackColor: context.colors.chatBackground,
        brightness: _isDarkTheme ? Brightness.dark : Brightness.light,
        child: wallpaper.remoteType == 'pattern'
            ? const Center(
                child: AppIcon(
                  HeroAppIcons.wandMagicSparkles,
                  size: 23,
                  color: Color(0xCCFFFFFF),
                ),
              )
            : null,
      ),
    );
  }

  Widget _themeChoices() {
    final dark = _isDarkTheme;
    final themes = _controller.availableThemes(
      dark: dark,
      chatId: widget.chatId,
      resolvePatterns: false,
    );
    final isGroup = _controller.isBoostedChat(widget.chatId!);
    return SizedBox(
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: themes.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          if (index == 0) {
            final selected = isGroup
                ? _selection == null
                : _themeSelection == null;
            return _choiceFrame(
              width: 104,
              selected: selected,
              onTap: () => setState(() {
                if (isGroup) {
                  _selection = null;
                } else {
                  _themeSelection = null;
                }
              }),
              child: ColoredBox(
                color: context.colors.chatBackground,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppIcon(
                        HeroAppIcons.circleXmark,
                        size: 28,
                        color: context.colors.textSecondary,
                      ),
                      const SizedBox(height: 7),
                      Text(
                        AppStringKeys.chatWallpaperNoTheme.l10n(context),
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
          final theme = themes[index - 1];
          final value = ChatWallpaper.theme(theme.name, themeKind: theme.kind);
          final access = isGroup
              ? _controller.accessFor(widget.chatId!, value)
              : null;
          return _choiceFrame(
            width: 104,
            selected:
                (isGroup ? _selection : _themeSelection)?.themeName ==
                    theme.name &&
                (isGroup ? _selection : _themeSelection)?.themeKind ==
                    theme.kind,
            onTap: () => setState(() {
              if (isGroup) {
                _selection = value;
              } else {
                _themeSelection = value;
              }
            }),
            access: access,
            child: ChatWallpaperBackground(
              wallpaper: theme.wallpaper,
              fallbackColor: context.colors.chatBackground,
              brightness: dark ? Brightness.dark : Brightness.light,
              child: Center(
                child: Text(
                  theme.label,
                  style: const TextStyle(
                    fontSize: 29,
                    shadows: [Shadow(color: Color(0x66000000), blurRadius: 6)],
                  ),
                ),
              ),
            ),
          );
        },
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
        brightness: _isDarkTheme ? Brightness.dark : Brightness.light,
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
        height: 112,
        padding: EdgeInsets.all(selected ? 3 : 1),
        decoration: BoxDecoration(
          color: selected ? c.linkBlue : c.divider,
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
    final value = _selection;
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
    final isTheme = _selection?.kind == ChatWallpaperKind.theme;
    final canUsePersonal =
        !widget.isGlobal &&
        !isTheme &&
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
                isTheme
                    ? AppStringKeys.chatWallpaperApplyForBoth
                    : canUsePersonal
                    ? AppStringKeys.chatWallpaperApplyForBoth
                    : access != null && !access.allowed
                    ? context.l10n.t(AppStringKeys.chatWallpaperBoostRequired, {
                        'value1': access.requiredLevel,
                      })
                    : AppStringKeys.chatWallpaperApply,
                onlyForSelf: false,
                primary: !isTheme,
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
