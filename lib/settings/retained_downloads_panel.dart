import 'dart:async';

import 'package:flutter/widgets.dart';

import '../chat/file_opener.dart';
import '../components/app_confirm_dialog.dart';
import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'retained_download_store.dart';

/// Embedded in Downloads. The independent index remains usable even after
/// TDLib evicts its cache or removes old entries from the download task list.
class RetainedDownloadsPanel extends StatefulWidget {
  const RetainedDownloadsPanel({
    super.key,
    required this.accountSlot,
    this.store,
  });

  final int accountSlot;
  final RetainedDownloadStore? store;

  @override
  State<RetainedDownloadsPanel> createState() => _RetainedDownloadsPanelState();
}

class _RetainedDownloadsPanelState extends State<RetainedDownloadsPanel> {
  RetainedDownloadStore? _store;
  List<RetainedDownload> _items = [];
  final Set<String> _removing = {};
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final store =
          widget.store ??
          await RetainedDownloadStore.forAccount(widget.accountSlot);
      final items = await store.list();
      if (mounted) {
        setState(() {
          _store = store;
          _items = items;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(RetainedDownload item) async {
    try {
      await openDownloadedFile(
        context,
        item.path,
        mimeType: mimeForFileName(item.fileName),
      );
    } catch (_) {
      if (mounted) {
        showToast(context, AppStringKeys.downloadsRetainedUnavailable);
      }
    }
  }

  Future<void> _remove(RetainedDownload item) async {
    if (!_removing.add(item.id)) return;
    setState(() {});
    try {
      final confirmed = await showAppConfirmDialog(
        context,
        title: AppStringKeys.downloadsRemoveRetained,
        message: AppStrings.t(AppStringKeys.downloadsRemoveRetainedConfirm, {
          'name': item.title,
        }),
        confirmText: AppStringKeys.downloadsRemoveRetained,
        destructive: true,
      );
      if (!confirmed || !mounted) return;
      await _store!.remove(item.id);
      if (mounted) setState(() => _items.removeWhere((e) => e.id == item.id));
    } catch (_) {
      if (mounted) {
        showToast(context, AppStringKeys.downloadsRetainedUnavailable);
      }
    } finally {
      _removing.remove(item.id);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  AppStrings.t(AppStringKeys.downloadsRetainedHint),
                  style: TextStyle(fontSize: 12, color: c.textSecondary),
                ),
              ),
              AppInteractiveSurface(
                key: const ValueKey('retained-downloads-refresh'),
                enabled: !_loading,
                semanticLabel: AppStrings.t(
                  AppStringKeys.downloadsRefreshDownloads,
                ),
                onTap: _load,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: AppIcon(
                    HeroAppIcons.arrowsRotate,
                    size: 20,
                    color: c.linkBlue,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: AppActivityIndicator())
              : _failed || _items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      AppStrings.t(
                        _failed
                            ? AppStringKeys.downloadsRetainedUnavailable
                            : AppStringKeys.downloadsNoRetained,
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.textSecondary),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return SettingsPanel(
                      key: ValueKey('retained-download-${item.id}'),
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Expanded(
                            child: AppInteractiveSurface(
                              onTap: () => unawaited(_open(item)),
                              child: Row(
                                children: [
                                  AppIcon(
                                    item.isVideo
                                        ? HeroAppIcons.video
                                        : HeroAppIcons.file,
                                    size: 26,
                                    color: c.linkBlue,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 15,
                                            color: c.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${AppStrings.t(AppStringKeys.downloadsKeptOnDevice)} · ${_bytes(item.size)}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: c.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          AppInteractiveSurface(
                            key: ValueKey('retained-remove-${item.id}'),
                            semanticLabel: AppStrings.t(
                              AppStringKeys.downloadsRemoveRetained,
                            ),
                            enabled: !_removing.contains(item.id),
                            onTap: () => unawaited(_remove(item)),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: AppIcon(
                                HeroAppIcons.trash,
                                size: 18,
                                color: c.textTertiary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  static String _bytes(int size) {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
