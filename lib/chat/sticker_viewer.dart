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
import '../components/ui_components.dart';
import '../l10n/telegram_language_controller.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import 'animated_sticker_view.dart';
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
                AppIcon(
                  HeroAppIcons.tableCells,
                  size: 24,
                  color: c.textPrimary,
                ),
                const SizedBox(width: 22),
                AppIcon(HeroAppIcons.ellipsis, size: 24, color: c.textPrimary),
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
