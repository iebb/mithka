import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/confirm_dialog.dart';
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../platform/adaptive_platform.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_models.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import 'auto_download_settings_view.dart';
import 'data_storage_service.dart';
import 'downloads_view.dart';
import 'network_usage_view.dart';

/// A normalized, immutable view of TDLib's fast and detailed storage reports.
///
/// The dashboard deliberately reports only storage TDLib owns. It does not
/// manufacture device-capacity values or imply that application databases can
/// be deleted through the media-cache optimizer.
class StorageSnapshot {
  const StorageSnapshot({
    required this.cacheSize,
    required this.fileCount,
    required this.databaseSize,
    required this.languagePackSize,
    required this.logSize,
    required this.chats,
    required this.sizeByFileType,
  });

  factory StorageSnapshot.fromTd({
    required Map<String, dynamic> fast,
    required Map<String, dynamic> detailed,
  }) {
    final byType = <String, int>{};
    for (final entry
        in detailed.objects('by_file_type') ?? const <Map<String, dynamic>>[]) {
      final type = entry.obj('file_type')?.type;
      if (type != null) byType[type] = entry.int64('size') ?? 0;
    }
    final chats =
        (detailed.objects('by_chat') ?? const <Map<String, dynamic>>[])
            .map(StorageChatUsage.fromTd)
            .where((chat) => chat.size > 0)
            .toList(growable: false);
    return StorageSnapshot(
      cacheSize: fast.int64('files_size') ?? detailed.int64('size') ?? 0,
      fileCount: fast.integer('file_count') ?? detailed.integer('count') ?? 0,
      databaseSize: fast.int64('database_size') ?? 0,
      languagePackSize: fast.int64('language_pack_database_size') ?? 0,
      logSize: fast.int64('log_size') ?? 0,
      chats: chats,
      sizeByFileType: Map.unmodifiable(byType),
    );
  }

  final int cacheSize;
  final int fileCount;
  final int databaseSize;
  final int languagePackSize;
  final int logSize;
  final List<StorageChatUsage> chats;
  final Map<String, int> sizeByFileType;

  int get otherManagedSize => databaseSize + languagePackSize + logSize;
  int get managedTotal => cacheSize + otherManagedSize;

  int sizeFor(StorageMediaFilter filter) {
    if (filter == StorageMediaFilter.all) return cacheSize;
    return sizeByFileType.entries
        .where((entry) => filter.includes(entry.key))
        .fold(0, (sum, entry) => sum + entry.value);
  }
}

class StorageChatUsage {
  const StorageChatUsage({
    required this.chatId,
    required this.size,
    required this.count,
    required this.sizeByFileType,
    required this.countByFileType,
  });

  factory StorageChatUsage.fromTd(Map<String, dynamic> object) {
    final byType = <String, int>{};
    final countByType = <String, int>{};
    for (final entry
        in object.objects('by_file_type') ?? const <Map<String, dynamic>>[]) {
      final type = entry.obj('file_type')?.type;
      if (type != null) {
        byType[type] = entry.int64('size') ?? 0;
        countByType[type] = entry.integer('count') ?? 0;
      }
    }
    return StorageChatUsage(
      chatId: object.int64('chat_id') ?? 0,
      size: object.int64('size') ?? 0,
      count: object.integer('count') ?? 0,
      sizeByFileType: Map.unmodifiable(byType),
      countByFileType: Map.unmodifiable(countByType),
    );
  }

  final int chatId;
  final int size;
  final int count;
  final Map<String, int> sizeByFileType;
  final Map<String, int> countByFileType;

  int sizeFor(StorageMediaFilter filter) {
    if (filter == StorageMediaFilter.all) return size;
    return sizeByFileType.entries
        .where((entry) => filter.includes(entry.key))
        .fold(0, (sum, entry) => sum + entry.value);
  }

  int countFor(StorageMediaFilter filter) {
    if (filter == StorageMediaFilter.all) return count;
    return countByFileType.entries
        .where((entry) => filter.includes(entry.key))
        .fold(0, (sum, entry) => sum + entry.value);
  }
}

enum StorageMediaFilter {
  all,
  photos,
  videos,
  audio,
  documents,
  stickers,
  other,
}

extension on StorageMediaFilter {
  static const _photos = {
    'fileTypePhoto',
    'fileTypeProfilePhoto',
    'fileTypeWallpaper',
  };
  static const _videos = {
    'fileTypeVideo',
    'fileTypeVideoNote',
    'fileTypeAnimation',
    'fileTypeStory',
  };
  static const _audio = {
    'fileTypeAudio',
    'fileTypeVoiceNote',
    'fileTypeNotificationSound',
  };
  static const _documents = {'fileTypeDocument'};
  static const _stickers = {'fileTypeSticker'};

  Set<String> get types => switch (this) {
    StorageMediaFilter.all => const {},
    StorageMediaFilter.photos => _photos,
    StorageMediaFilter.videos => _videos,
    StorageMediaFilter.audio => _audio,
    StorageMediaFilter.documents => _documents,
    StorageMediaFilter.stickers => _stickers,
    StorageMediaFilter.other => const {
      'fileTypeThumbnail',
      'fileTypeSecret',
      'fileTypeSecretThumbnail',
      'fileTypeSecure',
      'fileTypeSelfDestructing',
      'fileTypeSelfDestructingPhoto',
      'fileTypeSelfDestructingVideo',
      'fileTypeUnknown',
    },
  };

  bool includes(String type) {
    if (this == StorageMediaFilter.all) return true;
    if (this == StorageMediaFilter.other) {
      return !_photos.contains(type) &&
          !_videos.contains(type) &&
          !_audio.contains(type) &&
          !_documents.contains(type) &&
          !_stickers.contains(type);
    }
    return types.contains(type);
  }

  String get titleKey => switch (this) {
    StorageMediaFilter.all => AppStringKeys.storageManagerAllTypes,
    StorageMediaFilter.photos => AppStringKeys.storageTypePhotos,
    StorageMediaFilter.videos => AppStringKeys.storageTypeVideos,
    StorageMediaFilter.audio => AppStringKeys.storageTypeAudio,
    StorageMediaFilter.documents => AppStringKeys.storageTypeDocuments,
    StorageMediaFilter.stickers => AppStringKeys.storageTypeStickers,
    StorageMediaFilter.other => AppStringKeys.storageTypeOther,
  };

  AppIconData get icon => switch (this) {
    StorageMediaFilter.all => HeroAppIcons.solidFolder,
    StorageMediaFilter.photos => HeroAppIcons.image,
    StorageMediaFilter.videos => HeroAppIcons.video,
    StorageMediaFilter.audio => HeroAppIcons.music,
    StorageMediaFilter.documents => HeroAppIcons.file,
    StorageMediaFilter.stickers => HeroAppIcons.solidFaceSmile,
    StorageMediaFilter.other => HeroAppIcons.grip,
  };

  List<Map<String, dynamic>> get optimizeFileTypes => types
      .map((type) => <String, dynamic>{'@type': type})
      .toList(growable: false);
}

class _StorageChatIdentity {
  const _StorageChatIdentity({required this.title, this.photo});

  final String title;
  final TdFileRef? photo;
}

class StorageUsageView extends StatefulWidget {
  const StorageUsageView({
    super.key,
    this.showBackButton = true,
    this.service = const DataStorageService(),
  });

  final bool showBackButton;
  final DataStorageService service;

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

  StorageSnapshot? _snapshot;
  final Map<int, _StorageChatIdentity> _chatIdentities = {};
  Object? _loadError;
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
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final responses = await Future.wait([
        widget.service.fastStorageStatistics(),
        widget.service.storageStatistics(chatLimit: 200),
      ]);
      final snapshot = StorageSnapshot.fromTd(
        fast: responses[0],
        detailed: responses[1],
      );
      if (!mounted) return;
      setState(() {
        _retention = prefs.getInt(_retentionKey) ?? _foreverTtl;
        _limit = prefs.getInt(_limitKey) ?? 5368709120;
        _snapshot = snapshot;
      });
      for (final chat in snapshot.chats) {
        if (chat.chatId != 0 && !_chatIdentities.containsKey(chat.chatId)) {
          unawaited(_resolveChat(chat.chatId));
        }
      }
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resolveChat(int chatId) async {
    try {
      final chat = await widget.service.chat(chatId);
      if (!mounted) return;
      setState(() {
        _chatIdentities[chatId] = _StorageChatIdentity(
          title: chat.str('title') ?? '$chatId',
          photo: TDParse.smallPhoto(chat.obj('photo')),
        );
      });
    } catch (_) {
      // Cache rows can still be managed safely using their stable chat IDs.
    }
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
      await widget.service.optimize(size: _limit, ttl: _retention);
      await _load();
    } catch (_) {
      if (mounted) {
        showToast(context, AppStrings.t(AppStringKeys.storageClearFailed));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _clearAllCache() async {
    final confirmed = await confirmDialog(
      context,
      title: AppStrings.t(AppStringKeys.storageUsageClearCachedMedia),
      message: AppStrings.t(AppStringKeys.storageClearSafeDescription),
      confirmText: AppStrings.t(AppStringKeys.generalClearCache),
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _working = true);
    try {
      await widget.service.optimize(
        size: 0,
        ttl: 0,
        immunityDelay: 0,
        fileTypes: _allReportedFileTypes(_snapshot),
        returnDeletedStatistics: true,
        chatLimit: 200,
      );
      await _load();
    } catch (_) {
      if (mounted) {
        showToast(context, AppStrings.t(AppStringKeys.storageClearFailed));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _openManager() async {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _StorageManagerView(
          service: widget.service,
          snapshot: snapshot,
          chatIdentities: _chatIdentities,
        ),
      ),
    );
    if (mounted) await _load();
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
            onBack: widget.showBackButton && Navigator.of(context).canPop()
                ? () => Navigator.of(context).pop()
                : null,
            trailing: AppInteractiveSurface(
              onTap: _loading ? null : () => unawaited(_load()),
              semanticLabel: AppStrings.t(AppStringKeys.groupAdminRefresh),
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.all(7),
                child: AppIcon(HeroAppIcons.arrowsRotate, size: 19),
              ),
            ),
          ),
          Expanded(child: _content()),
        ],
      ),
    );
  }

  Widget _content() {
    if (_loading && _snapshot == null) {
      return const Center(child: AppActivityIndicator());
    }
    if (_loadError != null && _snapshot == null) {
      return _StorageErrorState(onRetry: _load);
    }
    final snapshot = _snapshot;
    if (snapshot == null) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktopDense =
            isDesktopTargetPlatform() && constraints.maxWidth >= 720;
        final maxWidth = desktopDense ? 980.0 : 680.0;
        final horizontal = desktopDense ? 24.0 : 14.0;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: ListView(
              key: const ValueKey('storage-dashboard'),
              padding: EdgeInsets.fromLTRB(horizontal, 18, horizontal, 32),
              children: [
                _StorageDonutSummary(
                  snapshot: snapshot,
                  desktopDense: desktopDense,
                ),
                SizedBox(height: desktopDense ? 12 : 16),
                _StorageActionCard(
                  key: const ValueKey('storage-chats-files-card'),
                  title: AppStrings.t(AppStringKeys.storageDashboardChatsFiles),
                  description: AppStrings.t(
                    AppStringKeys.storageDashboardChatsFilesDescription,
                  ),
                  value: formatStorageBytes(snapshot.cacheSize),
                  action: AppStrings.t(AppStringKeys.appearanceManage),
                  icon: HeroAppIcons.solidFolder,
                  iconColor: const Color(0xFF16B8D4),
                  desktopDense: desktopDense,
                  enabled: !_working,
                  onTap: _openManager,
                ),
                SizedBox(height: desktopDense ? 10 : 12),
                _StorageActionCard(
                  key: const ValueKey('storage-cache-card'),
                  title: AppStrings.t(AppStringKeys.storageDashboardCache),
                  description: AppStrings.t(
                    AppStringKeys.storageDashboardCacheDescription,
                  ),
                  value: AppStrings.t(
                    AppStringKeys.storageUsageValue1CachedFiles,
                    {'value1': snapshot.fileCount},
                  ),
                  action: _working
                      ? AppStrings.t(AppStringKeys.generalClearingCache)
                      : AppStrings.t(AppStringKeys.generalClearCache),
                  icon: HeroAppIcons.compactDisc,
                  iconColor: const Color(0xFF7C5CFC),
                  desktopDense: desktopDense,
                  destructive: true,
                  enabled: !_working,
                  showProgress: _working,
                  onTap: _clearAllCache,
                ),
                SizedBox(height: desktopDense ? 10 : 12),
                _otherDataCard(snapshot, desktopDense: desktopDense),
                SizedBox(height: desktopDense ? 10 : 12),
                _policyCard(desktopDense: desktopDense),
                SizedBox(height: desktopDense ? 10 : 12),
                _relatedStorageCard(desktopDense: desktopDense),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _otherDataCard(
    StorageSnapshot snapshot, {
    required bool desktopDense,
  }) {
    final c = context.colors;
    final rows = [
      (
        AppStringKeys.storageDashboardDatabase,
        snapshot.databaseSize,
        const Color(0xFFB967E8),
      ),
      (
        AppStringKeys.storageDashboardLanguagePacks,
        snapshot.languagePackSize,
        const Color(0xFFF3A83B),
      ),
      (
        AppStringKeys.storageDashboardLogs,
        snapshot.logSize,
        const Color(0xFFEC6B91),
      ),
    ];
    return Container(
      key: const ValueKey('storage-other-card'),
      padding: EdgeInsets.all(desktopDense ? 14 : 17),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(desktopDense ? 10 : 14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.t(AppStringKeys.storageDashboardOtherData),
            style: TextStyle(
              color: c.textPrimary,
              fontSize: desktopDense ? 15 : 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            AppStrings.t(AppStringKeys.storageDashboardOtherDescription),
            style: TextStyle(
              color: c.textSecondary,
              fontSize: desktopDense ? 12 : 14,
              height: 1.35,
            ),
          ),
          SizedBox(height: desktopDense ? 12 : 15),
          for (var index = 0; index < rows.length; index++) ...[
            if (index > 0) SizedBox(height: desktopDense ? 8 : 11),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: rows[index].$3,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    AppStrings.t(rows[index].$1),
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: desktopDense ? 13 : 15,
                    ),
                  ),
                ),
                Text(
                  formatStorageBytes(rows[index].$2),
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: desktopDense ? 12 : 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _policyCard({required bool desktopDense}) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(desktopDense ? 10 : 14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SettingsRow(
            height: desktopDense ? 44 : 52,
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
          Divider(height: 1, color: c.divider),
          SettingsRow(
            height: desktopDense ? 44 : 52,
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

  Widget _relatedStorageCard({required bool desktopDense}) {
    final c = context.colors;
    final destinations = <(String, AppIconData, Color, Widget)>[
      (
        AppStringKeys.generalAutoDownloadMedia,
        HeroAppIcons.download,
        const Color(0xFF16B0A0),
        const AutoDownloadSettingsView(),
      ),
      (
        AppStringKeys.generalDownloads,
        HeroAppIcons.solidFolder,
        const Color(0xFF3C8CF0),
        const DownloadsView(),
      ),
      (
        AppStringKeys.generalNetworkUsage,
        HeroAppIcons.networkWired,
        const Color(0xFFFF9500),
        const NetworkUsageView(),
      ),
    ];
    return Container(
      key: const ValueKey('storage-related-settings'),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(desktopDense ? 10 : 14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < destinations.length; index++) ...[
            if (index > 0) Divider(height: 1, color: c.divider),
            AppInteractiveSurface(
              semanticLabel: AppStrings.t(destinations[index].$1),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => destinations[index].$4),
              ),
              child: Container(
                constraints: BoxConstraints(minHeight: desktopDense ? 42 : 52),
                padding: EdgeInsets.symmetric(
                  horizontal: desktopDense ? 12 : 15,
                ),
                child: Row(
                  children: [
                    Container(
                      width: desktopDense ? 28 : 34,
                      height: desktopDense ? 28 : 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: destinations[index].$3.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(
                          desktopDense ? 7 : 9,
                        ),
                      ),
                      child: AppIcon(
                        destinations[index].$2,
                        size: desktopDense ? 15 : 18,
                        color: destinations[index].$3,
                      ),
                    ),
                    SizedBox(width: desktopDense ? 10 : 12),
                    Expanded(
                      child: Text(
                        AppStrings.t(destinations[index].$1),
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: desktopDense ? 13 : 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    AppIcon(
                      HeroAppIcons.chevronRight,
                      size: desktopDense ? 13 : 16,
                      color: c.textTertiary,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _choosePolicy({
    required String title,
    required Map<int, String> options,
    required int selected,
    required Future<void> Function(int value) onSelected,
  }) async {
    final value = await showAppModalSheet<int>(
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
}

class _StorageDonutSummary extends StatelessWidget {
  const _StorageDonutSummary({
    required this.snapshot,
    required this.desktopDense,
  });

  final StorageSnapshot snapshot;
  final bool desktopDense;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final segments = [
      _StorageSegment(snapshot.cacheSize, const Color(0xFF16B8D4)),
      _StorageSegment(snapshot.databaseSize, const Color(0xFFB967E8)),
      _StorageSegment(snapshot.languagePackSize, const Color(0xFFF3A83B)),
      _StorageSegment(snapshot.logSize, const Color(0xFFEC6B91)),
    ];
    final diameter = desktopDense ? 190.0 : 210.0;
    final chart = Semantics(
      label: AppStrings.t(AppStringKeys.storageDashboardManagedStorage),
      value: formatStorageBytes(snapshot.managedTotal),
      readOnly: true,
      child: SizedBox.square(
        dimension: diameter,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _StorageDonutPainter(
                  segments: segments,
                  trackColor: c.divider.withValues(alpha: 0.6),
                  strokeWidth: desktopDense ? 28 : 30,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(42),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    formatStorageBytes(snapshot.managedTotal),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: desktopDense ? 22 : 25,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    AppStrings.t(AppStringKeys.storageDashboardTotal),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: c.textSecondary,
                      fontSize: desktopDense ? 11 : 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    final text = Column(
      crossAxisAlignment: desktopDense
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Text(
          AppStrings.t(AppStringKeys.storageDashboardManagedStorage),
          textAlign: desktopDense ? TextAlign.start : TextAlign.center,
          style: TextStyle(
            color: c.textPrimary,
            fontSize: desktopDense ? 20 : 21,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          AppStrings.t(AppStringKeys.storageDashboardManagedDescription),
          textAlign: desktopDense ? TextAlign.start : TextAlign.center,
          style: TextStyle(
            color: c.textSecondary,
            fontSize: desktopDense ? 12 : 14,
            height: 1.4,
          ),
        ),
        SizedBox(height: desktopDense ? 14 : 16),
        _LegendDot(
          color: segments[0].color,
          title: AppStrings.t(AppStringKeys.storageDashboardCache),
          value: formatStorageBytes(snapshot.cacheSize),
          desktopDense: desktopDense,
        ),
        const SizedBox(height: 8),
        _LegendDot(
          color: segments[1].color,
          title: AppStrings.t(AppStringKeys.storageDashboardDatabase),
          value: formatStorageBytes(snapshot.databaseSize),
          desktopDense: desktopDense,
        ),
        const SizedBox(height: 8),
        _LegendDot(
          color: segments[2].color,
          title: AppStrings.t(AppStringKeys.storageDashboardLanguagePacks),
          value: formatStorageBytes(snapshot.languagePackSize),
          desktopDense: desktopDense,
        ),
        const SizedBox(height: 8),
        _LegendDot(
          color: segments[3].color,
          title: AppStrings.t(AppStringKeys.storageDashboardLogs),
          value: formatStorageBytes(snapshot.logSize),
          desktopDense: desktopDense,
        ),
      ],
    );
    if (desktopDense) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            chart,
            const SizedBox(width: 42),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 390),
                child: text,
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        chart,
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: text,
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.color,
    required this.title,
    required this.value,
    required this.desktopDense,
  });

  final Color color;
  final String title;
  final String value;
  final bool desktopDense;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 8),
      Text(
        title,
        style: TextStyle(
          color: context.colors.textSecondary,
          fontSize: desktopDense ? 12 : 13,
        ),
      ),
      const SizedBox(width: 8),
      Text(
        value,
        style: TextStyle(
          color: context.colors.textPrimary,
          fontSize: desktopDense ? 12 : 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _StorageSegment {
  const _StorageSegment(this.value, this.color);
  final int value;
  final Color color;
}

class _StorageDonutPainter extends CustomPainter {
  const _StorageDonutPainter({
    required this.segments,
    required this.trackColor,
    required this.strokeWidth,
  });

  final List<_StorageSegment> segments;
  final Color trackColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.max(
      0.0,
      math.min(size.width, size.height) / 2 - strokeWidth / 2,
    );
    final rect = Rect.fromCircle(center: center, radius: radius);
    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, track);
    final total = segments.fold<int>(
      0,
      (sum, segment) => sum + math.max(0, segment.value),
    );
    if (total == 0) return;
    var start = -math.pi / 2;
    const gap = 0.015;
    for (final segment in segments) {
      if (segment.value <= 0) continue;
      final sweep = 2 * math.pi * segment.value / total;
      final paint = Paint()
        ..color = segment.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        rect,
        start + gap,
        math.max(0, sweep - gap * 2),
        false,
        paint,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_StorageDonutPainter oldDelegate) =>
      oldDelegate.segments != segments ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.strokeWidth != strokeWidth;
}

class _StorageActionCard extends StatelessWidget {
  const _StorageActionCard({
    super.key,
    required this.title,
    required this.description,
    required this.value,
    required this.action,
    required this.icon,
    required this.iconColor,
    required this.desktopDense,
    required this.enabled,
    required this.onTap,
    this.destructive = false,
    this.showProgress = false,
  });

  final String title;
  final String description;
  final String value;
  final String action;
  final AppIconData icon;
  final Color iconColor;
  final bool desktopDense;
  final bool enabled;
  final VoidCallback onTap;
  final bool destructive;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: EdgeInsets.all(desktopDense ? 14 : 17),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(desktopDense ? 10 : 14),
      ),
      child: Row(
        children: [
          Container(
            width: desktopDense ? 34 : 42,
            height: desktopDense ? 34 : 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(desktopDense ? 8 : 10),
            ),
            child: AppIcon(
              icon,
              size: desktopDense ? 17 : 21,
              color: iconColor,
            ),
          ),
          SizedBox(width: desktopDense ? 12 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: desktopDense ? 15 : 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: desktopDense ? 14 : 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: desktopDense ? 12 : 13,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: desktopDense ? 12 : 14),
          AppInteractiveSurface(
            onTap: enabled ? onTap : null,
            semanticLabel: action,
            borderRadius: BorderRadius.circular(9),
            child: Container(
              constraints: BoxConstraints(
                minWidth: desktopDense ? 70 : 76,
                minHeight: desktopDense ? 30 : 40,
              ),
              padding: EdgeInsets.symmetric(horizontal: desktopDense ? 11 : 13),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: destructive
                    ? AppTheme.tagRed.withValues(alpha: 0.11)
                    : AppTheme.brand.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(9),
              ),
              child: showProgress
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: AppActivityIndicator(),
                    )
                  : Text(
                      action,
                      style: TextStyle(
                        color: destructive ? AppTheme.tagRed : AppTheme.brand,
                        fontSize: desktopDense ? 12 : 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StorageManagerView extends StatefulWidget {
  const _StorageManagerView({
    required this.service,
    required this.snapshot,
    this.chatIdentities = const {},
  });

  final DataStorageService service;
  final StorageSnapshot snapshot;
  final Map<int, _StorageChatIdentity> chatIdentities;

  @override
  State<_StorageManagerView> createState() => _StorageManagerViewState();
}

enum _StorageSort { size, name }

class _StorageManagerViewState extends State<_StorageManagerView> {
  late final Map<int, _StorageChatIdentity> _identities = {
    ...widget.chatIdentities,
  };
  final Set<int> _selected = {};
  StorageMediaFilter _filter = StorageMediaFilter.all;
  _StorageSort _sort = _StorageSort.size;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    for (final chat in widget.snapshot.chats) {
      if (chat.chatId != 0 && !_identities.containsKey(chat.chatId)) {
        unawaited(_resolveChat(chat.chatId));
      }
    }
  }

  Future<void> _resolveChat(int chatId) async {
    try {
      final chat = await widget.service.chat(chatId);
      if (!mounted) return;
      setState(() {
        _identities[chatId] = _StorageChatIdentity(
          title: chat.str('title') ?? '$chatId',
          photo: TDParse.smallPhoto(chat.obj('photo')),
        );
      });
    } catch (_) {}
  }

  List<StorageChatUsage> get _visibleChats {
    final chats = widget.snapshot.chats
        .where((chat) => chat.sizeFor(_filter) > 0)
        .toList();
    chats.sort((a, b) {
      if (_sort == _StorageSort.size) {
        return b.sizeFor(_filter).compareTo(a.sizeFor(_filter));
      }
      return _title(
        a.chatId,
      ).toLowerCase().compareTo(_title(b.chatId).toLowerCase());
    });
    return chats;
  }

  String _title(int chatId) =>
      _identities[chatId]?.title ??
      (chatId == 0
          ? AppStrings.t(AppStringKeys.storageManagerOther)
          : '$chatId');

  Future<void> _clearSelected() async {
    if (_selected.isEmpty) {
      showToast(
        context,
        AppStrings.t(AppStringKeys.storageManagerNothingSelected),
      );
      return;
    }
    final confirmed = await confirmDialog(
      context,
      title: AppStrings.t(AppStringKeys.storageManagerClearSelectedConfirm),
      message: AppStrings.t(AppStringKeys.storageClearSafeDescription),
      confirmText: AppStrings.t(AppStringKeys.storageManagerClearSelected),
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _working = true);
    try {
      await widget.service.optimize(
        size: 0,
        ttl: 0,
        immunityDelay: 0,
        chatIds: _selected.toList(growable: false),
        fileTypes: _reportedFileTypesForFilter(widget.snapshot, _filter),
        returnDeletedStatistics: true,
        chatLimit: 200,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        showToast(context, AppStrings.t(AppStringKeys.storageClearFailed));
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
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.storageManagerTitle),
            onBack: Navigator.of(context).canPop()
                ? () => Navigator.of(context).pop()
                : null,
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final desktop =
                    isDesktopTargetPlatform() && constraints.maxWidth >= 760;
                return desktop ? _desktopManager() : _mobileManager();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _desktopManager() => Row(
    children: [
      SizedBox(width: 208, child: _filterPane(desktopDense: true)),
      VerticalDivider(width: 1, color: context.colors.divider),
      Expanded(child: _chatPane(desktopDense: true)),
    ],
  );

  Widget _mobileManager() => Column(
    children: [
      SizedBox(
        height: 62,
        child: ListView.separated(
          key: const ValueKey('storage-mobile-filters'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          itemCount: StorageMediaFilter.values.length,
          separatorBuilder: (_, _) => const SizedBox(width: 7),
          itemBuilder: (context, index) => _filterChip(
            StorageMediaFilter.values[index],
            desktopDense: false,
          ),
        ),
      ),
      Divider(height: 1, color: context.colors.divider),
      Expanded(child: _chatPane(desktopDense: false)),
    ],
  );

  Widget _filterPane({required bool desktopDense}) => ListView(
    key: const ValueKey('storage-desktop-filters'),
    padding: const EdgeInsets.all(10),
    children: [
      for (final filter in StorageMediaFilter.values)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: _filterChip(filter, desktopDense: desktopDense),
        ),
    ],
  );

  Widget _filterChip(StorageMediaFilter filter, {required bool desktopDense}) {
    final c = context.colors;
    final selected = filter == _filter;
    return AppInteractiveSurface(
      key: ValueKey('storage-filter-${filter.name}'),
      selected: selected,
      semanticLabel: AppStrings.t(filter.titleKey),
      onTap: () => setState(() {
        _filter = filter;
        _selected.clear();
      }),
      borderRadius: BorderRadius.circular(desktopDense ? 8 : 18),
      child: Container(
        constraints: BoxConstraints(minHeight: desktopDense ? 36 : 42),
        padding: EdgeInsets.symmetric(horizontal: desktopDense ? 10 : 13),
        decoration: BoxDecoration(
          color: selected ? c.textPrimary.withValues(alpha: 0.10) : c.card,
          borderRadius: BorderRadius.circular(desktopDense ? 8 : 18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(
              filter.icon,
              size: desktopDense ? 15 : 18,
              color: selected ? AppTheme.brand : c.textSecondary,
            ),
            const SizedBox(width: 8),
            if (desktopDense)
              Expanded(
                child: Text(
                  AppStrings.t(filter.titleKey),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? c.textPrimary : c.textSecondary,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              )
            else ...[
              Text(
                AppStrings.t(filter.titleKey),
                style: TextStyle(
                  color: selected ? c.textPrimary : c.textSecondary,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatStorageBytes(widget.snapshot.sizeFor(filter)),
                style: TextStyle(color: c.textTertiary, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chatPane({required bool desktopDense}) {
    final chats = _visibleChats;
    final c = context.colors;
    return Column(
      children: [
        Container(
          key: const ValueKey('storage-manager-toolbar'),
          constraints: BoxConstraints(minHeight: desktopDense ? 44 : 52),
          padding: EdgeInsets.symmetric(horizontal: desktopDense ? 12 : 14),
          child: Row(
            children: [
              _selectionBox(
                selected:
                    chats.isNotEmpty &&
                    chats.every((chat) => _selected.contains(chat.chatId)),
                desktopDense: desktopDense,
                onTap: () => setState(() {
                  final allSelected =
                      chats.isNotEmpty &&
                      chats.every((chat) => _selected.contains(chat.chatId));
                  if (allSelected) {
                    _selected.removeAll(chats.map((chat) => chat.chatId));
                  } else {
                    _selected.addAll(chats.map((chat) => chat.chatId));
                  }
                }),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _selected.isEmpty
                      ? AppStrings.t(AppStringKeys.storageUsageStorageByChat)
                      : AppStrings.t(
                          AppStringKeys.storageManagerSelectedCount,
                          {'value1': _selected.length},
                        ),
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: desktopDense ? 13 : 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _sortButton(_StorageSort.name, desktopDense: desktopDense),
              const SizedBox(width: 6),
              _sortButton(_StorageSort.size, desktopDense: desktopDense),
              const SizedBox(width: 8),
              AppInteractiveSurface(
                key: const ValueKey('storage-clear-selected'),
                onTap: _working ? null : () => unawaited(_clearSelected()),
                semanticLabel: AppStrings.t(
                  AppStringKeys.storageManagerClearSelected,
                ),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  constraints: BoxConstraints(
                    minHeight: desktopDense ? 30 : 38,
                  ),
                  padding: EdgeInsets.symmetric(
                    horizontal: desktopDense ? 10 : 12,
                  ),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTheme.tagRed.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _working
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: AppActivityIndicator(),
                        )
                      : Text(
                          AppStrings.t(
                            AppStringKeys.storageManagerClearSelected,
                          ),
                          style: TextStyle(
                            color: AppTheme.tagRed,
                            fontSize: desktopDense ? 11 : 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: c.divider),
        Expanded(
          child: chats.isEmpty
              ? Center(
                  child: Text(
                    AppStrings.t(AppStringKeys.storageUsageNoCachedChatMedia),
                    style: TextStyle(color: c.textSecondary),
                  ),
                )
              : ListView.separated(
                  key: const ValueKey('storage-chat-rows'),
                  itemCount: chats.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: c.divider),
                  itemBuilder: (context, index) =>
                      _chatRow(chats[index], desktopDense: desktopDense),
                ),
        ),
      ],
    );
  }

  Widget _sortButton(_StorageSort sort, {required bool desktopDense}) {
    final selected = sort == _sort;
    final c = context.colors;
    final label = AppStrings.t(
      sort == _StorageSort.size
          ? AppStringKeys.storageManagerSortSize
          : AppStringKeys.storageManagerSortName,
    );
    return AppInteractiveSurface(
      key: ValueKey('storage-sort-${sort.name}'),
      selected: selected,
      semanticLabel: label,
      onTap: () => setState(() => _sort = sort),
      borderRadius: BorderRadius.circular(7),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: desktopDense ? 8 : 9,
          vertical: desktopDense ? 5 : 7,
        ),
        decoration: BoxDecoration(
          color: selected
              ? c.textPrimary.withValues(alpha: 0.09)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? c.textPrimary : c.textSecondary,
            fontSize: desktopDense ? 11 : 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _chatRow(StorageChatUsage chat, {required bool desktopDense}) {
    final c = context.colors;
    final selected = _selected.contains(chat.chatId);
    final identity = _identities[chat.chatId];
    final title = _title(chat.chatId);
    return AppInteractiveSurface(
      key: ValueKey('storage-chat-${chat.chatId}'),
      selected: selected,
      checked: selected,
      semanticLabel: title,
      semanticValue: formatStorageBytes(chat.sizeFor(_filter)),
      onTap: () => setState(() {
        if (selected) {
          _selected.remove(chat.chatId);
        } else {
          _selected.add(chat.chatId);
        }
      }),
      child: Container(
        constraints: BoxConstraints(minHeight: desktopDense ? 48 : 64),
        padding: EdgeInsets.symmetric(horizontal: desktopDense ? 12 : 14),
        child: Row(
          children: [
            _selectionBox(
              selected: selected,
              desktopDense: desktopDense,
              onTap: () => setState(() {
                if (selected) {
                  _selected.remove(chat.chatId);
                } else {
                  _selected.add(chat.chatId);
                }
              }),
            ),
            SizedBox(width: desktopDense ? 10 : 12),
            PhotoAvatar(
              title: title,
              photo: identity?.photo,
              size: desktopDense ? 30 : 40,
              allowAnimation: false,
            ),
            SizedBox(width: desktopDense ? 10 : 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: desktopDense ? 13 : 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (!desktopDense)
                    Text(
                      AppStrings.t(
                        AppStringKeys.storageUsageValue1CachedFiles,
                        {'value1': chat.countFor(_filter)},
                      ),
                      style: TextStyle(color: c.textTertiary, fontSize: 12),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              formatStorageBytes(chat.sizeFor(_filter)),
              style: TextStyle(
                color: c.textSecondary,
                fontSize: desktopDense ? 12 : 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _selectionBox({
    required bool selected,
    required bool desktopDense,
    required VoidCallback onTap,
  }) => AppInteractiveSurface(
    checked: selected,
    onTap: onTap,
    borderRadius: BorderRadius.circular(99),
    child: Container(
      width: desktopDense ? 18 : 22,
      height: desktopDense ? 18 : 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? AppTheme.brand : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? AppTheme.brand : context.colors.textTertiary,
          width: 1.4,
        ),
      ),
      child: selected
          ? AppIcon(
              HeroAppIcons.check,
              size: desktopDense ? 11 : 13,
              color: Colors.white,
            )
          : null,
    ),
  );
}

class _StorageErrorState extends StatelessWidget {
  const _StorageErrorState({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(HeroAppIcons.circleInfo, size: 34, color: c.textTertiary),
            const SizedBox(height: 12),
            Text(
              AppStrings.t(AppStringKeys.storageLoadFailed),
              textAlign: TextAlign.center,
              style: TextStyle(color: c.textSecondary, fontSize: 15),
            ),
            const SizedBox(height: 14),
            AppInteractiveSurface(
              onTap: () => unawaited(onRetry()),
              semanticLabel: AppStrings.t(AppStringKeys.callsRetry),
              borderRadius: BorderRadius.circular(9),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.brand.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  AppStrings.t(AppStringKeys.callsRetry),
                  style: TextStyle(
                    color: AppTheme.brand,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String formatStorageBytes(int bytes) {
  final safeBytes = math.max(0, bytes);
  if (safeBytes < 1024) return '$safeBytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = safeBytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final decimals = value >= 100
      ? 0
      : value >= 10
      ? 1
      : 2;
  return '${value.toStringAsFixed(decimals)} ${units[unit]}';
}

List<Map<String, dynamic>> _allReportedFileTypes(StorageSnapshot? snapshot) =>
    snapshot?.sizeByFileType.keys
        .map((type) => <String, dynamic>{'@type': type})
        .toList(growable: false) ??
    const <Map<String, dynamic>>[];

List<Map<String, dynamic>> _reportedFileTypesForFilter(
  StorageSnapshot snapshot,
  StorageMediaFilter filter,
) {
  if (filter == StorageMediaFilter.all || filter == StorageMediaFilter.other) {
    return snapshot.sizeByFileType.keys
        .where(filter.includes)
        .map((type) => <String, dynamic>{'@type': type})
        .toList(growable: false);
  }
  return filter.optimizeFileTypes;
}
