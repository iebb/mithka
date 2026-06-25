//
//  appearance_view.dart
//
//  外观: theme mode (跟随系统 / 浅色 / 深色) + tab-bar style (经典 / 系统), driving
//  ThemeController live. Mapped from QQ's 外观/装扮 entry.
//

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../components/ui_components.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';

class AppearanceView extends StatelessWidget {
  const AppearanceView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = context.watch<ThemeController>();
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(title: '外观', onBack: () => Navigator.of(context).pop()),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.section,
              ),
              children: [
                _label(context, '深色模式'),
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
                _label(context, '大小'),
                _fontSizeCard(context, theme),
                const SizedBox(height: AppSpacing.xl),
                _label(context, '主题颜色'),
                _colorCard(context, theme),
                const SizedBox(height: AppSpacing.xl),
                _label(context, '标签栏样式'),
                _card(context, [
                  for (final s in TabBarStyle.values)
                    _choiceRow(
                      context,
                      s.icon,
                      s.label,
                      theme.tabBarStyle == s,
                      () => theme.tabBarStyle = s,
                    ),
                ]),
                const SizedBox(height: AppSpacing.xl),
                _label(context, '显示'),
                _card(context, [
                  _toggleRow(
                    context,
                    Icons.groups_rounded,
                    '群聊头像显示为圆形',
                    theme.circularGroupAvatars,
                    (v) => theme.circularGroupAvatars = v,
                  ),
                  _toggleRow(
                    context,
                    Icons.badge_outlined,
                    '显示成员头衔',
                    theme.showMemberTags,
                    (v) => theme.showMemberTags = v,
                  ),
                  _toggleRow(
                    context,
                    Icons.photo_library_outlined,
                    '合并连续图片消息',
                    theme.groupImageMessages,
                    (v) => theme.groupImageMessages = v,
                  ),
                ]),
                const SizedBox(height: AppSpacing.xl),
                _label(context, '聊天界面'),
                _card(context, [
                  _toggleRow(
                    context,
                    Icons.palette_outlined,
                    '显示 Premium 名字颜色',
                    theme.showChatPremiumNameColors,
                    (v) => theme.showChatPremiumNameColors = v,
                  ),
                  _toggleRow(
                    context,
                    Icons.emoji_emotions_outlined,
                    '显示 Premium 状态表情',
                    theme.showChatPremiumEmojiStatus,
                    (v) => theme.showChatPremiumEmojiStatus = v,
                  ),
                  _toggleRow(
                    context,
                    Icons.edit_note_rounded,
                    '显示编辑和已读标记',
                    theme.showMessageMetaIndicators,
                    (v) => theme.showMessageMetaIndicators = v,
                  ),
                ]),
                const SizedBox(height: AppSpacing.xl),
                _label(context, '聊天列表'),
                _card(context, [
                  _toggleRow(
                    context,
                    Icons.filter_list_rounded,
                    '顶部显示聊天分组筛选',
                    theme.showChatFolderFilter,
                    (v) => theme.showChatFolderFilter = v,
                  ),
                  _toggleRow(
                    context,
                    Icons.palette_outlined,
                    '显示 Premium 名字颜色',
                    theme.showPremiumNameColors,
                    (v) => theme.showPremiumNameColors = v,
                  ),
                  _toggleRow(
                    context,
                    Icons.emoji_emotions_outlined,
                    '显示 Premium 状态表情',
                    theme.showPremiumEmojiStatus,
                    (v) => theme.showPremiumEmojiStatus = v,
                  ),
                ]),
                const SizedBox(height: AppSpacing.xl),
                _label(context, '消息红点'),
                _card(context, [
                  for (final m in UnreadBadgeMode.values)
                    _choiceRow(
                      context,
                      m.icon,
                      m.label,
                      theme.unreadBadgeMode == m,
                      () => theme.unreadBadgeMode = m,
                    ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const _palette = [
    Color(0xFF0099FF), // 蔚蓝 (default)
    Color(0xFF2DC100), // 绿
    Color(0xFF00C4B3), // 青
    Color(0xFF4A6CF7), // 靛蓝
    Color(0xFF8E7BFF), // 紫
    Color(0xFFFF5E7D), // 粉
    Color(0xFFFA5151), // 红
    Color(0xFFFF9500), // 橙
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
        spacing: AppSpacing.xxl,
        runSpacing: AppSpacing.xl,
        children: [
          for (final color in _palette)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => theme.brandColor = color,
              child: Container(
                width: AppMetric.hitTarget - AppSpacing.xxs,
                height: AppMetric.hitTarget - AppSpacing.xxs,
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
                    ? const Icon(Icons.check, size: 18, color: Colors.white)
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
            icon: Icons.text_fields_rounded,
            title: '字体大小',
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
            icon: Icons.space_dashboard_outlined,
            title: '界面大小',
            value: theme.interfaceScale,
            min: ThemeController.minInterfaceScale,
            max: ThemeController.maxInterfaceScale,
            divisions: 17,
            leading: Icon(
              Icons.crop_square,
              size: AppTextSize.body,
              color: c.textSecondary,
            ),
            trailing: Icon(
              Icons.crop_square,
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
                label,
                style: TextStyle(
                  fontSize: AppTextSize.bodyLarge,
                  color: c.textPrimary,
                ),
              ),
              const Spacer(),
              if (selected)
                Icon(Icons.check, size: AppIconSize.lg, color: AppTheme.brand),
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
    ValueChanged<bool> onChanged,
  ) {
    final c = context.colors;
    return SizedBox(
      height: AppMetric.menuRowHeight + AppSpacing.xxs,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        child: Row(
          children: [
            Icon(icon, size: AppIconSize.xl, color: AppTheme.brand),
            const SizedBox(width: AppSpacing.xl),
            Text(
              label,
              style: TextStyle(
                fontSize: AppTextSize.bodyLarge,
                color: c.textPrimary,
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
}
