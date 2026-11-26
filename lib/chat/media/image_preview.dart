import 'package:flutter/material.dart' show Brightness, Theme;
import 'package:flutter/widgets.dart';

import '../../app/desktop/desktop_image_preview_window.dart';
import '../../media/media_metadata.dart';
import '../../tdlib/td_models.dart';
import '../../theme/app_motion.dart';
import 'full_image_viewer.dart';

export 'full_image_viewer.dart';

@visibleForTesting
bool imagePreviewCanUseIndependentWindow({
  String? primaryActionLabel,
  Future<void> Function(int index)? onPrimaryAction,
  Future<void> Function(int index)? onMore,
}) =>
    // View in chat, Reply and media info travel to the native window's menu;
    // these custom actions run code it cannot reach.
    primaryActionLabel == null && onPrimaryAction == null && onMore == null;

/// Opens the selected image in an independent native window on desktop.
///
/// Mobile/tablet, previews with a custom primary or More action, and
/// native-window failures retain an in-app gallery above the tab navigators
/// and their navigation bars.
Future<void> openImagePreview(
  BuildContext context, {
  required List<TdFileRef> items,
  int startIndex = 0,
  String? primaryActionLabel,
  Future<void> Function(int index)? onPrimaryAction,
  Future<void> Function(int index)? onMore,
  ImageViewerMessageActions? messageActions,
  List<MediaMetadata?> metadata = const [],
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
      metadata: metadata,
      messageActions: messageActions,
    );
    if (opened) return;
  }
  if (!context.mounted) return;
  await Navigator.of(context, rootNavigator: true).push<void>(
    AppPageRoute<void>(
      fullscreenDialog: true,
      pageBuilder: (_, _, _) => FullImageViewer(
        items: items,
        startIndex: index,
        primaryActionLabel: primaryActionLabel,
        onPrimaryAction: onPrimaryAction,
        onMore: onMore,
        messageActions: messageActions,
        metadata: metadata,
      ),
    ),
  );
}
