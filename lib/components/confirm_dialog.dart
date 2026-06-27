//
//  confirm_dialog.dart
//
//  iOS-native confirm sheet (CupertinoAlertDialog) replacing Material's
//  AlertDialog app-wide. Returns true when the confirm action is chosen.
//

import 'package:flutter/cupertino.dart';

import '../l10n/app_localizations.dart';

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String confirmText = '确定',
  String cancelText = '取消',
  bool destructive = false,
}) async {
  final ok = await showCupertinoDialog<bool>(
    context: context,
    builder: (ctx) => CupertinoAlertDialog(
      title: Text(title.l10n(ctx)),
      content: message == null ? null : Text(message.l10n(ctx)),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(cancelText.l10n(ctx)),
        ),
        CupertinoDialogAction(
          isDestructiveAction: destructive,
          isDefaultAction: !destructive,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmText.l10n(ctx)),
        ),
      ],
    ),
  );
  return ok ?? false;
}
