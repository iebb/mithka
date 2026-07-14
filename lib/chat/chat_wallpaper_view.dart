import 'dart:io';

import 'package:flutter/widgets.dart';

import '../components/app_icons.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../media/app_asset_picker.dart';
import '../theme/app_theme.dart';
import 'chat_wallpaper.dart';

class ChatWallpaperView extends StatefulWidget {
  const ChatWallpaperView({
    super.key,
    required this.chatId,
    required this.chatTitle,
  });

  final int chatId;
  final String chatTitle;

  @override
  State<ChatWallpaperView> createState() => _ChatWallpaperViewState();
}

class _ChatWallpaperViewState extends State<ChatWallpaperView> {
  final _controller = ChatWallpaperController.shared;
  ChatWallpaper? _selection;
  ChatWallpaper? _initialRemote;
  bool _loaded = false;
  bool _saving = false;

  bool get _isDarkTheme => context.colors.background.computeLuminance() < 0.45;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
    _load();
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final current = _controller.selectionFor(widget.chatId);
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
    await _controller.load(widget.chatId);
    if (_controller.canApplyGiftTheme(widget.chatId)) {
      await _controller.loadGiftThemes();
    }
    if (!mounted) return;
    setState(() {
      _selection = _controller.selectionFor(widget.chatId);
      if (_selection?.kind == ChatWallpaperKind.telegram) {
        _initialRemote = _selection;
      }
      _loaded = true;
    });
  }

  Future<void> _pickPhoto() async {
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

  Future<void> _apply({required bool onlyForSelf}) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final value = _selection;
      if (value == null) {
        await _controller.clearAppearance(widget.chatId);
      } else if (value.kind == ChatWallpaperKind.theme) {
        await _controller.applyTheme(
          widget.chatId,
          value.themeName,
          kind: value.themeKind,
        );
      } else {
        await _controller.applyWallpaper(
          widget.chatId,
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
                        _preview(),
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
                        if (_controller.canApplyTheme(widget.chatId) &&
                            _controller
                                .availableThemes(
                                  dark: _isDarkTheme,
                                  chatId: widget.chatId,
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
                            AppStringKeys.chatWallpaperThemesShared.l10n(
                              context,
                            ),
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
    final previewWallpaper = _selection?.kind == ChatWallpaperKind.theme
        ? _controller.themeWallpaper(
            _selection?.themeName ?? '',
            kind: _selection?.themeKind ?? ChatThemeKind.emoji,
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
    final themeStyle = switch (_selection?.kind) {
      ChatWallpaperKind.theme => _controller.styleForTheme(
        _selection?.themeName ?? '',
        kind: _selection?.themeKind ?? ChatThemeKind.emoji,
        dark: dark,
      ),
      null => null,
      _ => _controller.themeStyleFor(widget.chatId, dark: dark),
    };
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
            if (_initialRemote != null) _remoteChoice(width, _initialRemote!),
            for (final preset in chatWallpaperPresets)
              _presetChoice(width, preset),
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

  Widget _themeChoices() {
    final dark = _isDarkTheme;
    final themes = _controller.availableThemes(
      dark: dark,
      chatId: widget.chatId,
      resolvePatterns: false,
    );
    return SizedBox(
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: themes.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final theme = themes[index];
          return _choiceFrame(
            width: 104,
            selected:
                _selection?.kind == ChatWallpaperKind.theme &&
                _selection?.themeName == theme.name &&
                _selection?.themeKind == theme.kind,
            onTap: () => setState(
              () => _selection = ChatWallpaper.theme(
                theme.name,
                themeKind: theme.kind,
              ),
            ),
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
  }) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: width,
        height: 112,
        padding: EdgeInsets.all(selected ? 3 : 1),
        decoration: BoxDecoration(
          color: selected ? c.linkBlue : c.divider,
          borderRadius: BorderRadius.circular(14),
        ),
        child: ClipRRect(borderRadius: BorderRadius.circular(11), child: child),
      ),
    );
  }

  Widget _applyBar() {
    final c = context.colors;
    final isTheme = _selection?.kind == ChatWallpaperKind.theme;
    final canUsePersonal =
        !isTheme &&
        _selection != null &&
        _controller.canApplyOnlyForSelf(widget.chatId);
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
                    : AppStringKeys.chatWallpaperApply,
                onlyForSelf: false,
                primary: !isTheme,
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
  }) {
    final c = context.colors;
    final background = primary ? c.linkBlue : const Color(0x00000000);
    final foreground = primary ? const Color(0xFFFFFFFF) : c.linkBlue;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _saving ? null : () => _apply(onlyForSelf: onlyForSelf),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _saving ? background.withValues(alpha: 0.55) : background,
          border: primary ? null : Border.all(color: c.linkBlue),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label.l10n(context),
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
