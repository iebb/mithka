import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../components/app_icons.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'download_storage.dart';

class DownloadLocationView extends StatefulWidget {
  const DownloadLocationView({super.key});

  @override
  State<DownloadLocationView> createState() => _DownloadLocationViewState();
}

class _DownloadLocationViewState extends State<DownloadLocationView> {
  List<String> _locations = [];
  String? _selected;
  String? _folder;
  bool _loading = true;
  bool _working = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final locations = await DownloadStorage.locations();
      final prefs = await SharedPreferences.getInstance();
      String? folder;
      try {
        folder = await DownloadStorage.saveFolder();
      } catch (_) {
        // A revoked grant should not prevent choosing a replacement folder.
      }
      if (!mounted) return;
      setState(() {
        _locations = locations;
        _selected =
            prefs.getString(DownloadStorage.selectedKey) ??
            locations.firstOrNull;
        _folder = folder;
        _failed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _select(String path) async {
    setState(() => _working = true);
    try {
      await DownloadStorage.select(path);
      if (mounted) setState(() => _selected = path);
    } catch (_) {
      if (mounted) {
        showToast(context, AppStringKeys.storageDownloadLocationFailed);
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _pickFolder() async {
    setState(() => _working = true);
    try {
      final folder = await DownloadStorage.pickSaveFolder();
      if (mounted && folder != null) setState(() => _folder = folder);
    } catch (_) {
      if (mounted) {
        showToast(context, AppStringKeys.storageDownloadLocationFailed);
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => SettingsPageScaffold(
    title: AppStrings.t(AppStringKeys.storageDownloadLocation),
    onBack: () => Navigator.of(context).pop(),
    child: _loading
        ? const Center(child: AppActivityIndicator())
        : ListView(
            padding: AppInsets.screen,
            children: [
              if (_failed)
                SettingsRow(
                  title: AppStrings.t(
                    AppStringKeys.storageDownloadLocationFailed,
                  ),
                  onTap: _load,
                ),
              const SettingsSectionHeader(
                AppStringKeys.storageDownloadCacheLocation,
              ),
              SettingsCard(
                children: [
                  for (var i = 0; i < _locations.length; i++) ...[
                    if (i > 0)
                      Divider(height: 1, color: context.colors.divider),
                    SettingsRow(
                      key: ValueKey('download-location-$i'),
                      title: AppStrings.t(
                        i == _locations.length - 1
                            ? AppStringKeys.storageDownloadPrivate
                            : AppStringKeys.storageDownloadShared,
                      ),
                      subtitle: _locations[i],
                      height: 84,
                      showChevron: false,
                      enabled: !_working,
                      trailing: AppIcon(
                        _selected == _locations[i]
                            ? HeroAppIcons.circleCheck
                            : HeroAppIcons.circle,
                        color: _selected == _locations[i]
                            ? AppTheme.brand
                            : context.colors.textSecondary,
                      ),
                      onTap: () => _select(_locations[i]),
                    ),
                  ],
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  AppStrings.t(
                    DownloadStorage.migrationFailed
                        ? AppStringKeys.storageDownloadMigrationFailed
                        : AppStringKeys.storageDownloadRestart,
                  ),
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
              if (DownloadStorage.currentRoot case final path?)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    AppStrings.t(AppStringKeys.storageDownloadCurrent, {
                      'value1': path,
                    }),
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              SettingsCard(
                children: [
                  SettingsRow(
                    key: const ValueKey('download-save-folder'),
                    leading: const AppIcon(HeroAppIcons.solidFolder),
                    title: AppStrings.t(
                      AppStringKeys.storageDownloadSaveFolder,
                    ),
                    subtitle:
                        _folder ??
                        AppStrings.t(
                          AppStringKeys.storageDownloadFolderNotSelected,
                        ),
                    height: 76,
                    enabled: !_working,
                    onTap: _pickFolder,
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  AppStrings.t(AppStringKeys.storageDownloadSaveHint),
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
  );
}
