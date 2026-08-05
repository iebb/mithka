//
//  sticker_set_detail_view.dart
//
//  表情详情 — a sticker-set detail page (modeled on the reference app's): a header, a card with
//  the set's cover + title + sticker count and an 添加/移除 (install/remove) button,
//  and a grid of the set's stickers rendered with animated previews. Loads the set
//  via TDLib getStickerSet and toggles install with changeStickerSet.
//

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../components/toast.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../theme/app_theme.dart';
import 'custom_emoji.dart'; // parseStickers
import 'sticker_export_service.dart';
import 'sticker_item.dart';
import 'sticker_preview.dart';
import 'sticker_set_studio_view.dart';

class StickerSetDetailView extends StatefulWidget {
  const StickerSetDetailView({super.key, required this.setId});
  final int setId;

  @override
  State<StickerSetDetailView> createState() => _StickerSetDetailViewState();
}

class _StickerSetDetailViewState extends State<StickerSetDetailView> {
  String _title = '';
  List<StickerItem> _stickers = const [];
  bool _installed = false;
  bool _owned = false;
  bool _loading = true;
  bool _working = false;
  bool _exporting = false;
  int _exportCompleted = 0;
  int _exportTotal = 0;
  StickerExportFormat? _exportFormat;
  final LayerLink _menuLink = LayerLink();
  OverlayEntry? _menu;

  @override
  void dispose() {
    _closeMenu();
    super.dispose();
  }

  void _closeMenu() {
    final menu = _menu;
    _menu = null;
    if (menu?.mounted == true) menu!.remove();
  }

  void _toggleMenu() {
    if (_menu != null) {
      _closeMenu();
      return;
    }
    final overlay = Overlay.of(context);
    final c = context.colors;
    final formats = StickerExportService.availableSetFormats(_stickers);
    final animated = _stickers.any(
      (sticker) => sticker.isAnimated || sticker.isVideo,
    );
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _closeMenu,
            ),
          ),
          CompositedTransformFollower(
            link: _menuLink,
            targetAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topRight,
            offset: const Offset(0, 6),
            showWhenUnlinked: false,
            child: Container(
              key: const ValueKey('sticker-set-export-menu'),
              width: 226,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(AppRadius.card),
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
                  for (var index = 0; index < formats.length; index++) ...[
                    if (index > 0) Container(height: 0.5, color: c.divider),
                    _menuItem(
                      c,
                      AppStrings.t(
                        formats[index] == StickerExportFormat.gif
                            ? AppStringKeys.stickerSetDetailSaveAllGif
                            : animated
                            ? AppStringKeys.stickerSetDetailSaveAllApng
                            : AppStringKeys.stickerSetDetailSaveAllPng,
                      ),
                      formats[index],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
    _menu = entry;
    overlay.insert(entry);
  }

  Widget _menuItem(dynamic c, String label, StickerExportFormat format) {
    return GestureDetector(
      key: ValueKey('sticker-set-export-${format.name}'),
      behavior: HitTestBehavior.opaque,
      onTap: _exporting ? null : () => _exportAll(format),
      child: SizedBox(
        height: 46,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              AppIcon(HeroAppIcons.folder, size: 20, color: c.textPrimary),
              const SizedBox(width: 11),
              Text(
                label,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 15,
                  decoration: TextDecoration.none,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportAll(StickerExportFormat format) async {
    _closeMenu();
    if (_exporting) return;
    setState(() {
      _exporting = true;
      _exportCompleted = 0;
      _exportTotal = _stickers.length;
      _exportFormat = format;
    });
    final result = await StickerExportService.exportSet(
      _stickers,
      title: _title,
      format: format,
      onProgress: (completed, total) {
        if (!mounted) return;
        setState(() {
          _exportCompleted = completed;
          _exportTotal = total;
        });
      },
    );
    if (!mounted) return;
    setState(() {
      _exporting = false;
      _exportFormat = null;
    });
    final feedback = switch (result) {
      StickerExportResult.saved => AppStrings.t(
        AppStringKeys.stickerExportSavedToFiles,
      ),
      StickerExportResult.failed => AppStrings.t(
        AppStringKeys.stickerExportFailed,
      ),
      StickerExportResult.unsupported => AppStrings.t(
        AppStringKeys.stickerExportUnsupported,
      ),
      StickerExportResult.cancelled => null,
      StickerExportResult.permissionDenied => AppStrings.t(
        AppStringKeys.stickerExportFailed,
      ),
    };
    if (feedback != null) showToast(context, feedback);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final set = await TdClient.shared.query({
        '@type': 'getStickerSet',
        'set_id': widget.setId,
      });
      if (!mounted) return;
      setState(() {
        _title = set.str('title') ?? '';
        _stickers = parseStickers(set.objects('stickers'));
        _installed = set.boolean('is_installed') ?? false;
        _owned = set.boolean('is_owned') ?? false;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle() async {
    if (_working) return;
    setState(() => _working = true);
    final target = !_installed;
    try {
      await TdClient.shared.query({
        '@type': 'changeStickerSet',
        'set_id': widget.setId,
        'is_installed': target,
        'is_archived': false,
      });
      if (!mounted) return;
      setState(() => _installed = target);
      showToast(
        context,
        target
            ? AppStrings.t(AppStringKeys.stickerSetDetailAddSuccess)
            : AppStrings.t(AppStringKeys.stickerSetDetailRemoved),
      );
    } catch (_) {
      if (mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.stickerSetDetailActionFailed),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _header(c),
                if (_loading)
                  const Expanded(
                    child: Center(
                      child: SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator.adaptive(
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _setCard(c),
                        const SizedBox(height: 18),
                        _grid(),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (_exporting) _exportProgress(c),
        ],
      ),
    );
  }

  Widget _exportProgress(dynamic c) {
    final total = _exportTotal;
    final completed = _exportCompleted.clamp(0, total);
    final progress = total == 0 ? 0.0 : completed / total;
    final animated = _stickers.any(
      (sticker) => sticker.isAnimated || sticker.isVideo,
    );
    final formatLabel = _exportFormat == StickerExportFormat.gif
        ? 'GIF ZIP'
        : animated
        ? 'APNG ZIP'
        : 'PNG ZIP';
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0x52000000),
        child: Center(
          child: Container(
            key: const ValueKey('sticker-set-export-progress'),
            width: 270,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x38000000),
                  blurRadius: 24,
                  offset: Offset(0, 9),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppStrings.t(AppStringKeys.stickerExportPreparing, {
                    'value1': formatLabel,
                  }),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 15),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    key: const ValueKey('sticker-set-export-progress-bar'),
                    value: progress,
                    minHeight: 6,
                    backgroundColor: c.searchFill,
                    valueColor: AlwaysStoppedAnimation(AppTheme.brand),
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  '$completed / $total',
                  style: TextStyle(color: c.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(dynamic c) {
    return SizedBox(
      height: 52,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            AppStrings.t(AppStringKeys.stickerSetDetailTitle),
            style: TextStyle(fontSize: 17, color: c.textPrimary),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: AppIcon(
                  HeroAppIcons.chevronLeft,
                  size: 24,
                  color: c.textPrimary,
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_owned)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () async {
                      await Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) =>
                              StickerSetManageView(setId: widget.setId),
                        ),
                      );
                      await _load();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: AppIcon(
                        HeroAppIcons.penToSquare,
                        size: 22,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                CompositedTransformTarget(
                  link: _menuLink,
                  child: GestureDetector(
                    key: const ValueKey('sticker-set-export-menu-button'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _loading || _exporting || _stickers.isEmpty
                        ? null
                        : _toggleMenu,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: AppIcon(
                        HeroAppIcons.ellipsis,
                        size: 24,
                        color: _exporting ? c.textTertiary : c.textPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _setCard(dynamic c) {
    final cover = _stickers.isNotEmpty ? _stickers.first : null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: cover != null
                ? StickerPreview(item: cover, cornerRadius: 8)
                : const SizedBox.shrink(),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  AppStrings.plural(
                    AppStringKeys.stickerSetDetailStickerCount,
                    _stickers.length,
                  ),
                  style: TextStyle(fontSize: 13, color: c.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _toggleButton(c),
        ],
      ),
    );
  }

  Widget _toggleButton(dynamic c) {
    return GestureDetector(
      onTap: _working ? null : _toggle,
      child: Container(
        height: 34,
        constraints: const BoxConstraints(minWidth: 72),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: _installed ? c.searchFill : AppTheme.brand,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: _working
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(AppTheme.onBrand),
                ),
              )
            : Text(
                _installed
                    ? AppStrings.t(AppStringKeys.chatInfoRemove)
                    : AppStrings.t(AppStringKeys.imageEditAdd),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _installed ? c.textSecondary : AppTheme.onBrand,
                ),
              ),
      ),
    );
  }

  Widget _grid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemCount: _stickers.length,
      itemBuilder: (context, i) => StickerPreview(item: _stickers[i]),
    );
  }
}
