//
//  profile_view.dart
//
//  The "我" side menu (slides in from the left, ~88% width). Redesigned to match
//  the reference app's drawer: an azure avatar banner → an edit-profile card → a vertical list
//  of rows (相册 / 收藏 / 文件 / 外观) → account switcher → a bottom bar
//  (设置 · 夜间模式). Backed by real TDLib via ProfileViewModel + AccountStore.
//

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../auth/account_store.dart';
import '../auth/auth_manager.dart';
import '../chat/chat_view.dart';
import '../chat/custom_emoji.dart';
import '../chat/shared_media_view.dart';
import '../components/app_icons.dart';
import '../components/confirm_dialog.dart';
import '../components/drawer_controller.dart' as dc;
import '../components/photo_avatar.dart';
import '../components/ui_components.dart';
import '../l10n/telegram_language_controller.dart';
import '../settings/edit_profile_view.dart';
import '../settings/settings_view.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'emoji_status_picker.dart';
import 'my_album_view.dart';
import 'profile_detail_view.dart';
import 'qr_code_view.dart';

class ProfileViewModel extends ChangeNotifier {
  CurrentUser? user;
  int? savedChatId;
  bool _loaded = false;
  StreamSubscription? _sub;

  void onAppear() {
    if (_loaded) return;
    _loaded = true;
    // Keep the profile (and the "我" drawer, which is this same view) live: when
    // our own user changes — e.g. after editing the name — TDLib emits updateUser
    // for us, so re-parse instead of waiting for an app restart.
    _sub = TdClient.shared.subscribe().listen((u) {
      if (u.type != 'updateUser') return;
      final usr = u.obj('user');
      if (usr != null && usr.int64('id') == user?.id) _applyUser(usr);
    });
    _getMe();
  }

  void _applyUser(Map<String, dynamic> me) {
    user = CurrentUser(
      id: me.int64('id') ?? user?.id ?? 0,
      name: TDParse.userName(me),
      phoneNumber: TDParse.formatPhone(me.str('phone_number')),
      username: me.obj('usernames')?.str('editable_username'),
      photo: TDParse.smallPhoto(me.obj('profile_photo')),
      emojiStatusId:
          me.obj('emoji_status')?.obj('type')?.int64('custom_emoji_id') ??
          me.obj('emoji_status')?.int64('custom_emoji_id') ??
          0,
      isPremium: me.boolean('is_premium') ?? false,
    );
    notifyListeners();
  }

  Future<void> _getMe() async {
    try {
      final me = await TdClient.shared.query({'@type': 'getMe'});
      _applyUser(me);
      final chat = await TdClient.shared.query({
        '@type': 'createPrivateChat',
        'user_id': user?.id ?? me.int64('id') ?? 0,
        'force': false,
      });
      savedChatId = chat.int64('id') ?? user?.id;
      notifyListeners();
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// Default emoji-status suggestions (custom_emoji_ids), resolved on demand
  /// for the status picker.
  Future<List<int>> statusOptions() async {
    final ids = <int>[];
    for (final type in const [
      'getThemedEmojiStatuses',
      'getDefaultEmojiStatuses',
    ]) {
      try {
        final res = await TdClient.shared.query({'@type': type});
        // Newer TDLib: { emoji_statuses: [emojiStatusTypeCustomEmoji{custom_emoji_id}] };
        // older: { custom_emoji_ids: [int64] }.
        for (final s
            in res.objects('emoji_statuses') ??
                const <Map<String, dynamic>>[]) {
          final id =
              s.int64('custom_emoji_id') ??
              s.obj('type')?.int64('custom_emoji_id');
          if (id != null && id != 0) ids.add(id);
        }
        for (final id in res.int64Array('custom_emoji_ids') ?? const <int>[]) {
          if (id != 0) ids.add(id);
        }
      } catch (_) {}
      if (ids.isNotEmpty) break;
    }
    return ids.toSet().toList();
  }

  /// Sets (id != 0) or clears (id == 0) the current user's emoji status.
  Future<bool> setEmojiStatus(int id) async {
    try {
      await TdClient.shared.query({
        '@type': 'setEmojiStatus',
        // Current TDLib: emojiStatus.type = emojiStatusTypeCustomEmoji{...}.
        // (Sending custom_emoji_id at the top level is silently ignored, so the
        // status never actually changes.)
        'emoji_status': id == 0
            ? null
            : {
                '@type': 'emojiStatus',
                'type': {
                  '@type': 'emojiStatusTypeCustomEmoji',
                  'custom_emoji_id': id,
                },
                'expiration_date': 0,
              },
      });
      user?.emojiStatusId = id;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }
}

class ProfileView extends StatefulWidget {
  const ProfileView({super.key});

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  final _vm = ProfileViewModel();

  @override
  void initState() {
    super.initState();
    _vm.addListener(() {
      if (mounted) setState(() {});
    });
    _vm.onAppear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AccountStore>().refresh();
    });
  }

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  NavigatorState get _root => Navigator.of(context, rootNavigator: true);

  void _openSaved(String title) {
    final cid = _vm.savedChatId ?? _vm.user?.id ?? 0;
    _root.push(
      MaterialPageRoute(
        builder: (_) => ChatView(chatId: cid, title: title),
      ),
    );
  }

  void _openStatusPicker() {
    showEmojiStatusPicker(
      context,
      currentStatusId: _vm.user?.emojiStatusId ?? 0,
    );
  }

  void _openMyProfile() {
    final user = _vm.user;
    if (user == null || user.id <= 0) return;
    _root.push(
      MaterialPageRoute(
        builder: (_) => ProfileDetailView(userId: user.id, name: user.name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      color: c.card,
      child: Column(
        children: [
          _banner(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(),
              children: [
                _rowsCard(),
                const SizedBox(height: 12),
                _accountsCard(),
              ],
            ),
          ),
          _bottomBar(),
        ],
      ),
    );
  }

  // MARK: - Azure avatar banner

  Widget _banner() {
    final user = _vm.user;
    final hidePhone = context.watch<ThemeController>().hideSidebarPhone;
    final username = (user?.username?.isNotEmpty ?? false)
        ? '@${user!.username}'
        : (hidePhone ? '' : (user?.phoneNumber ?? ''));
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      decoration: BoxDecoration(gradient: AppTheme.brandGradient),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top controls: QR + close.
            Row(
              children: [
                const Spacer(),
                GestureDetector(
                  onTap: _openMyProfile,
                  child: const AppIcon(
                    HeroAppIcons.circleUser,
                    size: 22,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: () => _root.push(
                    MaterialPageRoute(
                      builder: (_) => QRCodeView(
                        name:
                            user?.name ??
                            AppStrings.t(AppStringKeys.chatMeLabel),
                      ),
                    ),
                  ),
                  child: const AppIcon(
                    HeroAppIcons.qrcode,
                    size: 22,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: () => context.read<dc.DrawerController>().close(),
                  child: const AppIcon(
                    HeroAppIcons.xmark,
                    size: 22,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: PhotoAvatar(
                    title:
                        user?.name ?? AppStrings.t(AppStringKeys.chatMeLabel),
                    photo: user?.photo,
                    size: 64,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              user?.name ??
                                  AppStrings.t(AppStringKeys.contactsLoading),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          _nameStatusIcon(user),
                          if (user?.isPremium ?? false) ...[
                            const SizedBox(width: 6),
                            const _VipBadge(),
                          ],
                        ],
                      ),
                      if (username.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Edit profile — replaces the old duplicate 编辑资料 card.
                GestureDetector(
                  onTap: () => _root.push(
                    MaterialPageRoute(builder: (_) => const EditProfileView()),
                  ),
                  child: const AppIcon(
                    HeroAppIcons.penToSquare,
                    size: 22,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _nameStatusIcon(CurrentUser? user) {
    final hasStatus = (user?.emojiStatusId ?? 0) != 0;
    final premium = user?.isPremium ?? false;
    if (!hasStatus && !premium) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _openStatusPicker,
        child: hasStatus
            ? CustomEmojiView(
                id: user!.emojiStatusId,
                size: 24,
                color: Colors.white,
              )
            : Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
                child: AppIcon(
                  HeroAppIcons.plus,
                  size: 16,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
      ),
    );
  }

  // MARK: - custom vertical rows

  Widget _rowsCard() {
    return Container(
      decoration: BoxDecoration(color: context.colors.card),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _row(
            HeroAppIcons.image,
            const Color(0xFFF5A623),
            AppStrings.t(AppStringKeys.chatInfoAlbum),
            () {
              _root.push(
                MaterialPageRoute(
                  builder: (_) => MyAlbumView(userId: _vm.user?.id ?? 0),
                ),
              );
            },
          ),
          _row(
            HeroAppIcons.star,
            const Color(0xFFFF9D2E),
            AppStrings.t(AppStringKeys.messageActionFavorite),
            () => _openSaved(AppStrings.t(AppStringKeys.messageActionFavorite)),
          ),
          _row(
            HeroAppIcons.folder,
            const Color(0xFF3C8CF0),
            telegramText(AppStringKeys.topicPostContentFile),
            () {
              _root.push(
                MaterialPageRoute(
                  builder: (_) => SharedMediaView(
                    chatId: 0,
                    title: telegramText(AppStringKeys.topicPostContentFile),
                    initialTab: 1,
                    displayTitle: AppStringKeys.topicPostContentFile,
                  ),
                ),
              );
            },
          ),
          _row(
            HeroAppIcons.video,
            const Color(0xFF7B61FF),
            telegramText(AppStringKeys.sharedMediaVideos),
            () {
              _root.push(
                MaterialPageRoute(
                  builder: (_) => SharedMediaView(
                    chatId: 0,
                    title: telegramText(AppStringKeys.sharedMediaVideos),
                    initialTab: 4,
                    displayTitle: AppStringKeys.sharedMediaVideos,
                    lockedTab: true,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _row(AppIconData icon, Color color, String label, VoidCallback onTap) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 54,
        child: Padding(
          padding: const EdgeInsets.only(left: 8, right: 18),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 32,
                alignment: Alignment.center,
                child: AppIcon(icon, size: 20, color: color),
              ),
              const SizedBox(width: 12),
              Text(label, style: TextStyle(fontSize: 15, color: c.textPrimary)),
              const Spacer(),
              AppIcon(
                HeroAppIcons.chevronRight,
                size: 15,
                color: c.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // MARK: - Account switcher

  Widget _accountsCard() {
    final c = context.colors;
    final accounts = context.watch<AccountStore>();
    final hidePhone = context.watch<ThemeController>().hideSidebarPhone;
    return Container(
      margin: const EdgeInsets.symmetric(),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          const InsetDivider(leadingInset: 0),
          for (final s in accounts.summaries) ...[
            _SwipeAccountRow(
              onTap: () =>
                  accounts.switchTo(s.slot, context.read<AuthManager>()),
              onLongPress: () => _confirmRemoveAccount(accounts, s),
              onRemove: () => _confirmRemoveAccount(accounts, s),
              onLogout: () => _confirmLogOutAccount(accounts, s),
              child: _accountRow(
                s.name,
                hidePhone ? '' : s.phone,
                s.avatarPath,
                selected: s.slot == accounts.activeSlot,
              ),
            ),
            const InsetDivider(leadingInset: 64),
          ],
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => context.read<AccountStore>().addAccount(
              context.read<AuthManager>(),
            ),
            child: SizedBox(
              height: 54,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.brand.withValues(alpha: 0.12),
                      ),
                      child: AppIcon(
                        HeroAppIcons.plus,
                        size: 18,
                        color: AppTheme.brand,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      AppStrings.t(AppStringKeys.profileAddAccount),
                      style: TextStyle(fontSize: 15, color: AppTheme.brand),
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

  String _accountLabel(AccountSummary s) =>
      s.phone.isNotEmpty ? '${s.name}（${s.phone}）' : s.name;

  /// Long-press or swipe an account row to remove it from this device only.
  Future<void> _confirmRemoveAccount(
    AccountStore accounts,
    AccountSummary s,
  ) async {
    final ok = await confirmDialog(
      context,
      title: AppStrings.t(AppStringKeys.profileRemoveAccount),
      message: AppStrings.t(AppStringKeys.profileRemoveAccountConfirm, {
        'value1': _accountLabel(s),
      }),
      confirmText: AppStrings.t(AppStringKeys.chatInfoRemove),
      destructive: true,
    );
    if (!ok || !mounted) return;
    await accounts.removeAccount(s.slot, context.read<AuthManager>());
  }

  Future<void> _confirmLogOutAccount(
    AccountStore accounts,
    AccountSummary s,
  ) async {
    final ok = await confirmDialog(
      context,
      title: AppStrings.t(AppStringKeys.profileLogOutAccount),
      message: AppStrings.t(AppStringKeys.profileLogOutAccountConfirm, {
        'value1': _accountLabel(s),
      }),
      confirmText: AppStrings.t(AppStringKeys.settingsLogOut),
      destructive: true,
    );
    if (!ok || !mounted) return;
    await accounts.logOutAccount(s.slot, context.read<AuthManager>());
  }

  Widget _accountRow(
    String name,
    String phone,
    String? avatarPath, {
    required bool selected,
  }) {
    final c = context.colors;
    final avatarCacheSize = (36 * MediaQuery.devicePixelRatioOf(context))
        .ceil();
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            if (avatarPath != null && avatarPath.isNotEmpty)
              ClipOval(
                child: Image.file(
                  File(avatarPath),
                  width: 36,
                  height: 36,
                  fit: BoxFit.cover,
                  cacheWidth: avatarCacheSize,
                  cacheHeight: avatarCacheSize,
                ),
              )
            else
              PhotoAvatar(title: name, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, color: c.textPrimary),
                  ),
                  if (phone.isNotEmpty)
                    Text(
                      phone,
                      style: TextStyle(fontSize: 12, color: c.textSecondary),
                    ),
                ],
              ),
            ),
            if (selected)
              AppIcon(HeroAppIcons.check, size: 16, color: AppTheme.brand),
          ],
        ),
      ),
    );
  }

  // MARK: - Bottom bar (设置 · 夜间模式)

  Widget _bottomBar() {
    final c = context.colors;
    final theme = context.watch<ThemeController>();
    // Derive from the EFFECTIVE brightness, not just the stored mode: when mode
    // is `system` the rendered brightness comes from the OS, so a plain
    // `mode==dark` check would mislabel the button and the toggle could resolve
    // to the same brightness (a visible no-op after the first tap).
    final isDark =
        theme.mode == AppearanceMode.dark ||
        (theme.mode == AppearanceMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);
    return Container(
      decoration: BoxDecoration(
        color: c.navBar,
        border: Border(top: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 74,
          child: Row(
            children: [
              const SizedBox(width: 16),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _root.push(
                  MaterialPageRoute(builder: (_) => const SettingsView()),
                ),
                child: _barItem(
                  HeroAppIcons.gear.data,
                  AppStrings.t(AppStringKeys.profileSettings),
                ),
              ),
              const SizedBox(width: 24),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                // Flip between EXPLICIT light/dark every tap (never `system`,
                // which could equal the current brightness and do nothing).
                onTap: () => theme.mode = isDark
                    ? AppearanceMode.light
                    : AppearanceMode.dark,
                child: _barItem(
                  isDark ? HeroAppIcons.sun.data : HeroAppIcons.moon.data,
                  isDark
                      ? AppStrings.t(AppStringKeys.profileDayMode)
                      : AppStrings.t(AppStringKeys.profileNightMode),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _barItem(IconData icon, String label) {
    final c = context.colors;
    return SizedBox(
      width: 58,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 22, color: c.textPrimary),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: c.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwipeAccountRow extends StatefulWidget {
  const _SwipeAccountRow({
    required this.child,
    required this.onTap,
    required this.onLongPress,
    required this.onRemove,
    required this.onLogout,
  });

  final Widget child;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onRemove;
  final VoidCallback onLogout;

  @override
  State<_SwipeAccountRow> createState() => _SwipeAccountRowState();
}

class _SwipeAccountRowState extends State<_SwipeAccountRow> {
  static const double _actionWidth = 78;
  static const double _actionsWidth = _actionWidth * 2;
  double _offset = 0;

  void _close() {
    if (_offset == 0) return;
    setState(() => _offset = 0);
  }

  void _run(VoidCallback action) {
    _close();
    action();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: 56,
      child: Stack(
        children: [
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SwipeActionButton(
                    label: AppStrings.t(AppStringKeys.chatInfoRemove),
                    color: const Color(0xFFFF9500),
                    onTap: () => _run(widget.onRemove),
                  ),
                  _SwipeActionButton(
                    label: AppStrings.t(AppStringKeys.settingsLogOut),
                    color: AppTheme.tagRed,
                    onTap: () => _run(widget.onLogout),
                  ),
                ],
              ),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            left: _offset,
            right: -_offset,
            top: 0,
            bottom: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _offset < 0 ? _close : widget.onTap,
              onLongPress: widget.onLongPress,
              onHorizontalDragUpdate: (details) {
                final next = (_offset + details.delta.dx).clamp(
                  -_actionsWidth,
                  0.0,
                );
                if (next != _offset) setState(() => _offset = next);
              },
              onHorizontalDragEnd: (_) {
                setState(() {
                  _offset = _offset.abs() > _actionsWidth * 0.35
                      ? -_actionsWidth
                      : 0;
                });
              },
              child: ColoredBox(color: c.card, child: widget.child),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwipeActionButton extends StatelessWidget {
  const _SwipeActionButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: _SwipeAccountRowState._actionWidth,
        height: double.infinity,
        alignment: Alignment.center,
        color: color,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// custom VIP indicator shown next to a Telegram Premium user's name: the profile
/// penguin mascot followed by a gold "VIP" badge.
class _VipBadge extends StatelessWidget {
  const _VipBadge();

  static const _ink = Color(0xFF7A4A00); // dark-gold ink for glyph + lettering

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFE08A), Color(0xFFF5A623)],
        ),
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Penguin silhouette tinted to the same ink as the VIP lettering.
          const ColorFiltered(
            colorFilter: ColorFilter.mode(_ink, BlendMode.srcATop),
            child: Text('🐧', style: TextStyle(fontSize: 13, height: 1.1)),
          ),
          const SizedBox(width: 2),
          Text(
            AppStringKeys.vipBadgeLabel.l10n(context),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
              color: _ink,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}
