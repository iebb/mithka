import 'package:flutter/widgets.dart';

import '../chat/custom_emoji.dart';
import '../chat/emoji_store.dart';
import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../theme/app_theme.dart';

/// Telegram-backed picker for the custom emoji drawn behind a profile photo.
/// A result of zero means that the icon should be removed.
enum ProfileIconSource { profile, status }

class ProfileIconPickerView extends StatefulWidget {
  const ProfileIconPickerView({
    super.key,
    required this.selectedId,
    this.title = AppStringKeys.editProfileProfileIcon,
    this.source = ProfileIconSource.profile,
  });

  final int selectedId;
  final String title;
  final ProfileIconSource source;

  @override
  State<ProfileIconPickerView> createState() => _ProfileIconPickerViewState();
}

class _ProfileIconPickerViewState extends State<ProfileIconPickerView> {
  final TdClient _client = TdClient.shared;
  List<int> _ids = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (widget.source == ProfileIconSource.status) {
      // The topic icon and chat status/reaction surfaces accept any custom
      // emoji the account owns, so the user's installed custom-emoji packs are
      // part of their options. `EmojiStore` already enumerates those sets.
      EmojiStore.shared.addListener(_onEmojiStore);
      EmojiStore.shared.loadIfNeeded();
    }
    _load();
  }

  void _onEmojiStore() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    if (widget.source == ProfileIconSource.status) {
      EmojiStore.shared.removeListener(_onEmojiStore);
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final ids = widget.source == ProfileIconSource.profile
          ? await _loadProfileIcons()
          : await _loadStatusIcons();
      if (!mounted) return;
      setState(() {
        _ids = ids;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<int>> _loadProfileIcons() async {
    final response = await _client.query({
      '@type': 'getDefaultProfilePhotoCustomEmojiStickers',
    });
    return parseStickers(response.objects('stickers'))
        .map((item) => item.customEmojiId)
        .where((id) => id != 0)
        .toSet()
        .toList(growable: false);
  }

  Future<List<int>> _loadStatusIcons() async {
    for (final type in const [
      'getDefaultChatEmojiStatuses',
      'getDefaultEmojiStatuses',
    ]) {
      try {
        final response = await _client.query({'@type': type});
        final ids = <int>{};
        for (final status
            in response.objects('emoji_statuses') ??
                const <Map<String, dynamic>>[]) {
          final id =
              status.int64('custom_emoji_id') ??
              status.obj('type')?.int64('custom_emoji_id');
          if (id != null && id != 0) ids.add(id);
        }
        ids.addAll(
          (response.int64Array('custom_emoji_ids') ?? const <int>[]).where(
            (id) => id != 0,
          ),
        );
        if (ids.isNotEmpty) return ids.toList(growable: false);
      } catch (_) {}
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Profile background emoji come from Telegram's fixed catalogue; only the
    // status/topic surface accepts the user's own installed custom emoji.
    final packs = widget.source == ProfileIconSource.status
        ? EmojiStore.shared.customPacks
        : const <CustomEmojiPack>[];
    return ColoredBox(
      color: c.groupedBackground,
      child: Column(
        children: [
          NavHeader(
            title: widget.title,
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: _loading
                ? const Center(child: _ProfileIconSpinner())
                : _ids.isEmpty && packs.isEmpty
                ? Center(
                    child: Text(
                      AppStringKeys.editProfileProfileIconEmpty.l10n(context),
                      style: TextStyle(fontSize: 15, color: c.textSecondary),
                    ),
                  )
                : CustomScrollView(
                    slivers: [
                      const SliverToBoxAdapter(child: SizedBox(height: 14)),
                      _sectionHeader(
                        AppStringKeys.editProfileDefault.l10n(context),
                      ),
                      _iconGrid(_ids, includeNone: true),
                      for (final pack in packs) ..._packSlivers(pack),
                      const SliverToBoxAdapter(child: SizedBox(height: 28)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// One section per installed pack, in the order Telegram returns the sets.
  List<Widget> _packSlivers(CustomEmojiPack pack) {
    final ids = [
      for (final item in pack.emoji)
        if (item.customEmojiId != 0) item.customEmojiId,
    ];
    if (ids.isEmpty) return const [];
    return [
      _sectionHeader(pack.title, key: ValueKey('profile-icon-pack-${pack.id}')),
      _iconGrid(ids),
    ];
  }

  Widget _sectionHeader(String label, {Key? key}) => SliverToBoxAdapter(
    child: Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: context.colors.textSecondary,
        ),
      ),
    ),
  );

  Widget _iconGrid(List<int> ids, {bool includeNone = false}) {
    final leading = includeNone ? 1 : 0;
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 6,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
        ),
        delegate: SliverChildBuilderDelegate((context, index) {
          if (includeNone && index == 0) return _clearChoice();
          return _emojiChoice(ids[index - leading]);
        }, childCount: ids.length + leading),
      ),
    );
  }

  Widget _clearChoice() {
    final c = context.colors;
    return GestureDetector(
      key: const ValueKey('profile-icon-none'),
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).pop(0),
      child: Container(
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: widget.selectedId == 0
              ? Border.all(color: c.linkBlue, width: 2)
              : null,
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(HeroAppIcons.circleXmark, size: 22, color: c.textTertiary),
            const SizedBox(height: 2),
            Text(
              AppStringKeys.groupAppearanceNone.l10n(context),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: c.textTertiary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emojiChoice(int id) {
    final c = context.colors;
    return GestureDetector(
      key: ValueKey('profile-icon-emoji-$id'),
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).pop(id),
      child: Container(
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: widget.selectedId == id
              ? Border.all(color: c.linkBlue, width: 2)
              : null,
        ),
        alignment: Alignment.center,
        child: CustomEmojiView(id: id, size: 34, color: c.textPrimary),
      ),
    );
  }
}

class _ProfileIconSpinner extends StatefulWidget {
  const _ProfileIconSpinner();

  @override
  State<_ProfileIconSpinner> createState() => _ProfileIconSpinnerState();
}

class _ProfileIconSpinnerState extends State<_ProfileIconSpinner>
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
