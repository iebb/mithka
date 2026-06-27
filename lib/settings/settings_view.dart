//
//  settings_view.dart
//
//  设置 — presented full-screen from the 我 drawer. Pushes the functional
//  sub-screens (edit profile, notifications, privacy & security, general).
//  Port of the Swift `SettingsView`.
//

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/app_version.dart';
import '../auth/auth_manager.dart';
import '../components/sf_symbols.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'about_view.dart';
import 'appearance_view.dart';
import 'edit_profile_view.dart';
import 'feature_settings_view.dart';
import 'general_settings_view.dart';
import 'notification_settings_view.dart';
import 'privacy_security_view.dart';
import 'proxy_view.dart';
import 'translation_settings_view.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(title: '设置', onBack: () => Navigator.of(context).pop()),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
              children: [
                _card([
                  _navRow(
                    context,
                    'person.crop.circle.fill',
                    '编辑资料',
                    const Color(0xFF3C8CF0),
                    () => const EditProfileView(),
                  ),
                ]),
                const SizedBox(height: 14),
                _card([
                  _navRow(
                    context,
                    'bell.fill',
                    '消息通知',
                    const Color(0xFFF5A623),
                    () => const NotificationSettingsView(),
                  ),
                  const InsetDivider(leadingInset: 56),
                  _navRow(
                    context,
                    'lock.shield.fill',
                    '隐私与安全',
                    const Color(0xFF16B05A),
                    () => const PrivacySecurityView(),
                  ),
                ]),
                const SizedBox(height: 14),
                _card([
                  _navRow(
                    context,
                    'gearshape.fill',
                    '通用',
                    const Color(0xFF8E8E93),
                    () => const GeneralSettingsView(),
                  ),
                  const InsetDivider(leadingInset: 56),
                  _navRow(
                    context,
                    'square.grid.2x2.fill',
                    '功能',
                    const Color(0xFF3C8CF0),
                    () => const FeatureSettingsView(),
                  ),
                  const InsetDivider(leadingInset: 56),
                  _navRow(
                    context,
                    'sparkles',
                    '外观',
                    const Color(0xFF8E7BFF),
                    () => const AppearanceView(),
                  ),
                  const InsetDivider(leadingInset: 56),
                  _navRow(
                    context,
                    'character.book.closed',
                    '翻译',
                    const Color(0xFF34A2DF),
                    () => const TranslationSettingsView(),
                  ),
                  const InsetDivider(leadingInset: 56),
                  _navRow(
                    context,
                    'globe',
                    '代理',
                    const Color(0xFF34A2DF),
                    () => const ProxyView(),
                  ),
                  const InsetDivider(leadingInset: 56),
                  _aboutRow(context),
                ]),
                const SizedBox(height: 14),
                _logoutCard(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(List<Widget> children) => Builder(
    builder: (context) => Container(
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    ),
  );

  Widget _rowLabel(
    BuildContext context,
    String icon,
    String title,
    Color color, {
    String? trailing,
  }) {
    final c = context.colors;
    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(sfIcon(icon), size: 15, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title.l10n(context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16, color: c.textPrimary),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              SizedBox(
                width: 110,
                child: Text(
                  trailing,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 13, color: c.textTertiary),
                ),
              ),
            ],
            const SizedBox(width: 6),
            Icon(sfIcon('chevron.right'), size: 14, color: c.textTertiary),
          ],
        ),
      ),
    );
  }

  Widget _navRow(
    BuildContext context,
    String icon,
    String title,
    Color color,
    Widget Function() destination,
  ) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => destination())),
      child: _rowLabel(context, icon, title, color),
    );
  }

  Widget _aboutRow(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AboutView())),
    child: FutureBuilder<AppVersion>(
      future: AppVersion.load(),
      builder: (context, snapshot) => _rowLabel(
        context,
        'info.circle',
        '关于 Mithka',
        const Color(0xFF8E8E93),
        trailing: 'v${snapshot.data?.version ?? '...'}',
      ),
    ),
  );

  Widget _logoutCard(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Navigator.of(context).pop();
        context.read<AuthManager>().logOut();
      },
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '退出登录',
          style: TextStyle(fontSize: 16, color: AppTheme.tagRed),
        ),
      ),
    );
  }
}
