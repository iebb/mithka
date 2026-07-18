import 'dart:async';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../components/app_icons.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import 'data_storage_service.dart';

enum _DownloadFilter { all, active, completed }

enum _RemoveDownloadAction { keepFile, deleteFile }

class _DownloadItem {
  _DownloadItem({
    required this.fileId,
    required this.chatId,
    required this.messageId,
    required this.title,
    required this.isPaused,
    required this.completeDate,
    this.size = 0,
    this.downloaded = 0,
    this.path = '',
  });

  final int fileId;
  final int chatId;
  final int messageId;
  final String title;
  bool isPaused;
  final int completeDate;
  int size;
  int downloaded;
  String path;

  bool get completed => completeDate > 0 || (size > 0 && downloaded >= size);
}

class DownloadsView extends StatefulWidget {
  const DownloadsView({super.key});

  @override
  State<DownloadsView> createState() => _DownloadsViewState();
}

class _DownloadsViewState extends State<DownloadsView> {
  final _service = const DataStorageService();
  final _search = TextEditingController();
  final List<_DownloadItem> _items = [];
  StreamSubscription<Map<String, dynamic>>? _updates;
  Timer? _searchTimer;
  _DownloadFilter _filter = _DownloadFilter.all;
  String _nextOffset = '';
  bool _loading = true;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(_queueSearch);
    _updates = TdClient.shared.subscribe().listen(_handleUpdate);
    unawaited(_load(reset: true));
  }

  @override
  void dispose() {
    _updates?.cancel();
    _searchTimer?.cancel();
    _search
      ..removeListener(_queueSearch)
      ..dispose();
    super.dispose();
  }

  void _queueSearch() {
    _searchTimer?.cancel();
    _searchTimer = Timer(
      const Duration(milliseconds: 280),
      () => unawaited(_load(reset: true)),
    );
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() => _loading = true);
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
      for (final raw in result.objects('files') ?? const []) {
        final item = _parse(raw);
        if (item != null) next.add(item);
      }
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        final known = _items.map((item) => item.fileId).toSet();
        _items.addAll(next.where((item) => known.add(item.fileId)));
        _nextOffset = result.str('next_offset') ?? '';
      });
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    } finally {
      if (mounted) {
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
      isPaused: raw.boolean('is_paused') ?? false,
      completeDate: raw.integer('complete_date') ?? 0,
      size: file?.int64('size') ?? file?.int64('expected_size') ?? 0,
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
    return switch (raw.obj('content')?.type) {
      'messageVideo' => 'Video',
      'messagePhoto' => 'Photo',
      'messageVoiceNote' => 'Voice message',
      'messageVideoNote' => 'Video message',
      'messageAnimation' => 'GIF',
      _ => 'Telegram media',
    };
  }

  void _handleUpdate(Map<String, dynamic> update) {
    if (update.type == 'updateFile') {
      final file = update.obj('file');
      final fileId = file?.integer('id');
      if (fileId == null) return;
      final local = file?.obj('local');
      final index = _items.indexWhere((item) => item.fileId == fileId);
      if (index < 0 || !mounted) return;
      setState(() {
        final item = _items[index];
        item.size = file?.int64('size') ?? item.size;
        item.downloaded = local?.int64('downloaded_size') ?? item.downloaded;
        item.path = local?.str('path') ?? item.path;
      });
    } else if (update.type == 'updateFileAddedToDownloads' ||
        update.type == 'updateFileDownloads') {
      unawaited(_load(reset: true));
    }
  }

  Future<void> _toggle(_DownloadItem item) async {
    final paused = !item.isPaused;
    try {
      await _service.toggleDownload(item.fileId, paused: paused);
      if (mounted) setState(() => item.isPaused = paused);
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    }
  }

  Future<void> _remove(_DownloadItem item) async {
    final action = await showModalBottomSheet<_RemoveDownloadAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final c = sheetContext.colors;
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(18),
            ),
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
                        'Remove from downloads?',
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Keep the cached file or delete it from this device.',
                        style: TextStyle(color: c.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: c.divider),
                SettingsRow(
                  leading: const AppIcon(HeroAppIcons.circleMinus),
                  title: 'Remove and keep cached file',
                  onTap: () => Navigator.of(
                    sheetContext,
                  ).pop(_RemoveDownloadAction.keepFile),
                ),
                Divider(height: 1, color: c.divider),
                SettingsRow(
                  leading: const AppIcon(HeroAppIcons.trash),
                  title: 'Remove and delete file',
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
      setState(() => _items.remove(item));
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
    final hasRunning = _items.any((item) => !item.completed && !item.isPaused);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final c = sheetContext.colors;
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(18),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SettingsRow(
                  leading: const AppIcon(HeroAppIcons.arrowsRotate),
                  title: 'Refresh downloads',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    unawaited(_load(reset: true));
                  },
                ),
                Divider(height: 1, color: c.divider),
                SettingsRow(
                  leading: AppIcon(
                    hasRunning ? HeroAppIcons.pause : HeroAppIcons.play,
                  ),
                  title: hasRunning
                      ? 'Pause all downloads'
                      : 'Resume all downloads',
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await _service.toggleAllDownloads(paused: hasRunning);
                    await _load(reset: true);
                  },
                ),
                Divider(height: 1, color: c.divider),
                SettingsRow(
                  leading: const AppIcon(HeroAppIcons.trash),
                  title: 'Clear active downloads',
                  onTap: () => _clear(true, false),
                ),
                Divider(height: 1, color: c.divider),
                SettingsRow(
                  leading: const AppIcon(HeroAppIcons.trash),
                  title: 'Clear completed downloads',
                  onTap: () => _clear(false, true),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _open(_DownloadItem item) async {
    if (!item.completed || item.path.isEmpty) return;
    final result = await OpenFilex.open(item.path);
    if (result.type != ResultType.done && mounted) {
      showToast(context, result.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: 'Downloads',
            onBack: () => Navigator.of(context).pop(),
            trailing: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _showActions,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: AppIcon(HeroAppIcons.ellipsis, size: 22),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Search downloads',
                prefixIcon: const Padding(
                  padding: EdgeInsets.all(12),
                  child: AppIcon(HeroAppIcons.magnifyingGlass, size: 19),
                ),
                filled: true,
                fillColor: c.searchFill,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
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
                          'No downloads found.',
                          style: TextStyle(color: c.textSecondary),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    itemCount: _items.length + (_nextOffset.isEmpty ? 0 : 1),
                    itemBuilder: (context, index) {
                      if (index == _items.length) {
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _loadingMore
                              ? null
                              : () => _load(reset: false),
                          child: Container(
                            height: 46,
                            alignment: Alignment.center,
                            child: _loadingMore
                                ? const AppActivityIndicator(size: 20)
                                : Text(
                                    'Load more',
                                    style: TextStyle(
                                      color: AppTheme.brand,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        );
                      }
                      return _row(_items[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _filters() {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          for (final entry in const {
            _DownloadFilter.all: 'All',
            _DownloadFilter.active: 'Active',
            _DownloadFilter.completed: 'Completed',
          }.entries) ...[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                setState(() => _filter = entry.key);
                unawaited(_load(reset: true));
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: _filter == entry.key
                      ? AppTheme.brand.withValues(alpha: 0.13)
                      : c.card,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  entry.value,
                  style: TextStyle(
                    fontSize: 13,
                    color: _filter == entry.key
                        ? AppTheme.brand
                        : c.textSecondary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 7),
          ],
        ],
      ),
    );
  }

  Widget _row(_DownloadItem item) {
    final c = context.colors;
    final progress = item.size <= 0
        ? null
        : (item.downloaded / item.size).clamp(0.0, 1.0);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(13),
      ),
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
                          ? _bytes(item.size)
                          : item.isPaused
                          ? 'Paused · ${_bytes(item.downloaded)} / ${_bytes(item.size)}'
                          : '${_bytes(item.downloaded)} / ${_bytes(item.size)}',
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
              if (!item.completed)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _toggle(item),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: AppIcon(
                      item.isPaused ? HeroAppIcons.play : HeroAppIcons.pause,
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
