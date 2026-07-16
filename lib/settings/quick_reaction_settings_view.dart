import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../chat/custom_emoji.dart';
import '../chat/emoji_store.dart';
import '../chat/quick_reaction_choice.dart';
import '../components/app_icons.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';

class QuickReactionSettingsView extends StatefulWidget {
  const QuickReactionSettingsView({super.key});

  @override
  State<QuickReactionSettingsView> createState() =>
      _QuickReactionSettingsViewState();
}

class _QuickReactionSettingsViewState extends State<QuickReactionSettingsView> {
  static const _maximumReactions = 9;
  String _tab = 'standard';

  @override
  void initState() {
    super.initState();
    EmojiStore.shared.loadIfNeeded();
  }

  void _toggle(QuickReactionChoice reaction) {
    final controller = context.read<ThemeController>();
    final selected = [
      ...effectiveQuickReactions(
        controller.quickReactions,
        allowCustomEmoji: EmojiStore.shared.isPremium,
      ),
    ];
    final index = selected.indexOf(reaction);
    if (index >= 0) {
      if (selected.length == 1) {
        showToast(context, AppStringKeys.quickReactionsKeepOne);
        return;
      }
      selected.removeAt(index);
    } else {
      if (selected.length >= _maximumReactions) {
        showToast(context, AppStringKeys.quickReactionsLimit);
        return;
      }
      selected.add(reaction);
    }
    controller.setQuickReactions(selected);
  }

  void _move(QuickReactionChoice reaction, int targetIndex) {
    final controller = context.read<ThemeController>();
    final selected = [
      ...effectiveQuickReactions(
        controller.quickReactions,
        allowCustomEmoji: EmojiStore.shared.isPremium,
      ),
    ];
    final oldIndex = selected.indexOf(reaction);
    if (oldIndex < 0 || oldIndex == targetIndex) return;
    selected.removeAt(oldIndex);
    selected.insert(targetIndex.clamp(0, selected.length), reaction);
    controller.setQuickReactions(selected);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final controller = context.watch<ThemeController>();
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.quickReactionsTitle),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: AnimatedBuilder(
              animation: EmojiStore.shared,
              builder: (context, _) {
                final selected = effectiveQuickReactions(
                  controller.quickReactions,
                  allowCustomEmoji: EmojiStore.shared.isPremium,
                );
                return ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.xl,
                    AppSpacing.lg,
                    AppSpacing.section,
                  ),
                  children: [
                    _sectionLabel(AppStringKeys.quickReactionsSelected),
                    _selectedStrip(selected),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xxl,
                        AppSpacing.sm,
                        AppSpacing.xxl,
                        AppSpacing.xl,
                      ),
                      child: Text(
                        AppStrings.t(AppStringKeys.quickReactionsHint),
                        style: AppTextStyle.footnote(c.textTertiary),
                      ),
                    ),
                    _sectionLabel(AppStringKeys.quickReactionsAvailable),
                    _picker(selected),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String key) => Padding(
    padding: const EdgeInsets.only(left: AppSpacing.xxl, bottom: AppSpacing.sm),
    child: Text(
      AppStrings.t(key),
      style: AppTextStyle.footnote(context.colors.textTertiary),
    ),
  );

  Widget _selectedStrip(List<QuickReactionChoice> selected) {
    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        itemCount: selected.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
        itemBuilder: (context, index) {
          final reaction = selected[index];
          return DragTarget<QuickReactionChoice>(
            onWillAcceptWithDetails: (details) => details.data != reaction,
            onAcceptWithDetails: (details) => _move(details.data, index),
            builder: (context, candidates, _) => LongPressDraggable(
              data: reaction,
              axis: Axis.horizontal,
              feedback: Directionality(
                textDirection: Directionality.of(context),
                child: _reactionTile(reaction, selected: true, elevated: true),
              ),
              childWhenDragging: Opacity(
                opacity: 0.25,
                child: _reactionTile(reaction, selected: true),
              ),
              child: AnimatedScale(
                duration: const Duration(milliseconds: 120),
                scale: candidates.isEmpty ? 1 : 1.08,
                child: _reactionTile(
                  reaction,
                  selected: true,
                  onTap: () => _toggle(reaction),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _picker(List<QuickReactionChoice> selected) {
    final store = EmojiStore.shared;
    final packs = store.isPremium
        ? store.customPacks
        : const <CustomEmojiPack>[];
    if (_tab != 'standard' &&
        !packs.any((pack) => pack.id.toString() == _tab)) {
      _tab = 'standard';
    }
    return Container(
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            height: 50,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              children: [
                _tabButton(
                  'standard',
                  AppIcon(
                    HeroAppIcons.solidFaceSmile,
                    size: 22,
                    color: _tab == 'standard'
                        ? AppTheme.brand
                        : context.colors.textSecondary,
                  ),
                ),
                for (final pack in packs)
                  _tabButton(
                    pack.id.toString(),
                    pack.emoji.isEmpty
                        ? Text(
                            pack.title.isEmpty
                                ? ''
                                : pack.title.characters.first,
                            style: TextStyle(color: context.colors.textPrimary),
                          )
                        : CustomEmojiView(
                            id: pack.emoji.first.customEmojiId,
                            size: 28,
                            color: context.colors.textPrimary,
                          ),
                  ),
              ],
            ),
          ),
          const InsetDivider(leadingInset: 0),
          _reactionGrid(selected, packs),
        ],
      ),
    );
  }

  Widget _tabButton(String id, Widget child) {
    final active = _tab == id;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _tab = id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 42,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active
              ? AppTheme.brand.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: child,
      ),
    );
  }

  Widget _reactionGrid(
    List<QuickReactionChoice> selected,
    List<CustomEmojiPack> packs,
  ) {
    List<QuickReactionChoice> choices;
    if (_tab == 'standard') {
      choices = availableStandardReactions
          .map(QuickReactionChoice.emoji)
          .toList();
    } else {
      final pack = packs.where((p) => p.id.toString() == _tab).firstOrNull;
      choices = pack == null
          ? const []
          : pack.emoji
                .where((item) => item.customEmojiId != 0)
                .map((item) => QuickReactionChoice.custom(item.customEmojiId))
                .toList();
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.md),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: AppSpacing.xs,
        crossAxisSpacing: AppSpacing.xs,
      ),
      itemCount: choices.length,
      itemBuilder: (context, index) {
        final reaction = choices[index];
        return _reactionTile(
          reaction,
          selected: selected.contains(reaction),
          onTap: () => _toggle(reaction),
        );
      },
    );
  }

  Widget _reactionTile(
    QuickReactionChoice reaction, {
    required bool selected,
    bool elevated = false,
    VoidCallback? onTap,
  }) {
    final c = context.colors;
    final tile = Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? AppTheme.brand.withValues(alpha: 0.14) : c.card,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: selected ? Border.all(color: AppTheme.brand, width: 1.5) : null,
        boxShadow: elevated
            ? const [BoxShadow(color: Color(0x33000000), blurRadius: 10)]
            : null,
      ),
      child: reaction.isCustom
          ? CustomEmojiView(
              id: reaction.customEmojiId,
              size: 30,
              color: c.textPrimary,
            )
          : Text(
              reaction.emoji,
              textScaler: TextScaler.noScaling,
              style: const TextStyle(fontSize: 29),
            ),
    );
    if (onTap == null) return tile;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: tile,
    );
  }
}
