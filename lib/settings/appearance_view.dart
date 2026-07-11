//
//  appearance_view.dart
//

import 'dart:io';

//  外观: theme mode (跟随系统 / 浅色 / 深色) + tab-bar style (经典 / 系统), driving
//  ThemeController live. Mapped from the reference app's 外观/装扮 entry.
//

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/l10n/preview_texts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../components/app_icons.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../theme/app_theme.dart';
import '../theme/emoji_font_catalog.dart';
import '../theme/system_font_catalog.dart';
import '../theme/theme_controller.dart';
import 'app_icon_controller.dart';

class AppearanceView extends StatelessWidget {
  const AppearanceView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = context.watch<ThemeController>();
    final appIcons = context.watch<AppIconController>();
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.appearanceTitle),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.section,
              ),
              children: [
                _label(context, AppStrings.t(AppStringKeys.appearanceMode)),
                _card(context, [
                  for (final m in AppearanceMode.values)
                    _choiceRow(
                      context,
                      m.icon,
                      m.label,
                      theme.mode == m,
                      () => theme.mode = m,
                    ),
                ]),
                const SizedBox(height: AppSpacing.xl),
                _label(context, AppStrings.t(AppStringKeys.appIconTitle)),
                _card(context, [
                  _navigationRow(
                    context,
                    AppStrings.t(AppStringKeys.appIconTitle),
                    null,
                    () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AppIconSettingsView(),
                      ),
                    ),
                    preview: Image.asset(
                      appIcons.variant.asset,
                      width: AppIconSize.nav,
                      height: AppIconSize.nav,
                    ),
                  ),
                ]),
                const SizedBox(height: AppSpacing.xl),
                _label(context, AppStrings.t(AppStringKeys.appearanceFont)),
                _card(context, [
                  _navigationRow(
                    context,
                    AppStrings.t(AppStringKeys.appearanceFont),
                    theme.effectiveFontChainLabel,
                    () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const FontSettingsView(),
                      ),
                    ),
                    icon: HeroAppIcons.font.data,
                  ),
                ]),
                const SizedBox(height: AppSpacing.xl),
                _label(context, AppStrings.t(AppStringKeys.appearanceColor)),
                _colorCard(context, theme),
                const SizedBox(height: AppSpacing.xl),
                _label(context, AppStrings.t(AppStringKeys.appearanceSize)),
                _fontSizeCard(context, theme),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AppIconSettingsView extends StatelessWidget {
  const AppIconSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final controller = context.watch<AppIconController>();
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.appIconTitle),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Column(
              children: [
                if (!controller.supported)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      AppSpacing.xl,
                      AppSpacing.xl,
                      0,
                    ),
                    child: Text(
                      AppStrings.t(AppStringKeys.appIconUnsupported),
                      style: TextStyle(
                        fontSize: AppTextSize.footnote,
                        color: c.textTertiary,
                      ),
                    ),
                  ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      AppSpacing.xl,
                      AppSpacing.xl,
                      AppSpacing.section,
                    ),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 132,
                          mainAxisExtent: 116,
                          mainAxisSpacing: AppSpacing.xl,
                          crossAxisSpacing: AppSpacing.xl,
                        ),
                    itemCount: AppIconVariant.values.length,
                    itemBuilder: (context, index) {
                      final variant = AppIconVariant.values[index];
                      return _AppIconVariantTile(
                        variant: variant,
                        selected: controller.variant == variant,
                        loading: controller.loading,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AppIconVariantTile extends StatelessWidget {
  const _AppIconVariantTile({
    required this.variant,
    required this.selected,
    required this.loading,
  });

  final AppIconVariant variant;
  final bool selected;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final controller = context.read<AppIconController>();
    return Semantics(
      button: true,
      selected: selected,
      label: AppStrings.t(variant.labelKey),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: loading
            ? null
            : () async {
                final ok = await controller.setVariant(variant);
                if (!ok && context.mounted) {
                  showToast(context, AppStringKeys.appIconChangeFailed);
                }
              },
        child: Center(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 96,
                height: 96,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(23),
                  border: Border.all(
                    color: selected ? AppTheme.brand : c.divider,
                    width: selected ? 3 : 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.asset(variant.asset, fit: BoxFit.cover),
                ),
              ),
              if (selected)
                Positioned(
                  right: -6,
                  bottom: -6,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppTheme.brand,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.groupedBackground, width: 3),
                    ),
                    alignment: Alignment.center,
                    child: const AppIcon(
                      HeroAppIcons.check,
                      size: 15,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class DisplaySettingsView extends StatelessWidget {
  const DisplaySettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = context.watch<ThemeController>();
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.appearanceDisplay),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.section,
              ),
              children: [
                _card(context, [
                  _toggleRow(
                    context,
                    HeroAppIcons.users.data,
                    AppStrings.t(AppStringKeys.appearanceRoundGroupAvatars),
                    theme.circularGroupAvatars,
                    (v) => theme.circularGroupAvatars = v,
                  ),
                  _toggleRow(
                    context,
                    HeroAppIcons.eyeSlash.data,
                    AppStrings.t(AppStringKeys.appearanceHidePhoneInSidebar),
                    theme.hideSidebarPhone,
                    (v) => theme.hideSidebarPhone = v,
                  ),
                ]),
                const SizedBox(height: AppSpacing.xl),
                _label(context, AppStrings.t(AppStringKeys.appearanceChatView)),
                _card(context, [
                  _toggleRow(
                    context,
                    HeroAppIcons.idBadge.data,
                    AppStrings.t(AppStringKeys.appearanceShowGroupMemberTitles),
                    theme.showMemberTags,
                    (v) => theme.showMemberTags = v,
                  ),
                  _toggleRow(
                    context,
                    HeroAppIcons.images.data,
                    AppStrings.t(
                      AppStringKeys.appearanceMergeConsecutiveImages,
                    ),
                    theme.groupImageMessages,
                    (v) => theme.groupImageMessages = v,
                  ),
                  _toggleRow(
                    context,
                    HeroAppIcons.palette.data,
                    AppStrings.t(AppStringKeys.appearanceShowPremiumNameColor),
                    theme.showChatPremiumNameColors,
                    (v) => theme.showChatPremiumNameColors = v,
                  ),
                  _toggleRow(
                    context,
                    HeroAppIcons.solidFaceSmile.data,
                    AppStrings.t(
                      AppStringKeys.appearanceShowPremiumStatusEmoji,
                    ),
                    theme.showChatPremiumEmojiStatus,
                    (v) => theme.showChatPremiumEmojiStatus = v,
                  ),
                ]),
                const SizedBox(height: AppSpacing.xl),
                _label(context, AppStrings.t(AppStringKeys.appearanceChatList)),
                _card(context, [
                  _navigationRow(
                    context,
                    AppStrings.t(AppStringKeys.appearanceChatFolders),
                    AppStrings.t(theme.chatFolderDisplayMode.label),
                    () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ChatFolderSettingsView(),
                      ),
                    ),
                    icon: HeroAppIcons.folder.data,
                  ),
                  _toggleRow(
                    context,
                    HeroAppIcons.magnifyingGlass.data,
                    AppStrings.t(AppStringKeys.appearanceShowChatListSearch),
                    theme.showChatListSearch,
                    (v) => theme.showChatListSearch = v,
                  ),
                  _toggleRow(
                    context,
                    HeroAppIcons.thumbtack.data,
                    AppStrings.t(
                      AppStringKeys.appearanceDisplayOwnChatAsFavorites,
                    ),
                    theme.displayOwnChatAsFavorites,
                    (v) => theme.displayOwnChatAsFavorites = v,
                  ),
                  if (theme.chatFolderDisplayMode ==
                      ChatFolderDisplayMode.tabs) ...[
                    _toggleRow(
                      context,
                      HeroAppIcons.pictureInPicture.data,
                      AppStrings.t(
                        AppStringKeys.appearanceDisableChatListSwipeActions,
                      ),
                      theme.disableChatListSwipeActions,
                      (v) => theme.disableChatListSwipeActions = v,
                    ),
                    _toggleRow(
                      context,
                      HeroAppIcons.arrowsUpDown.data,
                      AppStrings.t(
                        AppStringKeys.appearanceChatListFolderSwipeSwitching,
                      ),
                      theme.chatListFolderSwipeSwitching,
                      (theme.disableChatListSwipeActions &&
                              theme.chatFolderDisplayMode ==
                                  ChatFolderDisplayMode.tabs)
                          ? (v) => theme.chatListFolderSwipeSwitching = v
                          : null,
                    ),
                  ],
                  _toggleRow(
                    context,
                    HeroAppIcons.palette.data,
                    AppStrings.t(AppStringKeys.appearanceShowPremiumNameColor),
                    theme.showPremiumNameColors,
                    (v) => theme.showPremiumNameColors = v,
                  ),
                  _toggleRow(
                    context,
                    HeroAppIcons.solidFaceSmile.data,
                    AppStrings.t(
                      AppStringKeys.appearanceShowPremiumStatusEmoji,
                    ),
                    theme.showPremiumEmojiStatus,
                    (v) => theme.showPremiumEmojiStatus = v,
                  ),
                ]),
                const SizedBox(height: AppSpacing.xl),
                _label(
                  context,
                  AppStrings.t(AppStringKeys.appearanceGroupAssistantPosition),
                ),
                _card(context, [
                  for (final m in GroupAssistantPlacement.values)
                    _choiceRow(
                      context,
                      m.icon,
                      m.label,
                      theme.groupAssistantPlacement == m,
                      () => theme.groupAssistantPlacement = m,
                    ),
                ]),
                const SizedBox(height: AppSpacing.xl),
                _label(
                  context,
                  AppStrings.t(AppStringKeys.appearanceUnreadBadge),
                ),
                _card(context, [
                  _toggleRow(
                    context,
                    HeroAppIcons.message.data,
                    AppStrings.t(AppStringKeys.appearanceShowUnreadChatCount),
                    theme.unreadBadgeShowsChatCount,
                    (v) => theme.unreadBadgeShowsChatCount = v,
                  ),
                  _toggleRow(
                    context,
                    HeroAppIcons.solidBell.data,
                    AppStrings.t(AppStringKeys.appearanceCapUnreadCountAt99),
                    theme.capUnreadBadgeAt99,
                    (v) => theme.capUnreadBadgeAt99 = v,
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String t) =>
      const AppearanceView()._label(context, t);

  Widget _card(BuildContext context, List<Widget> rows) =>
      const AppearanceView()._card(context, rows);

  Widget _choiceRow(
    BuildContext context,
    IconData icon,
    String label,
    bool selected,
    VoidCallback onTap,
  ) => const AppearanceView()._choiceRow(context, icon, label, selected, onTap);

  Widget _toggleRow(
    BuildContext context,
    IconData icon,
    String label,
    bool value,
    ValueChanged<bool>? onChanged,
  ) =>
      const AppearanceView()._toggleRow(context, icon, label, value, onChanged);

  Widget _navigationRow(
    BuildContext context,
    String label,
    String? value,
    VoidCallback onTap, {
    IconData? icon,
  }) => const AppearanceView()._navigationRow(
    context,
    label,
    value,
    onTap,
    icon: icon,
  );
}

class ChatFolderSettingsView extends StatelessWidget {
  const ChatFolderSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = context.watch<ThemeController>();
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.appearanceChatFolders),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.section,
              ),
              children: [
                const AppearanceView()._card(context, [
                  for (final mode in ChatFolderDisplayMode.values)
                    const AppearanceView()._choiceRow(
                      context,
                      mode.icon,
                      mode.label,
                      theme.chatFolderDisplayMode == mode,
                      () => theme.chatFolderDisplayMode = mode,
                    ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

extension _DisplayAppearanceHelpers on AppearanceView {
  static const _colorSwatchSize = (AppMetric.hitTarget - AppSpacing.xxs) * 0.9;
  static const _colorSwatchGap = AppSpacing.xxl * 0.9;

  static const _palette = [
    Color(0xFF0099FF), // 蔚蓝 (default)
    Color(0xFF2DC100), // 绿
    Color(0xFF00C4B3), // 青
    Color(0xFF4A6CF7), // 靛蓝
    Color(0xFF8E7BFF), // 紫
    Color(0xFFFF5E7D), // 粉
    Color(0xFFFA5151), // 红
    Color(0xFFFF9500), // 橙
    Color(0xFFFFCC00), // 黄
    Color(0xFF9ACD32), // 青柠
    Color(0xFF00A884), // 翠绿
    Color(0xFF32ADE6), // 天蓝
    Color(0xFF5E5CE6), // 蓝紫
    Color(0xFFAF52DE), // 洋紫
    Color(0xFFFF2D55), // 玫红
    Color(0xFF8E8E93), // 灰
  ];

  Widget _colorCard(BuildContext context, ThemeController theme) {
    final c = context.colors;
    final selected = theme.brandColor.toARGB32();
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxl,
        vertical: AppSpacing.xxl,
      ),
      child: Wrap(
        spacing: _colorSwatchGap,
        runSpacing: AppSpacing.xl * 0.9,
        children: [
          for (final color in _palette)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => theme.brandColor = color,
              child: Container(
                width: _colorSwatchSize,
                height: _colorSwatchSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: color.toARGB32() == selected
                      ? Border.all(
                          color: c.textPrimary,
                          width: AppMetric.selectedBorder,
                        )
                      : null,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.4),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: color.toARGB32() == selected
                    ? const AppIcon(
                        HeroAppIcons.check,
                        size: 18,
                        color: Colors.white,
                      )
                    : null,
              ),
            ),
        ],
      ),
    );
  }

  Widget _fontSizeCard(BuildContext context, ThemeController theme) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _scaleSlider(
            context,
            icon: HeroAppIcons.font.data,
            title: AppStrings.t(AppStringKeys.appearanceFontSize),
            value: theme.fontScale,
            min: ThemeController.minFontScale,
            max: ThemeController.maxFontScale,
            divisions: 24,
            leading: Text(
              'A',
              style: TextStyle(
                fontSize: AppTextSize.footnote,
                color: c.textSecondary,
              ),
            ),
            trailing: Text(
              'A',
              style: TextStyle(
                fontSize: AppTextSize.largeDisplay,
                color: c.textPrimary,
              ),
            ),
            onChanged: (value) => theme.fontScale = value,
          ),
          const InsetDivider(leadingInset: 52),
          _scaleSlider(
            context,
            icon: HeroAppIcons.tableCells.data,
            title: AppStrings.t(AppStringKeys.appearanceInterfaceSize),
            value: theme.interfaceScale,
            min: ThemeController.minInterfaceScale,
            max: ThemeController.maxInterfaceScale,
            divisions: 84,
            leading: AppIcon(
              HeroAppIcons.square,
              size: AppTextSize.body,
              color: c.textSecondary,
            ),
            trailing: AppIcon(
              HeroAppIcons.square,
              size: AppIconSize.add,
              color: c.textPrimary,
            ),
            onChanged: (value) => theme.interfaceScale = value,
          ),
        ],
      ),
    );
  }

  Widget _scaleSlider(
    BuildContext context, {
    required IconData icon,
    required String title,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required Widget leading,
    required Widget trailing,
    required ValueChanged<double> onChanged,
  }) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xxl,
        AppSpacing.lg,
        AppSpacing.xxl,
        AppSpacing.md,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AppTheme.brand),
              const SizedBox(width: AppSpacing.xl),
              Text(
                title,
                style: TextStyle(
                  fontSize: AppTextSize.bodyLarge,
                  color: c.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                '${(value * 100).round()}%',
                style: TextStyle(
                  fontSize: AppTextSize.body,
                  color: c.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              SizedBox(
                width: AppIconSize.nav,
                child: Center(child: leading),
              ),
              Expanded(
                child: CupertinoSlider(
                  value: value,
                  min: min,
                  max: max,
                  divisions: divisions,
                  activeColor: AppTheme.brand,
                  onChanged: onChanged,
                ),
              ),
              SizedBox(
                width: AppIconSize.toolbar + AppSpacing.xs,
                child: Center(child: trailing),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String t) => Padding(
    padding: const EdgeInsets.only(left: AppSpacing.xxl, bottom: AppSpacing.sm),
    child: Text(
      t,
      style: TextStyle(
        fontSize: AppTextSize.footnote,
        color: context.colors.textTertiary,
      ),
    ),
  );

  Widget _card(BuildContext context, List<Widget> rows) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i < rows.length - 1) const InsetDivider(leadingInset: 52),
          ],
        ],
      ),
    );
  }

  Widget _choiceRow(
    BuildContext context,
    IconData icon,
    String label,
    bool selected,
    VoidCallback onTap,
  ) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: AppMetric.menuRowHeight + AppSpacing.xxs,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
          child: Row(
            children: [
              Icon(icon, size: AppIconSize.xl, color: AppTheme.brand),
              const SizedBox(width: AppSpacing.xl),
              Text(
                label.l10n(context),
                style: TextStyle(
                  fontSize: AppTextSize.bodyLarge,
                  color: c.textPrimary,
                ),
              ),
              const Spacer(),
              if (selected)
                AppIcon(
                  HeroAppIcons.check,
                  size: AppIconSize.lg,
                  color: AppTheme.brand,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toggleRow(
    BuildContext context,
    IconData icon,
    String label,
    bool value,
    ValueChanged<bool>? onChanged,
  ) {
    final c = context.colors;
    final enabled = onChanged != null;
    return SizedBox(
      height: AppMetric.menuRowHeight + AppSpacing.xxs,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        child: Row(
          children: [
            Icon(
              icon,
              size: AppIconSize.xl,
              color: enabled ? AppTheme.brand : c.textTertiary,
            ),
            const SizedBox(width: AppSpacing.xl),
            Text(
              label,
              style: TextStyle(
                fontSize: AppTextSize.bodyLarge,
                color: enabled ? c.textPrimary : c.textTertiary,
              ),
            ),
            const Spacer(),
            CupertinoSwitch(
              value: value,
              activeTrackColor: AppTheme.brand,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }

  Widget _navigationRow(
    BuildContext context,
    String label,
    String? value,
    VoidCallback onTap, {
    IconData? icon,
    Widget? preview,
  }) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: AppMetric.menuRowHeight + AppSpacing.xxs,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: AppIconSize.xl, color: AppTheme.brand),
                const SizedBox(width: AppSpacing.xl),
              ] else if (preview != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: preview,
                ),
                const SizedBox(width: AppSpacing.xl),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: AppTextSize.bodyLarge,
                  color: c.textPrimary,
                ),
              ),
              if (value != null) ...[
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: AppTextSize.body,
                      color: c.textTertiary,
                    ),
                  ),
                ),
              ] else
                const Spacer(),
              const SizedBox(width: AppSpacing.sm),
              AppIcon(
                HeroAppIcons.chevronRight,
                size: AppIconSize.lg,
                color: c.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FontSettingsView extends StatelessWidget {
  const FontSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = context.watch<ThemeController>();
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.appearanceFont),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.section,
              ),
              children: [
                SettingsCard(
                  children: [
                    SettingsRow(
                      title: AppStrings.t(AppStringKeys.appearanceTextFont),
                      value: theme.effectiveFontChainLabel,
                      height: AppMetric.compactSettingsRowHeight,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const TextFontView()),
                      ),
                    ),
                    const InsetDivider(leadingInset: AppSpacing.xxl),
                    SettingsRow(
                      title: AppStrings.t(
                        AppStringKeys.appearanceMonospaceFont,
                      ),
                      value: theme.effectiveMonospaceFontLabel,
                      height: AppMetric.compactSettingsRowHeight,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const MonospaceFontPickerView(),
                        ),
                      ),
                    ),
                    const InsetDivider(leadingInset: AppSpacing.xxl),
                    SettingsRow(
                      title: AppStrings.t(AppStringKeys.appearanceEmojiFont),
                      value: theme.emojiFontChoice.label,
                      height: AppMetric.compactSettingsRowHeight,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const EmojiFontPickerView(),
                        ),
                      ),
                    ),
                    const InsetDivider(leadingInset: AppSpacing.xxl),
                    SettingsRow(
                      title: AppStrings.t(AppStringKeys.appearanceFontCache),
                      value: AppStrings.t(AppStringKeys.appearanceManage),
                      height: AppMetric.compactSettingsRowHeight,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const FontCacheManagementView(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xxl,
                  ),
                  child: Text(
                    AppStrings.t(AppStringKeys.appearanceFontChainDescription),
                    style: TextStyle(
                      fontSize: AppTextSize.footnote,
                      color: c.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class FontCacheManagementView extends StatefulWidget {
  const FontCacheManagementView({super.key});

  @override
  State<FontCacheManagementView> createState() =>
      _FontCacheManagementViewState();
}

class _FontCacheManagementViewState extends State<FontCacheManagementView> {
  late Future<_FontCacheSnapshot> _snapshot = _loadSnapshot();
  _FontCacheOperation? _operation;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.appearanceFontCache),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: FutureBuilder<_FontCacheSnapshot>(
              future: _snapshot,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final data = snapshot.data!;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.xl,
                    AppSpacing.lg,
                    AppSpacing.section,
                  ),
                  children: [
                    _summaryCard(context, data),
                    const SizedBox(height: AppSpacing.xl),
                    _actionCard(context, data),
                    const SizedBox(height: AppSpacing.xl),
                    _fontFilesCard(context, data),
                    const SizedBox(height: AppSpacing.md),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xxl,
                      ),
                      child: Text(
                        AppStrings.t(
                          AppStringKeys.appearanceFontCacheDescription,
                        ),
                        style: TextStyle(
                          fontSize: AppTextSize.footnote,
                          color: c.textTertiary,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<_FontCacheSnapshot> _loadSnapshot() async {
    final theme = context.read<ThemeController>();
    final supportDir = await getApplicationSupportDirectory();
    final activeFamilies = _activeGoogleFamilies(theme);
    final byFamily = <String, _FontCacheEntry>{};
    if (await supportDir.exists()) {
      await for (final entity in supportDir.list(followLinks: false)) {
        if (entity is! File) continue;
        final entry = await _FontCacheEntry.tryFromFile(entity, activeFamilies);
        if (entry == null) continue;
        final key = entry.normalizedDisplayName;
        final current = byFamily[key];
        byFamily[key] = current == null ? entry : current.merged(entry);
      }
    }
    final entries = byFamily.values.toList();
    entries.sort((a, b) {
      if (a.active != b.active) return a.active ? -1 : 1;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    return _FontCacheSnapshot(entries);
  }

  Set<String> _activeGoogleFamilies(ThemeController theme) {
    final googleFamilies = GoogleFonts.asMap().keys.toSet();
    final active = <String>{};
    void addIfGoogle(String? family) {
      final value = family?.trim();
      if (value == null || value.isEmpty) return;
      final decoded = decodeGoogleFontFamily(value) ?? value;
      if (googleFamilies.contains(decoded)) active.add(decoded);
    }

    for (final family in theme.fontFallbackChain) {
      addIfGoogle(family);
    }
    addIfGoogle(theme.monospaceFontChoice.googleFamily);
    if (theme.monospaceFontChoice.isCustom) {
      addIfGoogle(theme.customMonospaceFontFamily);
    }
    return active;
  }

  Widget _summaryCard(BuildContext context, _FontCacheSnapshot data) {
    return _cacheCard(context, [
      _plainRow(
        context,
        AppStrings.t(AppStringKeys.appearanceCacheFiles),
        AppStrings.t(AppStringKeys.appearanceFileCount, {
          'value1': data.entries.length,
        }),
      ),
      _plainRow(
        context,
        AppStrings.t(AppStringKeys.appearanceTotalSize),
        _formatBytes(data.totalBytes),
      ),
      _plainRow(
        context,
        AppStrings.t(AppStringKeys.appearanceInUseSize),
        AppStrings.t(AppStringKeys.appearanceFileCount, {
          'value1': data.activeCount,
        }),
      ),
      _plainRow(
        context,
        AppStrings.t(AppStringKeys.appearanceCleanableSize),
        AppStrings.t(AppStringKeys.appearanceFileCount, {
          'value1': data.unusedCount,
        }),
      ),
    ]);
  }

  Widget _actionCard(BuildContext context, _FontCacheSnapshot data) {
    final busy = _operation != null;
    return _cacheCard(context, [
      _actionRow(
        context,
        AppStrings.t(AppStringKeys.appearanceRefreshCacheList),
        HeroAppIcons.arrowsRotate.data,
        busy ? null : _refreshSnapshot,
        busy: _operation == _FontCacheOperation.refreshing,
        status: _operation == _FontCacheOperation.refreshed
            ? AppStrings.t(AppStringKeys.appearanceCacheRefreshed)
            : null,
      ),
      _actionRow(
        context,
        AppStrings.t(AppStringKeys.appearanceCleanUnusedFonts),
        HeroAppIcons.trash.data,
        busy || data.unusedCount == 0 ? null : () => _deleteUnused(data),
        destructive: true,
        busy: _operation == _FontCacheOperation.deletingUnused,
        status: _operation == _FontCacheOperation.deletedUnused
            ? AppStrings.t(AppStringKeys.appearanceCacheCleaned)
            : data.unusedCount == 0
            ? AppStrings.t(AppStringKeys.appearanceNoCleanableFonts)
            : null,
      ),
    ]);
  }

  Widget _fontFilesCard(BuildContext context, _FontCacheSnapshot data) {
    final c = context.colors;
    if (data.entries.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxl,
          vertical: AppSpacing.xxl,
        ),
        child: Text(
          AppStrings.t(AppStringKeys.appearanceNoDownloadedFontCache),
          style: TextStyle(fontSize: AppTextSize.body, color: c.textSecondary),
        ),
      );
    }
    return _cacheCard(context, [
      for (final entry in data.entries) _fileRow(context, entry),
    ]);
  }

  Widget _cacheCard(BuildContext context, List<Widget> rows) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i < rows.length - 1)
              const InsetDivider(leadingInset: AppSpacing.xxl),
          ],
        ],
      ),
    );
  }

  Widget _plainRow(BuildContext context, String label, String value) {
    final c = context.colors;
    return SizedBox(
      height: AppMetric.menuRowHeight + AppSpacing.xxs,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: AppTextSize.bodyLarge,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppTextSize.body,
                  color: c.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionRow(
    BuildContext context,
    String title,
    IconData icon,
    VoidCallback? onTap, {
    bool destructive = false,
    bool busy = false,
    String? status,
  }) {
    final c = context.colors;
    final enabled = onTap != null && !busy;
    final color = destructive ? AppTheme.unreadBadge : AppTheme.brand;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: SizedBox(
        height: AppMetric.menuRowHeight + AppSpacing.xxs,
        child: Opacity(
          opacity: enabled || busy || status != null ? 1 : 0.35,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
            child: Row(
              children: [
                Icon(icon, size: AppIconSize.xl, color: color),
                const SizedBox(width: AppSpacing.lg),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: AppTextSize.bodyLarge,
                    color: color,
                  ),
                ),
                const Spacer(),
                if (busy)
                  SizedBox(
                    width: AppIconSize.lg,
                    height: AppIconSize.lg,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: destructive
                          ? AppTheme.unreadBadge
                          : AppTheme.brand,
                    ),
                  )
                else if (status != null)
                  Text(
                    status,
                    style: TextStyle(
                      fontSize: AppTextSize.footnote,
                      color: c.textTertiary,
                    ),
                  )
                else
                  AppIcon(
                    HeroAppIcons.chevronRight,
                    size: AppIconSize.lg,
                    color: enabled && !destructive
                        ? c.textTertiary
                        : Colors.transparent,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fileRow(BuildContext context, _FontCacheEntry entry) {
    final c = context.colors;
    return SizedBox(
      height: AppMetric.menuRowHeight + AppSpacing.md,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppTextSize.bodyLarge,
                      color: c.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_formatBytes(entry.bytes)} · ${entry.modifiedLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppTextSize.footnote,
                      color: c.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Text(
              entry.active
                  ? AppStrings.t(AppStringKeys.appearanceFontInUse)
                  : AppStrings.t(AppStringKeys.appearanceFontUnused),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: AppTextSize.footnote,
                color: entry.active ? AppTheme.brand : c.textTertiary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: entry.active ? null : () => _deleteEntry(entry),
              child: SizedBox(
                width: AppMetric.hitTarget,
                height: AppMetric.hitTarget,
                child: Opacity(
                  opacity: entry.active ? 0.2 : 1,
                  child: Center(
                    child: AppIcon(
                      HeroAppIcons.trash,
                      size: AppIconSize.xl,
                      color: entry.active
                          ? c.textTertiary
                          : AppTheme.unreadBadge,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refreshSnapshot() async {
    if (_operation != null) return;
    setState(() {
      _operation = _FontCacheOperation.refreshing;
    });
    final snapshot = await _loadSnapshot();
    if (!mounted) return;
    setState(() {
      _snapshot = Future.value(snapshot);
      _operation = _FontCacheOperation.refreshed;
    });
    _clearOperationSoon(_FontCacheOperation.refreshed);
  }

  Future<void> _deleteUnused(_FontCacheSnapshot data) async {
    if (_operation != null) return;
    setState(() {
      _operation = _FontCacheOperation.deletingUnused;
    });
    for (final entry in data.entries.where((entry) => !entry.active)) {
      try {
        await entry.deleteFiles();
      } catch (_) {
        // The cache may have been removed by the font loader or the OS.
      }
    }
    if (!mounted) return;
    final snapshot = await _loadSnapshot();
    if (!mounted) return;
    setState(() {
      _snapshot = Future.value(snapshot);
      _operation = _FontCacheOperation.deletedUnused;
    });
    _clearOperationSoon(_FontCacheOperation.deletedUnused);
  }

  Future<void> _deleteEntry(_FontCacheEntry entry) async {
    try {
      await entry.deleteFiles();
    } catch (_) {
      // The cache may have been removed by the font loader or the OS.
    }
    if (!mounted) return;
    final snapshot = await _loadSnapshot();
    if (!mounted) return;
    setState(() {
      _snapshot = Future.value(snapshot);
    });
  }

  void _clearOperationSoon(_FontCacheOperation operation) {
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (!mounted || _operation != operation) return;
      setState(() {
        _operation = null;
      });
    });
  }

  String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    if (unit == 0) return '$bytes ${units[unit]}';
    return '${value.toStringAsFixed(value >= 10 ? 1 : 2)} ${units[unit]}';
  }
}

class _FontCacheSnapshot {
  const _FontCacheSnapshot(this.entries);

  final List<_FontCacheEntry> entries;

  int get totalBytes =>
      entries.fold<int>(0, (total, entry) => total + entry.bytes);
  int get activeCount => entries.where((entry) => entry.active).length;
  int get unusedCount => entries.length - activeCount;
}

enum _FontCacheOperation {
  refreshing,
  refreshed,
  deletingUnused,
  deletedUnused,
}

class _FontCacheEntry {
  const _FontCacheEntry({
    required this.files,
    required this.displayName,
    required this.bytes,
    required this.modified,
    required this.active,
  });

  static final _cacheFilePattern = RegExp(r'^(.+)_([a-fA-F0-9]{16,128})\.ttf$');

  final List<File> files;
  final String displayName;
  final int bytes;
  final DateTime modified;
  final bool active;

  String get normalizedDisplayName => _normalize(displayName);

  String get modifiedLabel {
    final local = modified.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  static Future<_FontCacheEntry?> tryFromFile(
    File file,
    Set<String> activeGoogleFamilies,
  ) async {
    final name = file.uri.pathSegments.isEmpty
        ? file.path
        : file.uri.pathSegments.last;
    final match = _cacheFilePattern.firstMatch(name);
    if (match == null) return null;
    final rawFamily = match.group(1)!;
    final displayName = _displayName(rawFamily);
    final stat = await file.stat();
    final normalizedFile = _normalize(rawFamily);
    final active = activeGoogleFamilies.any((family) {
      final normalizedFamily = _normalize(family);
      return normalizedFile.contains(normalizedFamily) ||
          normalizedFamily.contains(normalizedFile);
    });
    return _FontCacheEntry(
      files: [file],
      displayName: displayName,
      bytes: stat.size,
      modified: stat.modified,
      active: active,
    );
  }

  _FontCacheEntry merged(_FontCacheEntry other) {
    return _FontCacheEntry(
      files: [...files, ...other.files],
      displayName: displayName,
      bytes: bytes + other.bytes,
      modified: modified.isAfter(other.modified) ? modified : other.modified,
      active: active || other.active,
    );
  }

  Future<void> deleteFiles() async {
    for (final file in files) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Individual cache files can disappear while the list is open.
      }
    }
  }

  static String _displayName(String rawFamily) {
    final value = rawFamily
        .replaceAll(RegExp(r'_(regular|italic)$', caseSensitive: false), '')
        .replaceAll(
          RegExp(r'_(100|200|300|400|500|600|700|800|900)(italic)?$'),
          '',
        )
        .replaceAll('_', ' ');
    return value.trim().isEmpty ? rawFamily : value.trim();
  }

  static String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
}

Future<Set<String>> _cachedGoogleFontFamilies() async {
  final googleFamilies = GoogleFonts.asMap().keys.toList();
  final byNormalized = {
    for (final family in googleFamilies)
      _FontCacheEntry._normalize(family): family,
  };
  final supportDir = await getApplicationSupportDirectory();
  final cached = <String>{};
  if (!await supportDir.exists()) return cached;
  await for (final entity in supportDir.list(followLinks: false)) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.isEmpty
        ? entity.path
        : entity.uri.pathSegments.last;
    final match = _FontCacheEntry._cacheFilePattern.firstMatch(name);
    if (match == null) continue;
    final rawFamily = match.group(1)!;
    final normalizedFile = _FontCacheEntry._normalize(rawFamily);
    final exact = byNormalized[normalizedFile];
    if (exact != null) {
      cached.add(exact);
      continue;
    }
    for (final entry in byNormalized.entries) {
      if (normalizedFile.contains(entry.key) ||
          entry.key.contains(normalizedFile)) {
        cached.add(entry.value);
        break;
      }
    }
  }
  return cached;
}

List<String> _fontTitleFallback() {
  return switch (defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.macOS => const [
      '.AppleSystemUIFont',
      'SF Pro',
      'Helvetica Neue',
      'Arial',
    ],
    TargetPlatform.android => const ['sans-serif', 'Roboto', 'Noto Sans'],
    _ => const ['sans-serif', 'Arial'],
  };
}

TextStyle _fontTitleStyle(
  String family,
  TextStyle base, {
  String? googleFamily,
  bool googleLoaded = false,
}) {
  final fallback = _fontTitleFallback();
  if (googleFamily != null && googleLoaded) {
    return GoogleFonts.getFont(
      googleFamily,
      textStyle: base,
    ).copyWith(fontFamilyFallback: fallback);
  }
  if (googleFamily != null) return base.copyWith(fontFamilyFallback: fallback);
  return base.copyWith(fontFamily: family, fontFamilyFallback: fallback);
}

String _fontPreviewSample() => appFontPreviewText;

int _popularSystemFontPriority(String family) {
  final popular = switch (defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.macOS => const [
      '.AppleSystemUIFont',
      'SF Pro',
      'Helvetica Neue',
      'Helvetica',
      'Avenir Next',
      'Avenir',
      'Futura',
      'Gill Sans',
      'Optima',
      'Palatino',
      'Georgia',
      'Times New Roman',
      'Didot',
      'American Typewriter',
      'Courier New',
      'Menlo',
      'PingFang SC',
      'PingFang TC',
      'PingFang HK',
      'Hiragino Sans',
    ],
    TargetPlatform.android => const [
      'sans',
      'sans-serif',
      'Roboto',
      'Noto Sans',
      'Noto Serif',
      'Droid Sans',
      'monospace',
      'serif',
    ],
    _ => const [
      'Arial',
      'Helvetica',
      'Verdana',
      'Tahoma',
      'Georgia',
      'Times New Roman',
      'Courier New',
      'monospace',
      'sans-serif',
      'serif',
    ],
  };
  final exact = popular.indexWhere(
    (font) => font.toLowerCase() == family.toLowerCase(),
  );
  if (exact >= 0) return exact;
  final prefix = popular.indexWhere(
    (font) => family.toLowerCase().startsWith(font.toLowerCase()),
  );
  return prefix >= 0 ? prefix : popular.length + 1;
}

const _googleMonospaceFamilies = {
  'Anonymous Pro',
  'Azeret Mono',
  'B612 Mono',
  'Chivo Mono',
  'Courier Prime',
  'Cousine',
  'Cutive Mono',
  'DM Mono',
  'Datatype',
  'Fira Code',
  'Fira Mono',
  'Fragment Mono',
  'Geist Mono',
  'Google Sans Code',
  'IBM Plex Mono',
  'Inconsolata',
  'Intel One Mono',
  'Iosevka Charon',
  'Iosevka Charon Mono',
  'JetBrains Mono',
  'Kode Mono',
  'LXGW WenKai Mono TC',
  'Lekton',
  'Libertinus Mono',
  'Lilex',
  'M PLUS 1 Code',
  'M PLUS Code Latin',
  'Major Mono Display',
  'Martian Mono',
  'Monofett',
  'Nanum Gothic Coding',
  'Noto Sans Mono',
  'Nova Mono',
  'Overpass Mono',
  'Oxygen Mono',
  'PT Mono',
  'Red Hat Mono',
  'Reddit Mono',
  'Roboto Mono',
  'Rubik Mono One',
  'Share Tech Mono',
  'Sixtyfour',
  'Sixtyfour Convergence',
  'Sometype Mono',
  'Sono',
  'Source Code Pro',
  'Space Mono',
  'Spline Sans Mono',
  'Syne Mono',
  'Ubuntu Mono',
  'Ubuntu Sans Mono',
  'VT323',
  'Victor Mono',
  'Workbench',
  'Xanh Mono',
};

bool _isSystemMonospaceFontFamily(String family) {
  final normalized = family.toLowerCase();
  return normalized.contains('mono') ||
      normalized.contains('menlo') ||
      normalized.contains('courier');
}

class TextFontView extends StatelessWidget {
  const TextFontView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = context.watch<ThemeController>();
    final fonts = theme.fontFallbackChain;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.appearanceTextFont),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.section,
              ),
              children: [
                _chainCard(context, fonts),
                const SizedBox(height: AppSpacing.xl),
                _actionCard(context, theme),
                const SizedBox(height: AppSpacing.md),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xxl,
                  ),
                  child: Text(
                    AppStrings.t(AppStringKeys.appearanceTextFontOrderHint),
                    style: TextStyle(
                      fontSize: AppTextSize.footnote,
                      color: c.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chainCard(BuildContext context, List<String> fonts) {
    final c = context.colors;
    if (fonts.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxl,
          vertical: AppSpacing.xxl,
        ),
        child: Text(
          AppStrings.t(AppStringKeys.appearanceTextFontUnsetHint),
          style: TextStyle(fontSize: AppTextSize.body, color: c.textSecondary),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      clipBehavior: Clip.antiAlias,
      child: ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        itemCount: fonts.length,
        onReorderItem: context.read<ThemeController>().moveFontInFallbackChain,
        itemBuilder: (context, index) {
          final family = fonts[index];
          return Column(
            key: ValueKey('font-chain-$family-$index'),
            children: [
              _chainRow(context, family, index),
              if (index < fonts.length - 1)
                const InsetDivider(leadingInset: AppSpacing.xxl),
            ],
          );
        },
      ),
    );
  }

  Widget _chainRow(BuildContext context, String family, int index) {
    final c = context.colors;
    final googleFamily = decodeGoogleFontFamily(family);
    final displayFamily = displayStoredFontFamily(family);
    TextStyle previewStyle(TextStyle base) {
      if (googleFamily != null) {
        return GoogleFonts.getFont(googleFamily, textStyle: base);
      }
      return base.copyWith(fontFamily: family);
    }

    return SizedBox(
      height: AppMetric.menuRowHeight + AppSpacing.md,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: AppIcon(
                HeroAppIcons.bars,
                size: AppIconSize.xl,
                color: c.textTertiary,
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayFamily,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _fontTitleStyle(
                      family,
                      TextStyle(
                        fontSize: AppTextSize.bodyLarge,
                        color: c.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                      googleFamily: googleFamily,
                      googleLoaded: googleFamily != null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _fontPreviewSample(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: previewStyle(
                      TextStyle(
                        fontSize: AppTextSize.footnote,
                        color: c.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => context
                  .read<ThemeController>()
                  .removeFontFromFallbackChainAt(index),
              child: SizedBox(
                width: AppMetric.hitTarget,
                height: AppMetric.hitTarget,
                child: Center(
                  child: AppIcon(
                    HeroAppIcons.trash,
                    size: AppIconSize.xl,
                    color: c.textTertiary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionCard(BuildContext context, ThemeController theme) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _actionRow(
            context,
            AppStrings.t(AppStringKeys.appearanceAddTextFont),
            HeroAppIcons.plus.data,
            () async {
              final family = await Navigator.of(context).push<String>(
                MaterialPageRoute(builder: (_) => const FontAddView()),
              );
              if (family == null || !context.mounted) return;
              context.read<ThemeController>().addFontToFallbackChain(family);
            },
          ),
          if (theme.fontFallbackChain.isNotEmpty) ...[
            const InsetDivider(leadingInset: AppSpacing.xxl),
            _actionRow(
              context,
              AppStrings.t(AppStringKeys.appearanceClearTextFonts),
              HeroAppIcons.xmark.data,
              () => context.read<ThemeController>().setFontFallbackChain(
                const <String>[],
              ),
              destructive: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _actionRow(
    BuildContext context,
    String title,
    IconData icon,
    VoidCallback onTap, {
    bool destructive = false,
  }) {
    final c = context.colors;
    final color = destructive ? AppTheme.unreadBadge : AppTheme.brand;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: AppMetric.menuRowHeight + AppSpacing.xxs,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
          child: Row(
            children: [
              Icon(icon, size: AppIconSize.xl, color: color),
              const SizedBox(width: AppSpacing.lg),
              Text(
                title,
                style: TextStyle(fontSize: AppTextSize.bodyLarge, color: color),
              ),
              const Spacer(),
              AppIcon(
                HeroAppIcons.chevronRight,
                size: AppIconSize.lg,
                color: destructive ? Colors.transparent : c.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EmojiFontPickerView extends StatefulWidget {
  const EmojiFontPickerView({super.key});

  @override
  State<EmojiFontPickerView> createState() => _EmojiFontPickerViewState();
}

class _EmojiFontPickerViewState extends State<EmojiFontPickerView> {
  static const _fallbackPreviewAsset = 'assets/emoji_preview/noto.svg';
  static const _previewAssets = {
    'system': 'assets/emoji_preview/noto.svg',
    'noto': 'assets/emoji_preview/noto.svg',
    'noto-mono': 'assets/emoji_preview/noto-mono.svg',
    'blobmoji': 'assets/emoji_preview/blobmoji.svg',
    'fluent': 'assets/emoji_preview/fluent.png',
    'fluent-flat': 'assets/emoji_preview/fluent-flat.svg',
    'fluent-mono': 'assets/emoji_preview/fluent-mono.svg',
    'twemoji': 'assets/emoji_preview/twemoji.svg',
    'openmoji': 'assets/emoji_preview/openmoji.svg',
    'emojitwo': 'assets/emoji_preview/emojitwo.svg',
    'tossface': 'assets/emoji_preview/tossface.svg',
  };

  late final Future<List<EmojiFontManifestEntry>> _fonts = EmojiFontCatalog
      .shared
      .loadManifest(forceRefresh: true);
  String? _loadingKey;
  String? _failedKey;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = context.watch<ThemeController>();
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.appearanceEmojiFont),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: FutureBuilder<List<EmojiFontManifestEntry>>(
              future: _fonts,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError && !snapshot.hasData) {
                  return Center(
                    child: Text(
                      AppStrings.t(AppStringKeys.appearanceFontLoadFailed),
                      style: TextStyle(
                        fontSize: AppTextSize.bodyLarge,
                        color: c.textSecondary,
                      ),
                    ),
                  );
                }
                final entries =
                    snapshot.data ?? const <EmojiFontManifestEntry>[];
                return ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.xl,
                    AppSpacing.lg,
                    AppSpacing.section,
                  ),
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: c.card,
                        borderRadius: BorderRadius.circular(AppRadius.card),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          _systemRow(context, theme),
                          if (entries.isNotEmpty)
                            const InsetDivider(leadingInset: AppSpacing.xxl),
                          for (var i = 0; i < entries.length; i++) ...[
                            _entryRow(context, entries[i], theme),
                            if (i < entries.length - 1)
                              const InsetDivider(leadingInset: AppSpacing.xxl),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xxl,
                      ),
                      child: Text(
                        AppStrings.t(
                          AppStringKeys.appearanceEmojiFontCatalogDescription,
                        ),
                        style: TextStyle(
                          fontSize: AppTextSize.footnote,
                          color: c.textTertiary,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _systemRow(BuildContext context, ThemeController theme) {
    return _row(
      context,
      title: EmojiFontChoice.system.label,
      subtitle: AppStrings.t(AppStringKeys.appearanceSystemEmojiFont),
      previewAsset: _previewAssetForKey(EmojiFontChoice.system.key),
      selected: theme.emojiFontChoice.isSystem,
      loading: false,
      failed: false,
      onTap: () {
        context.read<ThemeController>().useSystemEmojiFont();
        setState(() {
          _loadingKey = null;
          _failedKey = null;
        });
      },
    );
  }

  Widget _entryRow(
    BuildContext context,
    EmojiFontManifestEntry entry,
    ThemeController theme,
  ) {
    return _row(
      context,
      title: entry.label,
      subtitle: [
        entry.license,
        if (entry.emojiVersion.isNotEmpty) 'Emoji ${entry.emojiVersion}',
      ].where((part) => part.isNotEmpty).join(' · '),
      previewAsset: _previewAssetForKey(entry.key),
      selected: theme.emojiFontChoice.key == entry.key,
      loading: _loadingKey == entry.key,
      failed: _failedKey == entry.key,
      onTap: () async {
        if (_loadingKey != null) return;
        setState(() {
          _loadingKey = entry.key;
          _failedKey = null;
        });
        try {
          await context.read<ThemeController>().setEmojiFont(entry);
        } catch (_) {
          if (mounted) setState(() => _failedKey = entry.key);
        } finally {
          if (mounted) setState(() => _loadingKey = null);
        }
      },
    );
  }

  Widget _row(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String previewAsset,
    required bool selected,
    required bool loading,
    required bool failed,
    required VoidCallback onTap,
  }) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: AppMetric.menuRowHeight + AppSpacing.md,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                child: Semantics(
                  label: AppStringKeys.emojiPreviewFaceWithTearsOfJoy.l10n(
                    context,
                  ),
                  image: true,
                  child: _EmojiPreviewImage(asset: previewAsset),
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.l10n(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppTextSize.bodyLarge,
                        color: c.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      failed
                          ? AppStrings.t(
                              AppStringKeys.appearanceFontDownloadFailedName,
                              {'value1': subtitle},
                            )
                          : subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppTextSize.footnote,
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (loading)
                const SizedBox(
                  width: AppIconSize.lg,
                  height: AppIconSize.lg,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (selected)
                AppIcon(
                  HeroAppIcons.check,
                  size: AppIconSize.lg,
                  color: AppTheme.brand,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _previewAssetForKey(String key) =>
      _previewAssets[key] ?? _fallbackPreviewAsset;
}

class _EmojiPreviewImage extends StatelessWidget {
  const _EmojiPreviewImage({required this.asset});

  final String asset;

  @override
  Widget build(BuildContext context) {
    if (asset.endsWith('.svg')) {
      return SvgPicture.asset(
        asset,
        width: 26,
        height: 26,
        placeholderBuilder: (_) => const _TearJoyFallbackIcon(),
        errorBuilder: (_, _, _) => const _TearJoyFallbackIcon(),
      );
    }
    return Image.asset(
      asset,
      width: 26,
      height: 26,
      errorBuilder: (_, _, _) => const _TearJoyFallbackIcon(),
    );
  }
}

class _TearJoyFallbackIcon extends StatelessWidget {
  const _TearJoyFallbackIcon();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 26,
      height: 26,
      child: CustomPaint(painter: _TearJoyFallbackPainter()),
    );
  }
}

class _TearJoyFallbackPainter extends CustomPainter {
  const _TearJoyFallbackPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final face = Paint()..color = const Color(0xFFFFD447);
    final stroke = Paint()
      ..color = const Color(0xFF5A3210)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.width * 0.08;
    final tear = Paint()..color = const Color(0xFF37A8FF);
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * 0.43;
    canvas.drawCircle(center, radius, face);

    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(size.width * 0.34, size.height * 0.39),
        width: size.width * 0.28,
        height: size.height * 0.18,
      ),
      0.15,
      2.6,
      false,
      stroke,
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(size.width * 0.66, size.height * 0.39),
        width: size.width * 0.28,
        height: size.height * 0.18,
      ),
      0.4,
      2.6,
      false,
      stroke,
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(size.width * 0.5, size.height * 0.55),
        width: size.width * 0.48,
        height: size.height * 0.34,
      ),
      0.1,
      2.95,
      false,
      stroke,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.18, size.height * 0.58),
        width: size.width * 0.18,
        height: size.height * 0.28,
      ),
      tear,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.82, size.height * 0.58),
        width: size.width * 0.18,
        height: size.height * 0.28,
      ),
      tear,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class FontAddView extends StatefulWidget {
  const FontAddView({super.key});

  @override
  State<FontAddView> createState() => _FontAddViewState();
}

class _FontAddViewState extends State<FontAddView> {
  late final Future<List<_FontCandidate>> _fonts = _loadFonts();
  String _query = '';
  String? _loadingGoogleFamily;
  String? _failedGoogleFamily;

  Future<List<_FontCandidate>> _loadFonts() async {
    final systemFonts = await SystemFontCatalog.loadFonts();
    final cachedGoogleFamilies = await _cachedGoogleFontFamilies();
    final candidates = <_FontCandidate>[
      for (final font in systemFonts)
        _FontCandidate(
          label: font,
          family: font,
          preview: _fontPreviewSample(),
          source: AppStringKeys.appearanceSystem,
          priority: _popularSystemFontPriority(font),
        ),
      for (final family in GoogleFonts.asMap().keys)
        _FontCandidate(
          label: family,
          family: family,
          preview: _fontPreviewSample(),
          source: 'Google',
          google: true,
          downloaded: cachedGoogleFamilies.contains(family),
        ),
    ];
    return candidates..sort((a, b) {
      final sourceCompare = a.sourceOrder.compareTo(b.sourceOrder);
      if (sourceCompare != 0) return sourceCompare;
      final priorityCompare = a.priority.compareTo(b.priority);
      if (priorityCompare != 0) return priorityCompare;
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.appearanceAddFont),
            onBack: () => Navigator.of(context).pop(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: CupertinoSearchTextField(
              placeholder: AppStrings.t(AppStringKeys.appearanceSearchFont),
              itemColor: c.textTertiary,
              prefixIcon: AppIcon(
                HeroAppIcons.magnifyingGlass,
                size: AppIconSize.lg,
                color: c.textTertiary,
              ),
              suffixIcon: Icon(
                HeroAppIcons.circleXmark.data,
                size: AppIconSize.lg,
                color: c.textTertiary,
              ),
              onChanged: (value) => setState(() => _query = value.trim()),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<_FontCandidate>>(
              future: _fonts,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final query = _query.toLowerCase();
                final fonts = snapshot.data!
                    .where(
                      (font) =>
                          query.isEmpty ||
                          font.label.toLowerCase().contains(query) ||
                          font.family.toLowerCase().contains(query),
                    )
                    .toList();
                return _fontList(context, fonts);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _fontList(BuildContext context, List<_FontCandidate> fonts) {
    final c = context.colors;
    if (fonts.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.section,
        ),
        children: [
          Container(
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Text(
              AppStrings.t(AppStringKeys.appearanceNoMatchingFonts),
              style: TextStyle(
                fontSize: AppTextSize.body,
                color: c.textSecondary,
              ),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.section,
      ),
      itemCount: fonts.length,
      itemBuilder: (context, index) => _virtualRow(
        context,
        first: index == 0,
        last: index == fonts.length - 1,
        child: _fontRow(context, fonts[index]),
      ),
      separatorBuilder: (context, index) => ColoredBox(
        color: c.card,
        child: const InsetDivider(leadingInset: AppSpacing.xxl),
      ),
    );
  }

  Widget _virtualRow(
    BuildContext context, {
    required bool first,
    required bool last,
    required Widget child,
  }) {
    const radius = Radius.circular(AppRadius.card);
    return ClipRRect(
      borderRadius: BorderRadius.vertical(
        top: first ? radius : Radius.zero,
        bottom: last ? radius : Radius.zero,
      ),
      child: ColoredBox(color: context.colors.card, child: child),
    );
  }

  Widget _fontRow(BuildContext context, _FontCandidate font) {
    final c = context.colors;
    final loading = font.google && _loadingGoogleFamily == font.family;
    final failed = font.google && _failedGoogleFamily == font.family;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _selectFont(context, font),
      child: SizedBox(
        height: AppMetric.menuRowHeight + AppSpacing.md,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      font.label.l10n(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: font.titleStyle(
                        TextStyle(
                          fontSize: AppTextSize.bodyLarge,
                          color: c.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      font.preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: font.previewStyle(
                        TextStyle(
                          fontSize: AppTextSize.footnote,
                          color: c.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                failed
                    ? AppStrings.t(AppStringKeys.appearanceDownloadFailed)
                    : font.google && font.downloaded
                    ? AppStrings.t(AppStringKeys.appearanceGoogleDownloaded)
                    : font.source.l10n(context),
                style: TextStyle(
                  fontSize: AppTextSize.footnote,
                  color: c.textTertiary,
                ),
              ),
              if (loading) ...[
                const SizedBox(width: AppSpacing.md),
                SizedBox(
                  width: 48,
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    color: AppTheme.brand,
                    backgroundColor: c.divider,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectFont(BuildContext context, _FontCandidate font) async {
    if (!font.google) {
      Navigator.of(context).pop(font.selectionFamily);
      return;
    }
    if (_loadingGoogleFamily != null) return;
    setState(() {
      _loadingGoogleFamily = font.family;
      _failedGoogleFamily = null;
    });
    try {
      GoogleFonts.getFont(font.family, textStyle: const TextStyle());
      await GoogleFonts.pendingFonts();
      if (!context.mounted) return;
      Navigator.of(context).pop(font.selectionFamily);
    } catch (_) {
      if (!mounted || _loadingGoogleFamily != font.family) return;
      setState(() => _failedGoogleFamily = font.family);
    } finally {
      if (mounted && _loadingGoogleFamily == font.family) {
        setState(() => _loadingGoogleFamily = null);
      }
    }
  }
}

class _FontCandidate {
  const _FontCandidate({
    required this.label,
    required this.family,
    required this.preview,
    required this.source,
    this.google = false,
    this.downloaded = false,
    this.priority = 0,
  });

  final String label;
  final String family;
  final String preview;
  final String source;
  final bool google;
  final bool downloaded;
  final int priority;

  String get selectionFamily =>
      google ? encodeGoogleFontFamily(family) : family;

  TextStyle titleStyle(TextStyle base) {
    return _fontTitleStyle(
      family,
      base,
      googleFamily: google ? family : null,
      googleLoaded: downloaded,
    );
  }

  TextStyle previewStyle(TextStyle base) {
    if (google) {
      return downloaded ? GoogleFonts.getFont(family, textStyle: base) : base;
    }
    return base.copyWith(fontFamily: family);
  }

  int get sourceOrder => switch (source) {
    AppStringKeys.appearanceSystem => 0,
    'Google' => 1,
    _ => 4,
  };
}

class _MonoFontCandidate {
  const _MonoFontCandidate({
    required this.label,
    required this.family,
    required this.preview,
    required this.source,
    this.choice,
    this.google = false,
    this.downloaded = false,
    required this.priority,
  });

  final String label;
  final String family;
  final String preview;
  final String source;
  final AppMonospaceFontChoice? choice;
  final bool google;
  final bool downloaded;
  final int priority;

  String get selectionKey {
    final selectedChoice = choice;
    if (selectedChoice != null && !google) {
      return 'choice:${selectedChoice.name}';
    }
    if (google) return 'google:$family';
    return 'system:$family';
  }

  TextStyle previewStyle(TextStyle base, {required bool selected}) {
    if (google && (selected || downloaded)) {
      return GoogleFonts.getFont(family, textStyle: base);
    }
    if (google) return base;
    return base.copyWith(fontFamily: family);
  }

  TextStyle titleStyle(TextStyle base, {required bool selected}) {
    return _fontTitleStyle(
      family,
      base,
      googleFamily: google ? family : null,
      googleLoaded: selected || downloaded,
    );
  }
}

class MonospaceFontPickerView extends StatefulWidget {
  const MonospaceFontPickerView({super.key});

  @override
  State<MonospaceFontPickerView> createState() =>
      _MonospaceFontPickerViewState();
}

class _MonospaceFontPickerViewState extends State<MonospaceFontPickerView> {
  late final Future<List<_MonoFontCandidate>> _fonts = _loadFonts();
  String? _loadingGoogleFamily;
  String? _failedGoogleFamily;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = context.watch<ThemeController>();
    final selectedKey = _selectedKey(theme);
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.appearanceMonospaceFont),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: FutureBuilder<List<_MonoFontCandidate>>(
              future: _fonts,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return _fontList(context, snapshot.data!, selectedKey);
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<List<_MonoFontCandidate>> _loadFonts() async {
    final systemFonts = await SystemFontCatalog.loadFonts();
    final cachedGoogleFamilies = await _cachedGoogleFontFamilies();
    final candidates = <_MonoFontCandidate>[
      ..._preferredPlatformMonospaceFonts(),
      ..._googleMonospaceFonts(cachedGoogleFamilies),
      for (final family in systemFonts.where(_isSystemMonospaceFontFamily))
        _MonoFontCandidate(
          label: family,
          family: family,
          preview: appMonospaceFontPreviewText,
          source: AppStringKeys.appearanceSystem,
          priority: _systemMonospacePriority(family),
        ),
    ];
    final byKey = <String, _MonoFontCandidate>{};
    for (final candidate in candidates) {
      byKey.putIfAbsent(candidate.selectionKey, () => candidate);
    }
    return byKey.values.toList()..sort((a, b) {
      final priorityCompare = a.priority.compareTo(b.priority);
      if (priorityCompare != 0) return priorityCompare;
      final sourceCompare = a.source.compareTo(b.source);
      if (sourceCompare != 0) return sourceCompare;
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });
  }

  List<_MonoFontCandidate> _preferredPlatformMonospaceFonts() {
    final choices = switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => const [
        AppMonospaceFontChoice.sfMono,
        AppMonospaceFontChoice.menlo,
        AppMonospaceFontChoice.courierNew,
      ],
      TargetPlatform.android => const [
        AppMonospaceFontChoice.system,
        AppMonospaceFontChoice.courierNew,
      ],
      _ => const [
        AppMonospaceFontChoice.system,
        AppMonospaceFontChoice.courierNew,
      ],
    };
    return [
      for (var i = 0; i < choices.length; i++)
        _MonoFontCandidate(
          label: choices[i].label,
          family: choices[i].fontFamily,
          preview: choices[i].previewText,
          source: AppStringKeys.appearanceSystem,
          choice: choices[i],
          priority: i,
        ),
    ];
  }

  List<_MonoFontCandidate> _googleMonospaceFonts(
    Set<String> cachedGoogleFamilies,
  ) {
    final families =
        GoogleFonts.asMap().keys
            .where(_googleMonospaceFamilies.contains)
            .toList()
          ..sort((a, b) {
            final priorityCompare = _googleMonospacePriority(
              a,
            ).compareTo(_googleMonospacePriority(b));
            if (priorityCompare != 0) return priorityCompare;
            return a.toLowerCase().compareTo(b.toLowerCase());
          });
    return [
      for (final family in families)
        _MonoFontCandidate(
          label: family,
          family: family,
          preview: appMonospaceFontPreviewText,
          source: 'Google',
          google: true,
          downloaded: cachedGoogleFamilies.contains(family),
          priority: 100 + _googleMonospacePriority(family),
        ),
    ];
  }

  int _systemMonospacePriority(String family) {
    final priorities = switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => const [
        'SF Mono',
        'Menlo',
        'Courier',
        'Courier New',
      ],
      TargetPlatform.android => const [
        'monospace',
        'Roboto Mono',
        'Noto Sans Mono',
      ],
      _ => const ['monospace', 'Courier New'],
    };
    final exact = priorities.indexWhere((value) => value == family);
    if (exact >= 0) return 10 + exact;
    final prefix = priorities.indexWhere((value) => family.startsWith(value));
    if (prefix >= 0) return 10 + prefix;
    return 50;
  }

  int _googleMonospacePriority(String family) {
    const priorities = [
      'Roboto Mono',
      'Source Code Pro',
      'JetBrains Mono',
      'Fira Code',
      'IBM Plex Mono',
      'Noto Sans Mono',
      'Space Mono',
      'Inconsolata',
      'Ubuntu Mono',
      'Anonymous Pro',
      'DM Mono',
      'Red Hat Mono',
      'Geist Mono',
      'Courier Prime',
    ];
    final index = priorities.indexOf(family);
    return index >= 0 ? index : 60;
  }

  String _selectedKey(ThemeController theme) {
    final selected = theme.monospaceFontChoice;
    if (selected.isCustom) {
      final customFamily = theme.customMonospaceFontFamily.trim();
      final googleFamily = decodeGoogleFontFamily(customFamily);
      if (googleFamily != null) return 'google:$googleFamily';
      if (customFamily.isNotEmpty) return 'system:$customFamily';
      return 'choice:${AppMonospaceFontChoice.system.name}';
    }
    if (selected.googleFamily != null) return 'google:${selected.googleFamily}';
    return 'choice:${selected.name}';
  }

  Widget _fontList(
    BuildContext context,
    List<_MonoFontCandidate> fonts,
    String selectedKey,
  ) {
    final c = context.colors;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.section,
      ),
      itemCount: fonts.length,
      itemBuilder: (context, index) {
        final font = fonts[index];
        return _virtualRow(
          context,
          first: index == 0,
          last: index == fonts.length - 1,
          child: _fontRow(
            context,
            font,
            selected: selectedKey == font.selectionKey,
            loading: font.google && _loadingGoogleFamily == font.family,
            failed: font.google && _failedGoogleFamily == font.family,
            onTap: () {
              final theme = context.read<ThemeController>();
              final choice = font.choice;
              if (choice != null && !font.google) {
                theme.monospaceFontChoice = choice;
                _trackGoogleFontLoad(null);
                return;
              }
              theme.customMonospaceFontFamily = font.google
                  ? encodeGoogleFontFamily(font.family)
                  : font.family;
              theme.monospaceFontChoice = AppMonospaceFontChoice.custom;
              _trackGoogleFontLoad(font.google ? font.family : null);
            },
          ),
        );
      },
      separatorBuilder: (context, index) => ColoredBox(
        color: c.card,
        child: const InsetDivider(leadingInset: AppSpacing.xxl),
      ),
    );
  }

  Widget _virtualRow(
    BuildContext context, {
    required bool first,
    required bool last,
    required Widget child,
  }) {
    const radius = Radius.circular(AppRadius.card);
    return ClipRRect(
      borderRadius: BorderRadius.vertical(
        top: first ? radius : Radius.zero,
        bottom: last ? radius : Radius.zero,
      ),
      child: ColoredBox(color: context.colors.card, child: child),
    );
  }

  Widget _fontRow(
    BuildContext context,
    _MonoFontCandidate font, {
    required bool selected,
    required bool loading,
    required bool failed,
    required VoidCallback onTap,
  }) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: AppMetric.menuRowHeight + AppSpacing.md,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      font.label.l10n(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: font.titleStyle(
                        TextStyle(
                          fontSize: AppTextSize.bodyLarge,
                          color: c.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                        selected: selected,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      font.preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: font.previewStyle(
                        TextStyle(
                          fontSize: AppTextSize.footnote,
                          color: c.textSecondary,
                        ),
                        selected: selected,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                failed
                    ? AppStrings.t(AppStringKeys.appearanceDownloadFailed)
                    : font.google && font.downloaded
                    ? AppStrings.t(AppStringKeys.appearanceGoogleDownloaded)
                    : font.source.l10n(context),
                style: TextStyle(
                  fontSize: AppTextSize.footnote,
                  color: c.textTertiary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              if (loading) ...[
                SizedBox(
                  width: 48,
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    color: AppTheme.brand,
                    backgroundColor: c.divider,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
              ],
              if (!loading && failed) ...[
                Text(
                  AppStrings.t(AppStringKeys.appearanceDownloadFailed),
                  style: TextStyle(
                    fontSize: AppTextSize.footnote,
                    color: c.textTertiary,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
              ],
              if (selected)
                AppIcon(
                  HeroAppIcons.check,
                  size: AppIconSize.lg,
                  color: AppTheme.brand,
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _trackGoogleFontLoad(String? googleFamily) {
    if (googleFamily == null) {
      if (_loadingGoogleFamily != null || _failedGoogleFamily != null) {
        setState(() {
          _loadingGoogleFamily = null;
          _failedGoogleFamily = null;
        });
      }
      return;
    }
    setState(() {
      _loadingGoogleFamily = googleFamily;
      _failedGoogleFamily = null;
    });
    try {
      GoogleFonts.getFont(googleFamily, textStyle: const TextStyle());
    } catch (_) {
      if (!mounted || _loadingGoogleFamily != googleFamily) return;
      setState(() {
        _loadingGoogleFamily = null;
        _failedGoogleFamily = googleFamily;
      });
      return;
    }
    GoogleFonts.pendingFonts().then(
      (_) {
        if (!mounted || _loadingGoogleFamily != googleFamily) return;
        setState(() => _loadingGoogleFamily = null);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!mounted || _loadingGoogleFamily != googleFamily) return;
        setState(() {
          _loadingGoogleFamily = null;
          _failedGoogleFamily = googleFamily;
        });
      },
    );
  }
}
