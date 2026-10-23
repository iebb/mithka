import 'dart:io';

import 'package:flutter/material.dart';

import '../auth/account_store.dart';
import '../components/app_interactive_surface.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';

/// Lets the user pick which signed-in account an account-less deep link
/// belongs to, instead of the shell silently dropping the request.
///
/// A chat id only means something inside the account that produced it, so a
/// link naming no account while several are signed in cannot be placed
/// automatically — but it can be placed by asking. The chosen slot is returned
/// through the future; a dismissed sheet resolves to null and the request is
/// dropped only because the user declined to disambiguate it.
Future<int?> showAccountPickerDialog(
  BuildContext context, {
  required List<AccountSummary> accounts,
  int? activeSlot,
}) async {
  final c = context.colors;
  return showGeneralDialog<int>(
    context: context,
    barrierDismissible: true,
    barrierLabel: AppStringKeys.countryPickerCancel.l10n(context),
    barrierColor: const Color(0x99000000),
    transitionDuration: AppMotion.duration(context, AppMotion.responsive),
    pageBuilder: (dialogContext, _, _) => Semantics(
      key: const ValueKey('account-picker-dialog'),
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x44000000),
                    blurRadius: 24,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Semantics(
                            header: true,
                            child: Text(
                              AppStringKeys.accountPickerTitle.l10n(
                                dialogContext,
                              ),
                              textAlign: TextAlign.center,
                              style: AppTextStyle.title(
                                c.textPrimary,
                                weight: AppTextWeight.semibold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            AppStringKeys.accountPickerMessage.l10n(
                              dialogContext,
                            ),
                            textAlign: TextAlign.center,
                            style: AppTextStyle.body(
                              c.textSecondary,
                            ).copyWith(height: 1.35),
                          ),
                          const SizedBox(height: 14),
                          for (final account in accounts)
                            _AccountPickerRow(
                              key: ValueKey(
                                'account-picker-row-${account.slot}',
                              ),
                              account: account,
                              selected: account.slot == activeSlot,
                              onTap: () =>
                                  Navigator.of(dialogContext).pop(account.slot),
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
    ),
  );
}

class _AccountPickerRow extends StatelessWidget {
  const _AccountPickerRow({
    super.key,
    required this.account,
    required this.selected,
    required this.onTap,
  });

  final AccountSummary account;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: AppInteractiveSurface(
        semanticLabel: account.name,
        selected: selected,
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Container(
          height: 50,
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.brand.withValues(alpha: 0.12)
                : c.searchFill,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              _AccountPickerAvatar(account: account, size: 34),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                    if (account.phone.isNotEmpty)
                      Text(
                        account.phone,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.textSecondary, fontSize: 11),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountPickerAvatar extends StatelessWidget {
  const _AccountPickerAvatar({required this.account, required this.size});

  final AccountSummary account;
  final double size;

  @override
  Widget build(BuildContext context) {
    final path = account.avatarPath;
    final name = account.name.trim();
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: AppTheme.brand, shape: BoxShape.circle),
      child: name.isEmpty
          ? const SizedBox.shrink()
          : Text(
              name.characters.first.toUpperCase(),
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.4,
                fontWeight: FontWeight.w600,
              ),
            ),
    );
    if (path == null || path.isEmpty) return fallback;
    final cacheSize = (size * MediaQuery.devicePixelRatioOf(context)).ceil();
    return ClipOval(
      child: Image.file(
        File(path),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: cacheSize,
        cacheHeight: cacheSize,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}
