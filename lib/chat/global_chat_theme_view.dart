import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../components/app_confirm_dialog.dart';
import '../components/app_icons.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'chat_appearance_preview.dart';
import 'chat_wallpaper.dart';

/// Global Telegram chat-theme selection. Official emoji chat themes and the
/// four stock variants live here; imported `.attheme` files are managed by
/// the separate global custom-theme screen.
class GlobalChatThemeView extends StatefulWidget {
  const GlobalChatThemeView({super.key, this.initialDark});

  /// Optional explicit slot used by callers that are already presenting a
  /// light/dark preview. Normal navigation follows the active app theme.
  final bool? initialDark;

  @override
  State<GlobalChatThemeView> createState() => _GlobalChatThemeViewState();
}

class _GlobalChatThemeViewState extends State<GlobalChatThemeView> {
  final _controller = ChatWallpaperController.shared;
  late bool _dark = widget.initialDark ?? false;
  late bool _brightnessInitialized = widget.initialDark != null;
  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_brightnessInitialized) return;
    _brightnessInitialized = true;
    _dark = context.colors.background.computeLuminance() < 0.45;
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    await _controller.loadGlobalChatThemes();
    if (mounted) setState(() => _loaded = true);
  }

  GlobalChatThemeOption get _selection =>
      _controller.globalThemeSelectionFor(dark: _dark);

  Future<void> _select(GlobalChatThemeOption option) async {
    if (_saving || option.id == _selection.id) return;
    setState(() => _saving = true);
    try {
      final nextWallpaper = option.wallpaper;
      if (nextWallpaper != null) {
        await _controller.loadDefaultWallpaper(dark: _dark);
        if (!mounted) return;
        final existingDefault = _controller.defaultWallpaper(dark: _dark);
        final previousWallpaper = _controller.globalThemeWallpaperFor(
          dark: _dark,
        );
        final useWallpaper = await showAppConfirmDialog(
          context,
          title: AppStringKeys.globalThemeWallpaperPrompt,
          confirmText: AppStringKeys.globalThemeWallpaperApply,
          cancelText: AppStringKeys.globalThemeWallpaperKeep,
        );
        if (!mounted) return;
        final wallpaper = useWallpaper
            ? nextWallpaper
            : existingDefault ?? previousWallpaper;
        if (wallpaper != null && (useWallpaper || existingDefault == null)) {
          await _controller.applyDefaultWallpaper(wallpaper, dark: _dark);
        }
      }
      await _controller.setGlobalChatTheme(option.id, dark: _dark);
    } catch (_) {
      if (mounted) showToast(context, AppStringKeys.chatThemeSaveFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
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
            title: AppStringKeys.chatThemeTitle,
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: _loaded
                ? ListView(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
                    children: [
                      _brightnessPicker(),
                      const SizedBox(height: 14),
                      _preview(_selection),
                      const SizedBox(height: 20),
                      Text(
                        AppStringKeys.chatThemeChoose.l10n(context),
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _themeGrid(),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _brightnessPicker() {
    final c = context.colors;
    return Container(
      key: const ValueKey('global-chat-theme-brightness-picker'),
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
    final selected = dark == _dark;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _dark = dark),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: selected
              ? c.linkBlue.withValues(alpha: 0.15)
              : const Color(0x00000000),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
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
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label.l10n(context),
                    maxLines: 1,
                    style: TextStyle(
                      color: selected ? c.linkBlue : c.textSecondary,
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
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

  Widget _preview(GlobalChatThemeOption option) {
    final c = context.colors;
    final appearance = context.watch<ThemeController>();
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: 220,
        child: ChatWallpaperBackground(
          wallpaper: _controller.globalThemeWallpaperFor(dark: _dark),
          fallbackColor: c.chatBackground,
          brightness: _dark ? Brightness.dark : Brightness.light,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 32, 14, 24),
            child: Column(
              children: [
                ChatAppearancePreview(
                  incomingBubbleColor: option.style.incomingColor,
                  incomingTextColor: option.style.incomingTextColor,
                  outgoingBubbleColor:
                      option.style.outgoingColor ?? AppTheme.bubbleOutgoing,
                  outgoingTextColor: option.style.outgoingTextColor,
                  incomingNameColor: option.style.nameColor,
                  outgoingNameColor: option.style.nameColor,
                  incomingMessage: AppStringKeys.chatWallpaperPreviewIncoming
                      .l10n(context),
                  outgoingMessage: AppStringKeys.chatWallpaperPreviewOutgoing
                      .l10n(context),
                  showSenderNamePlate:
                      appearance.showSenderNameReadabilityPlate,
                ),
                const Spacer(),
                Text(
                  option.label,
                  style: const TextStyle(
                    color: Color(0xF2FFFFFF),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    shadows: [Shadow(color: Color(0x77000000), blurRadius: 6)],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _themeGrid() {
    final options = _controller.globalThemeOptions(dark: _dark);
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final width = (constraints.maxWidth - gap * 2) / 3;
        return Wrap(
          spacing: gap,
          runSpacing: 14,
          children: [
            for (final option in options)
              SizedBox(width: width, child: _themeCard(option)),
          ],
        );
      },
    );
  }

  Widget _themeCard(GlobalChatThemeOption option) {
    final c = context.colors;
    final selected = option.id == _selection.id;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _select(option),
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            height: 126,
            padding: EdgeInsets.all(selected ? 3 : 1),
            decoration: BoxDecoration(
              color: selected ? c.linkBlue : c.divider,
              borderRadius: BorderRadius.circular(16),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: ChatWallpaperBackground(
                // Official emoji-theme cards mirror Telegram iOS: the emoji
                // stays legible over the authored fill/gradient, while the
                // vector pattern is reserved for the full preview and chat.
                wallpaper: option.wallpaper?.withoutPatternDocument(),
                fallbackColor: c.chatBackground,
                brightness: _dark ? Brightness.dark : Brightness.light,
                child: option.emoji == null
                    ? _cardBubbles(option.style)
                    : Center(
                        child: Text(
                          option.emoji!,
                          style: const TextStyle(
                            fontSize: 31,
                            shadows: [
                              Shadow(color: Color(0x66000000), blurRadius: 6),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            option.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? c.linkBlue : c.textSecondary,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardBubbles(ChatThemeStyle style) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 17, 12, 18),
    child: Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            width: 58,
            height: 22,
            decoration: BoxDecoration(
              color: style.outgoingColor,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: 55,
            height: 22,
            decoration: BoxDecoration(
              color: style.incomingColor,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    ),
  );
}
