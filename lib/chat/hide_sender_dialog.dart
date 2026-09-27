//
//  hide_sender_dialog.dart
//
//  Asks where to hide a member's messages: in this group, or in every chat.
//  Styled like showAppConfirmDialog — 320pt card, 50pt stacked actions — but
//  with two choices above Cancel.
//

import 'package:flutter/widgets.dart';

import '../components/app_interactive_surface.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';

enum HideSenderScope { thisGroup, everywhere }

Future<HideSenderScope?> showHideSenderDialog(
  BuildContext context, {
  required String name,
}) {
  final c = context.colors;
  return showGeneralDialog<HideSenderScope>(
    context: context,
    barrierDismissible: true,
    barrierLabel: AppStringKeys.countryPickerCancel.l10n(context),
    barrierColor: const Color(0x99000000),
    transitionDuration: AppMotion.duration(context, AppMotion.responsive),
    transitionBuilder: AppMotion.dialogTransition,
    pageBuilder: (dialogContext, _, _) {
      Widget action(
        String key,
        String label,
        Color color,
        VoidCallback onTap, {
        bool autofocus = false,
      }) => AppInteractiveSurface(
        key: ValueKey('hide-sender-$key'),
        semanticLabel: label,
        autofocus: autofocus,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 50),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Center(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: AppTextStyle.bodyLarge(
                  color,
                  weight: AppTextWeight.semibold,
                ),
              ),
            ),
          ),
        ),
      );
      final divider = ColoredBox(
        color: c.divider,
        child: const SizedBox(height: 1),
      );
      void close(HideSenderScope? scope) =>
          Navigator.of(dialogContext).pop(scope);
      return Semantics(
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
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
                      child: Column(
                        children: [
                          Semantics(
                            header: true,
                            child: Text(
                              AppStrings.t(AppStringKeys.hideSenderTitle, {
                                'value1': name,
                              }),
                              textAlign: TextAlign.center,
                              style: AppTextStyle.title(
                                c.textPrimary,
                                weight: AppTextWeight.semibold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            AppStrings.t(AppStringKeys.hideSenderMessage),
                            textAlign: TextAlign.center,
                            style: AppTextStyle.body(
                              c.textSecondary,
                            ).copyWith(height: 1.35),
                          ),
                        ],
                      ),
                    ),
                    divider,
                    action(
                      'this-group',
                      AppStrings.t(AppStringKeys.hideSenderInThisGroup),
                      c.linkBlue,
                      () => close(HideSenderScope.thisGroup),
                    ),
                    divider,
                    action(
                      'everywhere',
                      AppStrings.t(AppStringKeys.hideSenderEverywhere),
                      c.linkBlue,
                      () => close(HideSenderScope.everywhere),
                    ),
                    divider,
                    action(
                      'cancel',
                      AppStrings.t(AppStringKeys.countryPickerCancel),
                      c.textSecondary,
                      () => close(null),
                      autofocus: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
