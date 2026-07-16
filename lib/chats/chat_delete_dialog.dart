import 'package:flutter/cupertino.dart';

import '../l10n/app_localizations.dart';
import 'chat_delete_policy.dart';

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

  return showCupertinoDialog<ChatDeleteScope>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      title: Text(title.l10n(dialogContext)),
      content: Text(description.l10n(dialogContext)),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(AppStringKeys.countryPickerCancel.l10n(dialogContext)),
        ),
        if (capabilities.canDeleteForSelf)
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () =>
                Navigator.of(dialogContext).pop(ChatDeleteScope.self),
            child: Text(AppStringKeys.chatDeleteForMe.l10n(dialogContext)),
          ),
        if (capabilities.canDeleteForAllUsers)
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () =>
                Navigator.of(dialogContext).pop(ChatDeleteScope.allUsers),
            child: Text(
              (isGroupOrChannel
                      ? AppStringKeys.chatDeleteForAllMembers
                      : AppStringKeys.chatDeleteForBothSides)
                  .l10n(dialogContext),
            ),
          ),
      ],
    ),
  );
}
