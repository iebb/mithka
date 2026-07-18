import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';

enum SharedContactAction { viewProfile, message, call, copyNumber, addContact }

Future<SharedContactAction?> showSharedContactActions(
  BuildContext context,
  MessageContactCard contact,
) {
  return showModalBottomSheet<SharedContactAction>(
    context: context,
    backgroundColor: Colors.transparent,
    useSafeArea: true,
    builder: (context) => _SharedContactSheet(contact: contact),
  );
}

class _SharedContactSheet extends StatelessWidget {
  const _SharedContactSheet({required this.contact});

  final MessageContactCard contact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final actions = <(SharedContactAction, AppIconData, String)>[
      if (contact.userId > 0)
        (
          SharedContactAction.viewProfile,
          HeroAppIcons.circleUser,
          AppStringKeys.sharedContactViewProfile,
        ),
      if (contact.userId > 0)
        (
          SharedContactAction.message,
          HeroAppIcons.message,
          AppStringKeys.sharedContactMessage,
        ),
      if (contact.userId > 0)
        (
          SharedContactAction.call,
          HeroAppIcons.phone,
          AppStringKeys.sharedContactCall,
        ),
      if (contact.phoneNumber.isNotEmpty)
        (
          SharedContactAction.copyNumber,
          HeroAppIcons.clipboard,
          AppStringKeys.sharedContactCopyNumber,
        ),
      if (contact.phoneNumber.isNotEmpty)
        (
          SharedContactAction.addContact,
          HeroAppIcons.userPlus,
          AppStringKeys.sharedContactAdd,
        ),
    ];
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x30000000),
            blurRadius: 24,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 4,
            margin: const EdgeInsets.only(top: 9, bottom: 14),
            decoration: BoxDecoration(
              color: c.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTheme.brand.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: AppIcon(
                    HeroAppIcons.idBadge,
                    size: 23,
                    color: AppTheme.brand,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        contact.displayName,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary,
                        ),
                      ),
                      if (contact.phoneNumber.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          contact.phoneNumber,
                          style: TextStyle(
                            fontSize: 13,
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: c.divider),
          for (final action in actions)
            GestureDetector(
              key: ValueKey('sharedContactAction-${action.$1.name}'),
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(action.$1),
              child: SizedBox(
                height: 52,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    children: [
                      AppIcon(action.$2, size: 20, color: AppTheme.brand),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          action.$3.l10n(context),
                          style: TextStyle(fontSize: 15, color: c.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
