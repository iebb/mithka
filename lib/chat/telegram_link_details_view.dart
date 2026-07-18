import 'package:flutter/material.dart';

import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../theme/app_theme.dart';

class TelegramLinkDetail {
  const TelegramLinkDetail(this.label, this.value);

  final String label;
  final String value;
}

/// A compact in-app destination for Telegram links whose data is provided by
/// TDLib but doesn't otherwise have a dedicated Mithka screen yet.
class TelegramLinkDetailsView extends StatelessWidget {
  const TelegramLinkDetailsView({
    super.key,
    required this.title,
    required this.icon,
    required this.details,
    this.subtitle = '',
    this.trailing,
  });

  final String title;
  final AppIconData icon;
  final String subtitle;
  final List<TelegramLinkDetail> details;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(title: title, onBack: () => Navigator.of(context).pop()),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 28, 16, 32),
              children: [
                Center(
                  child: Container(
                    width: 76,
                    height: 76,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.linkBlue.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: AppIcon(icon, size: 36, color: c.linkBlue),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: AppTextStyle.title(
                    c.textPrimary,
                    weight: AppTextWeight.bold,
                  ).copyWith(fontSize: 21),
                ),
                if (subtitle.trim().isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: AppTextStyle.body(
                      c.textSecondary,
                    ).copyWith(height: 1.35),
                  ),
                ],
                const SizedBox(height: 24),
                if (details.isNotEmpty)
                  Container(
                    decoration: BoxDecoration(
                      color: c.card,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (
                          var index = 0;
                          index < details.length;
                          index++
                        ) ...[
                          _DetailRow(detail: details[index]),
                          if (index != details.length - 1)
                            Padding(
                              padding: const EdgeInsets.only(left: 16),
                              child: Divider(height: 1, color: c.divider),
                            ),
                        ],
                      ],
                    ),
                  ),
                if (trailing != null) ...[
                  const SizedBox(height: 18),
                  trailing!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.detail});

  final TelegramLinkDetail detail;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(
              detail.label,
              style: AppTextStyle.body(c.textSecondary),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              detail.value,
              textAlign: TextAlign.end,
              style: AppTextStyle.body(c.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
