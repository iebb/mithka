//
//  sticker_viewer.dart
//
//  Dedicated fullscreen viewer for sticker messages. Static stickers are not
//  photos, so they must not enter the chat image gallery.
//

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/telegram_language_controller.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import 'animated_sticker_view.dart';
import 'sticker_export_service.dart';
import 'sticker_set_detail_view.dart';
import 'video_sticker_view.dart';

class StickerViewer extends StatefulWidget {
  const StickerViewer({super.key, required this.message});

  final ChatMessage message;

  @override
  State<StickerViewer> createState() => _StickerViewerState();
}

class _StickerViewerState extends State<StickerViewer> {
  String _setTitle = telegramText(AppStringKeys.messageActionSticker);
  bool _installed = false;
  bool _exporting = false;
  final LayerLink _exportMenuLink = LayerLink();
  OverlayEntry? _exportMenu;

  ChatMessage get _message => widget.message;

  @override
  void initState() {
    super.initState();
    _loadSet();
  }

  Future<void> _loadSet() async {
    final setId = _message.stickerSetId;
    if (setId == null || setId == 0) return;
    try {
      final set = await TdClient.shared.query({
        '@type': 'getStickerSet',
        'set_id': setId,
      });
      if (!mounted) return;
      setState(() {
        _setTitle = set.str('title')?.trim().isNotEmpty == true
            ? set.str('title')!.trim()
            : _setTitle;
        _installed = set.boolean('is_installed') ?? false;
      });
    } catch (_) {}
  }

  void _openSet() {
    final setId = _message.stickerSetId;
    if (setId == null || setId == 0) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => StickerSetDetailView(setId: setId)),
    );
  }

  @override
  void dispose() {
    _closeExportMenu();
    super.dispose();
  }

  void _closeExportMenu() {
    final menu = _exportMenu;
    _exportMenu = null;
    if (menu?.mounted == true) menu!.remove();
  }

  void _toggleExportMenu() {
    if (_exportMenu != null) {
      _closeExportMenu();
      return;
    }

    final overlay = Overlay.of(context);
    final c = context.colors;
    final l10n = context.l10n;
    final isAnimated = StickerExportService.isAnimated(_message);
    final formats = StickerExportService.availableFormats(_message);
    final saveToPhotos = l10n.t(AppStringKeys.messageActionSaveToPhotos);
    final saveToFiles = l10n.t(AppStringKeys.stickerExportSaveToFiles);

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _closeExportMenu,
            ),
          ),
          CompositedTransformFollower(
            link: _exportMenuLink,
            targetAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topRight,
            offset: const Offset(0, 8),
            showWhenUnlinked: false,
            child: Container(
              key: const ValueKey('sticker-export-menu'),
              width: 248,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: c.divider, width: 0.5),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x35000000),
                    blurRadius: 18,
                    offset: Offset(0, 7),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final format in formats.where(
                    (format) => format != StickerExportFormat.lottie,
                  ))
                    _exportMenuItem(
                      c: c,
                      label: saveToPhotos,
                      format: format,
                      formatLabel: format.label(animated: isAnimated),
                      destination: StickerExportDestination.photos,
                    ),
                  Container(height: 0.5, color: c.divider),
                  for (final format in formats)
                    _exportMenuItem(
                      c: c,
                      label: saveToFiles,
                      format: format,
                      formatLabel: format.label(animated: isAnimated),
                      destination: StickerExportDestination.files,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    _exportMenu = entry;
    overlay.insert(entry);
  }

  Widget _exportMenuItem({
    required AppColors c,
    required String label,
    required StickerExportFormat format,
    required String formatLabel,
    required StickerExportDestination destination,
  }) {
    final icon = destination == StickerExportDestination.photos
        ? HeroAppIcons.image
        : HeroAppIcons.folder;
    return GestureDetector(
      key: ValueKey('sticker-export-${destination.name}-${format.name}'),
      behavior: HitTestBehavior.opaque,
      onTap: _exporting
          ? null
          : () => _exportSticker(destination: destination, format: format),
      child: SizedBox(
        height: 46,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              AppIcon(icon, size: 20, color: c.textPrimary),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 15,
                    decoration: TextDecoration.none,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                formatLabel,
                style: TextStyle(
                  color: c.textSecondary,
                  fontSize: 13,
                  decoration: TextDecoration.none,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportSticker({
    required StickerExportDestination destination,
    required StickerExportFormat format,
  }) async {
    _closeExportMenu();
    if (_exporting) return;
    final overlay = Overlay.of(context);
    final animated = StickerExportService.isAnimated(_message);
    final formatLabel = format.label(animated: animated);
    final l10n = context.l10n;
    setState(() => _exporting = true);
    showToastOverlay(
      overlay,
      l10n.t(AppStringKeys.stickerExportPreparing, {'value1': formatLabel}),
      visibleFor: const Duration(milliseconds: 1100),
    );
    final result = await StickerExportService.export(
      _message,
      format: format,
      destination: destination,
    );
    if (mounted) setState(() => _exporting = false);

    final feedback = switch (result) {
      StickerExportResult.saved =>
        destination == StickerExportDestination.photos
            ? l10n.t(AppStringKeys.chatSavedToPhotos)
            : l10n.t(AppStringKeys.stickerExportSavedToFiles),
      StickerExportResult.permissionDenied => l10n.t(
        AppStringKeys.chatSaveToPhotosPermissionDenied,
      ),
      StickerExportResult.unsupported => l10n.t(
        AppStringKeys.stickerExportUnsupported,
      ),
      StickerExportResult.failed => l10n.t(AppStringKeys.stickerExportFailed),
      StickerExportResult.cancelled => null,
    };
    if (feedback != null) showToastOverlay(overlay, feedback);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: [
          NavHeader(
            title: '',
            onBack: () => Navigator.of(context).pop(),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CompositedTransformTarget(
                  link: _exportMenuLink,
                  child: GestureDetector(
                    key: const ValueKey('sticker-export-menu-button'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _exporting ? null : _toggleExportMenu,
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Center(
                        child: AppIcon(
                          HeroAppIcons.ellipsis,
                          size: 24,
                          color: _exporting ? c.textTertiary : c.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 320,
                  maxHeight: 320,
                ),
                child: _sticker(),
              ),
            ),
          ),
          _setBar(),
        ],
      ),
    );
  }

  Widget _sticker() {
    if (_message.animatedSticker != null) {
      return AnimatedStickerView(file: _message.animatedSticker!);
    }
    if (_message.videoSticker != null) {
      return VideoStickerView(
        file: _message.videoSticker!,
        fallback: _message.image,
      );
    }
    if (_message.image != null) {
      return TDImage(
        photo: _message.image,
        cornerRadius: 0,
        fit: BoxFit.contain,
      );
    }
    return AppIcon(
      HeroAppIcons.solidFaceSmile,
      size: 96,
      color: AppTheme.brand,
    );
  }

  Widget _thumb() {
    final ref =
        _message.image ?? _message.animatedSticker ?? _message.videoSticker;
    if (ref == null) {
      return AppIcon(
        HeroAppIcons.solidFaceSmile,
        size: 34,
        color: AppTheme.brand,
      );
    }
    if (_message.animatedSticker != null) {
      return AnimatedStickerView(file: _message.animatedSticker!);
    }
    if (_message.videoSticker != null) {
      return VideoStickerView(
        file: _message.videoSticker!,
        fallback: _message.image,
      );
    }
    return TDImage(photo: ref, fit: BoxFit.contain);
  }

  Widget _setBar() {
    final c = context.colors;
    final canOpen = (_message.stickerSetId ?? 0) != 0;
    return SafeArea(
      top: false,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: canOpen ? _openSet : null,
        child: Container(
          height: 92,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: c.card,
            border: Border(top: BorderSide(color: c.divider, width: 0.5)),
          ),
          child: Row(
            children: [
              SizedBox(width: 58, height: 58, child: _thumb()),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  _setTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 18, color: c.textPrimary),
                ),
              ),
              if (canOpen) ...[
                const SizedBox(width: 12),
                Text(
                  _installed
                      ? AppStrings.t(AppStringKeys.stickerViewerInCollection)
                      : AppStrings.t(AppStringKeys.stickerViewerView),
                  style: TextStyle(fontSize: 16, color: c.textSecondary),
                ),
                const SizedBox(width: 8),
                AppIcon(
                  HeroAppIcons.chevronRight,
                  size: 18,
                  color: c.textTertiary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
