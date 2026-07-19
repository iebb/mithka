import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../components/app_icons.dart';
import '../components/confirm_dialog.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../theme/app_theme.dart';
import 'data_storage_service.dart';

class StorageUsageView extends StatefulWidget {
  const StorageUsageView({super.key});

  @override
  State<StorageUsageView> createState() => _StorageUsageViewState();
}

class _StorageUsageViewState extends State<StorageUsageView> {
  static const _retentionKey = 'storage.retentionSeconds';
  static const _limitKey = 'storage.maxCacheBytes';
  static const _unlimitedSize = 9007199254740991;
  static const _foreverTtl = 2147483647;
  static const _retentionOptions = <int, String>{
    259200: '3 days',
    604800: '1 week',
    2592000: '1 month',
    _foreverTtl: 'Forever',
  };
  static const _limitOptions = <int, String>{
    1073741824: '1 GB',
    5368709120: '5 GB',
    17179869184: '16 GB',
    _unlimitedSize: 'No limit',
  };

  final _service = const DataStorageService();
  List<Map<String, dynamic>> _chats = const [];
  final Map<int, String> _chatTitles = {};
  int _totalSize = 0;
  int _fileCount = 0;
  int _retention = _foreverTtl;
  int _limit = 5368709120;
  bool _loading = true;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    _retention = prefs.getInt(_retentionKey) ?? _foreverTtl;
    _limit = prefs.getInt(_limitKey) ?? 5368709120;
    try {
      final stats = await _service.storageStatistics();
      final chats = stats.objects('by_chat') ?? const [];
      for (final entry in chats) {
        final chatId = entry.int64('chat_id') ?? 0;
        if (chatId == 0) continue;
        unawaited(_resolveChatTitle(chatId));
      }
      if (!mounted) return;
      setState(() {
        _totalSize = stats.int64('size') ?? 0;
        _fileCount = stats.integer('count') ?? 0;
        _chats = chats;
      });
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resolveChatTitle(int chatId) async {
    try {
      final chat = await TdClient.shared.query({
        '@type': 'getChat',
        'chat_id': chatId,
      });
      if (!mounted) return;
      setState(() => _chatTitles[chatId] = chat.str('title') ?? '$chatId');
    } catch (_) {}
  }

  Future<void> _savePolicy({int? retention, int? limit}) async {
    setState(() {
      _retention = retention ?? _retention;
      _limit = limit ?? _limit;
      _working = true;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_retentionKey, _retention);
    await prefs.setInt(_limitKey, _limit);
    try {
      await _service.optimize(size: _limit, ttl: _retention);
      await _load();
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _clearAll() async {
    final confirmed = await confirmDialog(
      context,
      title: AppStrings.t(AppStringKeys.storageUsageClearCachedMedia),
      message:
          'Downloaded media can be fetched from Telegram again. Messages and '
          'local account data are kept.',
      confirmText: AppStrings.t(AppStringKeys.generalClearCache),
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _working = true);
    try {
      await _service.optimize(size: 0, ttl: 0);
      await _load();
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _clearChat(Map<String, dynamic> entry) async {
    final chatId = entry.int64('chat_id') ?? 0;
    final title =
        _chatTitles[chatId] ?? (chatId == 0 ? 'Other files' : '$chatId');
    final confirmed = await confirmDialog(
      context,
      title: AppStrings.t(AppStringKeys.storageUsageClearCacheForValue1, {
        'value1': title,
      }),
      message:
          'Cached files from this chat will be downloaded again on demand.',
      confirmText: AppStrings.t(AppStringKeys.emojiStatusClear),
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _working = true);
    try {
      await _service.optimize(size: 0, ttl: 0, chatIds: [chatId]);
      await _load();
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
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
            title: AppStrings.t(AppStringKeys.storageUsageStorageUsage),
            onBack: () => Navigator.of(context).pop(),
            trailing: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _loading ? null : _load,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: AppIcon(HeroAppIcons.arrowsRotate, size: 21),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: AppActivityIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    children: [
                      _summaryCard(),
                      const SizedBox(height: 14),
                      _policyCard(),
                      const SizedBox(height: 14),
                      Text(
                        AppStrings.t(AppStringKeys.storageUsageStorageByChat),
                        style: TextStyle(fontSize: 13, color: c.textTertiary),
                      ),
                      const SizedBox(height: 7),
                      _chatCard(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard() {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          AppIcon(HeroAppIcons.solidFolder, size: 34, color: AppTheme.brand),
          const SizedBox(height: 8),
          Text(
            _bytes(_totalSize),
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
          Text(
            AppStrings.t(AppStringKeys.storageUsageValue1CachedFiles, {
              'value1': _fileCount,
            }),
            style: TextStyle(fontSize: 13, color: c.textSecondary),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _working ? null : _clearAll,
            child: Container(
              width: double.infinity,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: AppTheme.tagRed),
              ),
              child: Text(
                _working ? 'Optimizing…' : 'Clear cached media',
                style: TextStyle(
                  color: AppTheme.tagRed,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _policyCard() {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          SettingsRow(
            title: AppStrings.t(AppStringKeys.storageUsageKeepMedia),
            value: _retentionOptions[_retention] ?? '',
            onTap: _working
                ? null
                : () => unawaited(
                    _choosePolicy(
                      title: AppStrings.t(AppStringKeys.storageUsageKeepMedia),
                      options: _retentionOptions,
                      selected: _retention,
                      onSelected: (value) => _savePolicy(retention: value),
                    ),
                  ),
          ),
          const Divider(height: 1),
          SettingsRow(
            title: AppStrings.t(AppStringKeys.storageUsageMaximumCacheSize),
            value: _limitOptions[_limit] ?? '',
            onTap: _working
                ? null
                : () => unawaited(
                    _choosePolicy(
                      title: AppStrings.t(
                        AppStringKeys.storageUsageMaximumCacheSize,
                      ),
                      options: _limitOptions,
                      selected: _limit,
                      onSelected: (value) => _savePolicy(limit: value),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _chatCard() {
    final c = context.colors;
    if (_chats.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          AppStrings.t(AppStringKeys.storageUsageNoCachedChatMedia),
          style: TextStyle(color: c.textSecondary),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < _chats.length; index++) ...[
            _chatRow(_chats[index]),
            if (index != _chats.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }

  Widget _chatRow(Map<String, dynamic> entry) {
    final chatId = entry.int64('chat_id') ?? 0;
    final title =
        _chatTitles[chatId] ?? (chatId == 0 ? 'Other files' : 'Chat $chatId');
    final types = entry.objects('by_file_type') ?? const [];
    final detail = types
        .take(3)
        .map((type) => _fileType(type.obj('file_type')?.type))
        .join(' · ');
    return SettingsRow(
      title: detail.isEmpty ? title : '$title · $detail',
      value: _bytes(entry.int64('size') ?? 0),
      onTap: _working ? null : () => _showChatDetails(entry),
    );
  }

  Future<void> _choosePolicy({
    required String title,
    required Map<int, String> options,
    required int selected,
    required Future<void> Function(int value) onSelected,
  }) async {
    final value = await showModalBottomSheet<int>(
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
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      title,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                for (var index = 0; index < options.length; index++) ...[
                  if (index > 0) Divider(height: 1, color: c.divider),
                  SettingsRow(
                    title: options.values.elementAt(index),
                    showChevron: false,
                    trailing: options.keys.elementAt(index) == selected
                        ? const AppIcon(HeroAppIcons.check, size: 20)
                        : null,
                    onTap: () => Navigator.of(
                      sheetContext,
                    ).pop(options.keys.elementAt(index)),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
    if (value != null && mounted) await onSelected(value);
  }

  Future<void> _showChatDetails(Map<String, dynamic> entry) async {
    final chatId = entry.int64('chat_id') ?? 0;
    final title =
        _chatTitles[chatId] ?? (chatId == 0 ? 'Other files' : '$chatId');
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              for (final type in entry.objects('by_file_type') ?? const [])
                SettingsRow(
                  title: _fileType(type.obj('file_type')?.type),
                  value: _bytes(type.int64('size') ?? 0),
                  showChevron: false,
                  height: 44,
                ),
              const SizedBox(height: 8),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_clearChat(entry));
                },
                child: Container(
                  width: double.infinity,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTheme.tagRed.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(
                    AppStrings.t(
                      AppStringKeys.storageUsageClearCacheForThisChat,
                    ),
                    style: TextStyle(
                      color: AppTheme.tagRed,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _fileType(String? type) => switch (type) {
    'fileTypePhoto' => 'Photos',
    'fileTypeVideo' => 'Videos',
    'fileTypeVoiceNote' => 'Voice messages',
    'fileTypeVideoNote' => 'Video messages',
    'fileTypeAudio' => 'Music',
    'fileTypeDocument' => 'Files',
    'fileTypeAnimation' => 'GIFs',
    'fileTypeSticker' => 'Stickers',
    'fileTypeStory' => 'Stories',
    _ => 'Other',
  };

  static String _bytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    var value = bytes / 1024;
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} ${units[unit]}';
  }
}
