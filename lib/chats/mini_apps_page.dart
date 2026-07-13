//
//  mini_apps_page.dart
//
//  Half-height QQ-style Telegram Mini Apps drawer. Recents come from TDLib's
//  Web App bot surfaces, and search resolves Telegram mini-app links via TDLib.
//

import 'package:flutter/material.dart';

import '../chat/telegram_mini_app_recents.dart';
import '../chat/telegram_mini_app_view.dart';
import '../components/app_icons.dart';
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../theme/app_theme.dart';

class MiniAppsDrawer extends StatefulWidget {
  const MiniAppsDrawer({
    super.key,
    required this.progress,
    this.interactive = true,
    this.onCollapse,
  });

  final double progress;
  final bool interactive;
  final VoidCallback? onCollapse;

  @override
  State<MiniAppsDrawer> createState() => _MiniAppsDrawerState();
}

class _MiniAppsDrawerState extends State<MiniAppsDrawer> {
  final TextEditingController _search = TextEditingController();
  late Future<List<TelegramMiniAppRecent>> _recents =
      TelegramMiniAppRecents.load();

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearch);
  }

  @override
  void didUpdateWidget(covariant MiniAppsDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progress == 0 && widget.progress > 0) _reload();
  }

  @override
  void dispose() {
    _search.removeListener(_onSearch);
    _search.dispose();
    super.dispose();
  }

  void _onSearch() {
    setState(() => _recents = TelegramMiniAppRecents.search(_search.text));
  }

  Future<void> _reload() async {
    setState(() => _recents = TelegramMiniAppRecents.search(_search.text));
    await _recents;
  }

  Future<void> _openRecent(TelegramMiniAppRecent app) async {
    if (!widget.interactive) return;
    final opened = await openTelegramMiniApp(
      context,
      chatId: app.chatId,
      botUserId: app.botUserId,
      url: app.url,
      title: app.title,
      keyboardButtonText: app.keyboardButtonText,
      mainWebApp: app.mainWebApp,
      startParameter: app.startParameter,
      webAppShortName: app.webAppShortName,
      allowWriteAccess: app.allowWriteAccess,
      photo: app.photo,
    );
    if (!opened && mounted) showToast(context, '小程序暂时无法启动');
    if (mounted) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final progress = widget.progress.clamp(0.0, 1.0);
    final panelColor =
        Color.lerp(c.background, c.searchFill, 0.38) ?? c.background;
    const panelRadius = BorderRadius.only(
      bottomLeft: Radius.circular(28),
      bottomRight: Radius.circular(28),
    );

    return IgnorePointer(
      ignoring: !widget.interactive,
      child: Opacity(
        opacity: progress,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: panelColor,
            borderRadius: panelRadius,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 24,
                spreadRadius: -8,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: AppTheme.brand.withValues(alpha: 0.08),
                blurRadius: 34,
                spreadRadius: -14,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: panelRadius,
            child: ColoredBox(
              color: panelColor,
              child: SafeArea(bottom: false, child: _drawerBody()),
            ),
          ),
        ),
      ),
    );
  }

  Widget _drawerBody() {
    return FutureBuilder<List<TelegramMiniAppRecent>>(
      future: _recents,
      builder: (context, snapshot) {
        final recents = snapshot.data ?? const [];
        return Column(
          children: [
            _MiniAppsHeader(
              interactive: widget.interactive,
              onCollapse: widget.onCollapse,
            ),
            _SearchPill(controller: _search, enabled: widget.interactive),
            const SizedBox(height: 24),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionHeader(context),
                    const SizedBox(height: 18),
                    Expanded(
                      child: _RecentBody(
                        loading:
                            snapshot.connectionState != ConnectionState.done,
                        searching: _search.text.trim().isNotEmpty,
                        recents: recents,
                        onTap: _openRecent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _bottomHandle(context, widget.onCollapse),
          ],
        );
      },
    );
  }
}

class _MiniAppsHeader extends StatelessWidget {
  const _MiniAppsHeader({required this.interactive, this.onCollapse});

  final bool interactive;
  final VoidCallback? onCollapse;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: 50,
      child: Row(
        children: [
          const SizedBox(width: 48),
          Expanded(
            child: Center(
              child: Text(
                '小程序',
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: AppTextSize.title,
                  fontWeight: context.appFontWeight(FontWeight.w600),
                ),
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: AppIcon(HeroAppIcons.bars, color: c.textPrimary, size: 24),
            onPressed: interactive ? () => showToast(context, '小程序菜单') : null,
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}

class _SearchPill extends StatelessWidget {
  const _SearchPill({required this.controller, required this.enabled});

  final TextEditingController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        height: AppMetric.searchHeight,
        decoration: BoxDecoration(
          color: c.searchFill,
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: TextField(
          controller: controller,
          enabled: enabled,
          textAlign: TextAlign.center,
          textAlignVertical: TextAlignVertical.center,
          style: TextStyle(
            color: c.textPrimary,
            fontSize: AppTextSize.body,
            fontWeight: context.appFontWeight(FontWeight.w400),
          ),
          decoration: InputDecoration(
            isCollapsed: true,
            border: InputBorder.none,
            hintText: '搜索',
            hintStyle: TextStyle(
              color: c.textTertiary,
              fontSize: AppTextSize.bodyLarge,
              fontWeight: context.appFontWeight(FontWeight.w400),
            ),
            prefixIcon: Icon(
              HeroAppIcons.magnifyingGlass.data,
              size: AppMetric.searchIcon,
              color: c.textTertiary,
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 32,
              minHeight: AppMetric.searchHeight,
            ),
            contentPadding: const EdgeInsets.only(top: 9, right: 32, bottom: 9),
          ),
        ),
      ),
    );
  }
}

class _RecentBody extends StatelessWidget {
  const _RecentBody({
    required this.loading,
    required this.searching,
    required this.recents,
    required this.onTap,
  });

  final bool loading;
  final bool searching;
  final List<TelegramMiniAppRecent> recents;
  final ValueChanged<TelegramMiniAppRecent> onTap;

  @override
  Widget build(BuildContext context) {
    if (loading) return _loadingState(context);
    if (recents.isEmpty) {
      return _emptyState(context, searching: searching);
    }
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 18,
        crossAxisSpacing: 14,
        childAspectRatio: 0.82,
      ),
      itemCount: recents.length,
      padding: EdgeInsets.zero,
      physics: const BouncingScrollPhysics(),
      itemBuilder: (context, index) {
        final app = recents[index];
        return _RecentMiniAppTile(app: app, onTap: () => onTap(app));
      },
    );
  }
}

Widget _sectionHeader(BuildContext context) {
  final c = context.colors;
  return Text(
    '最近使用',
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      color: c.textSecondary,
      fontSize: AppTextSize.bodyLarge,
      fontWeight: context.appFontWeight(FontWeight.w400),
    ),
  );
}

Widget _loadingState(BuildContext context) {
  return Center(
    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.brand),
  );
}

Widget _emptyState(BuildContext context, {required bool searching}) {
  final c = context.colors;
  return Center(
    child: Text(
      searching ? '没有匹配的小程序' : '暂无最近使用的小程序',
      style: TextStyle(
        color: c.textTertiary,
        fontSize: AppTextSize.body,
        fontWeight: context.appFontWeight(FontWeight.w400),
      ),
    ),
  );
}

Widget _bottomHandle(BuildContext context, VoidCallback? onCollapse) {
  final c = context.colors;
  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onCollapse,
    child: Container(
      height: 50,
      width: double.infinity,
      alignment: Alignment.center,
      child: AppIcon(HeroAppIcons.chevronUp, size: 30, color: c.textPrimary),
    ),
  );
}

class _RecentMiniAppTile extends StatelessWidget {
  const _RecentMiniAppTile({required this.app, required this.onTap});

  final TelegramMiniAppRecent app;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MiniAppIcon(app: app, size: 50),
          const SizedBox(height: 8),
          Text(
            app.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.textPrimary,
              fontSize: AppTextSize.footnote,
              fontWeight: context.appFontWeight(FontWeight.w400),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniAppIcon extends StatelessWidget {
  const _MiniAppIcon({required this.app, required this.size});

  final TelegramMiniAppRecent app;
  final double size;

  @override
  Widget build(BuildContext context) {
    return PhotoAvatar(title: app.title, photo: app.photo, size: size);
  }
}
