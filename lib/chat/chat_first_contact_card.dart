import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../auth/country_picker.dart';
import '../auth/telegram_country_names.dart';
import '../components/app_icons.dart';
import '../components/photo_avatar.dart';
import '../l10n/app_localizations.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import 'chat_first_contact_info.dart';

/// Compact QQ-style identity card shown inline above an unaccepted private
/// conversation. Unlike Telegram's modal-looking notice, it remains part of
/// the transcript and never blocks reading or replying.
class ChatFirstContactCard extends StatelessWidget {
  const ChatFirstContactCard({
    super.key,
    required this.info,
    required this.title,
    this.photo,
    this.onOpenProfile,
  });

  final ChatFirstContactInfo info;
  final String title;
  final TdFileRef? photo;
  final VoidCallback? onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final country = Country.all
        .where((candidate) => candidate.iso == info.countryCode)
        .firstOrNull;
    final countryName = country?.displayName(
      TelegramCountryNames.shared.cached,
    );
    final countryValue = [
      if (country != null) country.flag,
      if ((countryName ?? '').isNotEmpty) countryName!,
      if (country == null && info.countryCode.isNotEmpty) info.countryCode,
    ].join(' ');
    final registration = _registrationLabel();
    final details = <Widget>[
      if (countryValue.isNotEmpty)
        _detailTile(
          context,
          icon: HeroAppIcons.globe,
          label: AppStringKeys.chatFirstContactPhoneCountry.l10n(context),
          value: countryValue,
        ),
      if (registration.isNotEmpty)
        _detailTile(
          context,
          icon: HeroAppIcons.clock,
          label: AppStringKeys.chatFirstContactRegistration.l10n(context),
          value: registration,
        ),
    ];

    return Padding(
      key: const ValueKey('chat-first-contact-card'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  c.card.withValues(alpha: 0.98),
                  Color.alphaBlend(
                    AppTheme.brand.withValues(alpha: 0.09),
                    c.card,
                  ),
                ],
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: AppTheme.brand.withValues(alpha: 0.20),
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF000000).withValues(alpha: 0.14),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onOpenProfile,
                    child: Row(
                      children: [
                        PhotoAvatar(title: title, photo: photo, size: 54),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: c.textPrimary,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (!info.isContact) ...[
                                const SizedBox(height: 6),
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: AppTheme.brand.withValues(
                                      alpha: 0.14,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    child: Text(
                                      AppStringKeys.chatFirstContactNotContact
                                          .l10n(context),
                                      style: TextStyle(
                                        color: AppTheme.brand,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (onOpenProfile != null)
                          AppIcon(
                            HeroAppIcons.chevronRight,
                            size: 18,
                            color: c.textTertiary,
                          ),
                      ],
                    ),
                  ),
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final width = details.length == 1
                            ? constraints.maxWidth
                            : (constraints.maxWidth - 8) / 2;
                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final detail in details)
                              SizedBox(width: width, child: detail),
                          ],
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 10),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.groupedBackground.withValues(alpha: 0.70),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 9,
                      ),
                      child: Row(
                        children: [
                          AppIcon(
                            info.isOfficial
                                ? HeroAppIcons.shieldHalved
                                : HeroAppIcons.circleInfo,
                            size: 17,
                            color: info.isOfficial
                                ? AppTheme.brand
                                : c.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              (info.isOfficial
                                      ? AppStringKeys.chatFirstContactOfficial
                                      : AppStringKeys
                                            .chatFirstContactNotOfficial)
                                  .l10n(context),
                              style: TextStyle(
                                color: c.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailTile(
    BuildContext context, {
    required AppIconData icon,
    required String label,
    required String value,
  }) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.groupedBackground.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.brand.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(9),
              ),
              child: AppIcon(icon, size: 15, color: AppTheme.brand),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.textTertiary, fontSize: 10.5),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _registrationLabel() {
    if (!info.hasRegistrationDate) return '';
    try {
      return DateFormat.yMMMM().format(
        DateTime(info.registrationYear, info.registrationMonth),
      );
    } catch (_) {
      return '${info.registrationYear}-${info.registrationMonth.toString().padLeft(2, '0')}';
    }
  }
}
