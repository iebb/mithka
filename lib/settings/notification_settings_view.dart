//
//  notification_settings_view.dart
//
//  消息通知 — per-scope mute toggles + preview/sound, wired to TDLib
//  getScopeNotificationSettings / setScopeNotificationSettings. Port of the
//  Swift `NotificationSettingsView`.
//

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../theme/app_theme.dart';

class NotificationSettingsView extends StatefulWidget {
  const NotificationSettingsView({super.key});

  @override
  State<NotificationSettingsView> createState() =>
      _NotificationSettingsViewState();
}

class _NotificationSettingsViewState extends State<NotificationSettingsView> {
  static const _muteForever = 365 * 24 * 60 * 60;

  final TdClient _client = TdClient.shared;
  // Current scopeNotificationSettings object per scope @type.
  final Map<String, Map<String, dynamic>> _settings = {};
  bool _loading = true;

  static const _private = 'notificationSettingsScopePrivateChats';
  static const _group = 'notificationSettingsScopeGroupChats';
  static const _channel = 'notificationSettingsScopeChannelChats';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    for (final scope in const [_private, _group, _channel]) {
      try {
        final s = await _client.query({
          '@type': 'getScopeNotificationSettings',
          'scope': {'@type': scope},
        });
        _settings[scope] = Map<String, dynamic>.from(s);
      } catch (_) {}
    }
    if (mounted) setState(() => _loading = false);
  }

  bool _enabled(String scope) =>
      (_settings[scope]?.integer('mute_for') ?? 0) == 0;

  bool _preview(String scope) =>
      _settings[scope]?.boolean('show_preview') ?? true;

  bool _hasSound(String scope) =>
      (_settings[scope]?.int64('sound_id') ?? 0) != 0;

  Future<void> _push(String scope) async {
    final s = _settings[scope];
    if (s == null) return;
    try {
      await _client.query({
        '@type': 'setScopeNotificationSettings',
        'scope': {'@type': scope},
        'notification_settings': {
          '@type': 'scopeNotificationSettings',
          'mute_for': s.integer('mute_for') ?? 0,
          'sound_id': s.int64('sound_id') ?? 0,
          'show_preview': s.boolean('show_preview') ?? true,
          'use_default_mute_stories':
              s.boolean('use_default_mute_stories') ?? true,
          'mute_stories': s.boolean('mute_stories') ?? false,
          'story_sound_id': s.int64('story_sound_id') ?? 0,
          'show_story_sender': s.boolean('show_story_sender') ?? true,
          'disable_pinned_message_notifications':
              s.boolean('disable_pinned_message_notifications') ?? false,
          'disable_mention_notifications':
              s.boolean('disable_mention_notifications') ?? false,
        },
      });
    } catch (_) {}
  }

  void _toggleMute(String scope, bool on) {
    setState(() => _settings[scope]?['mute_for'] = on ? 0 : _muteForever);
    _push(scope);
  }

  void _togglePreview(String scope, bool on) {
    setState(() => _settings[scope]?['show_preview'] = on);
    _push(scope);
  }

  void _toggleSound(String scope, bool on) {
    setState(() => _settings[scope]?['sound_id'] = on ? 0 : -1);
    _push(scope);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.notificationTitle),
            onBack: () => Navigator.of(context).pop(),
          ),
          if (_loading)
            const Expanded(
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                ),
              ),
            )
          else
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
                children: [
                  _card([
                    _toggle(
                      HeroAppIcons.circleUser.data,
                      const Color(0xFF3C8CF0),
                      AppStrings.t(AppStringKeys.notificationPrivateMessages),
                      _enabled(_private),
                      (v) => _toggleMute(_private, v),
                    ),
                    const InsetDivider(leadingInset: 56),
                    _toggle(
                      HeroAppIcons.users.data,
                      const Color(0xFF16B05A),
                      AppStrings.t(AppStringKeys.notificationGroupMessages),
                      _enabled(_group),
                      (v) => _toggleMute(_group, v),
                    ),
                    const InsetDivider(leadingInset: 56),
                    _toggle(
                      HeroAppIcons.grip.data,
                      const Color(0xFFFF9D2E),
                      AppStrings.t(AppStringKeys.topicChatChannelMessages),
                      _enabled(_channel),
                      (v) => _toggleMute(_channel, v),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  _card([
                    _toggle(
                      HeroAppIcons.file.data,
                      const Color(0xFF8E7BFF),
                      AppStrings.t(AppStringKeys.notificationPreview),
                      _preview(_private),
                      (v) => _togglePreview(_private, v),
                    ),
                    const InsetDivider(leadingInset: 56),
                    _toggle(
                      HeroAppIcons.volumeHigh.data,
                      const Color(0xFFF5A623),
                      AppStrings.t(AppStringKeys.notificationSound),
                      _hasSound(_private),
                      (v) => _toggleSound(_private, v),
                    ),
                  ]),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _card(List<Widget> children) => Container(
    decoration: BoxDecoration(
      color: context.colors.card,
      borderRadius: BorderRadius.circular(12),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(children: children),
  );

  Widget _toggle(
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
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(icon, size: 15, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Text(title, style: TextStyle(fontSize: 16, color: c.textPrimary)),
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
}
