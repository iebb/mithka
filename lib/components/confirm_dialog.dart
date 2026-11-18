//
//  confirm_dialog.dart
//
//  Shared confirmation dialog entry point delegating to the project-owned
//  showAppConfirmDialog surface. Returns true when the confirm action is chosen.
//

import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';
import 'app_confirm_dialog.dart';

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String confirmText = AppStringKeys.confirmOk,
  String cancelText = AppStringKeys.countryPickerCancel,
  bool destructive = false,
}) => showAppConfirmDialog(
  context,
  title: title,
  message: message,
  confirmText: confirmText,
  cancelText: cancelText,
  destructive: destructive,
);
