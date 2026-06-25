//
//  profile_view.dart
//
//  The "我" side menu (slides in from the left, ~88% width). Redesigned to match
//  QQ's drawer: an azure avatar banner → an edit-profile card → a vertical list
//  of rows (相册 / 收藏 / 文件 / 外观 / 二维码) → account switcher → a bottom bar
//  (设置 · 夜间模式). Backed by real TDLib via ProfileViewModel + AccountStore.
//

import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../components/toast.dart';
import 'package:provider/provider.dart';

import '../auth/account_store.dart';
import '../auth/auth_manager.dart';
import '../chat/chat_view.dart';
import '../chat/custom_emoji.dart';
import '../chat/emoji_store.dart';
import '../components/confirm_dialog.dart';
import '../components/drawer_controller.dart' as dc;
import '../components/photo_avatar.dart';
import '../components/sf_symbols.dart';
import '../components/ui_components.dart';
import '../chat/shared_media_view.dart';
import '../settings/edit_profile_view.dart';
import '../settings/settings_view.dart';
import 'my_album_view.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
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

  /// QQ's status picker, mapped to Telegram's emoji status: suggested
  /// custom-emoji statuses plus — for Premium users — every installed custom-emoji
  /// pack, so any custom emoji can be set as the status. (+ a clear option) →
  /// setEmojiStatus.
  void _openStatusPicker() {
    EmojiStore.shared.loadIfNeeded(); // populate the Premium custom-emoji packs
    final optionsFuture = _vm.statusOptions();
    // A Cupertino modal popup on the root navigator — not Material's
    // showModalBottomSheet — so its barrier reliably covers the whole screen
    // (the drawer is itself an overlay; a non-root sheet let taps bleed through
    // to the chat list behind it).
    showCupertinoModalPopup<void>(
      context: context,
      useRootNavigator: true,
      builder: (sheetContext) {
        final c = sheetContext.colors;
        final maxHeight = MediaQuery.of(sheetContext).size.height * 0.6;

        Future<void> pick(int id) async {
          final ok = await _vm.setEmojiStatus(id);
          if (!sheetContext.mounted) return;
          Navigator.of(sheetContext).pop();
          if (!ok && mounted) showToast(context, '设置状态失败（需要 Premium）');
        }

        Widget grid(List<int> ids) {
          if (ids.isEmpty) {
            return Center(
              child: Text(
                '该表情包暂无可用状态',
                style: TextStyle(fontSize: 13, color: c.textSecondary),
              ),
            );
          }
          return GridView.count(
            crossAxisCount: 6,
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              for (final id in ids)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => pick(id),
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: CustomEmojiView(
                      id: id,
                      size: 34,
                      color: c.textPrimary,
                    ),
                  ),
                ),
            ],
          );
        }

        var statusTab = 0; // 0 = 推荐 (suggested); 1..N = custom packs
        return Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: maxHeight,
                child: ListenableBuilder(
                  listenable: EmojiStore.shared,
                  builder: (ctx, _) {
                    final packs = EmojiStore.shared.isPremium
                        ? EmojiStore.shared.customPacks
                        : const <CustomEmojiPack>[];
                    return StatefulBuilder(
                      builder: (ctx2, setSheet) {
                        if (statusTab > packs.length) statusTab = 0;
                        return Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                              child: Row(
                                children: [
                                  Text(
                                    '设置状态',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: c.textPrimary,
                                    ),
                                  ),
                                  const Spacer(),
                                  if ((_vm.user?.emojiStatusId ?? 0) != 0)
                                    GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => pick(0),
                                      child: Text(
                                        '清除',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: AppTheme.tagRed,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: statusTab == 0
                                    ? FutureBuilder<List<int>>(
                                        future: optionsFuture,
                                        builder: (context, snap) {
                                          if (snap.connectionState !=
                                              ConnectionState.done) {
                                            return const Center(
                                              child: SizedBox(
                                                width: 24,
                                                height: 24,
                                                child:
                                                    CircularProgressIndicator.adaptive(
                                                      strokeWidth: 2,
                                                    ),
                                              ),
                                            );
                                          }
                                          final ids =
                                              snap.data ?? const <int>[];
                                          if (ids.isEmpty && packs.isEmpty) {
                                            return Center(
                                              child: Text(
                                                '暂无可用状态（需要 Premium）',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: c.textSecondary,
                                                ),
                                              ),
                                            );
                                          }
                                          return grid(ids);
                                        },
                                      )
                                    : grid([
                                        for (final e
                                            in packs[statusTab - 1].emoji)
                                          if (e.customEmojiId != 0)
                                            e.customEmojiId,
                                      ]),
                              ),
                            ),
                            // Tabs: 推荐 + one per installed custom-emoji pack.
                            if (packs.isNotEmpty)
                              _statusTabStrip(
                                c,
                                packs,
                                statusTab,
                                (i) => setSheet(() => statusTab = i),
                              ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Bottom tab strip for the status picker: 推荐 + one tab per custom-emoji pack.
  Widget _statusTabStrip(
    dynamic c,
    List<CustomEmojiPack> packs,
    int selected,
    ValueChanged<int> onTap,
  ) {
    Widget tab(int i, Widget child) {
      final active = i == selected;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(i),
        child: Container(
          width: 42,
          height: 42,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: active ? c.searchFill : null,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: child,
        ),
      );
    }

    return Container(
      height: 54,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        children: [
          tab(
            0,
            Icon(
              sfIcon('star.fill'),
              size: 22,
              color: selected == 0 ? AppTheme.brand : c.textSecondary,
            ),
          ),
          for (var i = 0; i < packs.length; i++)
            tab(i + 1, _packTabIcon(packs[i], c)),
        ],
      ),
    );
  }

  Widget _packTabIcon(CustomEmojiPack pack, dynamic c) {
    final withId = pack.emoji.where((e) => e.customEmojiId != 0).toList();
    if (withId.isNotEmpty) {
      return CustomEmojiView(
        id: withId.first.customEmojiId,
        size: 26,
        color: c.textPrimary,
      );
    }
    if (pack.cover != null) {
      return SizedBox(
        width: 26,
        height: 26,
        child: TDImage(photo: pack.cover, cornerRadius: 4),
      );
    }
    return Icon(sfIcon('square.grid.2x2'), size: 22, color: c.textSecondary);
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
              padding: const EdgeInsets.only(top: 0, bottom: 0),
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
    final username = (user?.username?.isNotEmpty ?? false)
        ? '@${user!.username}'
        : (user?.phoneNumber ?? '');
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
                  onTap: () => _root.push(
                    MaterialPageRoute(
                      builder: (_) => QRCodeView(name: user?.name ?? '我'),
                    ),
                  ),
                  child: Icon(sfIcon('qrcode'), size: 22, color: Colors.white),
                ),
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: () => context.read<dc.DrawerController>().close(),
                  child: Icon(sfIcon('xmark'), size: 22, color: Colors.white),
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
                    title: user?.name ?? '我',
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
                              user?.name ?? '加载中…',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          if (user?.isPremium ?? false) ...[
                            const SizedBox(width: 6),
                            const _VipBadge(),
                          ],
                          if ((user?.emojiStatusId ?? 0) != 0) ...[
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: _openStatusPicker,
                              child: CustomEmojiView(
                                id: user!.emojiStatusId,
                                size: 24,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ],
                      ),
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
                  ),
                ),
                const SizedBox(width: 8),
                // Edit profile — replaces the old duplicate 编辑资料 card.
                GestureDetector(
                  onTap: () => _root.push(
                    MaterialPageRoute(builder: (_) => const EditProfileView()),
                  ),
                  child: Icon(
                    sfIcon('square.and.pencil'),
                    size: 22,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Builder(
              builder: (context) {
                final premium = user?.isPremium ?? false;
                final hasStatus = (user?.emojiStatusId ?? 0) != 0;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _openStatusPicker,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (hasStatus)
                          CustomEmojiView(
                            id: user!.emojiStatusId,
                            size: 16,
                            color: Colors.white,
                          )
                        else
                          const Icon(
                            Icons.circle,
                            size: 8,
                            color: Color(0xFF1AC81A),
                          ),
                        const SizedBox(width: 5),
                        Text(
                          hasStatus ? '设置状态' : '在线',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                          ),
                        ),
                        if (premium) ...[
                          const SizedBox(width: 3),
                          Icon(
                            sfIcon('chevron.down'),
                            size: 10,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // MARK: - QQ-style vertical rows

  Widget _rowsCard() {
    return Container(
      decoration: BoxDecoration(color: context.colors.card),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _row('photo', const Color(0xFFF5A623), '相册', () {
            _root.push(
              MaterialPageRoute(
                builder: (_) => MyAlbumView(userId: _vm.user?.id ?? 0),
              ),
            );
          }),
          _row('star', const Color(0xFFFF9D2E), '收藏', () => _openSaved('收藏')),
          _row('folder', const Color(0xFF3C8CF0), '文件', () {
            final cid = _vm.savedChatId ?? _vm.user?.id ?? 0;
            _root.push(
              MaterialPageRoute(
                builder: (_) =>
                    SharedMediaView(chatId: cid, title: '文件', initialTab: 1),
              ),
            );
          }),
          _row('qrcode', AppTheme.brand, '二维码名片', () {
            _root.push(
              MaterialPageRoute(
                builder: (_) => QRCodeView(name: _vm.user?.name ?? '我'),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _row(String icon, Color color, String label, VoidCallback onTap) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 54,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 32,
                alignment: Alignment.center,
                child: Icon(sfIcon(icon), size: 20, color: color),
              ),
              const SizedBox(width: 12),
              Text(label, style: TextStyle(fontSize: 15, color: c.textPrimary)),
              const Spacer(),
              Icon(sfIcon('chevron.right'), size: 15, color: c.textTertiary),
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
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          const InsetDivider(leadingInset: 0),
          for (final s in accounts.summaries) ...[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () =>
                  accounts.switchTo(s.slot, context.read<AuthManager>()),
              onLongPress: accounts.summaries.length > 1
                  ? () => _confirmRemoveAccount(accounts, s)
                  : null,
              child: _accountRow(
                s.name,
                s.phone,
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
                      child: Icon(
                        sfIcon('plus'),
                        size: 18,
                        color: AppTheme.brand,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '添加账号',
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

  /// Long-press an account row to remove it from the switcher — for clearing a
  /// leftover "未登录" entry or a logged-out account you no longer want.
  Future<void> _confirmRemoveAccount(
    AccountStore accounts,
    AccountSummary s,
  ) async {
    final label = s.phone.isNotEmpty ? '${s.name}（${s.phone}）' : s.name;
    final ok = await confirmDialog(
      context,
      title: '移除账号',
      message: '将从账号列表移除 $label。可随时重新登录。',
      confirmText: '移除',
      destructive: true,
    );
    if (!ok || !mounted) return;
    accounts.removeAccount(s.slot, context.read<AuthManager>());
  }

  Widget _accountRow(
    String name,
    String phone,
    String? avatarPath, {
    required bool selected,
  }) {
    final c = context.colors;
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
              Icon(sfIcon('checkmark'), size: 16, color: AppTheme.brand),
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
                child: _barItem('gearshape', '设置'),
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
                  isDark ? 'sun.max' : 'moon',
                  isDark ? '日间' : '夜间',
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _barItem(String icon, String label) {
    final c = context.colors;
    return SizedBox(
      width: 58,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(sfIcon(icon), size: 22, color: c.textPrimary),
          const SizedBox(height: 5),
          Text(label, style: TextStyle(fontSize: 13, color: c.textPrimary)),
        ],
      ),
    );
  }
}

/// QQ-style VIP indicator shown next to a Telegram Premium user's name: the QQ
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
          const Text(
            'VIP',
            style: TextStyle(
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
