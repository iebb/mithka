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
import '../pro/mithka_pro_service.dart';
import '../pro/mithka_pro_view.dart';
import '../theme/app_theme.dart';
import 'about_view.dart';
import 'advanced_settings_view.dart';
import 'ai_settings_view.dart';
import 'appearance_view.dart';
import 'blocking_settings_view.dart';
import 'developer_mode_controller.dart';
import 'developer_settings_view.dart';
import 'edit_profile_view.dart';
import 'feature_settings_view.dart';
import 'general_settings_view.dart';
import 'language_settings_view.dart';
import 'notification_settings_view.dart';
import 'privacy_security_view.dart';
import 'proxy_view.dart';

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
    final developer = context.watch<DeveloperModeController>();
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
                    HeroAppIcons.solidCircleUser,
                    AppStrings.t(AppStringKeys.editProfileTitle),
                    const Color(0xFF3C8CF0),
                    () => const EditProfileView(),
                  ),
                ]),
                const SizedBox(height: 14),
                _card([
                  _navRow(
                    context,
                    HeroAppIcons.solidStar,
                    AppStrings.t(AppStringKeys.mithkaProTitle),
                    const Color(0xFF7C5CFC),
                    () => const MithkaProView(),
                    trailing: context.watch<MithkaProService>().isPro
                        ? AppStrings.t(AppStringKeys.mithkaProActive)
                        : null,
                    platformNeutralRoute: true,
                  ),
                ]),
                const SizedBox(height: 14),
                _card([
                  _navRow(
                    context,
                    HeroAppIcons.solidBell,
                    AppStrings.t(AppStringKeys.notificationTitle),
                    const Color(0xFFF5A623),
                    () => const NotificationSettingsView(),
                  ),
                  const InsetDivider(leadingInset: 56),
                  _navRow(
                    context,
                    HeroAppIcons.shieldHalved,
                    AppStrings.t(AppStringKeys.privacySecurityTitle),
                    const Color(0xFF16B05A),
                    () => const PrivacySecurityView(),
                  ),
                  const InsetDivider(leadingInset: 56),
                  _navRow(
                    context,
                    HeroAppIcons.ban,
                    AppStrings.t(AppStringKeys.blockingTitle),
                    const Color(0xFFDA405B),
                    () => const BlockingSettingsView(),
                  ),
                ]),
                const SizedBox(height: 14),
                _card([
                  _navRow(
                    context,
                    HeroAppIcons.gear,
                    AppStrings.t(AppStringKeys.generalTitle),
                    const Color(0xFF8E8E93),
                    () => const GeneralSettingsView(),
                  ),
                  const InsetDivider(leadingInset: 56),
                  _navRow(
                    context,
                    HeroAppIcons.language,
                    AppStrings.t(AppStringKeys.languageTitle),
                    const Color(0xFF34A2DF),
                    () => const LanguageSettingsView(),
                  ),
                  const InsetDivider(leadingInset: 56),
                  _navRow(
                    context,
                    HeroAppIcons.grip,
                    AppStrings.t(AppStringKeys.featureTitle),
                    const Color(0xFF3C8CF0),
                    () => const FeatureSettingsView(),
                  ),
                  const InsetDivider(leadingInset: 56),
                  _navRow(
                    context,
                    HeroAppIcons.cpuChip,
                    AppStrings.t(AppStringKeys.aiSettingsTitle),
                    const Color(0xFF7467F0),
                    () => const AiSettingsView(),
                  ),
                  const InsetDivider(leadingInset: 56),
                  _navRow(
                    context,
                    HeroAppIcons.wandMagicSparkles,
                    AppStrings.t(AppStringKeys.appearanceTitle),
                    const Color(0xFF8E7BFF),
                    () => const AppearanceView(),
                  ),
                  const InsetDivider(leadingInset: 56),
                  _navRow(
                    context,
                    HeroAppIcons.eye,
                    AppStrings.t(AppStringKeys.appearanceSize),
                    const Color(0xFF34A2DF),
                    () => const DisplaySettingsView(),
                  ),
                  const InsetDivider(leadingInset: 56),
                  _navRow(
                    context,
                    HeroAppIcons.globe,
                    AppStrings.t(AppStringKeys.proxyTitle),
                    const Color(0xFF34A2DF),
                    () => const ProxyView(),
                  ),
                  const InsetDivider(leadingInset: 56),
                  _navRow(
                    context,
                    HeroAppIcons.objectGroup,
                    AppStrings.t(AppStringKeys.advancedTitle),
                    const Color(0xFF16B0A0),
                    () => const AdvancedSettingsView(),
                  ),
                  if (developer.unlocked) ...[
                    const InsetDivider(leadingInset: 56),
                    _navRow(
                      context,
                      HeroAppIcons.code,
                      AppStrings.t(AppStringKeys.developerModeTitle),
                      const Color(0xFFFF5A5F),
                      () => const DeveloperSettingsView(),
                    ),
                  ],
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
    AppIconData icon,
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
            SettingsIconTile(icon: icon, backgroundColor: color),
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
    AppIconData icon,
    String title,
    Color color,
    Widget Function() destination, {
    String? trailing,
    bool platformNeutralRoute = false,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(
        platformNeutralRoute
            ? PageRouteBuilder<void>(pageBuilder: (_, _, _) => destination())
            : MaterialPageRoute<void>(builder: (_) => destination()),
      ),
      child: _rowLabel(context, icon, title, color, trailing: trailing),
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
        HeroAppIcons.circleInfo,
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
