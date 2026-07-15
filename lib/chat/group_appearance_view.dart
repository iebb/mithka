import 'package:flutter/widgets.dart';

import '../chat/custom_emoji.dart';
import '../components/app_icons.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../profile/profile_icon_picker_view.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import 'chat_sticker_set_picker_view.dart';
import 'chat_theme_view.dart';
import 'chat_wallpaper_view.dart';

class GroupAppearanceView extends StatefulWidget {
  const GroupAppearanceView({
    super.key,
    required this.chatId,
    required this.supergroupId,
    required this.title,
    required this.isChannel,
    required this.canChangeInfo,
  });

  final int chatId;
  final int supergroupId;
  final String title;
  final bool isChannel;
  final bool canChangeInfo;

  @override
  State<GroupAppearanceView> createState() => _GroupAppearanceViewState();
}

class _GroupAppearanceViewState extends State<GroupAppearanceView> {
  static const _fallbackProfileColors = <_ProfileColorOption>[
    _ProfileColorOption(id: 0, colors: [0xCC5049]),
    _ProfileColorOption(id: 1, colors: [0xD67722]),
    _ProfileColorOption(id: 2, colors: [0x955CDB]),
    _ProfileColorOption(id: 3, colors: [0x40A920]),
    _ProfileColorOption(id: 4, colors: [0x309EBA]),
    _ProfileColorOption(id: 5, colors: [0x368AD1]),
    _ProfileColorOption(id: 6, colors: [0xC7508B]),
  ];

  final TdClient _client = TdClient.shared;
  bool _loading = true;
  int _boostLevel = 0;
  int _profileColorId = -1;
  int _profileIconId = 0;
  int _emojiStatusId = 0;
  int _customEmojiSetId = 0;
  int _stickerSetId = 0;
  int _profileIconLevel = 0;
  int _emojiStatusLevel = 0;
  int _customEmojiSetLevel = 0;
  List<_ProfileColorOption> _profileColors = _fallbackProfileColors;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait([
        _client.query({'@type': 'getChat', 'chat_id': widget.chatId}),
        _client.query({
          '@type': 'getSupergroupFullInfo',
          'supergroup_id': widget.supergroupId,
        }),
        _client.query({
          '@type': 'getChatBoostStatus',
          'chat_id': widget.chatId,
        }),
        _client.query({
          '@type': 'getChatBoostFeatures',
          'is_channel': widget.isChannel,
        }),
        _client.query({'@type': 'getCurrentState'}),
      ]);
      final chat = values[0];
      final full = values[1];
      final status = values[2];
      final features = values[3];
      final state = values[4];
      if (!mounted) return;
      _profileColorId = chat.integer('profile_accent_color_id') ?? -1;
      _profileIconId = chat.int64('profile_background_custom_emoji_id') ?? 0;
      _emojiStatusId = TDParse.emojiStatusCustomEmojiId(
        chat.obj('emoji_status'),
      );
      _customEmojiSetId = full.int64('custom_emoji_sticker_set_id') ?? 0;
      _stickerSetId = full.int64('sticker_set_id') ?? 0;
      _boostLevel = status.integer('level') ?? 0;
      _profileIconLevel =
          features.integer('min_profile_background_custom_emoji_boost_level') ??
          0;
      _emojiStatusLevel = features.integer('min_emoji_status_boost_level') ?? 0;
      _customEmojiSetLevel =
          features.integer('min_custom_emoji_sticker_set_boost_level') ?? 0;
      _profileColors = _parseProfileColors(
        state,
        dark: context.colors.background.computeLuminance() < 0.45,
      );
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  List<_ProfileColorOption> _parseProfileColors(
    Map<String, dynamic> state, {
    required bool dark,
  }) {
    Map<String, dynamic>? update;
    for (final value
        in state.objects('updates') ?? const <Map<String, dynamic>>[]) {
      if (value.type == 'updateProfileAccentColors') {
        update = value;
        break;
      }
    }
    if (update == null) return _fallbackProfileColors;
    final valuesById = <int, Map<String, dynamic>>{};
    for (final value
        in update.objects('colors') ?? const <Map<String, dynamic>>[]) {
      final id = value.integer('id');
      if (id != null) valuesById[id] = value;
    }
    final options = <_ProfileColorOption>[];
    for (final id
        in update.int64Array('available_accent_color_ids') ?? const <int>[]) {
      final value = valuesById[id];
      if (value == null) continue;
      final colors =
          value
              .obj(dark ? 'dark_theme_colors' : 'light_theme_colors')
              ?.int64Array('palette_colors') ??
          const <int>[];
      if (colors.isEmpty) continue;
      options.add(
        _ProfileColorOption(
          id: id,
          colors: colors,
          requiredLevel:
              value.integer(
                widget.isChannel
                    ? 'min_channel_chat_boost_level'
                    : 'min_supergroup_chat_boost_level',
              ) ??
              0,
        ),
      );
    }
    return options.isEmpty ? _fallbackProfileColors : options;
  }

  bool _canUse(int level) =>
      widget.canChangeInfo && (level <= 0 || _boostLevel >= level);

  void _explainLock(int level) {
    if (!widget.canChangeInfo) {
      showToast(context, AppStringKeys.groupManagementNoEditInfoPermission);
      return;
    }
    showToast(
      context,
      context.l10n.t(AppStringKeys.chatWallpaperBoostRequired, {
        'value1': level,
      }),
    );
  }

  Future<void> _setProfileColor(_ProfileColorOption option) async {
    if (!_canUse(option.requiredLevel)) {
      _explainLock(option.requiredLevel);
      return;
    }
    if (option.id == _profileColorId) return;
    try {
      await _client.query({
        '@type': 'setChatProfileAccentColor',
        'chat_id': widget.chatId,
        'profile_accent_color_id': option.id,
        'profile_background_custom_emoji_id': _profileIconId,
      });
      if (mounted) setState(() => _profileColorId = option.id);
    } catch (_) {
      if (mounted) showToast(context, AppStringKeys.groupManagementSetFailed);
    }
  }

  Future<void> _pickProfileIcon() async {
    if (!_canUse(_profileIconLevel)) {
      _explainLock(_profileIconLevel);
      return;
    }
    final id = await Navigator.of(context).push<int>(
      PageRouteBuilder<int>(
        pageBuilder: (_, _, _) => ProfileIconPickerView(
          selectedId: _profileIconId,
          title: AppStringKeys.groupAppearanceProfileIcon,
        ),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
    if (!mounted || id == null || id == _profileIconId) return;
    final colorId = _profileColorId < 0 ? 0 : _profileColorId;
    try {
      await _client.query({
        '@type': 'setChatProfileAccentColor',
        'chat_id': widget.chatId,
        'profile_accent_color_id': colorId,
        'profile_background_custom_emoji_id': id,
      });
      if (!mounted) return;
      setState(() {
        _profileColorId = colorId;
        _profileIconId = id;
      });
    } catch (_) {
      if (mounted) {
        showToast(context, AppStringKeys.groupManagementSetFailed);
      }
    }
  }

  Future<void> _pickEmojiStatus() async {
    if (!_canUse(_emojiStatusLevel)) {
      _explainLock(_emojiStatusLevel);
      return;
    }
    final id = await Navigator.of(context).push<int>(
      PageRouteBuilder<int>(
        pageBuilder: (_, _, _) => ProfileIconPickerView(
          selectedId: _emojiStatusId,
          title: AppStringKeys.groupAppearanceEmojiStatus,
          source: ProfileIconSource.status,
        ),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
    if (!mounted || id == null || id == _emojiStatusId) return;
    try {
      await _client.query({
        '@type': 'setChatEmojiStatus',
        'chat_id': widget.chatId,
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
      if (!mounted) return;
      setState(() => _emojiStatusId = id);
    } catch (_) {
      if (mounted) {
        showToast(context, AppStringKeys.groupManagementSetFailed);
      }
    }
  }

  Future<void> _pickStickerSet({required bool customEmoji}) async {
    final requiredLevel = customEmoji ? _customEmojiSetLevel : 0;
    if (!_canUse(requiredLevel)) {
      _explainLock(requiredLevel);
      return;
    }
    final current = customEmoji ? _customEmojiSetId : _stickerSetId;
    final id = await Navigator.of(context).push<int>(
      PageRouteBuilder<int>(
        pageBuilder: (_, _, _) => ChatStickerSetPickerView(
          title: customEmoji
              ? AppStringKeys.groupAppearanceEmojiPack
              : AppStringKeys.groupAppearanceStickers,
          customEmoji: customEmoji,
          selectedId: current,
        ),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
    if (!mounted || id == null || id == current) return;
    try {
      await _client.query({
        '@type': customEmoji
            ? 'setSupergroupCustomEmojiStickerSet'
            : 'setSupergroupStickerSet',
        'supergroup_id': widget.supergroupId,
        if (customEmoji) 'custom_emoji_sticker_set_id': id,
        if (!customEmoji) 'sticker_set_id': id,
      });
      if (!mounted) return;
      setState(() {
        if (customEmoji) {
          _customEmojiSetId = id;
        } else {
          _stickerSetId = id;
        }
      });
    } catch (_) {
      if (mounted) {
        showToast(context, AppStringKeys.groupManagementSetFailed);
      }
    }
  }

  void _openWallpaper() {
    if (!widget.canChangeInfo) {
      _explainLock(0);
      return;
    }
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) =>
            ChatWallpaperView(chatId: widget.chatId, chatTitle: widget.title),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  void _openTheme() {
    if (!widget.canChangeInfo) {
      _explainLock(0);
      return;
    }
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) =>
            ChatThemeView(chatId: widget.chatId, chatTitle: widget.title),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
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
            title: AppStringKeys.groupAppearanceTitle,
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: _loading
                ? const Center(child: _GroupAppearanceSpinner())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
                    children: [
                      _boostCard(),
                      const SizedBox(height: 14),
                      _profileColorCard(),
                      const SizedBox(height: 14),
                      _settingsCard(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _boostCard() {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          AppIcon(HeroAppIcons.flash, size: 24, color: c.linkBlue),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              context.l10n.t(AppStringKeys.groupAppearanceBoostLevel, {
                'value1': _boostLevel,
              }),
              style: TextStyle(fontSize: 15, color: c.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileColorCard() {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStringKeys.editProfileProfileColor.l10n(context),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final option in _profileColors.take(8))
                Opacity(
                  opacity: _canUse(option.requiredLevel) ? 1 : 0.48,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _setProfileColor(option),
                    child: Container(
                      width: 34,
                      height: 34,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: option.id == _profileColorId
                            ? Border.all(color: c.linkBlue, width: 2)
                            : null,
                      ),
                      child: ClipOval(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: option.colors.length > 1
                                ? LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: option.colors
                                        .map(
                                          (value) => Color(
                                            0xFF000000 | (value & 0x00FFFFFF),
                                          ),
                                        )
                                        .toList(growable: false),
                                  )
                                : null,
                            color: option.colors.length == 1
                                ? Color(
                                    0xFF000000 |
                                        (option.colors.first & 0x00FFFFFF),
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _settingsCard() {
    final c = context.colors;
    final rows = <Widget>[
      _row(
        AppStringKeys.groupAppearanceProfileIcon,
        requiredLevel: _profileIconLevel,
        emojiId: _profileIconId,
        onTap: _pickProfileIcon,
      ),
      _row(
        AppStringKeys.groupAppearanceEmojiPack,
        requiredLevel: _customEmojiSetLevel,
        onTap: () => _pickStickerSet(customEmoji: true),
      ),
      _row(
        AppStringKeys.groupAppearanceEmojiStatus,
        requiredLevel: _emojiStatusLevel,
        emojiId: _emojiStatusId,
        onTap: _pickEmojiStatus,
      ),
      _row(
        AppStringKeys.groupAppearanceStickers,
        onTap: () => _pickStickerSet(customEmoji: false),
      ),
      _row(AppStringKeys.chatThemeTitle, onTap: _openTheme),
      _row(AppStringKeys.groupAppearanceWallpaper, onTap: _openWallpaper),
    ];
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i != 0) const InsetDivider(leadingInset: 14),
            rows[i],
          ],
        ],
      ),
    );
  }

  Widget _row(
    String key, {
    required VoidCallback onTap,
    int requiredLevel = 0,
    int emojiId = 0,
  }) {
    final c = context.colors;
    final locked = !_canUse(requiredLevel);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  key.l10n(context),
                  style: TextStyle(
                    fontSize: 15,
                    color: locked ? c.textTertiary : c.textPrimary,
                  ),
                ),
              ),
              if (emojiId != 0) ...[
                CustomEmojiView(id: emojiId, size: 24, color: c.textPrimary),
                const SizedBox(width: 8),
              ],
              if (locked && requiredLevel > 0) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const AppIcon(
                        HeroAppIcons.lock,
                        size: 11,
                        color: Color(0xFFFFFFFF),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        context.l10n.t(AppStringKeys.chatWallpaperBoostLevel, {
                          'value1': requiredLevel,
                        }),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFFFFFFF),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],
              AppIcon(
                HeroAppIcons.chevronRight,
                size: 14,
                color: c.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileColorOption {
  const _ProfileColorOption({
    required this.id,
    required this.colors,
    this.requiredLevel = 0,
  });

  final int id;
  final List<int> colors;
  final int requiredLevel;
}

class _GroupAppearanceSpinner extends StatefulWidget {
  const _GroupAppearanceSpinner();

  @override
  State<_GroupAppearanceSpinner> createState() =>
      _GroupAppearanceSpinnerState();
}

class _GroupAppearanceSpinnerState extends State<_GroupAppearanceSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
    turns: _controller,
    child: AppIcon(
      HeroAppIcons.rotate,
      size: 24,
      color: context.colors.textTertiary,
    ),
  );
}
