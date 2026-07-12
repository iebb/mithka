import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Compact VIP indicator shown next to a Telegram Premium user's name.
class VipBadge extends StatelessWidget {
  const VipBadge({super.key});

  static const _ink = Color(0xFF7A4A00);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFE08A), Color(0xFFF5A623)],
        ),
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ColorFiltered(
            colorFilter: ColorFilter.mode(_ink, BlendMode.srcATop),
            child: Text('🐧', style: TextStyle(fontSize: 13, height: 1.1)),
          ),
          const SizedBox(width: 2),
          Text(
            AppStringKeys.vipBadgeLabel.l10n(context),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
              color: _ink,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}
