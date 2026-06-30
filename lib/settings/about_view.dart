//
//  about_view.dart
//
//  关于 — app identity (penguin icon, name, version) plus tappable links
//  that resolve through the shared link handler.
//

import 'package:flutter/material.dart';

import '../app/app_version.dart';
import '../chat/link_handler.dart';
import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../theme/app_theme.dart';
import 'package:mithka/l10n/app_localizations.dart';

class AboutView extends StatefulWidget {
  const AboutView({super.key});

  @override
  State<AboutView> createState() => _AboutViewState();
}

class _AboutViewState extends State<AboutView> {
  static const _websiteUrl = 'https://mithka.ieb.app';
  static const _channelUrl = 'https://t.me/mithka';
  static const _githubUrl = 'https://github.com/iebb/mithka';
  late final Future<AppVersion> _versionFuture = AppVersion.load();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.aboutTitle),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 32, 12, 24),
              children: [
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          gradient: AppTheme.brandGradient,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(10),
                          child: Image(
                            image: AssetImage('assets/penguin.png'),
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Mithka',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      FutureBuilder<AppVersion>(
                        future: _versionFuture,
                        builder: (context, snapshot) {
                          final version = snapshot.data?.display ?? '...';
                          return Text(
                            AppStrings.t(AppStringKeys.aboutVersion, {
                              'value1': version,
                            }),
                            style: TextStyle(
                              fontSize: 13,
                              color: c.textSecondary,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                Container(
                  decoration: BoxDecoration(
                    color: c.card,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      _AboutLinkRow(
                        icon: HeroAppIcons.globe.data,
                        title: 'Website',
                        value: 'mithka.ieb.app',
                        onTap: () => openLink(context, _websiteUrl),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 48),
                        child: Divider(height: 1, color: c.divider),
                      ),
                      _AboutLinkRow(
                        icon: HeroAppIcons.solidPaperPlane.data,
                        title: AppStrings.t(AppStringKeys.aboutTelegramChannel),
                        value: 't.me/mithka',
                        onTap: () => openLink(context, _channelUrl),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 48),
                        child: Divider(height: 1, color: c.divider),
                      ),
                      _AboutLinkRow(
                        icon: HeroAppIcons.code.data,
                        title: 'GitHub',
                        value: 'github.com/iebb/mithka',
                        onTap: () => openLink(context, _githubUrl),
                      ),
                    ],
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

class _AboutLinkRow extends StatelessWidget {
  const _AboutLinkRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
              const SizedBox(width: 12),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16, color: c.textPrimary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 14, color: c.textSecondary),
                ),
              ),
              const SizedBox(width: 6),
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
