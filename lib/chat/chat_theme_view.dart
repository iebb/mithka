import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../components/app_icons.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'chat_wallpaper.dart';

/// Telegram's peer theme picker. Peer themes are the emoji-labelled themes
/// exposed by updateEmojiChatThemes; global .attheme files belong in
/// Appearance and are deliberately not shown here.
class ChatThemeView extends StatefulWidget {
  const ChatThemeView({
    super.key,
    required this.chatId,
    required this.chatTitle,
  });

  final int chatId;
  final String chatTitle;

  @override
  State<ChatThemeView> createState() => _ChatThemeViewState();
}

class _ChatThemeViewState extends State<ChatThemeView> {
  final _controller = ChatWallpaperController.shared;
  ChatWallpaper? _selection;
  bool _loaded = false;
  bool _saving = false;

  bool get _dark => context.colors.background.computeLuminance() < 0.45;

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
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    await _controller.load(widget.chatId);
    if (!mounted) return;
    setState(() {
      final current = _controller.themeSelectionFor(widget.chatId);
      _selection = current?.themeKind == ChatThemeKind.emoji ? current : null;
      _loaded = true;
    });
  }

  List<ChatThemeOption> get _themes => _controller
      .availableThemes(
        dark: _dark,
        chatId: widget.chatId,
        resolvePatterns: false,
      )
      .where((theme) => theme.kind == ChatThemeKind.emoji)
      .toList(growable: false);

  Future<void> _apply() async {
    if (_saving) return;
    final access = _controller.accessFor(widget.chatId, _selection);
    if (!access.allowed) {
      _showBoostRequirement(access.requiredLevel);
      return;
    }
    setState(() => _saving = true);
    try {
      await _controller.applyTheme(widget.chatId, _selection?.themeName);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showToast(context, AppStringKeys.chatThemeSaveFailed);
    }
  }

  void _showBoostRequirement(int level) {
    showToast(
      context,
      context.l10n.t(AppStringKeys.chatWallpaperBoostRequired, {
        'value1': level,
      }),
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
            title: AppStringKeys.chatThemeTitle,
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: _loaded
                ? ListView(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
                    children: [
                      _preview(),
                      const SizedBox(height: 18),
                      Text(
                        AppStringKeys.chatThemeChoose.l10n(context),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: c.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        (_controller.isBoostedChat(widget.chatId)
                                ? AppStringKeys
                                      .chatWallpaperThemesSharedWithChat
                                : AppStringKeys.chatWallpaperThemesShared)
                            .l10n(context),
                        style: TextStyle(fontSize: 12, color: c.textTertiary),
                      ),
                      const SizedBox(height: 10),
                      _choices(),
                    ],
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
    final wallpaper = _selection == null
        ? null
        : _controller.themeWallpaper(_selection?.themeName ?? '', dark: _dark);
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: 270,
        child: ChatWallpaperBackground(
          wallpaper: wallpaper,
          fallbackColor: c.chatBackground,
          brightness: _dark ? Brightness.dark : Brightness.light,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 24, 14, 18),
            child: Column(
              children: [
                _bubble(
                  AppStringKeys.chatWallpaperPreviewIncoming.l10n(context),
                  outgoing: false,
                ),
                const SizedBox(height: 10),
                _bubble(
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

  Widget _bubble(String text, {required bool outgoing}) {
    final c = context.colors;
    final style = _selection == null
        ? null
        : _controller.styleForTheme(_selection?.themeName ?? '', dark: _dark);
    final global = context.watch<ThemeController>().cloudThemeFor(
      _dark ? Brightness.dark : Brightness.light,
    );
    final background = outgoing
        ? style?.outgoingColor ?? global?.outgoingColor ?? c.linkBlue
        : style?.incomingColor ?? global?.incomingColor ?? c.bubbleIncoming;
    final foreground = outgoing
        ? style?.outgoingTextColor ??
              global?.outgoingTextColor ??
              readableForeground(background)
        : style?.incomingTextColor ??
              global?.incomingTextColor ??
              c.bubbleIncomingText;
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
    final themes = _themes;
    return SizedBox(
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: themes.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          if (index == 0) return _noThemeChoice();
          return _themeChoice(themes[index - 1]);
        },
      ),
    );
  }

  Widget _noThemeChoice() => _choiceFrame(
    selected: _selection == null,
    onTap: () => setState(() => _selection = null),
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

  Widget _themeChoice(ChatThemeOption theme) {
    final value = ChatWallpaper.theme(theme.name);
    final access = _controller.accessFor(widget.chatId, value);
    return _choiceFrame(
      selected: _selection?.themeName == theme.name,
      access: access,
      onTap: () => setState(() => _selection = value),
      child: ChatWallpaperBackground(
        wallpaper: theme.wallpaper,
        fallbackColor: context.colors.chatBackground,
        brightness: _dark ? Brightness.dark : Brightness.light,
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
  }

  Widget _choiceFrame({
    required bool selected,
    required VoidCallback onTap,
    required Widget child,
    ChatWallpaperBoostAccess? access,
  }) {
    final c = context.colors;
    final locked = access != null && !access.allowed;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: locked ? () => _showBoostRequirement(access.requiredLevel) : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 104,
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
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 7),
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

  Widget _applyBar() {
    final c = context.colors;
    final access = _controller.accessFor(widget.chatId, _selection);
    final enabled = !_saving && access.allowed;
    return ColoredBox(
      color: c.card,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? _apply : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: enabled ? c.linkBlue : c.linkBlue.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              access.allowed
                  ? AppStringKeys.chatThemeApply.l10n(context)
                  : context.l10n.t(AppStringKeys.chatWallpaperBoostRequired, {
                      'value1': access.requiredLevel,
                    }),
              style: const TextStyle(
                color: Color(0xFFFFFFFF),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
