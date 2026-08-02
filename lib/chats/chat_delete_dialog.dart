import 'package:flutter/widgets.dart';

import '../components/app_confirm_dialog.dart';
import '../components/app_interactive_surface.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import 'chat_delete_policy.dart';

/// Selects who a chat deletion affects. The scope choice is deliberately kept
/// separate from the final irreversible confirmation.
Future<ChatDeleteScope?> showChatDeleteScopeDialog(
  BuildContext context, {
  required ChatDeleteCapabilities capabilities,
  required bool isGroupOrChannel,
  required String title,
  required String selfOnlyDescription,
}) {
  final bothScopes =
      capabilities.canDeleteForSelf && capabilities.canDeleteForAllUsers;
  final description = switch ((
    bothScopes,
    capabilities.canDeleteForAllUsers,
    isGroupOrChannel,
  )) {
    (true, _, true) => AppStringKeys.chatDeleteScopeGroupDescription,
    (true, _, false) => AppStringKeys.chatDeleteScopePrivateDescription,
    (false, true, true) => AppStringKeys.chatDeleteAllMembersDescription,
    (false, true, false) => AppStringKeys.chatDeleteBothSidesDescription,
    _ => selfOnlyDescription,
  };

  return showGeneralDialog<ChatDeleteScope>(
    context: context,
    barrierDismissible: true,
    barrierLabel: AppStringKeys.countryPickerCancel.l10n(context),
    barrierColor: const Color(0x99000000),
    transitionDuration: AppMotion.duration(context, AppMotion.responsive),
    transitionBuilder: AppMotion.dialogTransition,
    pageBuilder: (dialogContext, _, _) => _ChatDeleteScopeDialog(
      title: title.l10n(dialogContext),
      description: description.l10n(dialogContext),
      capabilities: capabilities,
      isGroupOrChannel: isGroupOrChannel,
    ),
  );
}

/// Requires both a deletion-scope decision and a distinct final confirmation.
/// Saved Messages is a self-chat, so it receives two dedicated clear prompts
/// rather than the irrelevant self/all-users scope chooser.
Future<ChatDeleteScope?> showTwoStepChatDeleteDialog(
  BuildContext context, {
  required ChatDeleteCapabilities capabilities,
  required bool isGroupOrChannel,
  required bool isSavedMessages,
  required String chatTitle,
  required String title,
  required String selfOnlyDescription,
  String? selfConfirmText,
}) async {
  if (isSavedMessages) {
    final confirmed = await showTwoStepDestructiveConfirmation(
      context,
      firstTitle: AppStringKeys.savedMessagesClearQuestion,
      firstMessage: AppStringKeys.savedMessagesClearDescription,
      firstConfirmText: AppStringKeys.confirmContinue,
      finalTitle: AppStringKeys.savedMessagesClearFinalQuestion,
      finalMessage: AppStringKeys.chatDeleteFinalWarning,
      finalConfirmText: AppStringKeys.savedMessagesClear,
    );
    return confirmed ? ChatDeleteScope.self : null;
  }

  final scope = await showChatDeleteScopeDialog(
    context,
    capabilities: capabilities,
    isGroupOrChannel: isGroupOrChannel,
    title: title,
    selfOnlyDescription: selfOnlyDescription,
  );
  if (!context.mounted || scope == null) return null;
  await _waitForDialogDismissal(context);
  if (!context.mounted) return null;

  final impact = switch ((scope, isGroupOrChannel)) {
    (ChatDeleteScope.self, true) => selfOnlyDescription.l10n(context),
    (ChatDeleteScope.self, false) =>
      AppStringKeys.chatDeleteForMeDescription.l10n(context),
    (ChatDeleteScope.allUsers, true) =>
      AppStringKeys.chatDeleteAllMembersDescription.l10n(context),
    (ChatDeleteScope.allUsers, false) =>
      AppStringKeys.chatDeleteBothSidesDescription.l10n(context),
  };
  final finalWarning = AppStringKeys.chatDeleteFinalWarning.l10n(context);
  final confirmText = switch ((scope, isGroupOrChannel)) {
    (ChatDeleteScope.self, true) =>
      selfConfirmText ?? AppStringKeys.chatDeleteForMe,
    (ChatDeleteScope.self, false) => AppStringKeys.chatDeleteForMe,
    (ChatDeleteScope.allUsers, true) => AppStringKeys.chatDeleteForAllMembers,
    (ChatDeleteScope.allUsers, false) => AppStringKeys.chatDeleteForBothSides,
  };
  final confirmed = await showAppConfirmDialog(
    context,
    title: AppStrings.t(AppStringKeys.chatDeleteFinalQuestion, {
      'value1': chatTitle,
    }),
    message: '$impact\n\n$finalWarning',
    confirmText: confirmText,
    destructive: true,
  );
  return confirmed ? scope : null;
}

/// The common two-stage gate used by destructive chat-history operations.
Future<bool> showTwoStepDestructiveConfirmation(
  BuildContext context, {
  required String firstTitle,
  required String firstMessage,
  required String firstConfirmText,
  required String finalTitle,
  required String finalMessage,
  required String finalConfirmText,
}) async {
  final first = await showAppConfirmDialog(
    context,
    title: firstTitle,
    message: firstMessage,
    confirmText: firstConfirmText,
    destructive: true,
  );
  if (!context.mounted || !first) return false;
  await _waitForDialogDismissal(context);
  if (!context.mounted) return false;
  return showAppConfirmDialog(
    context,
    title: finalTitle,
    message: finalMessage,
    confirmText: finalConfirmText,
    destructive: true,
  );
}

Future<bool> showTwoStepClearHistoryDialog(
  BuildContext context, {
  required String chatTitle,
}) => showTwoStepDestructiveConfirmation(
  context,
  firstTitle: AppStringKeys.chatInfoClearHistoryQuestion,
  firstMessage: AppStringKeys.chatInfoClearHistoryDescription,
  firstConfirmText: AppStringKeys.chatInfoClear,
  finalTitle: AppStrings.t(AppStringKeys.chatInfoClearHistoryFinalQuestion, {
    'value1': chatTitle,
  }),
  finalMessage: AppStringKeys.chatInfoClearHistoryIrreversibleWarning,
  finalConfirmText: AppStringKeys.chatInfoConfirmClearHistory,
);

Future<void> _waitForDialogDismissal(BuildContext context) async {
  final duration = AppMotion.duration(context, AppMotion.responsive);
  if (duration > Duration.zero) await Future<void>.delayed(duration);
}

class _ChatDeleteScopeDialog extends StatelessWidget {
  const _ChatDeleteScopeDialog({
    required this.title,
    required this.description,
    required this.capabilities,
    required this.isGroupOrChannel,
  });

  final String title;
  final String description;
  final ChatDeleteCapabilities capabilities;
  final bool isGroupOrChannel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final actions = <Widget>[
      if (capabilities.canDeleteForSelf)
        _ScopeAction(
          key: const ValueKey('chat-delete-scope-self'),
          label: AppStringKeys.chatDeleteForMe.l10n(context),
          destructive: true,
          onTap: () => Navigator.of(context).pop(ChatDeleteScope.self),
        ),
      if (capabilities.canDeleteForAllUsers)
        _ScopeAction(
          key: const ValueKey('chat-delete-scope-all'),
          label:
              (isGroupOrChannel
                      ? AppStringKeys.chatDeleteForAllMembers
                      : AppStringKeys.chatDeleteForBothSides)
                  .l10n(context),
          destructive: true,
          onTap: () => Navigator.of(context).pop(ChatDeleteScope.allUsers),
        ),
      _ScopeAction(
        key: const ValueKey('chat-delete-scope-cancel'),
        label: AppStringKeys.countryPickerCancel.l10n(context),
        autofocus: true,
        onTap: () => Navigator.of(context).pop(),
      ),
    ];

    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: c.divider, width: 0.5),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x44000000),
                      blurRadius: 24,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: DefaultTextStyle(
                  style: AppTextStyle.body(c.textPrimary),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 24, 22, 10),
                        child: Semantics(
                          header: true,
                          child: Text(
                            title,
                            textAlign: TextAlign.center,
                            style: AppTextStyle.title(
                              c.textPrimary,
                              weight: AppTextWeight.semibold,
                            ),
                          ),
                        ),
                      ),
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
                          child: Text(
                            description,
                            textAlign: TextAlign.center,
                            style: AppTextStyle.body(
                              c.textSecondary,
                            ).copyWith(height: 1.35),
                          ),
                        ),
                      ),
                      for (var index = 0; index < actions.length; index++) ...[
                        ColoredBox(
                          color: c.divider,
                          child: const SizedBox(height: 1),
                        ),
                        actions[index],
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScopeAction extends StatelessWidget {
  const _ScopeAction({
    super.key,
    required this.label,
    required this.onTap,
    this.destructive = false,
    this.autofocus = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool destructive;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => AppInteractiveSurface(
    semanticLabel: label,
    autofocus: autofocus,
    onTap: onTap,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: AppTextStyle.bodyLarge(
              destructive ? AppTheme.tagRed : context.colors.textSecondary,
              weight: AppTextWeight.semibold,
            ),
          ),
        ),
      ),
    ),
  );
}
