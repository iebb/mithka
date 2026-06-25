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
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
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
                const SizedBox(height: 14),
                _label(context, '字体大小'),
                _fontSizeCard(context, theme),
                const SizedBox(height: 14),
                _label(context, '主题颜色'),
                _colorCard(context, theme),
                const SizedBox(height: 14),
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
                const SizedBox(height: 14),
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
                    Icons.filter_list_rounded,
                    '顶部显示聊天分组筛选',
                    theme.showChatFolderFilter,
                    (v) => theme.showChatFolderFilter = v,
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
                  _toggleRow(
                    context,
                    Icons.photo_library_outlined,
                    '合并连续图片消息',
                    theme.groupImageMessages,
                    (v) => theme.groupImageMessages = v,
                  ),
                ]),
                const SizedBox(height: 14),
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
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Wrap(
        spacing: 16,
        runSpacing: 14,
        children: [
          for (final color in _palette)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => theme.brandColor = color,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: color.toARGB32() == selected
                      ? Border.all(color: c.textPrimary, width: 2.5)
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
    final steps = ThemeController.fontScaleSteps;
    const labels = ['小', '标准', '大', '超大'];
    var index = 0;
    var best = double.infinity;
    for (var i = 0; i < steps.length; i++) {
      final delta = (steps[i] - theme.fontScale).abs();
      if (delta < best) {
        best = delta;
        index = i;
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            height: 52,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(
                    Icons.text_fields_rounded,
                    size: 20,
                    color: AppTheme.brand,
                  ),
                  const SizedBox(width: 14),
                  Text(
                    '聊天字体',
                    style: TextStyle(fontSize: 16, color: c.textPrimary),
                  ),
                  const Spacer(),
                  Text(
                    labels[index],
                    style: TextStyle(fontSize: 15, color: c.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          const InsetDivider(leadingInset: 52),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                Text(
                  'A',
                  style: TextStyle(fontSize: 14, color: c.textSecondary),
                ),
                Expanded(
                  child: CupertinoSlider(
                    value: index.toDouble(),
                    min: 0,
                    max: (steps.length - 1).toDouble(),
                    divisions: steps.length - 1,
                    activeColor: AppTheme.brand,
                    onChanged: (value) =>
                        theme.fontScale = steps[value.round()],
                  ),
                ),
                Text('A', style: TextStyle(fontSize: 24, color: c.textPrimary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String t) => Padding(
    padding: const EdgeInsets.only(left: 16, bottom: 6),
    child: Text(
      t,
      style: TextStyle(fontSize: 13, color: context.colors.textTertiary),
    ),
  );

  Widget _card(BuildContext context, List<Widget> rows) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
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
        height: 52,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppTheme.brand),
              const SizedBox(width: 14),
              Text(label, style: TextStyle(fontSize: 16, color: c.textPrimary)),
              const Spacer(),
              if (selected) Icon(Icons.check, size: 18, color: AppTheme.brand),
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
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppTheme.brand),
            const SizedBox(width: 14),
            Text(label, style: TextStyle(fontSize: 16, color: c.textPrimary)),
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
