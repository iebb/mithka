//
//  general_settings_view.dart
//
//  Data and storage controls plus Mithka's separate chat-behavior settings.
//  Port of the Swift `GeneralSettingsView` / `GeneralSettingsViewModel`.
//

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../components/app_icons.dart';
import '../components/desktop_content_constraint.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
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
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStringKeys.settingsDataAndStorage,
            onBack: widget.showBackButton && Navigator.of(context).canPop()
                ? () => Navigator.of(context).pop()
                : null,
          ),
          Expanded(
            child: DesktopContentConstraint(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
                children: [
                  _storageCard(),
                  const SizedBox(height: 14),
                  _autoDownloadCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
    padding: const EdgeInsets.only(left: 16, bottom: 6),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title.l10n(context),
        style: TextStyle(fontSize: 13, color: context.colors.textTertiary),
      ),
    ),
  );

  Widget _autoDownloadCard() {
    final auto = context.watch<AutoDownloadMediaController>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(AppStrings.t(AppStringKeys.generalAutoDownloadMedia)),
        _card([
          _toggleRowWithSubtitle(
            HeroAppIcons.mobileScreenButton,
            const Color(0xFF34C759),
            AppStrings.t(AppStringKeys.generalAutoDownloadMobileData),
            auto.mobileHighResImages
                ? AppStrings.t(AppStringKeys.generalAutoDownloadHighResImages)
                : AppStrings.t(AppStringKeys.generalAutoDownloadDisabled),
            auto.mobileHighResImages,
            auto.isApplying,
            (value) =>
                _setAutoDownload(() => auto.setMobileHighResImages(value)),
          ),
          const InsetDivider(leadingInset: 56),
          _toggleRowWithSubtitle(
            HeroAppIcons.image,
            const Color(0xFF1D9BF0),
            AppStrings.t(AppStringKeys.generalAutoDownloadWifi),
            auto.wifiHighResImages
                ? AppStrings.t(AppStringKeys.generalAutoDownloadHighResImages)
                : AppStrings.t(AppStringKeys.generalAutoDownloadDisabled),
            auto.wifiHighResImages,
            auto.isApplying,
            (value) => _setAutoDownload(() => auto.setWifiHighResImages(value)),
          ),
          const InsetDivider(leadingInset: 56),
          _navigationRow(
            HeroAppIcons.gear,
            const Color(0xFFAF52DE),
            AppStrings.t(AppStringKeys.generalAdvancedAutomaticDownload),
            () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const AutoDownloadSettingsView(),
              ),
            ),
          ),
        ]),
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

  Widget _iconBadge(AppIconData icon, Color color) =>
      SettingsIconTile(icon: icon, backgroundColor: color);

  Widget _card(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _storageCard() {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(AppStrings.t(AppStringKeys.generalStorage)),
        _card([
          SizedBox(
            height: 52,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _iconBadge(HeroAppIcons.solidFolder, const Color(0xFF16B0A0)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      AppStrings.t(AppStringKeys.generalCacheSize),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 16, color: c.textPrimary),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (_loadingCache)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Text(
                      _cacheSize,
                      style: TextStyle(fontSize: 15, color: c.textSecondary),
                    ),
                ],
              ),
            ),
          ),
          const InsetDivider(leadingInset: 56),
          _navigationRow(
            HeroAppIcons.compactDisc,
            const Color(0xFF16B0A0),
            AppStrings.t(AppStringKeys.generalDetailedStorageUsage),
            () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const StorageUsageView())),
          ),
          const InsetDivider(leadingInset: 56),
          _navigationRow(
            HeroAppIcons.download,
            const Color(0xFF3C8CF0),
            AppStrings.t(AppStringKeys.generalDownloads),
            () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const DownloadsView())),
          ),
          const InsetDivider(leadingInset: 56),
          _navigationRow(
            HeroAppIcons.networkWired,
            const Color(0xFFFF9500),
            AppStrings.t(AppStringKeys.generalNetworkUsage),
            () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const NetworkUsageView())),
          ),
        ]),
      ],
    );
  }

  Widget _navigationRow(
    AppIconData icon,
    Color color,
    String title,
    VoidCallback onTap,
  ) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _iconBadge(icon, color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title.l10n(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, color: c.textPrimary),
                ),
              ),
              const SizedBox(width: 8),
              AppIcon(
                HeroAppIcons.chevronRight,
                size: 17,
                color: c.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toggleRowWithSubtitle(
    AppIconData icon,
    Color color,
    String title,
    String subtitle,
    bool value,
    bool disabled,
    ValueChanged<bool> onChanged,
  ) {
    final c = context.colors;
    return SizedBox(
      height: 66,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            _iconBadge(icon, color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.l10n(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 17, color: c.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle.l10n(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, color: c.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            AppSwitch(
              value: value,
              enabled: !disabled,
              semanticLabel: title.l10n(context),
              onChanged: onChanged,
            ),
          ],
        ),
      ),
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
  SettingsIconTile _icon(AppIconData icon, Color color) =>
      SettingsIconTile(icon: icon, backgroundColor: color);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = context.watch<ThemeController>();
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStringKeys.settingsChatBehavior,
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: DesktopContentConstraint(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
                children: [
                  SettingsCard(
                    children: [
                      SettingsSwitchRow(
                        key: const ValueKey('chat-behavior-enter-to-send'),
                        title: AppStringKeys.generalSendMessageWithEnter,
                        value: theme.enterToSend,
                        leading: _icon(
                          HeroAppIcons.reply,
                          const Color(0xFF3C8CF0),
                        ),
                        onChanged: (value) => theme.enterToSend = value,
                      ),
                      const InsetDivider(leadingInset: 56),
                      SettingsSwitchRow(
                        key: const ValueKey('chat-behavior-open-at-latest'),
                        title: AppStringKeys.generalOpenChatAtLatestMessage,
                        value: theme.openChatsAtLatest,
                        leading: _icon(
                          HeroAppIcons.download,
                          const Color(0xFF3C8CF0),
                        ),
                        onChanged: (value) => theme.openChatsAtLatest = value,
                      ),
                      const InsetDivider(leadingInset: 56),
                      SettingsSwitchRow(
                        key: const ValueKey('chat-behavior-preserve-sender'),
                        title: AppStringKeys.generalRepeatPreserveSender,
                        value: theme.preserveSenderWhenRepeating,
                        leading: _icon(
                          HeroAppIcons.arrowsRotate,
                          const Color(0xFF16B0A0),
                        ),
                        onChanged: (value) =>
                            theme.preserveSenderWhenRepeating = value,
                      ),
                      const InsetDivider(leadingInset: 56),
                      SettingsSwitchRow(
                        key: const ValueKey('chat-behavior-quick-replies'),
                        title: AppStringKeys.businessToolsQuickReplies,
                        value: theme.quickRepliesEnabled,
                        leading: _icon(
                          HeroAppIcons.solidMessage,
                          const Color(0xFF34C759),
                        ),
                        onChanged: (value) => theme.quickRepliesEnabled = value,
                      ),
                      const InsetDivider(leadingInset: 56),
                      SettingsRow(
                        key: const ValueKey('chat-behavior-video-playback'),
                        title: AppStringKeys.videoPlaybackSettingsTitle,
                        leading: _icon(
                          HeroAppIcons.video,
                          const Color(0xFFAF52DE),
                        ),
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
            ),
          ),
        ],
      ),
    );
  }
}
