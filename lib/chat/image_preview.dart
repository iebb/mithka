import 'package:flutter/material.dart' show Brightness, Theme;
import 'package:flutter/widgets.dart';

import '../app/desktop_image_preview_window.dart';
import '../tdlib/td_models.dart';
import '../theme/app_motion.dart';
import 'full_image_viewer.dart';

export 'full_image_viewer.dart';

@visibleForTesting
bool imagePreviewCanUseIndependentWindow({
  String? primaryActionLabel,
  Future<void> Function(int index)? onPrimaryAction,
  Future<void> Function(int index)? onMore,
}) => primaryActionLabel == null && onPrimaryAction == null && onMore == null;

/// Opens the selected image in an independent native window on desktop.
///
/// Mobile/tablet, action-bearing previews, and native-window failures retain
/// the existing in-app gallery without changing navigation behavior.
Future<void> openImagePreview(
  BuildContext context, {
  required List<TdFileRef> items,
  int startIndex = 0,
  String? primaryActionLabel,
  Future<void> Function(int index)? onPrimaryAction,
  Future<void> Function(int index)? onMore,
}) async {
  if (items.isEmpty) return;
  final index = startIndex.clamp(0, items.length - 1);
  if (imagePreviewCanUseIndependentWindow(
    primaryActionLabel: primaryActionLabel,
    onPrimaryAction: onPrimaryAction,
    onMore: onMore,
  )) {
    final opened = await DesktopImagePreviewWindowService.instance.open(
      items,
      startIndex: index,
      dark: Theme.of(context).brightness == Brightness.dark,
    );
    if (opened) return;
  }
  if (!context.mounted) return;
  await Navigator.of(context).push<void>(
    AppPageRoute<void>(
      fullscreenDialog: true,
      pageBuilder: (_, _, _) => FullImageViewer(
        items: items,
        startIndex: index,
        primaryActionLabel: primaryActionLabel,
        onPrimaryAction: onPrimaryAction,
        onMore: onMore,
      ),
    ),
  );
}
