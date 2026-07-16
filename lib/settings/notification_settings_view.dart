//
//  notification_settings_view.dart
//
//  Telegram-style notification settings backed by TDLib scope, story, and
//  reaction settings plus Mithka's foreground presentation preferences.
//

import 'dart:async';

import 'package:flutter/material.dart';

import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../notifications/notification_preferences.dart';
import '../notifications/notification_settings_payload.dart';
import '../notifications/scope_notification_settings.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../theme/app_theme.dart';

String _notificationExceptionCount(int count) => AppStrings.t(
  count == 1
      ? AppStringKeys.notificationException
      : AppStringKeys.notificationExceptions,
  {'value1': count},
);

class NotificationSettingsView extends StatefulWidget {
  const NotificationSettingsView({super.key});

  @override
  State<NotificationSettingsView> createState() =>
      _NotificationSettingsViewState();
}

class _NotificationSettingsViewState extends State<NotificationSettingsView> {
  static const _private = 'notificationSettingsScopePrivateChats';
  static const _group = 'notificationSettingsScopeGroupChats';
  static const _channel = 'notificationSettingsScopeChannelChats';

  final TdClient _client = TdClient.shared;
  final NotificationPreferences _preferences = NotificationPreferences.shared;
  final Map<String, Map<String, dynamic>> _settings = {};
  final Map<String, int> _exceptionCounts = {};
  Map<String, dynamic> _reactionSettings = reactionNotificationSettingsPayload(
    const {},
  );
  int _defaultSoundId = 0;
  StreamSubscription<Map<String, dynamic>>? _updates;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _preferences.addListener(_preferencesChanged);
    _updates = _client.subscribe().listen(_handleUpdate);
    unawaited(_load());
  }

  @override
  void dispose() {
    _preferences.removeListener(_preferencesChanged);
    unawaited(_updates?.cancel());
    super.dispose();
  }

  void _preferencesChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final loadedSettings = <String, Map<String, dynamic>>{};
    final loadedExceptions = <String, int>{};
    for (final scope in const [_private, _group, _channel]) {
      try {
        final result = await _client.query({
          '@type': 'getScopeNotificationSettings',
          'scope': {'@type': scope},
        });
        loadedSettings[scope] = Map<String, dynamic>.from(result);
      } catch (_) {}
      try {
        final result = await _client.query({
          '@type': 'getChatNotificationSettingsExceptions',
          'scope': {'@type': scope},
          'compare_sound': true,
        });
        loadedExceptions[scope] =
            result.int64Array('chat_ids')?.length ??
            result.integer('total_count') ??
            0;
      } catch (_) {
        loadedExceptions[scope] = 0;
      }
    }

    var defaultSoundId = loadedSettings.values
        .map((settings) => settings.int64('sound_id') ?? 0)
        .firstWhere((id) => id > 0, orElse: () => 0);
    if (defaultSoundId == 0) {
      try {
        final sounds = await _client.query({
          '@type': 'getSavedNotificationSounds',
        });
        defaultSoundId =
            sounds
                .objects('notification_sounds')
                ?.map((sound) => sound.int64('id') ?? 0)
                .firstWhere((id) => id > 0, orElse: () => 0) ??
            0;
      } catch (_) {}
    }

    Map<String, dynamic>? reactionSettings;
    try {
      final currentState = await _client.query({'@type': 'getCurrentState'});
      for (final update
          in currentState.objects('updates') ??
              const <Map<String, dynamic>>[]) {
        if (update.type == 'updateReactionNotificationSettings') {
          reactionSettings = update.obj('notification_settings');
        }
      }
    } catch (_) {}

    try {
      final storyExceptions = await _client.query({
        '@type': 'getStoryNotificationSettingsExceptions',
      });
      loadedExceptions['stories'] =
          storyExceptions.int64Array('chat_ids')?.length ??
          storyExceptions.integer('total_count') ??
          0;
    } catch (_) {
      loadedExceptions['stories'] = 0;
    }

    if (!mounted) return;
    setState(() {
      _settings.addAll(loadedSettings);
      _exceptionCounts.addAll(loadedExceptions);
      if (reactionSettings != null) {
        _reactionSettings = Map<String, dynamic>.from(reactionSettings);
      }
      _defaultSoundId = defaultSoundId;
      _loading = false;
    });
  }

  void _handleUpdate(Map<String, dynamic> update) {
    if (!mounted) return;
    if (update.type == 'updateScopeNotificationSettings') {
      final scope = update.obj('scope')?.type;
      final settings = update.obj('notification_settings');
      if (scope == null || settings == null) return;
      setState(() => _settings[scope] = Map<String, dynamic>.from(settings));
      return;
    }
    if (update.type == 'updateReactionNotificationSettings') {
      final settings = update.obj('notification_settings');
      if (settings != null) {
        setState(() => _reactionSettings = Map<String, dynamic>.from(settings));
      }
    }
  }

  bool _enabled(String scope) =>
      (_settings[scope]?.integer('mute_for') ?? 0) == 0;

  String _enabledLabel(bool enabled) => AppStrings.t(
    enabled ? AppStringKeys.privacyEnabled : AppStringKeys.privacyDisabled,
  );

  String _exceptionsLabel(String key) {
    final count = _exceptionCounts[key] ?? 0;
    if (count == 0) return '';
    return _notificationExceptionCount(count);
  }

  Future<void> _setScopeSettings(
    String scope,
    Map<String, dynamic> settings,
  ) async {
    final copy = Map<String, dynamic>.from(settings);
    setState(() => _settings[scope] = copy);
    ScopeNotificationSettings.shared.update(
      scope,
      copy.integer('mute_for') ?? 0,
    );
    ScopeNotificationSettings.shared.updateShowPreview(
      scope,
      copy.boolean('show_preview') ?? true,
    );
    ScopeNotificationSettings.shared.updateSoundId(
      scope,
      copy.int64('sound_id') ?? 0,
    );
    try {
      await _client.query({
        '@type': 'setScopeNotificationSettings',
        'scope': {'@type': scope},
        'notification_settings': scopeNotificationSettingsPayload(copy),
      });
    } catch (_) {}
  }

  Future<void> _setReactionSettings(Map<String, dynamic> settings) async {
    final copy = Map<String, dynamic>.from(settings);
    setState(() => _reactionSettings = copy);
    try {
      await _client.query({
        '@type': 'setReactionNotificationSettings',
        'notification_settings': reactionNotificationSettingsPayload(copy),
      });
    } catch (_) {}
  }

  void _openScope(String scope, String title) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ScopeNotificationSettingsView(
          title: title,
          settings: Map<String, dynamic>.from(_settings[scope] ?? const {}),
          exceptionCount: _exceptionCounts[scope] ?? 0,
          defaultSoundId: _defaultSoundId,
          onChanged: (settings) => _setScopeSettings(scope, settings),
        ),
      ),
    );
  }

  void _openStories() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _StoryNotificationSettingsView(
          settings: Map<String, dynamic>.from(_settings[_private] ?? const {}),
          exceptionCount: _exceptionCounts['stories'] ?? 0,
          defaultSoundId: _defaultSoundId,
          onChanged: (settings) => _setScopeSettings(_private, settings),
        ),
      ),
    );
  }

  void _openReactions() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ReactionNotificationSettingsView(
          settings: Map<String, dynamic>.from(_reactionSettings),
          defaultSoundId: _defaultSoundId,
          onChanged: _setReactionSettings,
        ),
      ),
    );
  }

  String get _storySummary {
    return switch (storyNotificationMode(_settings[_private])) {
      StoryNotificationMode.topFive => AppStrings.t(
        AppStringKeys.notificationTopFive,
      ),
      StoryNotificationMode.all => AppStrings.t(AppStringKeys.privacyEnabled),
      StoryNotificationMode.off => AppStrings.t(AppStringKeys.privacyDisabled),
    };
  }

  String get _reactionSummary {
    final labels = <String>[];
    if (reactionSourceEnabled(
      _reactionSettings.obj('message_reaction_source'),
    )) {
      labels.add(AppStrings.t(AppStringKeys.notificationReactionMessages));
    }
    if (reactionSourceEnabled(_reactionSettings.obj('story_reaction_source'))) {
      labels.add(AppStrings.t(AppStringKeys.notificationStories));
    }
    return labels.isEmpty
        ? AppStrings.t(AppStringKeys.privacyDisabled)
        : labels.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.notificationNotifications),
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
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
                children: [
                  if (_client.configuredSlots.length > 1) ...[
                    _sectionTitle(
                      AppStrings.t(
                        AppStringKeys.notificationShowNotificationsFrom,
                      ),
                    ),
                    _card([
                      _plainSwitchRow(
                        AppStrings.t(AppStringKeys.notificationAllAccounts),
                        _preferences.allAccounts,
                        _preferences.setAllAccounts,
                      ),
                    ]),
                    _footnote(
                      AppStrings.t(
                        _preferences.allAccounts
                            ? AppStringKeys.notificationAllAccountsDescription
                            : AppStringKeys
                                  .notificationAllAccountsDescriptionOff,
                      ),
                    ),
                  ],
                  _sectionTitle(
                    AppStrings.t(
                      AppStringKeys.notificationMessageNotifications,
                    ),
                  ),
                  _card([
                    _navigationRow(
                      icon: HeroAppIcons.circleUser,
                      color: const Color(0xFF3295F6),
                      title: AppStrings.t(
                        AppStringKeys.notificationPrivateMessages,
                      ),
                      subtitle: _exceptionsLabel(_private),
                      value: _enabledLabel(_enabled(_private)),
                      onTap: () => _openScope(
                        _private,
                        AppStrings.t(AppStringKeys.notificationPrivateMessages),
                      ),
                    ),
                    const InsetDivider(leadingInset: 62),
                    _navigationRow(
                      icon: HeroAppIcons.users,
                      color: const Color(0xFF37C961),
                      title: AppStrings.t(
                        AppStringKeys.notificationGroupMessages,
                      ),
                      subtitle: _exceptionsLabel(_group),
                      value: _enabledLabel(_enabled(_group)),
                      onTap: () => _openScope(
                        _group,
                        AppStrings.t(AppStringKeys.notificationGroupMessages),
                      ),
                    ),
                    const InsetDivider(leadingInset: 62),
                    _navigationRow(
                      icon: HeroAppIcons.towerBroadcast,
                      color: const Color(0xFFFFA928),
                      title: AppStrings.t(AppStringKeys.notificationChannels),
                      subtitle: _exceptionsLabel(_channel),
                      value: _enabledLabel(_enabled(_channel)),
                      onTap: () => _openScope(
                        _channel,
                        AppStrings.t(AppStringKeys.notificationChannels),
                      ),
                    ),
                    const InsetDivider(leadingInset: 62),
                    _navigationRow(
                      icon: HeroAppIcons.circleNotch,
                      color: const Color(0xFF6B63F6),
                      title: AppStrings.t(AppStringKeys.notificationStories),
                      subtitle: _exceptionsLabel('stories'),
                      value: _storySummary,
                      onTap: _openStories,
                    ),
                    const InsetDivider(leadingInset: 62),
                    _navigationRow(
                      icon: HeroAppIcons.heart,
                      color: const Color(0xFFFF3C69),
                      title: AppStrings.t(AppStringKeys.notificationReactions),
                      subtitle: _reactionSummary,
                      value: _enabledLabel(
                        reactionSourceEnabled(
                              _reactionSettings.obj('message_reaction_source'),
                            ) ||
                            reactionSourceEnabled(
                              _reactionSettings.obj('story_reaction_source'),
                            ),
                      ),
                      onTap: _openReactions,
                    ),
                  ]),
                  _sectionTitle(
                    AppStrings.t(AppStringKeys.notificationInAppSection),
                  ),
                  _card([
                    _plainSwitchRow(
                      AppStrings.t(AppStringKeys.notificationInAppSounds),
                      _preferences.inAppSounds,
                      _preferences.setInAppSounds,
                    ),
                    const InsetDivider(leadingInset: 16),
                    _plainSwitchRow(
                      AppStrings.t(AppStringKeys.notificationInAppVibrate),
                      _preferences.inAppVibrate,
                      _preferences.setInAppVibrate,
                    ),
                    const InsetDivider(leadingInset: 16),
                    _plainSwitchRow(
                      AppStrings.t(AppStringKeys.notificationInAppPreview),
                      _preferences.inAppPreview,
                      _preferences.setInAppPreview,
                    ),
                  ]),
                  const SizedBox(height: 22),
                  _card([
                    _plainSwitchRow(
                      AppStrings.t(AppStringKeys.notificationNamesOnLockScreen),
                      _preferences.namesOnLockScreen,
                      _preferences.setNamesOnLockScreen,
                    ),
                  ]),
                  _footnote(
                    AppStrings.t(
                      AppStringKeys.notificationNamesOnLockScreenDescription,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 12, 8),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        color: context.colors.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.2,
      ),
    ),
  );

  Widget _footnote(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 14, 2),
    child: Text(
      text,
      style: TextStyle(
        color: context.colors.textSecondary,
        fontSize: 12.5,
        height: 1.3,
      ),
    ),
  );

  Widget _card(List<Widget> children) => Container(
    decoration: BoxDecoration(
      color: context.colors.card,
      borderRadius: BorderRadius.circular(18),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(children: children),
  );

  Widget _plainSwitchRow(
    String title,
    bool value,
    Future<void> Function(bool) onChanged,
  ) => SizedBox(
    height: 58,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(color: context.colors.textPrimary, fontSize: 16),
            ),
          ),
          _NotificationToggle(
            value: value,
            onChanged: (v) => unawaited(onChanged(v)),
          ),
        ],
      ),
    ),
  );

  Widget _navigationRow({
    required AppIconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required String value,
    required VoidCallback onTap,
  }) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 68,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              SettingsIconTile(
                icon: icon,
                backgroundColor: color,
                size: 32,
                iconSize: 18,
                radius: 9,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.textPrimary, fontSize: 16),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.textSecondary, fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                value,
                style: TextStyle(color: c.textSecondary, fontSize: 15),
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
}

class _ScopeNotificationSettingsView extends StatefulWidget {
  const _ScopeNotificationSettingsView({
    required this.title,
    required this.settings,
    required this.exceptionCount,
    required this.defaultSoundId,
    required this.onChanged,
  });

  final String title;
  final Map<String, dynamic> settings;
  final int exceptionCount;
  final int defaultSoundId;
  final Future<void> Function(Map<String, dynamic>) onChanged;

  @override
  State<_ScopeNotificationSettingsView> createState() =>
      _ScopeNotificationSettingsViewState();
}

class _ScopeNotificationSettingsViewState
    extends State<_ScopeNotificationSettingsView> {
  static const _muteForever = 365 * 24 * 60 * 60;
  late final Map<String, dynamic> _settings = Map.from(widget.settings);

  void _set(String key, Object value) {
    setState(() => _settings[key] = value);
    unawaited(widget.onChanged(_settings));
  }

  void _setSound(bool enabled) {
    final current = _settings.int64('sound_id') ?? 0;
    _set(
      'sound_id',
      enabled ? (current > 0 ? current : widget.defaultSoundId) : 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = (_settings.integer('mute_for') ?? 0) == 0;
    final hasNotifications = enabled || widget.exceptionCount > 0;
    return _NotificationDetailScaffold(
      title: widget.title,
      children: [
        _NotificationCard(
          children: [
            _NotificationSwitchRow(
              title: AppStrings.t(AppStringKeys.notificationNotifications),
              value: enabled,
              onChanged: (value) => _set('mute_for', value ? 0 : _muteForever),
            ),
          ],
        ),
        if (hasNotifications) ...[
          _NotificationSectionTitle(
            AppStrings.t(AppStringKeys.notificationOptions),
          ),
          _NotificationCard(
            children: [
              _NotificationSwitchRow(
                title: AppStrings.t(AppStringKeys.notificationPreview),
                value: _settings.boolean('show_preview') ?? true,
                enabled: hasNotifications,
                onChanged: (value) => _set('show_preview', value),
              ),
              const InsetDivider(leadingInset: 16),
              _NotificationSwitchRow(
                title: AppStrings.t(AppStringKeys.notificationSound),
                value: (_settings.int64('sound_id') ?? 0) > 0,
                enabled:
                    hasNotifications &&
                    ((_settings.int64('sound_id') ?? 0) > 0 ||
                        widget.defaultSoundId > 0),
                onChanged: _setSound,
              ),
            ],
          ),
        ],
        _NotificationFootnote(
          _notificationExceptionCount(widget.exceptionCount),
        ),
      ],
    );
  }
}

class _StoryNotificationSettingsView extends StatefulWidget {
  const _StoryNotificationSettingsView({
    required this.settings,
    required this.exceptionCount,
    required this.defaultSoundId,
    required this.onChanged,
  });

  final Map<String, dynamic> settings;
  final int exceptionCount;
  final int defaultSoundId;
  final Future<void> Function(Map<String, dynamic>) onChanged;

  @override
  State<_StoryNotificationSettingsView> createState() =>
      _StoryNotificationSettingsViewState();
}

class _StoryNotificationSettingsViewState
    extends State<_StoryNotificationSettingsView> {
  late Map<String, dynamic> _settings = Map.from(widget.settings);

  void _replace(Map<String, dynamic> settings) {
    setState(() => _settings = settings);
    unawaited(widget.onChanged(_settings));
  }

  void _set(String key, Object value) {
    _replace({..._settings, key: value});
  }

  void _setAllStories(bool enabled) {
    _replace(
      withStoryNotificationMode(
        _settings,
        enabled ? StoryNotificationMode.all : StoryNotificationMode.topFive,
      ),
    );
  }

  void _setImportantStories(bool enabled) {
    _replace(
      withStoryNotificationMode(
        _settings,
        enabled ? StoryNotificationMode.topFive : StoryNotificationMode.off,
      ),
    );
  }

  void _setSound(bool enabled) {
    final current = _settings.int64('story_sound_id') ?? 0;
    _set(
      'story_sound_id',
      enabled ? (current > 0 ? current : widget.defaultSoundId) : 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final mode = storyNotificationMode(_settings);
    final hasNotifications =
        mode != StoryNotificationMode.off || widget.exceptionCount > 0;
    return _NotificationDetailScaffold(
      title: AppStrings.t(AppStringKeys.notificationStories),
      children: [
        _NotificationCard(
          children: [
            _NotificationSwitchRow(
              title: AppStrings.t(AppStringKeys.notificationAllStories),
              value: mode == StoryNotificationMode.all,
              onChanged: _setAllStories,
            ),
            if (mode != StoryNotificationMode.all) ...[
              const InsetDivider(leadingInset: 16),
              _NotificationSwitchRow(
                title: AppStrings.t(AppStringKeys.notificationTopFive),
                subtitle: AppStrings.t(
                  AppStringKeys.notificationTopFiveDescription,
                ),
                value: mode == StoryNotificationMode.topFive,
                onChanged: _setImportantStories,
              ),
            ],
          ],
        ),
        if (hasNotifications) ...[
          _NotificationSectionTitle(
            AppStrings.t(AppStringKeys.notificationOptions),
          ),
          _NotificationCard(
            children: [
              _NotificationSwitchRow(
                title: AppStrings.t(AppStringKeys.notificationStoryPoster),
                value:
                    _settings.boolean('show_story_poster') ??
                    _settings.boolean('show_story_sender') ??
                    true,
                enabled: hasNotifications,
                onChanged: (value) => _set('show_story_poster', value),
              ),
              const InsetDivider(leadingInset: 16),
              _NotificationSwitchRow(
                title: AppStrings.t(AppStringKeys.notificationSound),
                value: (_settings.int64('story_sound_id') ?? 0) > 0,
                enabled:
                    hasNotifications &&
                    ((_settings.int64('story_sound_id') ?? 0) > 0 ||
                        widget.defaultSoundId > 0),
                onChanged: _setSound,
              ),
            ],
          ),
        ],
        _NotificationFootnote(
          _notificationExceptionCount(widget.exceptionCount),
        ),
      ],
    );
  }
}

class _ReactionNotificationSettingsView extends StatefulWidget {
  const _ReactionNotificationSettingsView({
    required this.settings,
    required this.defaultSoundId,
    required this.onChanged,
  });

  final Map<String, dynamic> settings;
  final int defaultSoundId;
  final Future<void> Function(Map<String, dynamic>) onChanged;

  @override
  State<_ReactionNotificationSettingsView> createState() =>
      _ReactionNotificationSettingsViewState();
}

class _ReactionNotificationSettingsViewState
    extends State<_ReactionNotificationSettingsView> {
  late final Map<String, dynamic> _settings = Map.from(widget.settings);

  void _set(String key, Object value) {
    setState(() => _settings[key] = value);
    unawaited(widget.onChanged(_settings));
  }

  String _sourceLabel(String key) {
    return AppStrings.t(
      reactionSourceIsEveryone(_settings.obj(key))
          ? AppStringKeys.privacyVisibilityEveryone
          : AppStringKeys.privacyVisibilityContacts,
    );
  }

  Future<void> _chooseSource(String key, String title) async {
    final everyone = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _ReactionAudienceView(
          title: title,
          everyone: reactionSourceIsEveryone(_settings.obj(key)),
        ),
      ),
    );
    if (everyone == null || !mounted) return;
    _set(key, reactionSourceWithAudience(everyone: everyone));
  }

  void _setSound(bool enabled) {
    final current = _settings.int64('sound_id') ?? 0;
    _set(
      'sound_id',
      enabled ? (current > 0 ? current : widget.defaultSoundId) : 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final messagesEnabled = reactionSourceEnabled(
      _settings.obj('message_reaction_source'),
    );
    final storiesEnabled = reactionSourceEnabled(
      _settings.obj('story_reaction_source'),
    );
    final enabled = messagesEnabled || storiesEnabled;
    return _NotificationDetailScaffold(
      title: AppStrings.t(AppStringKeys.notificationReactions),
      children: [
        _NotificationCard(
          children: [
            _ReactionSourceRow(
              title: AppStrings.t(AppStringKeys.notificationReactionMessages),
              subtitle: _sourceLabel('message_reaction_source'),
              value: messagesEnabled,
              onTap: () => _chooseSource(
                'message_reaction_source',
                AppStrings.t(AppStringKeys.notificationReactionMessages),
              ),
              onChanged: (value) =>
                  _set('message_reaction_source', reactionSource(value)),
            ),
            const InsetDivider(leadingInset: 16),
            _ReactionSourceRow(
              title: AppStrings.t(AppStringKeys.notificationStories),
              subtitle: _sourceLabel('story_reaction_source'),
              value: storiesEnabled,
              onTap: () => _chooseSource(
                'story_reaction_source',
                AppStrings.t(AppStringKeys.notificationStories),
              ),
              onChanged: (value) =>
                  _set('story_reaction_source', reactionSource(value)),
            ),
          ],
        ),
        if (enabled) ...[
          _NotificationSectionTitle(
            AppStrings.t(AppStringKeys.notificationOptions),
          ),
          _NotificationCard(
            children: [
              _NotificationSwitchRow(
                title: AppStrings.t(AppStringKeys.notificationPreview),
                value: _settings.boolean('show_preview') ?? true,
                onChanged: (value) => _set('show_preview', value),
              ),
              const InsetDivider(leadingInset: 16),
              _NotificationSwitchRow(
                title: AppStrings.t(AppStringKeys.notificationSound),
                value: (_settings.int64('sound_id') ?? 0) > 0,
                enabled:
                    (_settings.int64('sound_id') ?? 0) > 0 ||
                    widget.defaultSoundId > 0,
                onChanged: _setSound,
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ReactionAudienceView extends StatelessWidget {
  const _ReactionAudienceView({required this.title, required this.everyone});

  final String title;
  final bool everyone;

  @override
  Widget build(BuildContext context) {
    return _NotificationDetailScaffold(
      title: title,
      children: [
        _NotificationCard(
          children: [
            _NotificationChoiceRow(
              title: AppStrings.t(AppStringKeys.privacyVisibilityContacts),
              selected: !everyone,
              onTap: () => Navigator.of(context).pop(false),
            ),
            const InsetDivider(leadingInset: 16),
            _NotificationChoiceRow(
              title: AppStrings.t(AppStringKeys.privacyVisibilityEveryone),
              selected: everyone,
              onTap: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ],
    );
  }
}

class _NotificationDetailScaffold extends StatelessWidget {
  const _NotificationDetailScaffold({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.groupedBackground,
      body: Column(
        children: [
          NavHeader(title: title, onBack: () => Navigator.of(context).pop()),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _NotificationSectionTitle extends StatelessWidget {
  const _NotificationSectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 12, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: context.colors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _NotificationSwitchRow extends StatelessWidget {
  const _NotificationSwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.subtitle,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: subtitle == null ? 58 : 72),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: subtitle == null ? 0 : 9,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: enabled
                          ? context.colors.textPrimary
                          : context.colors.textTertiary,
                      fontSize: 16,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        color: enabled
                            ? context.colors.textSecondary
                            : context.colors.textTertiary,
                        fontSize: 12.5,
                        height: 1.25,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            _NotificationToggle(
              value: value,
              enabled: enabled,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReactionSourceRow extends StatelessWidget {
  const _ReactionSourceRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onTap,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final VoidCallback onTap;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: 68,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: value ? onTap : null,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(color: c.textPrimary, fontSize: 16),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(color: c.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            _NotificationToggle(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

class _NotificationToggle extends StatelessWidget {
  const _NotificationToggle({
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      enabled: enabled,
      toggled: value,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged(!value) : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 160),
          opacity: enabled ? 1 : 0.45,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            width: 50,
            height: 30,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: value ? c.linkBlue : c.textTertiary,
              borderRadius: BorderRadius.circular(15),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFFFFF),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x30000000),
                      blurRadius: 3,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationChoiceRow extends StatelessWidget {
  const _NotificationChoiceRow({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 58),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(color: c.textPrimary, fontSize: 16),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              AppIcon(
                selected ? HeroAppIcons.circleCheck : HeroAppIcons.circle,
                size: 23,
                color: selected ? AppTheme.brand : c.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationFootnote extends StatelessWidget {
  const _NotificationFootnote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 0),
      child: Text(
        text,
        style: TextStyle(color: context.colors.textSecondary, fontSize: 12.5),
      ),
    );
  }
}
