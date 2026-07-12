//
//  general_settings_view.dart
//
//  通用 (General): storage controls and general chat preference toggles. Port
//  of the Swift `GeneralSettingsView` / `GeneralSettingsViewModel`.
//

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../components/app_icons.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'auto_download_media_controller.dart';
import 'rich_message_relay_config.dart';
import 'rich_message_relay_view.dart';

class GeneralSettingsView extends StatefulWidget {
  const GeneralSettingsView({super.key});

  @override
  State<GeneralSettingsView> createState() => _GeneralSettingsViewState();
}

class _GeneralSettingsViewState extends State<GeneralSettingsView> {
  String _cacheSize = '—';
  bool _loadingCache = true;
  bool _clearing = false;
  bool _enterToSend = false;
  bool _richMessageRelayConfigured = false;
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _loadCache();
  }

  Future<void> _loadPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    final relayConfigured = await RichMessageRelayConfig.isConfigured();
    if (!mounted) return;
    setState(() {
      _enterToSend = _prefs!.getBool('enterToSend') ?? false;
      _richMessageRelayConfigured = relayConfigured;
    });
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

  Future<void> _clearCache() async {
    setState(() => _clearing = true);
    TdClient.shared.send({
      '@type': 'optimizeStorage',
      'size': 0,
      'ttl': 0,
      'count': 0,
      'immunity_delay': 0,
      'chat_limit': 0,
      'return_deleted_file_statistics': false,
    });
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) setState(() => _clearing = false);
    await _loadCache();
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
            title: AppStrings.t(AppStringKeys.generalTitle),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
              children: [
                _storageCard(),
                const SizedBox(height: 14),
                _autoDownloadCard(),
                const SizedBox(height: 14),
                _richMessageCard(),
                const SizedBox(height: 14),
                _chatCard(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _richMessageCard() {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(AppStringKeys.richTextRelayBotTitle),
        _card([
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () async {
              await Navigator.of(context).push<void>(
                PageRouteBuilder<void>(
                  pageBuilder: (_, _, _) => const RichMessageRelayView(),
                  transitionsBuilder: (_, animation, _, child) =>
                      FadeTransition(opacity: animation, child: child),
                ),
              );
              final configured = await RichMessageRelayConfig.isConfigured();
              if (mounted) {
                setState(() => _richMessageRelayConfigured = configured);
              }
            },
            child: SizedBox(
              height: 56,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _iconBadge(HeroAppIcons.key.data, const Color(0xFF8E7BFF)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        AppStringKeys.richTextRelayBotTitle.l10n(context),
                        style: TextStyle(fontSize: 16, color: c.textPrimary),
                      ),
                    ),
                    Text(
                      (_richMessageRelayConfigured
                              ? AppStringKeys.richTextRelayBotConfigured
                              : AppStringKeys.richTextRelayBotNotConfigured)
                          .l10n(context),
                      style: TextStyle(fontSize: 14, color: c.textSecondary),
                    ),
                    const SizedBox(width: 8),
                    AppIcon(
                      HeroAppIcons.chevronRight,
                      size: AppIconSize.chevron,
                      color: c.textTertiary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ]),
      ],
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
            HeroAppIcons.mobileScreenButton.data,
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
            HeroAppIcons.image.data,
            const Color(0xFF1D9BF0),
            AppStrings.t(AppStringKeys.generalAutoDownloadWifi),
            auto.wifiHighResImages
                ? AppStrings.t(AppStringKeys.generalAutoDownloadHighResImages)
                : AppStrings.t(AppStringKeys.generalAutoDownloadDisabled),
            auto.wifiHighResImages,
            auto.isApplying,
            (value) => _setAutoDownload(() => auto.setWifiHighResImages(value)),
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

  Widget _iconBadge(IconData icon, Color color) => Container(
    width: 28,
    height: 28,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(7),
    ),
    child: Icon(icon, size: 15, color: Colors.white),
  );

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
                  _iconBadge(
                    HeroAppIcons.solidFolder.data,
                    const Color(0xFF16B0A0),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    AppStrings.t(AppStringKeys.generalCacheSize),
                    style: TextStyle(fontSize: 16, color: c.textPrimary),
                  ),
                  const Spacer(),
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
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _clearing || _loadingCache ? null : _clearCache,
            child: SizedBox(
              height: 52,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text(
                      _clearing
                          ? AppStrings.t(AppStringKeys.generalClearingCache)
                          : AppStrings.t(AppStringKeys.generalClearCache),
                      style: TextStyle(fontSize: 16, color: AppTheme.tagRed),
                    ),
                    const Spacer(),
                    if (_clearing)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _chatCard() {
    final theme = context.watch<ThemeController>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(AppStrings.t(AppStringKeys.audioSearchChatTab)),
        _card([
          _toggleRow(
            HeroAppIcons.reply.data,
            const Color(0xFF3C8CF0),
            AppStrings.t(AppStringKeys.generalSendMessageWithEnter),
            _enterToSend,
            (v) {
              setState(() => _enterToSend = v);
              _prefs?.setBool('enterToSend', v);
            },
          ),
          const InsetDivider(leadingInset: 56),
          _toggleRow(
            HeroAppIcons.download.data,
            const Color(0xFF3C8CF0),
            AppStrings.t(AppStringKeys.generalOpenChatAtLatestMessage),
            theme.openChatsAtLatest,
            (v) => theme.openChatsAtLatest = v,
          ),
          const InsetDivider(leadingInset: 56),
          _toggleRow(
            HeroAppIcons.arrowsRotate.data,
            const Color(0xFF16B0A0),
            AppStrings.t(AppStringKeys.generalRepeatPreserveSender),
            theme.preserveSenderWhenRepeating,
            (v) => theme.preserveSenderWhenRepeating = v,
          ),
        ]),
      ],
    );
  }

  Widget _toggleRow(
    IconData icon,
    Color color,
    String title,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    final c = context.colors;
    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            _iconBadge(icon, color),
            const SizedBox(width: 12),
            Text(
              title.l10n(context),
              style: TextStyle(fontSize: 16, color: c.textPrimary),
            ),
            const Spacer(),
            CupertinoSwitch(
              value: value,
              activeTrackColor: AppTheme.brand,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }

  Widget _toggleRowWithSubtitle(
    IconData icon,
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
            CupertinoSwitch(
              value: value,
              activeTrackColor: AppTheme.brand,
              onChanged: disabled ? null : onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
