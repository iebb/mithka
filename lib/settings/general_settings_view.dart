//
//  general_settings_view.dart
//
//  Data and storage controls plus Mithka's separate chat-behavior settings.
//  Port of the Swift `GeneralSettingsView` / `GeneralSettingsViewModel`.
//

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../chat/link_browser.dart';
import '../components/app_icons.dart';
import '../components/settings_selection_row.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../platform/adaptive_platform.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'auto_download_media_controller.dart';
import 'auto_download_settings_view.dart';
import 'downloads_view.dart';
import 'network_usage_view.dart';
import 'storage_usage_view.dart';
import 'video_playback_settings_view.dart';

class GeneralSettingsView extends StatefulWidget {
  const GeneralSettingsView({super.key, this.showBackButton = true});

  final bool showBackButton;

  @override
  State<GeneralSettingsView> createState() => _GeneralSettingsViewState();
}

class _GeneralSettingsViewState extends State<GeneralSettingsView> {
  String _cacheSize = '—';
  bool _loadingCache = true;

  @override
  void initState() {
    super.initState();
    _loadCache();
  }

  Future<void> _loadCache() async {
    setState(() => _loadingCache = true);
    try {
      final stats = await TdClient.shared.query({
        '@type': 'getStorageStatisticsFast',
      });
      _cacheSize = _formatBytes(stats.int64('files_size') ?? 0);
    } catch (_) {
      _cacheSize = '—';
    }
    if (mounted) setState(() => _loadingCache = false);
  }

  static String _formatBytes(int bytes) {
    final b = bytes < 0 ? 0 : bytes;
    if (b < 1024) return '$b B';
    const units = ['KB', 'MB', 'GB'];
    var size = b / 1024;
    var i = 0;
    while (size >= 1024 && i < units.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(1)} ${units[i]}';
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPageScaffold(
      title: AppStringKeys.settingsDataAndStorage,
      showBackButton: widget.showBackButton,
      onBack: () => Navigator.of(context).pop(),
      child: SettingsListView(children: [_storageCard(), _autoDownloadCard()]),
    );
  }

  Widget _autoDownloadCard() {
    final auto = context.watch<AutoDownloadMediaController>();
    final desktop = isDesktopTargetPlatform(Theme.of(context).platform);
    return SettingsSection(
      titleKey: AppStringKeys.generalAutoDownloadMedia,
      rows: [
        if (!desktop)
          SettingsSwitchRow(
            key: const ValueKey('general-auto-download-mobile'),
            title: AppStrings.t(AppStringKeys.generalAutoDownloadMobileData),
            subtitle: auto.mobileHighResImages
                ? AppStrings.t(AppStringKeys.generalAutoDownloadHighResImages)
                : AppStrings.t(AppStringKeys.generalAutoDownloadDisabled),
            value: auto.mobileHighResImages,
            enabled: !auto.isApplying,
            leading: const SettingsLeadingIcon(
              icon: HeroAppIcons.mobileScreenButton,
            ),
            onChanged: (value) =>
                _setAutoDownload(() => auto.setMobileHighResImages(value)),
          ),
        SettingsSwitchRow(
          key: const ValueKey('general-auto-download-wifi'),
          title: AppStrings.t(AppStringKeys.generalAutoDownloadWifi),
          subtitle: auto.wifiHighResImages
              ? AppStrings.t(AppStringKeys.generalAutoDownloadHighResImages)
              : AppStrings.t(AppStringKeys.generalAutoDownloadDisabled),
          value: auto.wifiHighResImages,
          enabled: !auto.isApplying,
          leading: const SettingsLeadingIcon(icon: HeroAppIcons.image),
          onChanged: (value) =>
              _setAutoDownload(() => auto.setWifiHighResImages(value)),
        ),
        SettingsRow(
          title: AppStrings.t(AppStringKeys.generalAdvancedAutomaticDownload),
          leading: const SettingsLeadingIcon(icon: HeroAppIcons.gear),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AutoDownloadSettingsView()),
          ),
        ),
      ],
    );
  }

  Future<void> _setAutoDownload(Future<void> Function() update) async {
    try {
      await update();
    } catch (_) {
      if (mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.generalAutoDownloadFailed),
        );
      }
    }
  }

  Widget _storageCard() {
    return SettingsSection(
      titleKey: AppStringKeys.generalStorage,
      rows: [
        SettingsRow(
          title: AppStrings.t(AppStringKeys.generalCacheSize),
          value: _loadingCache ? '' : _cacheSize,
          leading: const SettingsLeadingIcon(icon: HeroAppIcons.solidFolder),
          trailing: _loadingCache
              ? const AppActivityIndicator(size: AppIconSize.md)
              : null,
          showChevron: false,
        ),
        SettingsRow(
          title: AppStrings.t(AppStringKeys.generalDetailedStorageUsage),
          leading: const SettingsLeadingIcon(icon: HeroAppIcons.compactDisc),
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const StorageUsageView())),
        ),
        SettingsRow(
          title: AppStrings.t(AppStringKeys.generalDownloads),
          leading: const SettingsLeadingIcon(icon: HeroAppIcons.download),
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const DownloadsView())),
        ),
        SettingsRow(
          title: AppStrings.t(AppStringKeys.generalNetworkUsage),
          leading: const SettingsLeadingIcon(icon: HeroAppIcons.networkWired),
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const NetworkUsageView())),
        ),
      ],
    );
  }
}

/// Mithka-only chat behavior that was previously mixed into data and storage.
class ChatBehaviorSettingsView extends StatefulWidget {
  const ChatBehaviorSettingsView({super.key});

  @override
  State<ChatBehaviorSettingsView> createState() =>
      _ChatBehaviorSettingsViewState();
}

class _ChatBehaviorSettingsViewState extends State<ChatBehaviorSettingsView> {
  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    final supportsInternalBrowser = internalBrowserSupported(
      platform: Theme.of(context).platform,
    );
    final selectedLinkMode = supportsInternalBrowser
        ? theme.linkOpenMode
        : LinkOpenMode.defaultBrowser;
    final linkModes = supportsInternalBrowser
        ? const [
            LinkOpenMode.askEveryTime,
            LinkOpenMode.internalBrowser,
            LinkOpenMode.defaultBrowser,
          ]
        : const [LinkOpenMode.defaultBrowser];
    return SettingsPageScaffold(
      title: AppStringKeys.settingsChatBehavior,
      onBack: () => Navigator.of(context).pop(),
      child: SettingsListView(
        children: [
          SettingsCard.rows(
            rows: [
              SettingsSwitchRow(
                key: const ValueKey('chat-behavior-enter-to-send'),
                title: AppStringKeys.generalSendMessageWithEnter,
                value: theme.enterToSend,
                leading: const SettingsLeadingIcon(icon: HeroAppIcons.reply),
                onChanged: (value) => theme.enterToSend = value,
              ),
              SettingsSwitchRow(
                key: const ValueKey('chat-behavior-open-at-latest'),
                title: AppStringKeys.generalOpenChatAtLatestMessage,
                value: theme.openChatsAtLatest,
                leading: const SettingsLeadingIcon(icon: HeroAppIcons.download),
                onChanged: (value) => theme.openChatsAtLatest = value,
              ),
              SettingsSwitchRow(
                key: const ValueKey('chat-behavior-saved-messages-identity'),
                title: AppStringKeys.generalShowSavedMessagesIdentity,
                value: theme.showSavedMessagesIdentity,
                leading: const SettingsLeadingIcon(icon: HeroAppIcons.bookmark),
                onChanged: (value) => theme.showSavedMessagesIdentity = value,
              ),
              SettingsSwitchRow(
                key: const ValueKey('chat-behavior-preserve-sender'),
                title: AppStringKeys.generalRepeatPreserveSender,
                value: theme.preserveSenderWhenRepeating,
                leading: const SettingsLeadingIcon(
                  icon: HeroAppIcons.arrowsRotate,
                ),
                onChanged: (value) => theme.preserveSenderWhenRepeating = value,
              ),
              // Only mobile composers offer a camera button, so only they can
              // put a capture in the system album.
              if (!isDesktopTargetPlatform(Theme.of(context).platform))
                SettingsSwitchRow(
                  key: const ValueKey('chat-behavior-save-captured-photos'),
                  title: AppStringKeys.generalSaveCapturedPhotos,
                  subtitle: AppStringKeys.generalSaveCapturedPhotosHint,
                  value: theme.saveCapturedPhotosToAlbum,
                  leading: const SettingsLeadingIcon(icon: HeroAppIcons.camera),
                  onChanged: (value) => theme.saveCapturedPhotosToAlbum = value,
                ),
              SettingsSwitchRow(
                key: const ValueKey('chat-behavior-quick-replies'),
                title: AppStringKeys.businessToolsQuickReplies,
                value: theme.quickRepliesEnabled,
                leading: const SettingsLeadingIcon(
                  icon: HeroAppIcons.solidMessage,
                ),
                onChanged: (value) => theme.quickRepliesEnabled = value,
              ),
              SettingsSelectionRow<LinkOpenMode>(
                key: const ValueKey('chat-behavior-link-browser'),
                title: AppStrings.t(AppStringKeys.linkBrowserOpenLinksIn),
                value: AppStrings.t(selectedLinkMode.label),
                menuTitle: AppStringKeys.linkBrowserOpenLinksIn,
                menuKey: const ValueKey('link-browser-setting-menu'),
                leading: const SettingsLeadingIcon(icon: HeroAppIcons.globe),
                enabled: supportsInternalBrowser,
                options: [
                  for (final mode in linkModes)
                    SettingsSelectionOption<LinkOpenMode>(
                      id: 'link-browser-mode-${mode.name}',
                      value: mode,
                      label: AppStrings.t(mode.label),
                      subtitle: AppStrings.t(mode.description),
                      icon: mode.icon,
                    ),
                ],
                isSelected: (mode) => mode == selectedLinkMode,
                onSelected: (mode) => theme.linkOpenMode = mode,
              ),
              SettingsRow(
                key: const ValueKey('chat-behavior-video-playback'),
                title: AppStringKeys.videoPlaybackSettingsTitle,
                leading: const SettingsLeadingIcon(icon: HeroAppIcons.video),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const VideoPlaybackSettingsView(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
