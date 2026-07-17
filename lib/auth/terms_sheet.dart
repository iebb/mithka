import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../components/app_icons.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

const telegramTermsUrl = 'https://telegram.org/tos';

Future<void> showTelegramTermsSheet(
  BuildContext context, {
  Future<void> Function()? onAccept,
  bool isDismissible = true,
  bool enableDrag = true,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _TermsSheet(
      onAccept: () async {
        await onAccept?.call();
        if (sheetContext.mounted) Navigator.of(sheetContext).pop();
      },
    ),
  );
}

class _TermsSheet extends StatelessWidget {
  const _TermsSheet({required this.onAccept});

  final Future<void> Function() onAccept;

  Future<void> _openTelegramTerms() async {
    final uri = Uri.parse(telegramTermsUrl);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final height = MediaQuery.sizeOf(context).height;
    return Padding(
      padding: EdgeInsets.only(
        left: 10,
        right: 10,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 10,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: height * 0.86),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 28,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: c.divider,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: const Image(
                          image: AssetImage('assets/penguin.png'),
                          width: 48,
                          height: 48,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          AppStrings.t(AppStringKeys.loginTermsTitle),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                      AppIcon(
                        HeroAppIcons.shieldHalved,
                        size: 24,
                        color: c.textSecondary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    AppStrings.t(AppStringKeys.loginTermsBody),
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.48,
                      color: c.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _openTelegramTerms,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      decoration: BoxDecoration(
                        color: c.searchFill,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          AppIcon(
                            HeroAppIcons.link,
                            size: 19,
                            color: AppTheme.brand,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              AppStrings.t(
                                AppStringKeys.loginTermsOpenTelegram,
                              ),
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: c.textPrimary,
                              ),
                            ),
                          ),
                          Text(
                            'telegram.org/tos',
                            style: TextStyle(
                              fontSize: 13,
                              color: c.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _TermsAcceptButton(onPressed: onAccept),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TermsAcceptButton extends StatefulWidget {
  const _TermsAcceptButton({required this.onPressed});

  final Future<void> Function() onPressed;

  @override
  State<_TermsAcceptButton> createState() => _TermsAcceptButtonState();
}

class _TermsAcceptButtonState extends State<_TermsAcceptButton> {
  bool _working = false;

  Future<void> _submit() async {
    if (_working) return;
    setState(() => _working = true);
    await widget.onPressed();
    if (mounted) setState(() => _working = false);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppTheme.brand,
          borderRadius: BorderRadius.circular(18),
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _working ? null : _submit,
          child: Center(
            child: _working
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation(AppTheme.onBrand),
                    ),
                  )
                : Text(
                    // Telegram's BotWebAppDisclaimerCheck string contains
                    // Markdown emphasis markers in several language packs.
                    // This app-owned action uses our plain localized label so
                    // those markers are never rendered literally.
                    AppStrings.tLocal(AppStringKeys.loginTermsAccept),
                    style: TextStyle(
                      color: AppTheme.onBrand,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
