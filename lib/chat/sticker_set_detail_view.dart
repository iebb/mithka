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
import 'sticker_item.dart';
import 'sticker_preview.dart';

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
  bool _loading = true;
  bool _working = false;

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
      body: SafeArea(
        child: Column(
          children: [
            _header(c),
            if (_loading)
              const Expanded(
                child: Center(
                  child: SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [_setCard(c), const SizedBox(height: 18), _grid()],
                ),
              ),
          ],
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
        borderRadius: BorderRadius.circular(14),
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
                  AppStrings.t(AppStringKeys.stickerSetDetailStickerCount, {
                    'value1': _stickers.length,
                  }),
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
          gradient: _installed ? null : AppTheme.brandGradient,
          color: _installed ? c.searchFill : null,
          borderRadius: BorderRadius.circular(17),
        ),
        child: _working
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
            : Text(
                _installed
                    ? AppStrings.t(AppStringKeys.chatInfoRemove)
                    : AppStrings.t(AppStringKeys.imageEditAdd),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _installed ? c.textSecondary : Colors.white,
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
