//
//  about_view.dart
//
//  关于 — app identity (penguin icon, name, version) plus a tappable Telegram
//  channel link (t.me/mithka) that resolves in-app via the link handler.
//

import 'package:flutter/material.dart';

import '../app/app_version.dart';
import '../chat/link_handler.dart';
import '../components/sf_symbols.dart';
import '../components/ui_components.dart';
import '../theme/app_theme.dart';

class AboutView extends StatelessWidget {
  const AboutView({super.key});

  static const _channelUrl = 'https://t.me/mithka';
  static const _githubUrl = 'https://github.com/iebb/mithka';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(title: '关于', onBack: () => Navigator.of(context).pop()),
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
                        future: AppVersion.load(),
                        builder: (context, snapshot) {
                          final version = snapshot.data?.display ?? '...';
                          return Text(
                            '版本 $version',
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
                        icon: sfIcon('paperplane.fill'),
                        title: 'Telegram 频道',
                        value: 't.me/mithka',
                        onTap: () => openLink(context, _channelUrl),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 48),
                        child: Divider(height: 1, color: c.divider),
                      ),
                      _AboutLinkRow(
                        icon: sfIcon('chevron.left.forwardslash.chevron.right'),
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
              Icon(sfIcon('chevron.right'), size: 14, color: c.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}
