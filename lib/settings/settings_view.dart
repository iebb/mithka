//
//  settings_view.dart
//
//  设置 — presented full-screen from the 我 drawer. Pushes the functional
//  sub-screens (edit profile, notifications, privacy & security, general).
//  Port of the Swift `SettingsView`.
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/app_version.dart';
import '../auth/account_store.dart';
import '../auth/auth_manager.dart';
import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'about_view.dart';
import 'api_credentials_view.dart';
import 'appearance_view.dart';
import 'edit_profile_view.dart';
import 'feature_settings_view.dart';
import 'general_settings_view.dart';
import 'notification_settings_view.dart';
import 'privacy_security_view.dart';
import 'proxy_view.dart';
import 'translation_settings_view.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late final Future<AppVersion> _versionFuture = AppVersion.load();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.profileSettings),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
              children: [
                _card([
                  _navRow(
                    context,
                    HeroAppIcons.solidCircleUser.data,
                    AppStrings.t(AppStringKeys.editProfileTitle),
                    const Color(0xFF3C8CF0),
                    () => const EditProfileView(),
                  ),
                ]),
                const SizedBox(height: 14),
                _card([
                  _navRow(
                    context,
                    HeroAppIcons.solidBell.data,
                    AppStrings.t(AppStringKeys.notificationTitle),
                    const Color(0xFFF5A623),
                    () => const NotificationSettingsView(),
                  ),
                  const InsetDivider(leadingInset: 56),
                  _navRow(
                    context,
                    HeroAppIcons.shieldHalved.data,
                    AppStrings.t(AppStringKeys.privacySecurityTitle),
                    const Color(0xFF16B05A),
                    () => const PrivacySecurityView(),
                  ),
                ]),
                const SizedBox(height: 14),
                _card([
                  _navRow(
                    context,
                    HeroAppIcons.gear.data,
                    AppStrings.t(AppStringKeys.generalTitle),
                    const Color(0xFF8E8E93),
                    () => const GeneralSettingsView(),
                  ),
                  const InsetDivider(leadingInset: 56),
                  _navRow(
                    context,
                    HeroAppIcons.grip.data,
                    AppStrings.t(AppStringKeys.featureTitle),
                    const Color(0xFF3C8CF0),
                    () => const FeatureSettingsView(),
                  ),
                  const InsetDivider(leadingInset: 56),
                  _navRow(
                    context,
                    HeroAppIcons.wandMagicSparkles.data,
                    AppStrings.t(AppStringKeys.appearanceTitle),
                    const Color(0xFF8E7BFF),
                    () => const AppearanceView(),
                  ),
                  const InsetDivider(leadingInset: 56),
                  _navRow(
                    context,
                    HeroAppIcons.eye.data,
                    AppStrings.t(AppStringKeys.appearanceDisplay),
                    const Color(0xFF34A2DF),
                    () => const DisplaySettingsView(),
                  ),
                  const InsetDivider(leadingInset: 56),
                  _navRow(
                    context,
                    HeroAppIcons.language.data,
                    AppStrings.t(AppStringKeys.messageActionTranslate),
                    const Color(0xFF34A2DF),
                    () => const TranslationSettingsView(),
                  ),
                  const InsetDivider(leadingInset: 56),
                  _navRow(
                    context,
                    HeroAppIcons.globe.data,
                    AppStrings.t(AppStringKeys.proxyTitle),
                    const Color(0xFF34A2DF),
                    () => const ProxyView(),
                  ),
                  const InsetDivider(leadingInset: 56),
                  _navRow(
                    context,
                    HeroAppIcons.cloudArrowDown.data,
                    AppStringKeys.apiCredentialsTitle,
                    const Color(0xFF2FBF71),
                    () => const ApiCredentialsView(),
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
    IconData icon,
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
              child: Icon(icon, size: 15, color: Colors.white),
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
            AppIcon(HeroAppIcons.chevronRight, size: 14, color: c.textTertiary),
          ],
        ),
      ),
    );
  }

  Widget _navRow(
    BuildContext context,
    IconData icon,
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
      future: _versionFuture,
      builder: (context, snapshot) => _rowLabel(
        context,
        HeroAppIcons.circleInfo.data,
        AppStrings.t(AppStringKeys.settingsAboutMithka),
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
        unawaited(
          context.read<AccountStore>().logOutActive(
            context.read<AuthManager>(),
          ),
        );
      },
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          AppStrings.t(AppStringKeys.settingsLogOut),
          style: TextStyle(fontSize: 16, color: AppTheme.tagRed),
        ),
      ),
    );
  }
}
