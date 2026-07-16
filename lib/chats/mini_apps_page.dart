//
//  mini_apps_page.dart
//
//  Telegram Mini Apps surfaced from the chat search screen. The active search
//  query is resolved by TelegramMiniAppRecents through TDLib.
//

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../chat/telegram_mini_app_recents.dart';
import '../chat/telegram_mini_app_view.dart';
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../theme/app_theme.dart';

class MiniAppsSearchTab extends StatefulWidget {
  const MiniAppsSearchTab({super.key, required this.query});

  final String query;

  @override
  State<MiniAppsSearchTab> createState() => _MiniAppsSearchTabState();
}

class _MiniAppsSearchTabState extends State<MiniAppsSearchTab> {
  late Future<List<TelegramMiniAppRecent>> _apps = _load();

  @override
  void didUpdateWidget(covariant MiniAppsSearchTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query == widget.query) return;
    setState(() => _apps = _load());
  }

  Future<List<TelegramMiniAppRecent>> _load() =>
      TelegramMiniAppRecents.search(widget.query);

  Future<void> _open(TelegramMiniAppRecent app) async {
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
    if (!opened && mounted) {
      showToast(context, AppStrings.t(AppStringKeys.miniAppCannotStart));
    }
    if (mounted) setState(() => _apps = _load());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return FutureBuilder<List<TelegramMiniAppRecent>>(
      future: _apps,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.brand,
            ),
          );
        }
        final apps = snapshot.data ?? const <TelegramMiniAppRecent>[];
        if (apps.isEmpty) {
          return Center(
            child: Text(
              widget.query.trim().isEmpty
                  ? AppStrings.t(AppStringKeys.miniAppRecentEmpty)
                  : AppStrings.t(AppStringKeys.miniAppNoMatches),
              style: TextStyle(fontSize: 14, color: c.textTertiary),
            ),
          );
        }
        return CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                child: Text(
                  widget.query.trim().isEmpty
                      ? AppStrings.t(AppStringKeys.miniAppRecentSection)
                      : 'Mini App',
                  style: TextStyle(fontSize: 16, color: c.textSecondary),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _MiniAppTile(
                    app: apps[index],
                    onTap: () => _open(apps[index]),
                  ),
                  childCount: apps.length,
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 18,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.82,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MiniAppTile extends StatelessWidget {
  const _MiniAppTile({required this.app, required this.onTap});

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
          PhotoAvatar(title: app.displayTitle, photo: app.photo),
          const SizedBox(height: 8),
          Text(
            app.displayTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.textPrimary,
              fontSize: AppTextSize.caption,
              fontWeight: context.appFontWeight(FontWeight.w400),
            ),
          ),
        ],
      ),
    );
  }
}
