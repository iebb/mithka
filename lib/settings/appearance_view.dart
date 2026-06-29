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
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../components/ui_components.dart';
import '../theme/app_theme.dart';
import '../theme/system_font_catalog.dart';
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
                _label(context, '字体'),
                _card(context, [
                  _navigationRow(
                    context,
                    '字体',
                    theme.effectiveFontChainLabel,
                    () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const FontSettingsView(),
                      ),
                    ),
                    icon: FontAwesomeIcons.font.data,
                  ),
                ]),
                const SizedBox(height: AppSpacing.xl),
                _label(context, '主题颜色'),
                _colorCard(context, theme),
                const SizedBox(height: AppSpacing.xl),
                _label(context, '显示'),
                _card(context, [
                  _toggleRow(
                    context,
                    FontAwesomeIcons.users.data,
                    '群聊头像显示为圆形',
                    theme.circularGroupAvatars,
                    (v) => theme.circularGroupAvatars = v,
                  ),
                  _toggleRow(
                    context,
                    FontAwesomeIcons.eyeSlash.data,
                    '侧边栏隐藏手机号',
                    theme.hideSidebarPhone,
                    (v) => theme.hideSidebarPhone = v,
                  ),
                ]),
                const SizedBox(height: AppSpacing.xl),
                _label(context, '聊天界面'),
                _card(context, [
                  _toggleRow(
                    context,
                    FontAwesomeIcons.idBadge.data,
                    '群成员显示头衔',
                    theme.showMemberTags,
                    (v) => theme.showMemberTags = v,
                  ),
                  _toggleRow(
                    context,
                    FontAwesomeIcons.images.data,
                    '连续图片合并显示',
                    theme.groupImageMessages,
                    (v) => theme.groupImageMessages = v,
                  ),
                  _toggleRow(
                    context,
                    FontAwesomeIcons.palette.data,
                    '显示 Premium 名字颜色',
                    theme.showChatPremiumNameColors,
                    (v) => theme.showChatPremiumNameColors = v,
                  ),
                  _toggleRow(
                    context,
                    FontAwesomeIcons.solidFaceSmile.data,
                    '显示 Premium 状态表情',
                    theme.showChatPremiumEmojiStatus,
                    (v) => theme.showChatPremiumEmojiStatus = v,
                  ),
                  _toggleRow(
                    context,
                    FontAwesomeIcons.penToSquare.data,
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
                    FontAwesomeIcons.filter.data,
                    '顶部显示聊天分组筛选',
                    theme.showChatFolderFilter,
                    (v) => theme.showChatFolderFilter = v,
                  ),
                  _toggleRow(
                    context,
                    FontAwesomeIcons.magnifyingGlass.data,
                    '显示聊天列表搜索',
                    theme.showChatListSearch,
                    (v) => theme.showChatListSearch = v,
                  ),
                  _toggleRow(
                    context,
                    FontAwesomeIcons.palette.data,
                    '显示 Premium 名字颜色',
                    theme.showPremiumNameColors,
                    (v) => theme.showPremiumNameColors = v,
                  ),
                  _toggleRow(
                    context,
                    FontAwesomeIcons.solidFaceSmile.data,
                    '显示 Premium 状态表情',
                    theme.showPremiumEmojiStatus,
                    (v) => theme.showPremiumEmojiStatus = v,
                  ),
                ]),
                const SizedBox(height: AppSpacing.xl),
                _label(context, '群助手位置'),
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
                _label(context, '消息红点'),
                _card(context, [
                  _toggleRow(
                    context,
                    FontAwesomeIcons.message.data,
                    '显示未读会话数',
                    theme.unreadBadgeShowsChatCount,
                    (v) => theme.unreadBadgeShowsChatCount = v,
                  ),
                  _toggleRow(
                    context,
                    FontAwesomeIcons.solidBell.data,
                    '超过 99 显示为 99+',
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
                    ? FaIcon(
                        FontAwesomeIcons.check,
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
            icon: FontAwesomeIcons.font.data,
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
            icon: FontAwesomeIcons.tableCells.data,
            title: '界面大小',
            value: theme.interfaceScale,
            min: ThemeController.minInterfaceScale,
            max: ThemeController.maxInterfaceScale,
            divisions: 17,
            leading: FaIcon(
              FontAwesomeIcons.square,
              size: AppTextSize.body,
              color: c.textSecondary,
            ),
            trailing: FaIcon(
              FontAwesomeIcons.square,
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
                FaIcon(
                  FontAwesomeIcons.check,
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

  Widget _navigationRow(
    BuildContext context,
    String label,
    String value,
    VoidCallback onTap, {
    IconData? icon,
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
              ],
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: AppTextSize.body,
                    color: c.textTertiary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              FaIcon(
                FontAwesomeIcons.chevronRight,
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
          NavHeader(title: '字体', onBack: () => Navigator.of(context).pop()),
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
                      title: '文本字体',
                      value: theme.effectiveFontChainLabel,
                      height: AppMetric.compactSettingsRowHeight,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const TextFontView()),
                      ),
                    ),
                    const InsetDivider(leadingInset: AppSpacing.xxl),
                    SettingsRow(
                      title: '等宽字体',
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
                      title: '表情字体',
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
                      title: '字体缓存',
                      value: '管理',
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
                    '文本字体按顺序用于整个界面的字体链；表情字体优先用于 emoji；等宽字体用于代码块。',
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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(title: '字体缓存', onBack: () => Navigator.of(context).pop()),
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
                        '只管理运行时下载的 Google 字体缓存；当前字体链、等宽字体和表情字体正在使用的文件会被保留。',
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
    final entries = <_FontCacheEntry>[];
    if (await supportDir.exists()) {
      await for (final entity in supportDir.list(followLinks: false)) {
        if (entity is! File) continue;
        final entry = await _FontCacheEntry.tryFromFile(entity, activeFamilies);
        if (entry != null) entries.add(entry);
      }
    }
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
    addIfGoogle(theme.emojiFontChoice.googleFamily);
    return active;
  }

  Widget _summaryCard(BuildContext context, _FontCacheSnapshot data) {
    return _cacheCard(context, [
      _plainRow(context, '缓存文件', '${data.entries.length} 个'),
      _plainRow(context, '总大小', _formatBytes(data.totalBytes)),
      _plainRow(context, '正在使用', '${data.activeCount} 个'),
      _plainRow(context, '可清理', '${data.unusedCount} 个'),
    ]);
  }

  Widget _actionCard(BuildContext context, _FontCacheSnapshot data) {
    return _cacheCard(context, [
      _actionRow(context, '刷新缓存列表', FontAwesomeIcons.arrowsRotate.data, () {
        setState(() => _snapshot = _loadSnapshot());
      }),
      _actionRow(
        context,
        '清理未使用字体',
        FontAwesomeIcons.trash.data,
        data.unusedCount == 0 ? null : () => _deleteUnused(data),
        destructive: true,
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
          '没有已下载的字体缓存。',
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
  }) {
    final c = context.colors;
    final enabled = onTap != null;
    final color = destructive ? AppTheme.unreadBadge : AppTheme.brand;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: AppMetric.menuRowHeight + AppSpacing.xxs,
        child: Opacity(
          opacity: enabled ? 1 : 0.35,
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
                FaIcon(
                  FontAwesomeIcons.chevronRight,
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
              entry.active ? '使用中' : '未使用',
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
                  child: FaIcon(
                    FontAwesomeIcons.trash,
                    size: AppIconSize.xl,
                    color: entry.active ? c.textTertiary : AppTheme.unreadBadge,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteUnused(_FontCacheSnapshot data) async {
    for (final entry in data.entries.where((entry) => !entry.active)) {
      try {
        await entry.file.delete();
      } catch (_) {
        // The cache may have been removed by the font loader or the OS.
      }
    }
    if (!mounted) return;
    setState(() => _snapshot = _loadSnapshot());
  }

  Future<void> _deleteEntry(_FontCacheEntry entry) async {
    try {
      await entry.file.delete();
    } catch (_) {
      // The cache may have been removed by the font loader or the OS.
    }
    if (!mounted) return;
    setState(() => _snapshot = _loadSnapshot());
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

class _FontCacheEntry {
  const _FontCacheEntry({
    required this.file,
    required this.displayName,
    required this.bytes,
    required this.modified,
    required this.active,
  });

  static final _cacheFilePattern = RegExp(r'^(.+)_([a-fA-F0-9]{16,128})\.ttf$');

  final File file;
  final String displayName;
  final int bytes;
  final DateTime modified;
  final bool active;

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
      file: file,
      displayName: displayName,
      bytes: stat.size,
      modified: stat.modified,
      active: active,
    );
  }

  static String _displayName(String rawFamily) {
    var value = rawFamily
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
          NavHeader(title: '文本字体', onBack: () => Navigator.of(context).pop()),
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
                    '按顺序应用文本字体；未覆盖的字符继续使用系统字体。',
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
          '未设置文本字体，当前使用系统默认。',
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
    return SizedBox(
      height: AppMetric.menuRowHeight + AppSpacing.md,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: FaIcon(
                FontAwesomeIcons.bars,
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
                    family,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: family,
                      fontSize: AppTextSize.bodyLarge,
                      color: c.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Aa 123 门 門 戸 說 説',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: family,
                      fontSize: AppTextSize.footnote,
                      color: c.textSecondary,
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
                child: FaIcon(
                  FontAwesomeIcons.trash,
                  size: AppIconSize.xl,
                  color: c.textTertiary,
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
          _actionRow(context, '添加文本字体', FontAwesomeIcons.plus.data, () async {
            final family = await Navigator.of(context).push<String>(
              MaterialPageRoute(builder: (_) => const FontAddView()),
            );
            if (family == null || !context.mounted) return;
            context.read<ThemeController>().addFontToFallbackChain(family);
          }),
          if (theme.fontFallbackChain.isNotEmpty) ...[
            const InsetDivider(leadingInset: AppSpacing.xxl),
            _actionRow(
              context,
              '清空文本字体',
              FontAwesomeIcons.xmark.data,
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
              FaIcon(
                FontAwesomeIcons.chevronRight,
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

class EmojiFontPickerView extends StatelessWidget {
  const EmojiFontPickerView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = context.watch<ThemeController>();
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(title: '表情字体', onBack: () => Navigator.of(context).pop()),
          Expanded(
            child: ListView(
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
                      for (
                        var i = 0;
                        i < EmojiFontChoice.values.length;
                        i++
                      ) ...[
                        _row(context, EmojiFontChoice.values[i], theme),
                        if (i < EmojiFontChoice.values.length - 1)
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
                    'Noto Color Emoji 依赖系统可用字体；不可用时会继续使用系统 fallback。',
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

  Widget _row(
    BuildContext context,
    EmojiFontChoice choice,
    ThemeController theme,
  ) {
    final c = context.colors;
    final selected = theme.emojiFontChoice == choice;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.read<ThemeController>().emojiFontChoice = choice,
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
                      choice.label,
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
                      '😀 👍 ❤️ 🏁',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _previewStyle(choice).copyWith(
                        fontSize: AppTextSize.footnote,
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                FaIcon(
                  FontAwesomeIcons.check,
                  size: AppIconSize.lg,
                  color: AppTheme.brand,
                ),
            ],
          ),
        ),
      ),
    );
  }

  TextStyle _previewStyle(EmojiFontChoice choice) {
    final googleFamily = choice.googleFamily;
    if (googleFamily != null) {
      return GoogleFonts.getFont(googleFamily, textStyle: const TextStyle());
    }
    return TextStyle(fontFamilyFallback: choice.fontFamilies);
  }
}

class FontAddView extends StatefulWidget {
  const FontAddView({super.key});

  @override
  State<FontAddView> createState() => _FontAddViewState();
}

class _FontAddViewState extends State<FontAddView> {
  late final Future<List<_FontCandidate>> _fonts = _loadFonts();
  String _query = '';

  Future<List<_FontCandidate>> _loadFonts() async {
    final systemFonts = await SystemFontCatalog.loadFonts();
    final candidates = <_FontCandidate>[
      for (final font in AppFontChoice.primaryOptions)
        if (!font.isCustom)
          _FontCandidate(
            label: font.label,
            family: font.isGoogleFont ? font.googleFamily! : font.fontFamily,
            preview: font.previewText,
            source: font.isGoogleFont ? 'Google' : '内置',
          ),
      for (final font in AppFontChoice.cjkOptions)
        if (!font.isCustom)
          _FontCandidate(
            label: font.label,
            family: font.isGoogleFont ? font.googleFamily! : font.fontFamily,
            preview: font.previewText,
            source: font.isGoogleFont ? 'Google' : '内置',
          ),
      for (final font in AppMonospaceFontChoice.values)
        if (!font.isCustom)
          _FontCandidate(
            label: font.label,
            family: font.isGoogleFont ? font.googleFamily! : font.fontFamily,
            preview: font.previewText,
            source: font.isGoogleFont ? 'Google' : '内置',
          ),
      for (final font in systemFonts)
        _FontCandidate(
          label: font,
          family: font,
          preview: 'Aa 123 门 門 戸 說 説',
          source: '系统',
        ),
    ];
    final byFamily = <String, _FontCandidate>{};
    for (final candidate in candidates) {
      byFamily.putIfAbsent(candidate.family, () => candidate);
    }
    return byFamily.values.toList()..sort((a, b) {
      final sourceCompare = a.sourceOrder.compareTo(b.sourceOrder);
      if (sourceCompare != 0) return sourceCompare;
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
          NavHeader(title: '添加字体', onBack: () => Navigator.of(context).pop()),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: CupertinoSearchTextField(
              placeholder: '搜索字体',
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
                return ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.section,
                  ),
                  children: [_fontCard(context, fonts)],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _fontCard(BuildContext context, List<_FontCandidate> fonts) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < fonts.length; i++) ...[
            _fontRow(context, fonts[i]),
            if (i < fonts.length - 1)
              const InsetDivider(leadingInset: AppSpacing.xxl),
          ],
        ],
      ),
    );
  }

  Widget _fontRow(BuildContext context, _FontCandidate font) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).pop(font.family),
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
                      font.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: font.family,
                        fontSize: AppTextSize.bodyLarge,
                        color: c.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      font.preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: font.family,
                        fontSize: AppTextSize.footnote,
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                font.source,
                style: TextStyle(
                  fontSize: AppTextSize.footnote,
                  color: c.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FontCandidate {
  const _FontCandidate({
    required this.label,
    required this.family,
    required this.preview,
    required this.source,
  });

  final String label;
  final String family;
  final String preview;
  final String source;

  int get sourceOrder => switch (source) {
    '内置' => 0,
    'Google' => 1,
    '系统' => 2,
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
    required this.priority,
  });

  final String label;
  final String family;
  final String preview;
  final String source;
  final AppMonospaceFontChoice? choice;
  final bool google;
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
    if (google && selected) return GoogleFonts.getFont(family, textStyle: base);
    return base.copyWith(
      fontFamily: google ? family.replaceAll(' ', '') : family,
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
          NavHeader(title: '等宽字体', onBack: () => Navigator.of(context).pop()),
          Expanded(
            child: FutureBuilder<List<_MonoFontCandidate>>(
              future: _fonts,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.xl,
                    AppSpacing.lg,
                    AppSpacing.section,
                  ),
                  children: [_fontCard(context, snapshot.data!, selectedKey)],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<List<_MonoFontCandidate>> _loadFonts() async {
    final systemFonts = await SystemFontCatalog.loadFonts();
    final candidates = <_MonoFontCandidate>[
      ..._preferredPlatformMonospaceFonts(),
      ..._googleMonospaceFonts(),
      for (final family in systemFonts.where(_isSystemMonospaceFamily))
        _MonoFontCandidate(
          label: family,
          family: family,
          preview: 'final count = 123;',
          source: '系统',
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
        AppMonospaceFontChoice.monaco,
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
          source: '系统',
          choice: choices[i],
          priority: i,
        ),
    ];
  }

  List<_MonoFontCandidate> _googleMonospaceFonts() {
    final families =
        GoogleFonts.asMap().keys.where(_isGoogleMonospaceFamily).toList()
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
          preview: 'final count = 123;',
          source: 'Google',
          google: true,
          priority: 100 + _googleMonospacePriority(family),
        ),
    ];
  }

  bool _isSystemMonospaceFamily(String family) {
    final normalized = family.toLowerCase();
    return normalized.contains('mono') ||
        family == 'SF Mono' ||
        family == 'Menlo' ||
        family == 'Monaco' ||
        family.startsWith('Courier');
  }

  bool _isGoogleMonospaceFamily(String family) {
    final normalized = family.toLowerCase();
    return normalized.contains('mono') ||
        normalized.contains('source code') ||
        normalized.contains('fira code') ||
        normalized.contains('jetbrains') ||
        normalized.contains('inconsolata') ||
        normalized.contains('anonymous pro') ||
        normalized.contains('cascadia') ||
        normalized.contains('courier prime') ||
        normalized.contains('commit mono') ||
        normalized.contains('geist mono') ||
        normalized.contains('ibm plex mono') ||
        normalized.contains('pt mono') ||
        normalized.contains('space mono') ||
        normalized.contains('ubuntu mono') ||
        normalized.contains('victor mono') ||
        normalized == 'sono';
  }

  int _systemMonospacePriority(String family) {
    final priorities = switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => const [
        'SF Mono',
        'Menlo',
        'Courier',
        'Courier New',
        'Monaco',
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

  Widget _fontCard(
    BuildContext context,
    List<_MonoFontCandidate> fonts,
    String selectedKey,
  ) {
    final c = context.colors;
    final rows = fonts
        .map(
          (font) => _fontRow(
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
        )
        .toList();
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
                      font.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: font.previewStyle(
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
                font.source,
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
                  '下载失败',
                  style: TextStyle(
                    fontSize: AppTextSize.footnote,
                    color: c.textTertiary,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
              ],
              if (selected)
                FaIcon(
                  FontAwesomeIcons.check,
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
