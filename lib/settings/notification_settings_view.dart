//
//  notification_settings_view.dart
//
//  Telegram notification rules and on-device presentation preferences in one
//  task-oriented screen.
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/account_store.dart';
import '../components/app_icons.dart';
import '../components/desktop_content_constraint.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../notifications/notification_preferences.dart';
import '../notifications/notification_settings_payload.dart';
import '../notifications/scope_notification_settings.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';

String _notificationExceptionCount(int count) => AppStrings.t(
  count == 1
      ? AppStringKeys.notificationException
      : AppStringKeys.notificationExceptions,
  {'value1': count},
);

class NotificationSettingsView extends StatefulWidget {
  const NotificationSettingsView({super.key, this.showBackButton = true});

  final bool showBackButton;

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
  bool _loadInProgress = false;

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

  void _openAccountSelection() {
    final accounts = context.read<AccountStore>();
    Navigator.of(context).push(
      AppPageRoute<void>(
        pageBuilder: (_, _, _) => _AccountNotificationSelectionView(
          accounts: List<AccountSummary>.from(accounts.summaries),
          activeSlot: accounts.activeSlot,
        ),
      ),
    );
  }

  String get _accountSelectionSummary {
    return switch (_preferences.accountMode) {
      NotificationAccountMode.all => AppStringKeys.notificationAllAccounts.l10n(
        context,
      ),
      NotificationAccountMode.current =>
        AppStringKeys.notificationCurrentAccount.l10n(context),
      NotificationAccountMode.selected =>
        AppStringKeys.notificationSelectedAccounts.l10n(context),
    };
  }

  Future<void> _load() async {
    if (_loadInProgress || !_client.hasActiveClient) return;
    _loadInProgress = true;
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

    _loadInProgress = false;
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
    if (update.type == 'updateAuthorizationState' &&
        update.obj('authorization_state')?.type == 'authorizationStateReady') {
      if (_loading) unawaited(_load());
      return;
    }
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
    final hasMultipleAccounts = TdClient.shared.configuredSlots.length > 1;
    return Scaffold(
      key: const ValueKey('notification-settings'),
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.notificationNotifications),
            onBack: widget.showBackButton && Navigator.of(context).canPop()
                ? () => Navigator.of(context).pop()
                : null,
          ),
          Expanded(
            child: DesktopContentConstraint(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.section,
                ),
                children: [
                  Column(
                    key: const ValueKey('notification-section-telegram'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SettingsSectionHeader(
                        AppStringKeys.notificationMessageNotifications,
                      ),
                      if (_loading)
                        const SettingsPanel(
                          key: ValueKey('notification-telegram-loading'),
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator.adaptive(
                              strokeWidth: 2,
                            ),
                          ),
                        )
                      else
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
                              AppStrings.t(
                                AppStringKeys.notificationPrivateMessages,
                              ),
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
                              AppStrings.t(
                                AppStringKeys.notificationGroupMessages,
                              ),
                            ),
                          ),
                          const InsetDivider(leadingInset: 62),
                          _navigationRow(
                            icon: HeroAppIcons.towerBroadcast,
                            color: const Color(0xFFFFA928),
                            title: AppStrings.t(
                              AppStringKeys.notificationChannels,
                            ),
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
                            title: AppStrings.t(
                              AppStringKeys.notificationStories,
                            ),
                            subtitle: _exceptionsLabel('stories'),
                            value: _storySummary,
                            onTap: _openStories,
                          ),
                          const InsetDivider(leadingInset: 62),
                          _navigationRow(
                            icon: HeroAppIcons.heart,
                            color: const Color(0xFFFF3C69),
                            title: AppStrings.t(
                              AppStringKeys.notificationReactions,
                            ),
                            subtitle: _reactionSummary,
                            value: _enabledLabel(
                              reactionSourceEnabled(
                                    _reactionSettings.obj(
                                      'message_reaction_source',
                                    ),
                                  ) ||
                                  reactionSourceEnabled(
                                    _reactionSettings.obj(
                                      'story_reaction_source',
                                    ),
                                  ),
                            ),
                            onTap: _openReactions,
                          ),
                        ]),
                    ],
                  ),
                  Column(
                    key: const ValueKey('notification-section-device'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SettingsSectionHeader(
                        AppStringKeys.notificationOnDeviceTitle,
                      ),
                      SettingsCard(
                        children: [
                          if (hasMultipleAccounts) ...[
                            SettingsRow(
                              key: const ValueKey(
                                'mithka-notification-accounts-row',
                              ),
                              title: AppStringKeys
                                  .notificationShowNotificationsFrom,
                              value: _accountSelectionSummary,
                              leading: const SettingsIconTile(
                                icon: HeroAppIcons.users,
                                backgroundColor: Color(0xFF3295F6),
                              ),
                              onTap: _openAccountSelection,
                            ),
                            const InsetDivider(leadingInset: 56),
                          ],
                          SettingsSwitchRow(
                            key: const ValueKey(
                              'mithka-notification-in-app-sounds',
                            ),
                            title: AppStringKeys.notificationInAppSounds,
                            value: _preferences.inAppSounds,
                            leading: const SettingsIconTile(
                              icon: HeroAppIcons.volumeHigh,
                              backgroundColor: Color(0xFFF5A623),
                            ),
                            onChanged: (value) =>
                                unawaited(_preferences.setInAppSounds(value)),
                          ),
                          const InsetDivider(leadingInset: 56),
                          SettingsSwitchRow(
                            key: const ValueKey(
                              'mithka-notification-in-app-vibrate',
                            ),
                            title: AppStringKeys.notificationInAppVibrate,
                            value: _preferences.inAppVibrate,
                            leading: const SettingsIconTile(
                              icon: HeroAppIcons.mobileScreenButton,
                              backgroundColor: Color(0xFF7467F0),
                            ),
                            onChanged: (value) =>
                                unawaited(_preferences.setInAppVibrate(value)),
                          ),
                          const InsetDivider(leadingInset: 56),
                          SettingsSwitchRow(
                            key: const ValueKey(
                              'mithka-notification-in-app-preview',
                            ),
                            title: AppStringKeys.notificationInAppPreview,
                            value: _preferences.inAppPreview,
                            leading: const SettingsIconTile(
                              icon: HeroAppIcons.eye,
                              backgroundColor: Color(0xFF34A2DF),
                            ),
                            onChanged: (value) =>
                                unawaited(_preferences.setInAppPreview(value)),
                          ),
                          const InsetDivider(leadingInset: 56),
                          SettingsSwitchRow(
                            key: const ValueKey(
                              'mithka-notification-lock-screen-names',
                            ),
                            title: AppStringKeys.notificationNamesOnLockScreen,
                            value: _preferences.namesOnLockScreen,
                            leading: const SettingsIconTile(
                              icon: HeroAppIcons.lock,
                              backgroundColor: Color(0xFF16B05A),
                            ),
                            onChanged: (value) => unawaited(
                              _preferences.setNamesOnLockScreen(value),
                            ),
                          ),
                        ],
                      ),
                      _NotificationFootnote(
                        AppStrings.t(
                          AppStringKeys
                              .notificationNamesOnLockScreenDescription,
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

  Widget _card(List<Widget> children) => SettingsCard(children: children);

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

class _AccountNotificationSelectionView extends StatefulWidget {
  const _AccountNotificationSelectionView({
    required this.accounts,
    required this.activeSlot,
  });

  final List<AccountSummary> accounts;
  final int activeSlot;

  @override
  State<_AccountNotificationSelectionView> createState() =>
      _AccountNotificationSelectionViewState();
}

class _AccountNotificationSelectionViewState
    extends State<_AccountNotificationSelectionView> {
  final NotificationPreferences _preferences = NotificationPreferences.shared;

  @override
  void initState() {
    super.initState();
    _preferences.addListener(_preferencesChanged);
  }

  @override
  void dispose() {
    _preferences.removeListener(_preferencesChanged);
    super.dispose();
  }

  void _preferencesChanged() {
    if (mounted) setState(() {});
  }

  int? get _activeUserId {
    for (final account in widget.accounts) {
      if (account.slot == widget.activeSlot) return account.userId;
    }
    return null;
  }

  Future<void> _selectMode(NotificationAccountMode mode) async {
    if (mode == NotificationAccountMode.selected) {
      final availableIds = widget.accounts
          .map((account) => account.userId)
          .toSet();
      if (_preferences.selectedAccountIds.intersection(availableIds).isEmpty) {
        final activeUserId = _activeUserId;
        if (activeUserId != null) {
          await _preferences.setSelectedAccountIds([activeUserId]);
        }
      }
    }
    await _preferences.setAccountMode(
      mode,
      defaultSelectedAccountIds: [?_activeUserId],
    );
  }

  Future<void> _setAccountEnabled(int userId, bool enabled) async {
    final selected = _preferences.selectedAccountIds.toSet();
    if (enabled) {
      selected.add(userId);
    } else {
      final availableSelected = widget.accounts
          .where((account) => selected.contains(account.userId))
          .length;
      if (availableSelected <= 1) return;
      selected.remove(userId);
    }
    await _preferences.setSelectedAccountIds(selected);
  }

  @override
  Widget build(BuildContext context) {
    final mode = _preferences.accountMode;
    return _NotificationDetailScaffold(
      title: AppStrings.t(AppStringKeys.notificationShowNotificationsFrom),
      children: [
        _NotificationCard(
          children: [
            _NotificationChoiceRow(
              title: AppStrings.t(AppStringKeys.notificationAllAccounts),
              selected: mode == NotificationAccountMode.all,
              onTap: () => unawaited(_selectMode(NotificationAccountMode.all)),
            ),
            const InsetDivider(leadingInset: 16),
            _NotificationChoiceRow(
              title: AppStrings.t(AppStringKeys.notificationCurrentAccount),
              selected: mode == NotificationAccountMode.current,
              onTap: () =>
                  unawaited(_selectMode(NotificationAccountMode.current)),
            ),
            const InsetDivider(leadingInset: 16),
            _NotificationChoiceRow(
              title: AppStrings.t(AppStringKeys.notificationSelectedAccounts),
              selected: mode == NotificationAccountMode.selected,
              onTap: () =>
                  unawaited(_selectMode(NotificationAccountMode.selected)),
            ),
          ],
        ),
        if (mode == NotificationAccountMode.selected) ...[
          const SettingsSectionHeader(AppStringKeys.notificationAccounts),
          _NotificationCard(
            children: [
              for (var index = 0; index < widget.accounts.length; index++) ...[
                SettingsSwitchRow(
                  title: widget.accounts[index].name,
                  subtitle: widget.accounts[index].phone,
                  value: _preferences.selectedAccountIds.contains(
                    widget.accounts[index].userId,
                  ),
                  onChanged: (enabled) => unawaited(
                    _setAccountEnabled(widget.accounts[index].userId, enabled),
                  ),
                ),
                if (index != widget.accounts.length - 1)
                  const InsetDivider(leadingInset: 16),
              ],
            ],
          ),
          _NotificationFootnote(
            AppStrings.t(AppStringKeys.notificationSelectedAccountsDescription),
          ),
        ],
      ],
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
            SettingsSwitchRow(
              title: AppStrings.t(AppStringKeys.notificationNotifications),
              value: enabled,
              onChanged: (value) => _set('mute_for', value ? 0 : _muteForever),
            ),
          ],
        ),
        if (hasNotifications) ...[
          const SettingsSectionHeader(AppStringKeys.notificationOptions),
          _NotificationCard(
            children: [
              SettingsSwitchRow(
                title: AppStrings.t(AppStringKeys.notificationPreview),
                value: _settings.boolean('show_preview') ?? true,
                enabled: hasNotifications,
                onChanged: (value) => _set('show_preview', value),
              ),
              const InsetDivider(leadingInset: 16),
              SettingsSwitchRow(
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
            SettingsSwitchRow(
              title: AppStrings.t(AppStringKeys.notificationAllStories),
              value: mode == StoryNotificationMode.all,
              onChanged: _setAllStories,
            ),
            if (mode != StoryNotificationMode.all) ...[
              const InsetDivider(leadingInset: 16),
              SettingsSwitchRow(
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
          const SettingsSectionHeader(AppStringKeys.notificationOptions),
          _NotificationCard(
            children: [
              SettingsSwitchRow(
                title: AppStrings.t(AppStringKeys.notificationStoryPoster),
                value:
                    _settings.boolean('show_story_poster') ??
                    _settings.boolean('show_story_sender') ??
                    true,
                enabled: hasNotifications,
                onChanged: (value) => _set('show_story_poster', value),
              ),
              const InsetDivider(leadingInset: 16),
              SettingsSwitchRow(
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
          const SettingsSectionHeader(AppStringKeys.notificationOptions),
          _NotificationCard(
            children: [
              SettingsSwitchRow(
                title: AppStrings.t(AppStringKeys.notificationPreview),
                value: _settings.boolean('show_preview') ?? true,
                onChanged: (value) => _set('show_preview', value),
              ),
              const InsetDivider(leadingInset: 16),
              SettingsSwitchRow(
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
    return SettingsCard(children: children);
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
            AppSwitch(value: value, onChanged: onChanged),
          ],
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
