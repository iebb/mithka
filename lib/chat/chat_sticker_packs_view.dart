//
//  chat_sticker_packs_view.dart
//
//  Sticker and emoji packs used in one chat, or across every chat (the
//  global finder), deduplicated, in two tabs. The scan keeps reading older
//  messages in the background while the page is open, until history runs
//  out or the user pauses it, and the list updates after every batch.
//  A toolbar filters by title and by "not added", and sorts by use count,
//  recency, name or size — tapping the active sort flips its direction.
//  Each row shows the pack title over a strip of its first stickers and
//  adds the pack in one tap.
//
//  Touch layouts: 72pt rows with 32pt previews. Pointer layouts: 58pt rows
//  with 24pt previews, split into two columns from 620pt wide.
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../platform/adaptive_platform.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../theme/app_theme.dart';
import 'chat_sticker_packs_service.dart';
import 'sticker_item.dart';
import 'sticker_preview.dart';
import 'sticker_set_detail_view.dart';

class ChatStickerPacksView extends StatefulWidget {
  /// A null [chatId] scans the user's recent chats instead of one chat.
  const ChatStickerPacksView({
    super.key,
    this.chatId,
    this.service,
    this.showBackButton = true,
  });

  final int? chatId;
  final ChatStickerPacksService? service;

  /// Off when the page is a window's root, with nothing to go back to.
  final bool showBackButton;

  @override
  State<ChatStickerPacksView> createState() => _ChatStickerPacksViewState();
}

class _ChatStickerPacksViewState extends State<ChatStickerPacksView> {
  late final ChatStickerPacksService _service =
      widget.service ?? ChatStickerPacksService();

  /// Null until opened: the global scanner first reads back this
  /// account's saved scan.
  ChatPackScanner? _scanner;
  final TextEditingController _filter = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _firstBatch = true;

  /// The background scan loop is between batches or inside one.
  bool _scanning = false;
  bool _paused = false;
  int _tab = 0;
  ChatPackSort _sort = ChatPackSort.usage;
  bool _descending = true;
  bool _onlyMissing = false;
  final Set<int> _working = {};
  bool _addingAll = false;

  bool get _global => widget.chatId == null;

  List<ChatUsedPack> get _stickers => _scanner?.stickers ?? const [];
  List<ChatUsedPack> get _emoji => _scanner?.emoji ?? const [];
  bool get _exhausted => _scanner?.exhausted ?? false;

  List<ChatUsedPack> get _tabPacks => _tab == 0 ? _stickers : _emoji;

  List<ChatUsedPack> get _visible => sortPacks(
    filterPacks(_tabPacks, query: _filter.text, onlyMissing: _onlyMissing),
    _sort,
    descending: _descending,
  );

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    unawaited(_scanner?.save(force: true));
    _scanner?.close();
    _scroll.dispose();
    _filter.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final chatId = widget.chatId;
    final scanner = chatId == null
        ? await _service.openGlobalScanner()
        : _service.chatScanner(chatId);
    if (!mounted) return;
    _scanner = scanner..onChanged = _onScannerChanged;
    if (scanner.scannedMessages > 0) {
      // A restored scan: put back what it found before reading anything new.
      await scanner.resolveKnown();
      if (!mounted) return;
      setState(_showFirstResults);
    }
    await _scan();
  }

  Timer? _refreshTimer;

  /// Pack lookups land one small group at a time; repaint at most five
  /// times a second for them.
  void _onScannerChanged() {
    if (_refreshTimer != null) return;
    _refreshTimer = Timer(const Duration(milliseconds: 200), () {
      _refreshTimer = null;
      if (mounted) setState(_showFirstResults);
    });
  }

  void _showFirstResults() {
    if (!_firstBatch) return;
    _firstBatch = false;
    // Open on whichever tab has content.
    if (_stickers.isEmpty && _emoji.isNotEmpty) _tab = 1;
  }

  /// Reads older and older messages, a batch at a time, for as long as the
  /// page is open, until history runs out or the user pauses. The list
  /// updates after every batch, and the global scan is saved as it goes.
  Future<void> _scan() async {
    final scanner = _scanner;
    if (scanner == null || _scanning) return;
    setState(() => _scanning = true);
    while (mounted && !_paused && !scanner.exhausted) {
      try {
        await scanner.loadMore();
      } catch (_) {
        // A failing batch would otherwise spin; wait for the user to resume.
        _paused = true;
      }
      if (!mounted) return;
      setState(_showFirstResults);
      unawaited(scanner.save());
      // Let the frame with this batch's results paint before the next one.
      await Future<void>.delayed(Duration.zero);
    }
    unawaited(scanner.save(force: true));
    if (mounted) setState(() => _scanning = false);
  }

  void _togglePaused() {
    setState(() => _paused = !_paused);
    if (_paused) {
      unawaited(_scanner?.save(force: true));
    } else {
      unawaited(_scan());
    }
  }

  void _selectTab(int index) {
    setState(() => _tab = index);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _selectSort(ChatPackSort sort) {
    setState(() {
      if (_sort == sort) {
        _descending = !_descending;
      } else {
        _sort = sort;
        // Names read A→Z; every numeric sort starts with the largest.
        _descending = sort != ChatPackSort.name;
      }
    });
  }

  Future<void> _add(ChatUsedPack pack) async {
    if (pack.installed || _working.contains(pack.id)) return;
    setState(() => _working.add(pack.id));
    final ok = await _service.install(pack);
    if (ok) ChatStickerPacksService.refreshComposerStores();
    if (!mounted) return;
    setState(() => _working.remove(pack.id));
    if (!ok) {
      showToast(
        context,
        AppStrings.t(AppStringKeys.stickerSetDetailActionFailed),
      );
    }
  }

  Future<void> _addAll(List<ChatUsedPack> visible) async {
    if (_addingAll) return;
    final pending = visible.where((p) => !p.installed).toList();
    if (pending.isEmpty) return;
    setState(() {
      _addingAll = true;
      _working.addAll(pending.map((p) => p.id));
    });
    final added = await _service.installAll(pending);
    if (!mounted) return;
    setState(() {
      _addingAll = false;
      _working.removeAll(pending.map((p) => p.id));
    });
    showToast(
      context,
      added == 0
          ? AppStrings.t(AppStringKeys.stickerSetDetailActionFailed)
          : AppStrings.plural(AppStringKeys.chatStickerPacksAddedCount, added),
    );
  }

  Future<void> _openDetail(ChatUsedPack pack) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => StickerSetDetailView(setId: pack.id)),
    );
    // The detail page can install or remove the set; mirror its state.
    try {
      final set = await TdClient.shared.query({
        '@type': 'getStickerSet',
        'set_id': pack.id,
      });
      final installed = set.boolean('is_installed') ?? pack.installed;
      if (mounted && installed != pack.installed) {
        setState(() => pack.installed = installed);
        ChatStickerPacksService.refreshComposerStores();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dense = isDesktopTargetPlatform(Theme.of(context).platform);
    final visible = _firstBatch ? const <ChatUsedPack>[] : _visible;
    // Transparent Material: the filter's TextField needs one above it, and
    // this page is pushed on routes that do not provide it.
    return Material(
      type: MaterialType.transparency,
      child: ColoredBox(
        color: c.groupedBackground,
        child: Column(
          children: [
            NavHeader(
              title: _global
                  ? AppStringKeys.chatStickerPacksFinderTitle
                  : AppStringKeys.chatStickerPacksTitle,
              onBack: widget.showBackButton
                  ? () => Navigator.of(context).pop()
                  : null,
            ),
            _tabBar(dense),
            if (!_firstBatch && _tabPacks.isNotEmpty) _toolbar(dense),
            if (!_firstBatch) _summaryBar(dense, visible),
            Expanded(child: _body(dense, visible)),
          ],
        ),
      ),
    );
  }

  Widget _tabBar(bool dense) {
    Widget tab(int index, String key, int count) => Expanded(
      child: SettingsFilterChip(
        key: ValueKey('chat-sticker-packs-tab-$index'),
        label: AppStrings.t(key),
        trailingLabel: _firstBatch ? null : '$count',
        selected: _tab == index,
        onTap: () => _selectTab(index),
      ),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(12, dense ? 8 : 10, 12, dense ? 6 : 8),
      child: Row(
        children: [
          tab(0, AppStringKeys.chatStickerPacksTabStickers, _stickers.length),
          SizedBox(width: dense ? 6 : 8),
          tab(1, AppStringKeys.chatStickerPacksTabEmoji, _emoji.length),
        ],
      ),
    );
  }

  Widget _toolbar(bool dense) {
    final search = SettingsSearchField(
      key: const ValueKey('chat-sticker-packs-filter'),
      hintText: AppStringKeys.chatStickerPacksFilterHint,
      controller: _filter,
      compact: true,
      onChanged: (_) => setState(() {}),
    );
    final chips = <Widget>[
      _chip(
        key: 'not-added',
        label: AppStrings.t(AppStringKeys.chatStickerPacksNotAdded),
        icon: HeroAppIcons.filter,
        selected: _onlyMissing,
        dense: dense,
        onTap: () => setState(() => _onlyMissing = !_onlyMissing),
      ),
      Container(
        width: 1,
        height: dense ? 14 : 16,
        margin: EdgeInsets.symmetric(horizontal: dense ? 4 : 6),
        color: context.colors.divider,
      ),
      for (final (sort, key) in const [
        (ChatPackSort.usage, AppStringKeys.chatStickerPacksSortUsage),
        (ChatPackSort.recent, AppStringKeys.chatStickerPacksSortRecent),
        (ChatPackSort.name, AppStringKeys.chatStickerPacksSortName),
        (ChatPackSort.size, AppStringKeys.chatStickerPacksSortSize),
      ]) ...[
        _chip(
          key: 'sort-${sort.name}',
          label: AppStrings.t(key),
          icon: _sort == sort
              ? (_descending ? HeroAppIcons.arrowDown : HeroAppIcons.arrowUp)
              : null,
          selected: _sort == sort,
          dense: dense,
          onTap: () => _selectSort(sort),
        ),
        const SizedBox(width: 4),
      ],
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        // Wide panes keep search and controls on one 34pt line; narrow ones
        // stack them and let the chips scroll sideways.
        if (constraints.maxWidth >= 640) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Row(
              children: [
                Expanded(child: search),
                const SizedBox(width: 8),
                ...chips,
              ],
            ),
          );
        }
        return Padding(
          padding: EdgeInsets.fromLTRB(12, 0, 12, dense ? 2 : 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              search,
              SizedBox(height: dense ? 6 : 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: chips),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _chip({
    required String key,
    required String label,
    required bool selected,
    required bool dense,
    required VoidCallback onTap,
    AppIconData? icon,
  }) {
    final c = context.colors;
    final height = dense ? 26.0 : 30.0;
    final foreground = selected ? c.linkBlue : c.textSecondary;
    return AppInteractiveSurface(
      key: ValueKey('chat-sticker-packs-$key'),
      onTap: onTap,
      selected: selected,
      semanticLabel: label,
      borderRadius: BorderRadius.circular(height / 2),
      child: Container(
        height: height,
        padding: EdgeInsets.symmetric(horizontal: dense ? 9 : 11),
        decoration: BoxDecoration(
          color: selected ? c.linkBlue.withValues(alpha: 0.13) : c.card,
          borderRadius: BorderRadius.circular(height / 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              AppIcon(icon, size: dense ? 11 : 13, color: foreground),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: dense ? AppTextSize.caption : AppTextSize.footnote,
                fontWeight: selected
                    ? AppTextWeight.semibold
                    : AppTextWeight.medium,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryBar(bool dense, List<ChatUsedPack> visible) {
    final c = context.colors;
    final missing = visible.where((p) => !p.installed).length;
    final scope = AppStrings.plural(
      _global
          ? AppStringKeys.chatStickerPacksScannedGlobal
          : AppStringKeys.chatStickerPacksScanned,
      _scanner?.scannedMessages ?? 0,
    );
    final fontSize = dense ? AppTextSize.caption : AppTextSize.footnote;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 8, dense ? 2 : 4),
      child: SizedBox(
        height: dense ? 26 : 32,
        child: Row(
          children: [
            Expanded(
              child: Text(
                scope,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: fontSize, color: c.textSecondary),
              ),
            ),
            if (!_exhausted)
              AppInteractiveSurface(
                key: const ValueKey('chat-sticker-packs-pause'),
                onTap: _togglePaused,
                isButton: true,
                semanticLabel: AppStrings.t(
                  _paused
                      ? AppStringKeys.chatStickerPacksResumeScan
                      : AppStringKeys.chatStickerPacksPauseScan,
                ),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: SizedBox.square(
                  dimension: dense ? 24 : 30,
                  child: Center(
                    child: AppIcon(
                      _paused ? HeroAppIcons.play : HeroAppIcons.pause,
                      size: dense ? 13 : 15,
                      color: c.textSecondary,
                    ),
                  ),
                ),
              ),
            if (missing > 0)
              AppInteractiveSurface(
                key: const ValueKey('chat-sticker-packs-add-all'),
                onTap: _addingAll ? null : () => unawaited(_addAll(visible)),
                isButton: true,
                semanticLabel: AppStrings.t(
                  AppStringKeys.chatStickerPacksAddAll,
                ),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Center(
                    child: Text(
                      '${AppStrings.t(AppStringKeys.chatStickerPacksAddAll)} ($missing)',
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: AppTextWeight.semibold,
                        color: _addingAll ? c.textTertiary : c.linkBlue,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _body(bool dense, List<ChatUsedPack> visible) {
    if (_firstBatch) return const Center(child: AppActivityIndicator(size: 22));
    final c = context.colors;
    final rowHeight = dense ? 58.0 : 72.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = dense && constraints.maxWidth >= 620;
        final radius = Radius.circular(
          dense ? AppRadius.control : AppRadius.card,
        );
        return CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
              sliver: twoColumns
                  ? SliverGrid.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisExtent: rowHeight,
                        crossAxisSpacing: 6,
                        mainAxisSpacing: 6,
                      ),
                      itemCount: visible.length,
                      itemBuilder: (context, index) => DecoratedBox(
                        decoration: BoxDecoration(
                          color: c.card,
                          borderRadius: BorderRadius.circular(
                            AppRadius.control,
                          ),
                        ),
                        child: _row(
                          visible[index],
                          dense: dense,
                          height: rowHeight,
                        ),
                      ),
                    )
                  : SliverList.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, index) => Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: c.card,
                          borderRadius: BorderRadius.vertical(
                            top: index == 0 ? radius : Radius.zero,
                            bottom: index == visible.length - 1
                                ? radius
                                : Radius.zero,
                          ),
                        ),
                        child: Column(
                          children: [
                            if (index > 0)
                              InsetDivider(leadingInset: dense ? 10 : 12),
                            _row(
                              visible[index],
                              dense: dense,
                              height: rowHeight,
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
            if (visible.isEmpty && (_exhausted || _tabPacks.isNotEmpty))
              SliverToBoxAdapter(child: _emptyMessage(dense)),
            SliverToBoxAdapter(child: _footer(dense)),
          ],
        );
      },
    );
  }

  Widget _emptyMessage(bool dense) {
    final c = context.colors;
    final String message;
    if (_tabPacks.isNotEmpty) {
      message = AppStringKeys.chatStickerPacksNoMatches;
    } else if (_global) {
      message = AppStringKeys.chatStickerPacksNoneFound;
    } else {
      message = _tab == 0
          ? AppStringKeys.chatStickerPacksEmptyStickers
          : AppStringKeys.chatStickerPacksEmptyEmoji;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 8),
      child: Column(
        children: [
          AppIcon(
            _tab == 0 ? HeroAppIcons.grip : HeroAppIcons.solidFaceSmile,
            size: dense ? 28 : 34,
            color: c.textTertiary,
          ),
          const SizedBox(height: 10),
          Text(
            AppStrings.t(message),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: dense ? AppTextSize.footnote : AppTextSize.callout,
              color: c.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// The scan's state at the end of the list: reading, paused, or done.
  Widget _footer(bool dense) {
    final c = context.colors;
    final fontSize = dense ? AppTextSize.caption : AppTextSize.footnote;
    final Widget child;
    if (_exhausted) {
      child = Text(
        AppStrings.t(AppStringKeys.chatStickerPacksNoOlder),
        style: TextStyle(fontSize: fontSize, color: c.textTertiary),
      );
    } else if (_paused) {
      child = AppInteractiveSurface(
        key: const ValueKey('chat-sticker-packs-resume'),
        onTap: _togglePaused,
        isButton: true,
        semanticLabel: AppStrings.t(AppStringKeys.chatStickerPacksResumeScan),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            AppStrings.t(AppStringKeys.chatStickerPacksResumeScan),
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: AppTextWeight.semibold,
              color: c.linkBlue,
            ),
          ),
        ),
      );
    } else {
      child = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppActivityIndicator(size: dense ? 12 : 14, color: c.textTertiary),
          const SizedBox(width: 6),
          Text(
            AppStrings.t(AppStringKeys.chatStickerPacksLoadingMore),
            style: TextStyle(fontSize: fontSize, color: c.textTertiary),
          ),
        ],
      );
    }
    return SizedBox(
      key: const ValueKey('chat-sticker-packs-footer'),
      height: dense ? 44 : 52,
      child: Center(child: child),
    );
  }

  Widget _row(
    ChatUsedPack pack, {
    required bool dense,
    required double height,
  }) {
    final c = context.colors;
    // Built means on screen (the list is lazy): bring its preview and added
    // state up to date if they came from the saved scan.
    _scanner?.requestPack(pack.id);
    return AppInteractiveSurface(
      key: ValueKey('chat-sticker-pack-${pack.id}'),
      onTap: () => unawaited(_openDetail(pack)),
      semanticLabel: pack.title,
      borderRadius: BorderRadius.circular(
        dense ? AppRadius.control : AppRadius.card,
      ),
      child: SizedBox(
        height: height,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pack.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: dense
                            ? AppTextSize.footnote
                            : AppTextSize.body,
                        fontWeight: AppTextWeight.medium,
                        color: c.textPrimary,
                      ),
                    ),
                    SizedBox(height: dense ? 4 : 6),
                    _PreviewStrip(
                      items: pack.previews,
                      size: dense ? 24 : 32,
                      gap: dense ? 4 : 5,
                    ),
                  ],
                ),
              ),
              SizedBox(width: dense ? 8 : 10),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _stats(pack, dense: dense),
                  SizedBox(height: dense ? 4 : 6),
                  _addButton(pack, dense: dense),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Use count and distinct people, right-aligned over the add button.
  Widget _stats(ChatUsedPack pack, {required bool dense}) {
    final color = context.colors.textTertiary;
    final iconSize = dense ? 11.0 : 12.0;
    final style = TextStyle(
      fontSize: dense ? AppTextSize.tiny + 1 : AppTextSize.caption,
      fontWeight: AppTextWeight.medium,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
      height: 1,
    );
    return Semantics(
      label: AppStrings.t(AppStringKeys.chatStickerPacksStats, {
        'value1': pack.uses,
        'value2': pack.users,
      }),
      excludeSemantics: true,
      child: Row(
        key: ValueKey('chat-sticker-pack-stats-${pack.id}'),
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(HeroAppIcons.message, size: iconSize, color: color),
          const SizedBox(width: 2),
          Text('${pack.uses}', style: style),
          SizedBox(width: dense ? 7 : 9),
          AppIcon(HeroAppIcons.users, size: iconSize, color: color),
          const SizedBox(width: 2),
          Text('${pack.users}', style: style),
        ],
      ),
    );
  }

  Widget _addButton(ChatUsedPack pack, {required bool dense}) {
    final c = context.colors;
    final fontSize = dense ? AppTextSize.caption : AppTextSize.footnote;
    if (pack.installed) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(
            HeroAppIcons.check,
            size: dense ? 12 : 14,
            color: c.textTertiary,
          ),
          const SizedBox(width: 4),
          Text(
            AppStrings.t(AppStringKeys.chatStickerPacksAdded),
            style: TextStyle(fontSize: fontSize, color: c.textTertiary),
          ),
        ],
      );
    }
    final working = _working.contains(pack.id);
    final height = dense ? 24.0 : 28.0;
    final label = AppStrings.t(AppStringKeys.chatStickerPacksAddCount, {
      'value1': pack.itemCount,
    });
    return AppInteractiveSurface(
      key: ValueKey('chat-sticker-pack-add-${pack.id}'),
      onTap: working ? null : () => unawaited(_add(pack)),
      isButton: true,
      semanticLabel: label,
      borderRadius: BorderRadius.circular(height / 2),
      child: Container(
        height: height,
        constraints: BoxConstraints(minWidth: dense ? 56 : 64),
        padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: working ? c.searchFill : c.linkBlue,
          borderRadius: BorderRadius.circular(height / 2),
        ),
        child: working
            ? AppActivityIndicator(
                size: dense ? 12 : 14,
                color: c.textSecondary,
              )
            : Text(
                label,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: AppTextWeight.semibold,
                  color: c.onAccent,
                ),
              ),
      ),
    );
  }
}

/// As many of the set's first stickers as fit on one line. Static
/// thumbnails only, so a long list never starts animated decoders.
class _PreviewStrip extends StatelessWidget {
  const _PreviewStrip({
    required this.items,
    required this.size,
    required this.gap,
  });

  final List<StickerItem> items;
  final double size;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: size,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fit = ((constraints.maxWidth + gap) / (size + gap)).floor();
          final count = fit.clamp(0, items.length);
          return RepaintBoundary(
            child: Row(
              children: [
                for (var i = 0; i < count; i++) ...[
                  if (i > 0) SizedBox(width: gap),
                  SizedBox.square(
                    dimension: size,
                    child: Center(child: StickerTabPreview(item: items[i])),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
