import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../chat/file_opener.dart';
import '../chat/shared_media_view.dart';
import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import 'data_storage_service.dart';
import 'retain_download_button.dart';
import 'retained_downloads_panel.dart';

enum _DownloadFilter { all, active, completed }

enum _DownloadsSection { tasks, files, videos, retained }

enum _RemoveDownloadAction { keepFile, deleteFile }

class _DownloadItem {
  _DownloadItem({
    required this.fileId,
    required this.chatId,
    required this.messageId,
    required this.title,
    required this.isPaused,
    required this.completeDate,
    required this.completed,
    required this.active,
    this.size = 0,
    this.downloaded = 0,
    this.path = '',
    this.canRetain = false,
    this.isVideo = false,
  });

  final int fileId;
  final int chatId;
  final int messageId;
  final String title;
  bool isPaused;
  int completeDate;
  bool completed;
  bool active;
  int size;
  int downloaded;
  String path;
  final bool canRetain;
  final bool isVideo;

  bool get needsResume => isPaused || !active;

  /// Bumped per updateFile chunk. TDLib emits those tens of times a second per
  /// active download, and only this row's progress moves — the page-wide
  /// setState rebuilt the header, the search field and every visible row.
  final ValueNotifier<int> revision = ValueNotifier(0);
}

class DownloadsView extends StatefulWidget {
  const DownloadsView({super.key, this.accountSlot});
  final int? accountSlot;

  @override
  State<DownloadsView> createState() => _DownloadsViewState();
}

class _DownloadsViewState extends State<DownloadsView> {
  late final int _accountSlot;
  late final DataStorageService _service;
  final _search = TextEditingController();
  final List<_DownloadItem> _items = [];
  StreamSubscription<Map<String, dynamic>>? _updates;
  Timer? _searchTimer;
  Timer? _refreshTimer;
  int _generation = 0;
  _DownloadFilter _filter = _DownloadFilter.all;
  _DownloadsSection _section = _DownloadsSection.tasks;
  final Set<int> _toggling = {};
  String _nextOffset = '';
  bool _loading = true;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _accountSlot = widget.accountSlot ?? TdClient.shared.activeSlot;
    _service = DataStorageService(TdClient.shared, _accountSlot);
    _search.addListener(_queueSearch);
    _updates = TdClient.shared
        .subscribeAll()
        .where(
          (update) =>
              TdClient.shared.slotForClient(
                update.integer('@client_id') ?? -1,
              ) ==
              _accountSlot,
        )
        .listen(_handleUpdate);
    unawaited(_load(reset: true));
  }

  @override
  void dispose() {
    _updates?.cancel();
    _searchTimer?.cancel();
    _refreshTimer?.cancel();
    for (final item in _items) {
      item.revision.dispose();
    }
    _search
      ..removeListener(_queueSearch)
      ..dispose();
    super.dispose();
  }

  void _queueSearch() {
    _generation++;
    _searchTimer?.cancel();
    _searchTimer = Timer(
      const Duration(milliseconds: 280),
      () => unawaited(_load(reset: true)),
    );
  }

  Future<void> _load({required bool reset, bool quiet = false}) async {
    if (!mounted) return;
    final generation = reset ? ++_generation : _generation;
    if (reset) {
      if (!quiet) setState(() => _loading = true);
    } else {
      if (_nextOffset.isEmpty || _loadingMore) return;
      setState(() => _loadingMore = true);
    }
    try {
      final result = await _service.searchDownloads(
        query: _search.text.trim(),
        onlyActive: _filter == _DownloadFilter.active,
        onlyCompleted: _filter == _DownloadFilter.completed,
        offset: reset ? '' : _nextOffset,
      );
      final next = <_DownloadItem>[];
      for (final raw
          in result.objects('files') ?? const <Map<String, dynamic>>[]) {
        final item = _parse(raw);
        if (item != null) next.add(item);
      }
      if (!mounted || generation != _generation) {
        for (final item in next) {
          item.revision.dispose();
        }
        return;
      }
      setState(() {
        if (reset) {
          for (final item in _items) {
            item.revision.dispose();
          }
          _items.clear();
        }
        final known = _items.map((item) => item.fileId).toSet();
        for (final item in next) {
          if (known.add(item.fileId)) {
            _items.add(item);
          } else {
            item.revision.dispose();
          }
        }
        _nextOffset = result.str('next_offset') ?? '';
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        showToast(context, error.toString());
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  _DownloadItem? _parse(Map<String, dynamic> raw) {
    final fileId = raw.integer('file_id');
    final messageRaw = raw.obj('message');
    if (fileId == null || messageRaw == null) return null;
    final message = TDParse.message(messageRaw);
    final file = _findFile(messageRaw, fileId);
    final local = file?.obj('local');
    return _DownloadItem(
      fileId: fileId,
      chatId: messageRaw.int64('chat_id') ?? 0,
      messageId: messageRaw.int64('id') ?? 0,
      title: _title(message, messageRaw),
      canRetain: const [
        'messageVideo',
        'messageDocument',
      ].contains(messageRaw.obj('content')?.type),
      isVideo: messageRaw.obj('content')?.type == 'messageVideo',
      isPaused: raw.boolean('is_paused') ?? false,
      completeDate: raw.integer('complete_date') ?? 0,
      completed: local?.boolean('is_downloading_completed') == true,
      active: local?.boolean('is_downloading_active') == true,
      size: (file?.int64('size') ?? 0) > 0
          ? file!.int64('size')!
          : file?.int64('expected_size') ?? 0,
      downloaded:
          local?.int64('downloaded_size') ??
          local?.int64('downloaded_prefix_size') ??
          0,
      path: local?.str('path') ?? '',
    );
  }

  Map<String, dynamic>? _findFile(dynamic value, int fileId) {
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      if (map.type == 'file' && map.integer('id') == fileId) return map;
      for (final child in map.values) {
        final found = _findFile(child, fileId);
        if (found != null) return found;
      }
    } else if (value is List) {
      for (final child in value) {
        final found = _findFile(child, fileId);
        if (found != null) return found;
      }
    }
    return null;
  }

  String _title(ChatMessage? message, Map<String, dynamic> raw) {
    final document = message?.document?.fileName.trim();
    if (document != null && document.isNotEmpty) return document;
    final videoName = raw
        .obj('content')
        ?.obj('video')
        ?.str('file_name')
        ?.trim();
    if (videoName != null && videoName.isNotEmpty) return videoName;
    final music = message?.music;
    if (music != null) {
      final value = [
        music.performer,
        music.title,
      ].whereType<String>().where((part) => part.trim().isNotEmpty).join(' — ');
      if (value.isNotEmpty) return value;
    }
    final text = message?.text.trim() ?? '';
    if (text.isNotEmpty) return text;
    return AppStrings.t(switch (raw.obj('content')?.type) {
      'messageVideo' => AppStringKeys.downloadsMediaVideo,
      'messagePhoto' => AppStringKeys.downloadsMediaPhoto,
      'messageVoiceNote' => AppStringKeys.downloadsMediaVoiceMessage,
      'messageVideoNote' => AppStringKeys.downloadsMediaVideoMessage,
      'messageAnimation' => AppStringKeys.downloadsMediaAnimation,
      _ => AppStringKeys.downloadsMediaTelegramMedia,
    });
  }

  void _handleUpdate(Map<String, dynamic> update) {
    if (update.type == 'updateFile') {
      final file = update.obj('file');
      final fileId = file?.integer('id');
      if (fileId == null) return;
      final local = file?.obj('local');
      final index = _items.indexWhere((item) => item.fileId == fileId);
      if (index < 0 || !mounted) return;
      final item = _items[index];
      final completedBefore = item.completed;
      final size = file?.int64('size') ?? 0;
      item.size = size > 0 ? size : file?.int64('expected_size') ?? item.size;
      item.downloaded = local?.int64('downloaded_size') ?? item.downloaded;
      item.path = local?.str('path') ?? item.path;
      item.completed =
          local?.boolean('is_downloading_completed') ?? item.completed;
      item.active = local?.boolean('is_downloading_active') ?? item.active;
      item.revision.value++;
      if (completedBefore != item.completed && _filter != _DownloadFilter.all) {
        _refresh();
      }
    } else if (update.type == 'updateFileDownload') {
      final item = _items
          .where((item) => item.fileId == update.integer('file_id'))
          .firstOrNull;
      if (item != null) {
        item.isPaused = update.boolean('is_paused') ?? item.isPaused;
        item.completeDate =
            update.integer('complete_date') ?? item.completeDate;
        item.revision.value++;
      }
      if (_filter != _DownloadFilter.all) _refresh();
    } else if (update.type == 'updateFileRemovedFromDownloads') {
      final removed = _items
          .where((item) => item.fileId == update.integer('file_id'))
          .toList();
      if (mounted) setState(() => _items.removeWhere(removed.contains));
      for (final item in removed) {
        item.revision.dispose();
      }
    } else if (update.type == 'updateFileAddedToDownloads') {
      _refresh();
    }
  }

  void _refresh() {
    _refreshTimer ??= Timer(const Duration(milliseconds: 180), () {
      _refreshTimer = null;
      if (mounted) unawaited(_load(reset: true, quiet: true));
    });
  }

  Future<void> _toggle(_DownloadItem item) async {
    if (!_toggling.add(item.fileId)) return;
    item.revision.value++;
    final paused = !item.needsResume;
    try {
      if (paused) {
        await _service.pauseDownload(item.fileId);
      } else if (item.completeDate > 0 && !item.completed) {
        // Completed download history can outlive the cached file. Unpausing
        // that historical task is a no-op in TDLib; re-register it explicitly.
        final file = await _service.addDownload(
          fileId: item.fileId,
          chatId: item.chatId,
          messageId: item.messageId,
        );
        item.completeDate = 0;
        _handleUpdate({'@type': 'updateFile', 'file': file});
      } else {
        await _service.toggleDownload(item.fileId, paused: false);
      }
      if (mounted && _items.contains(item)) {
        item.isPaused = paused;
        item.active = !paused && !item.completed;
        item.revision.value++;
      }
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    } finally {
      _toggling.remove(item.fileId);
      if (mounted && _items.contains(item)) item.revision.value++;
    }
  }

  Future<void> _remove(_DownloadItem item) async {
    final action = await showAppModalSheet<_RemoveDownloadAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final c = sheetContext.colors;
        return SafeArea(
          top: false,
          child: SettingsPanel(
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 10),
            margin: const EdgeInsets.all(10),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 15, 16, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppStrings.t(
                          AppStringKeys.downloadsRemoveFromDownloads,
                        ),
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        AppStrings.t(
                          AppStringKeys
                              .downloadsKeepTheCachedFileOrDeleteItFrom,
                        ),
                        style: TextStyle(color: c.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: c.divider),
                SettingsRow(
                  leading: const AppIcon(HeroAppIcons.circleMinus),
                  title: AppStrings.t(
                    AppStringKeys.downloadsRemoveAndKeepCachedFile,
                  ),
                  onTap: () => Navigator.of(
                    sheetContext,
                  ).pop(_RemoveDownloadAction.keepFile),
                ),
                Divider(height: 1, color: c.divider),
                SettingsRow(
                  leading: const AppIcon(HeroAppIcons.trash),
                  title: AppStrings.t(
                    AppStringKeys.downloadsRemoveAndDeleteFile,
                  ),
                  onTap: () => Navigator.of(
                    sheetContext,
                  ).pop(_RemoveDownloadAction.deleteFile),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || action == null) return;
    try {
      await _service.removeDownload(
        item.fileId,
        deleteFromCache: action == _RemoveDownloadAction.deleteFile,
      );
      if (mounted && _items.contains(item)) {
        setState(() => _items.remove(item));
        item.revision.dispose();
      }
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    }
  }

  Future<void> _clear(bool active, bool completed) async {
    Navigator.of(context).pop();
    try {
      await _service.clearDownloads(active: active, completed: completed);
      await _load(reset: true);
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    }
  }

  Future<void> _showActions() async {
    await showAppModalSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final c = sheetContext.colors;
        return SafeArea(
          top: false,
          child: SettingsCard(
            margin: const EdgeInsets.all(10),
            children: [
              SettingsRow(
                leading: const AppIcon(HeroAppIcons.arrowsRotate),
                title: AppStrings.t(AppStringKeys.downloadsRefreshDownloads),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_load(reset: true));
                },
              ),
              Divider(height: 1, color: c.divider),
              for (final paused in [true, false]) ...[
                SettingsRow(
                  key: ValueKey('downloads-toggle-all-$paused'),
                  leading: AppIcon(
                    paused ? HeroAppIcons.pause : HeroAppIcons.play,
                  ),
                  title: AppStrings.t(
                    paused
                        ? AppStringKeys.downloadsPauseAllDownloads
                        : AppStringKeys.downloadsResumeAllDownloads,
                  ),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    try {
                      await _service.toggleAllDownloads(paused: paused);
                      await _load(reset: true);
                    } catch (error) {
                      if (mounted) showToast(context, error.toString());
                    }
                  },
                ),
                Divider(height: 1, color: c.divider),
              ],
              SettingsRow(
                leading: const AppIcon(HeroAppIcons.trash),
                title: AppStrings.t(
                  AppStringKeys.downloadsClearActiveDownloads,
                ),
                onTap: () => _clear(true, false),
              ),
              Divider(height: 1, color: c.divider),
              SettingsRow(
                leading: const AppIcon(HeroAppIcons.trash),
                title: AppStrings.t(
                  AppStringKeys.downloadsClearCompletedDownloads,
                ),
                onTap: () => _clear(false, true),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _open(_DownloadItem item) async {
    if (!item.completed || item.path.isEmpty) return;
    await openDownloadedFile(
      context,
      item.path,
      mimeType: mimeForFileName(item.title),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SettingsPageScaffold(
      title: AppStrings.t(AppStringKeys.generalDownloads),
      onBack: () => Navigator.of(context).pop(),
      trailing: _section != _DownloadsSection.tasks
          ? null
          : GestureDetector(
              key: const ValueKey('downloads-actions'),
              behavior: HitTestBehavior.opaque,
              onTap: _showActions,
              child: const Padding(
                padding: EdgeInsets.all(AppSpacing.sm),
                child: AppIcon(HeroAppIcons.ellipsis, size: 22),
              ),
            ),
      child: Column(
        children: [
          _sections(),
          if (_section == _DownloadsSection.retained)
            Expanded(child: RetainedDownloadsPanel(accountSlot: _accountSlot))
          else if (_section != _DownloadsSection.tasks) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                AppStrings.t(AppStringKeys.downloadsCacheHint),
                style: TextStyle(fontSize: 12, color: c.textSecondary),
              ),
            ),
            Expanded(
              child: SharedMediaView(
                key: ValueKey('downloads-${_section.name}'),
                chatId: 0,
                title: '',
                initialTab: _section == _DownloadsSection.files ? 1 : 4,
                initialFileFilter: SharedMediaFileFilter.cached,
                lockedTab: true,
                embeddedInDownloads: true,
                accountSlot: _accountSlot,
              ),
            ),
          ] else ...[
            Padding(
              padding: AppInsets.screen.copyWith(bottom: AppSpacing.sm),
              child: SettingsSearchField(
                controller: _search,
                hintText: AppStringKeys.downloadsSearchDownloads,
              ),
            ),
            _filters(),
            Expanded(
              child: _loading
                  ? const Center(child: AppActivityIndicator())
                  : _items.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 160),
                        Center(
                          child: Text(
                            AppStrings.t(
                              AppStringKeys.downloadsNoDownloadsFound,
                            ),
                            style: TextStyle(color: c.textSecondary),
                          ),
                        ),
                        if (_nextOffset.isNotEmpty) _loadMoreButton(),
                      ],
                    )
                  : ListView.builder(
                      padding: AppInsets.screen.copyWith(top: AppSpacing.sm),
                      itemCount: _items.length + (_nextOffset.isEmpty ? 0 : 1),
                      itemBuilder: (context, index) {
                        if (index == _items.length) {
                          return _loadMoreButton();
                        }
                        return _row(_items[index]);
                      },
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _loadMoreButton() => AppInteractiveSurface(
    key: const ValueKey('downloads-load-more'),
    enabled: !_loadingMore,
    onTap: () => unawaited(_load(reset: false)),
    child: SizedBox(
      height: 46,
      child: Center(
        child: _loadingMore
            ? const AppActivityIndicator(size: 20)
            : Text(
                AppStrings.t(AppStringKeys.publicDiscoveryLoadMore),
                style: TextStyle(
                  color: AppTheme.brand,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    ),
  );

  Widget _sections() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final section in _DownloadsSection.values)
            SettingsFilterChip(
              key: ValueKey('downloads-section-${section.name}'),
              label: AppStrings.t(switch (section) {
                _DownloadsSection.tasks => AppStringKeys.downloadsTasks,
                _DownloadsSection.files => AppStringKeys.searchTabFiles,
                _DownloadsSection.videos => AppStringKeys.sharedMediaVideos,
                _DownloadsSection.retained => AppStringKeys.downloadsRetained,
              }),
              selected: _section == section,
              onTap: () => setState(() => _section = section),
            ),
        ],
      ),
    ),
  );

  Widget _filters() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Wrap(
        runSpacing: 7,
        children: [
          for (final entry in const {
            _DownloadFilter.all: AppStringKeys.downloadsFilterAll,
            _DownloadFilter.active: AppStringKeys.downloadsFilterActive,
            _DownloadFilter.completed: AppStringKeys.downloadsFilterCompleted,
          }.entries) ...[
            SettingsFilterChip(
              label: AppStrings.t(entry.value),
              selected: _filter == entry.key,
              onTap: () {
                setState(() => _filter = entry.key);
                unawaited(_load(reset: true));
              },
            ),
            const SizedBox(width: 7),
          ],
        ],
      ),
    );
  }

  Widget _row(_DownloadItem item) => ValueListenableBuilder<int>(
    key: ValueKey('download-row-${item.fileId}'),
    valueListenable: item.revision,
    builder: (_, _, _) => _rowContent(item),
  );

  Widget _rowContent(_DownloadItem item) {
    final c = context.colors;
    final progress = item.size <= 0
        ? null
        : (item.downloaded / item.size).clamp(0.0, 1.0);
    return SettingsPanel(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      margin: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: item.completed ? () => _open(item) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.brand.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: AppIcon(
                  item.completed
                      ? HeroAppIcons.solidFolder
                      : HeroAppIcons.download,
                  size: 21,
                  color: AppTheme.brand,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.completed
                          ? '${AppStrings.t(AppStringKeys.downloadsFilterCompleted)} · ${_bytes(item.size)}'
                          : item.isPaused
                          ? AppStrings.t(
                              AppStringKeys.downloadsPausedProgress,
                              {
                                'value1': _bytes(item.downloaded),
                                'value2': _bytes(item.size),
                              },
                            )
                          : '${AppStrings.t(item.active
                                ? AppStringKeys.sharedMediaFilterDownloading
                                : item.downloaded > 0
                                ? AppStringKeys.sharedMediaFilterPartial
                                : AppStringKeys.sharedMediaFilterNotDownloaded)} · ${_bytes(item.downloaded)} / ${_bytes(item.size)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.textSecondary, fontSize: 12),
                    ),
                    if (!item.completed && progress != null) ...[
                      const SizedBox(height: 5),
                      AppProgressBar(value: progress),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              if (item.completed && item.canRetain)
                RetainDownloadButton(
                  key: ValueKey('download-retain-${item.fileId}'),
                  accountSlot: _accountSlot,
                  fileId: item.fileId,
                  title: item.title,
                  isVideo: item.isVideo,
                ),
              if (!item.completed)
                AppInteractiveSurface(
                  key: ValueKey('download-toggle-${item.fileId}'),
                  semanticLabel: AppStrings.t(
                    item.needsResume
                        ? AppStringKeys.downloadsResume
                        : AppStringKeys.downloadsPause,
                  ),
                  enabled: !_toggling.contains(item.fileId),
                  onTap: () => _toggle(item),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: _toggling.contains(item.fileId)
                        ? const AppActivityIndicator(size: 19)
                        : AppIcon(
                            item.needsResume
                                ? HeroAppIcons.play
                                : HeroAppIcons.pause,
                            size: 19,
                            color: AppTheme.brand,
                          ),
                  ),
                ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _remove(item),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: AppIcon(
                    HeroAppIcons.trash,
                    size: 18,
                    color: c.textTertiary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _bytes(int value) {
    if (value <= 0) return '—';
    if (value < 1024) return '$value B';
    const units = ['KB', 'MB', 'GB'];
    var size = value / 1024;
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(size >= 10 ? 0 : 1)} ${units[unit]}';
  }
}
