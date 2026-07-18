import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../components/app_confirm_dialog.dart';
import '../components/app_icons.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../media/app_asset_picker.dart';
import '../profile/profile_icon_picker_view.dart';
import '../settings/edit_field_view.dart';
import '../tdlib/json_helpers.dart';
import '../theme/app_theme.dart';
import 'custom_emoji.dart';
import 'group_administration_service.dart';
import 'image_edit_view.dart';

class GroupAdvancedAdministrationView extends StatefulWidget {
  const GroupAdvancedAdministrationView({
    super.key,
    required this.chatId,
    required this.supergroupId,
  });

  final int chatId;
  final int supergroupId;

  @override
  State<GroupAdvancedAdministrationView> createState() =>
      _GroupAdvancedAdministrationViewState();
}

class _GroupAdvancedAdministrationViewState
    extends State<GroupAdvancedAdministrationView> {
  final _service = GroupAdministrationService();
  bool _loading = true;
  bool _isChannel = false;
  bool _protectedContent = false;
  bool _hiddenMembers = false;
  bool _canHideMembers = false;
  bool _antiSpam = false;
  bool _canToggleAntiSpam = false;
  bool _automaticTranslation = false;
  bool _signMessages = false;
  bool _showMessageSender = false;
  bool _allHistoryAvailable = false;
  bool _isForum = false;
  bool _hasForumTabs = false;
  bool _isPublic = false;
  bool _hasPhoto = false;
  String _description = '';
  int _slowMode = 0;
  int _linkedChatId = 0;
  Map<String, dynamic> _availableReactions = const {
    '@type': 'chatAvailableReactionsAll',
    'max_reaction_count': 11,
  };

  bool get _historyToggleApplies =>
      !_isChannel && !_isForum && _linkedChatId == 0 && !_isPublic;
  bool get _forumToggleApplies =>
      !_isChannel && (_isForum || _linkedChatId == 0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait([
        _service.getChat(widget.chatId),
        _service.getSupergroup(widget.supergroupId),
        _service.getSupergroupFullInfo(widget.supergroupId),
      ]);
      if (!mounted) return;
      final chat = values[0];
      final supergroup = values[1];
      final full = values[2];
      setState(() {
        _isChannel = supergroup.boolean('is_channel') ?? false;
        _signMessages = supergroup.boolean('sign_messages') ?? false;
        _showMessageSender = supergroup.boolean('show_message_sender') ?? false;
        _isForum = supergroup.boolean('is_forum') ?? false;
        _hasForumTabs = supergroup.boolean('has_forum_tabs') ?? false;
        _protectedContent = chat.boolean('has_protected_content') ?? false;
        _availableReactions =
            chat.obj('available_reactions') ?? _availableReactions;
        _slowMode = full.integer('slow_mode_delay') ?? 0;
        _linkedChatId = full.int64('linked_chat_id') ?? 0;
        _hiddenMembers = full.boolean('has_hidden_members') ?? false;
        _canHideMembers = full.boolean('can_hide_members') ?? false;
        _antiSpam = full.boolean('has_aggressive_anti_spam_enabled') ?? false;
        _canToggleAntiSpam =
            full.boolean('can_toggle_aggressive_anti_spam') ?? false;
        _automaticTranslation =
            supergroup.boolean('has_automatic_translation') ?? false;
        _allHistoryAvailable =
            full.boolean('is_all_history_available') ?? false;
        _description = full.str('description') ?? '';
        _hasPhoto = full.obj('photo') != null;
        final activeUsernames = supergroup.obj(
          'usernames',
        )?['active_usernames'];
        _isPublic = activeUsernames is List && activeUsernames.isNotEmpty;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      showToast(
        context,
        context.l10n.t(AppStringKeys.groupAdminErrorLoad, {'value1': error}),
      );
    }
  }

  Future<void> _setProtected(bool value) async {
    final previous = _protectedContent;
    setState(() => _protectedContent = value);
    try {
      await _service.setProtectedContent(widget.chatId, value);
    } catch (error) {
      if (!mounted) return;
      setState(() => _protectedContent = previous);
      showToast(
        context,
        context.l10n.t(AppStringKeys.groupAdminErrorProtection, {
          'value1': error,
        }),
      );
    }
  }

  Future<void> _setHidden(bool value) async {
    final previous = _hiddenMembers;
    setState(() => _hiddenMembers = value);
    try {
      await _service.setHiddenMembers(widget.supergroupId, value);
    } catch (error) {
      if (!mounted) return;
      setState(() => _hiddenMembers = previous);
      showToast(
        context,
        context.l10n.t(AppStringKeys.groupAdminErrorMemberVisibility, {
          'value1': error,
        }),
      );
    }
  }

  Future<void> _setAntiSpam(bool value) async {
    final previous = _antiSpam;
    setState(() => _antiSpam = value);
    try {
      await _service.setAggressiveAntiSpam(widget.supergroupId, value);
    } catch (error) {
      if (!mounted) return;
      setState(() => _antiSpam = previous);
      showToast(
        context,
        context.l10n.t(AppStringKeys.groupAdminErrorAntiSpam, {
          'value1': error,
        }),
      );
    }
  }

  Future<void> _setTranslation(bool value) async {
    final previous = _automaticTranslation;
    setState(() => _automaticTranslation = value);
    try {
      await _service.setAutomaticTranslation(widget.supergroupId, value);
    } catch (error) {
      if (!mounted) return;
      setState(() => _automaticTranslation = previous);
      showToast(
        context,
        context.l10n.t(AppStringKeys.groupAdminErrorTranslation, {
          'value1': error,
        }),
      );
    }
  }

  Future<void> _editDescription() async {
    final value = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => EditFieldView(
          title: AppStringKeys.groupAdminDescription.l10n(context),
          initial: _description,
          hint: AppStringKeys.groupAdminDescriptionHint.l10n(context),
          multiline: true,
          maxLength: 255,
        ),
      ),
    );
    if (value == null || value == _description) return;
    try {
      await _service.setDescription(widget.chatId, value);
      if (mounted) setState(() => _description = value.trim());
    } catch (error) {
      if (mounted) {
        showToast(
          context,
          context.l10n.t(AppStringKeys.groupAdminErrorDescription, {
            'value1': error,
          }),
        );
      }
    }
  }

  Future<void> _changePhoto() async {
    final emptyPhotoError = AppStringKeys.groupAdminErrorPhotoEmpty.l10n(
      context,
    );
    try {
      final selection = await AppAssetPicker.pickDetailed(
        context,
        type: AppAssetPickerType.image,
        maxAssets: 1,
      );
      if (selection.assets.isEmpty || !mounted) return;
      final edited = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => ImageEditView(
            sourcePath: selection.assets.first.file.path,
            avatar: true,
          ),
        ),
      );
      if (edited == null) return;
      final file = File(edited);
      if (!await file.exists() || await file.length() == 0) {
        throw StateError(emptyPhotoError);
      }
      await _service.setPhoto(widget.chatId, edited);
      if (mounted) setState(() => _hasPhoto = true);
    } catch (error) {
      if (mounted) {
        showToast(
          context,
          context.l10n.t(AppStringKeys.groupAdminErrorPhoto, {'value1': error}),
        );
      }
    }
  }

  Future<void> _removePhoto() async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: AppStringKeys.groupAdminRemovePhotoConfirm.l10n(context),
      confirmText: AppStringKeys.stickerStudioRemove.l10n(context),
    );
    if (!confirmed) return;
    try {
      await _service.removePhoto(widget.chatId);
      if (mounted) setState(() => _hasPhoto = false);
    } catch (error) {
      if (mounted) {
        showToast(
          context,
          context.l10n.t(AppStringKeys.groupAdminErrorPhotoRemove, {
            'value1': error,
          }),
        );
      }
    }
  }

  Future<void> _setSignMessages(bool value) async {
    final previousSign = _signMessages;
    final previousSender = _showMessageSender;
    final nextSender = value ? _showMessageSender : false;
    setState(() {
      _signMessages = value;
      _showMessageSender = nextSender;
    });
    try {
      await _service.setSignedMessages(
        supergroupId: widget.supergroupId,
        signMessages: value,
        showMessageSender: nextSender,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _signMessages = previousSign;
        _showMessageSender = previousSender;
      });
      showToast(
        context,
        context.l10n.t(AppStringKeys.groupAdminErrorSignatures, {
          'value1': error,
        }),
      );
    }
  }

  Future<void> _setShowMessageSender(bool value) async {
    final previousSign = _signMessages;
    final previousSender = _showMessageSender;
    final nextSign = value || _signMessages;
    setState(() {
      _signMessages = nextSign;
      _showMessageSender = value;
    });
    try {
      await _service.setSignedMessages(
        supergroupId: widget.supergroupId,
        signMessages: nextSign,
        showMessageSender: value,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _signMessages = previousSign;
        _showMessageSender = previousSender;
      });
      showToast(
        context,
        context.l10n.t(AppStringKeys.groupAdminErrorSenderProfiles, {
          'value1': error,
        }),
      );
    }
  }

  Future<void> _setHistory(bool value) async {
    final previous = _allHistoryAvailable;
    setState(() => _allHistoryAvailable = value);
    try {
      await _service.setAllHistoryAvailable(widget.supergroupId, value);
    } catch (error) {
      if (!mounted) return;
      setState(() => _allHistoryAvailable = previous);
      showToast(
        context,
        context.l10n.t(AppStringKeys.groupAdminErrorHistory, {'value1': error}),
      );
    }
  }

  Future<void> _setForum(bool value) async {
    final previousForum = _isForum;
    final previousTabs = _hasForumTabs;
    final tabs = value && _hasForumTabs;
    setState(() {
      _isForum = value;
      _hasForumTabs = tabs;
    });
    try {
      await _service.setForumMode(
        supergroupId: widget.supergroupId,
        isForum: value,
        hasForumTabs: tabs,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isForum = previousForum;
        _hasForumTabs = previousTabs;
      });
      showToast(
        context,
        context.l10n.t(AppStringKeys.groupAdminErrorForum, {'value1': error}),
      );
    }
  }

  Future<void> _setForumTabs(bool value) async {
    final previous = _hasForumTabs;
    setState(() => _hasForumTabs = value);
    try {
      await _service.setForumMode(
        supergroupId: widget.supergroupId,
        isForum: true,
        hasForumTabs: value,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _hasForumTabs = previous);
      showToast(
        context,
        context.l10n.t(AppStringKeys.groupAdminErrorTopicLayout, {
          'value1': error,
        }),
      );
    }
  }

  Future<void> _pickSlowMode() async {
    const values = [0, 5, 10, 30, 60, 300, 900, 3600];
    final selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: context.colors.card,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final value in values)
              _AdminNavRow(
                title: _slowModeLabel(sheetContext, value),
                trailing: value == _slowMode
                    ? AppIcon(
                        HeroAppIcons.check,
                        size: 20,
                        color: AppTheme.brand,
                      )
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(value),
              ),
          ],
        ),
      ),
    );
    if (selected == null || selected == _slowMode) return;
    try {
      await _service.setSlowMode(widget.chatId, selected);
      if (mounted) setState(() => _slowMode = selected);
    } catch (error) {
      if (mounted) {
        showToast(
          context,
          context.l10n.t(AppStringKeys.groupAdminErrorSlowMode, {
            'value1': error,
          }),
        );
      }
    }
  }

  Future<void> _openReactions() async {
    final value = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => ReactionConfigurationView(
          chatId: widget.chatId,
          initial: _availableReactions,
          service: _service,
        ),
      ),
    );
    if (value != null && mounted) setState(() => _availableReactions = value);
  }

  Future<void> _openDiscussion() async {
    final value = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => DiscussionGroupPickerView(
          chatId: widget.chatId,
          selectedChatId: _linkedChatId,
          service: _service,
        ),
      ),
    );
    if (value != null && mounted) setState(() => _linkedChatId = value);
  }

  @override
  Widget build(BuildContext context) => _AdminPage(
    title: AppStringKeys.groupAdminAdvancedTitle.l10n(context),
    child: _loading
        ? const Center(child: AppActivityIndicator())
        : ListView(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 30),
            children: [
              _AdminSection(
                title: AppStringKeys.groupAdminProfileSection.l10n(context),
                children: [
                  _AdminNavRow(
                    title: AppStringKeys.groupAdminDescription.l10n(context),
                    value: _description.isEmpty
                        ? AppStringKeys.groupAdminNotSet.l10n(context)
                        : _description,
                    leading: AppIcon(
                      HeroAppIcons.font,
                      size: 21,
                      color: context.colors.textSecondary,
                    ),
                    onTap: _editDescription,
                  ),
                  _AdminNavRow(
                    title: _hasPhoto
                        ? AppStringKeys.groupAdminChangePhoto.l10n(context)
                        : AppStringKeys.groupAdminAddPhoto.l10n(context),
                    leading: AppIcon(
                      HeroAppIcons.camera,
                      size: 21,
                      color: context.colors.textSecondary,
                    ),
                    onTap: _changePhoto,
                  ),
                  if (_hasPhoto)
                    _AdminNavRow(
                      title: AppStringKeys.groupAdminRemovePhoto.l10n(context),
                      leading: AppIcon(
                        HeroAppIcons.trash,
                        size: 21,
                        color: AppTheme.tagRed,
                      ),
                      onTap: _removePhoto,
                    ),
                ],
              ),
              const SizedBox(height: 20),
              _AdminSection(
                title: AppStringKeys.groupAdminMessagesSection.l10n(context),
                children: [
                  if (!_isChannel)
                    _AdminNavRow(
                      title: AppStringKeys.groupAdminSlowMode.l10n(context),
                      value: _slowModeLabel(context, _slowMode),
                      onTap: _pickSlowMode,
                    ),
                  _AdminSwitchRow(
                    title: AppStringKeys.groupAdminProtectContent.l10n(context),
                    value: _protectedContent,
                    onChanged: _setProtected,
                  ),
                  _AdminNavRow(
                    title: AppStringKeys.groupAdminAvailableReactions.l10n(
                      context,
                    ),
                    value: _reactionSummary(context, _availableReactions),
                    onTap: _openReactions,
                  ),
                  if (_isChannel)
                    _AdminSwitchRow(
                      title: AppStringKeys.groupAdminSignMessages.l10n(context),
                      value: _signMessages,
                      onChanged: _setSignMessages,
                    ),
                  if (_isChannel && _signMessages)
                    _AdminSwitchRow(
                      title: AppStringKeys.groupAdminShowSenderProfiles.l10n(
                        context,
                      ),
                      value: _showMessageSender,
                      onChanged: _setShowMessageSender,
                    ),
                ],
              ),
              const SizedBox(height: 20),
              _AdminSection(
                title: AppStringKeys.groupAdminCommunitySection.l10n(context),
                children: [
                  if (_isChannel)
                    _AdminNavRow(
                      title: AppStringKeys.groupAdminDiscussionGroup.l10n(
                        context,
                      ),
                      value: _linkedChatId == 0
                          ? AppStringKeys.groupAdminNotLinked.l10n(context)
                          : AppStringKeys.groupAdminLinked.l10n(context),
                      onTap: _openDiscussion,
                    ),
                  if (_canHideMembers)
                    _AdminSwitchRow(
                      title: AppStringKeys.groupAdminHideMembers.l10n(context),
                      value: _hiddenMembers,
                      onChanged: _setHidden,
                    ),
                  if (_canToggleAntiSpam)
                    _AdminSwitchRow(
                      title: AppStringKeys.groupAdminAggressiveAntiSpam.l10n(
                        context,
                      ),
                      value: _antiSpam,
                      onChanged: _setAntiSpam,
                    ),
                  if (_isChannel)
                    _AdminSwitchRow(
                      title: AppStringKeys.groupAdminAutomaticTranslation.l10n(
                        context,
                      ),
                      value: _automaticTranslation,
                      onChanged: _setTranslation,
                    ),
                  if (_historyToggleApplies)
                    _AdminSwitchRow(
                      title: AppStringKeys.groupAdminHistoryForNewMembers.l10n(
                        context,
                      ),
                      value: _allHistoryAvailable,
                      onChanged: _setHistory,
                    ),
                  if (_forumToggleApplies)
                    _AdminSwitchRow(
                      title: AppStringKeys.groupAdminTopics.l10n(context),
                      value: _isForum,
                      onChanged: _setForum,
                    ),
                  if (_forumToggleApplies && _isForum)
                    _AdminSwitchRow(
                      title: AppStringKeys.groupAdminTopicTabs.l10n(context),
                      value: _hasForumTabs,
                      onChanged: _setForumTabs,
                    ),
                ],
              ),
            ],
          ),
  );
}

String _slowModeLabel(BuildContext context, int seconds) => switch (seconds) {
  0 => AppStringKeys.groupAdminOff.l10n(context),
  5 ||
  10 ||
  30 => context.l10n.t(AppStringKeys.groupAdminSeconds, {'value1': seconds}),
  60 => AppStringKeys.groupAdminMinute.l10n(context),
  300 => context.l10n.t(AppStringKeys.groupAdminMinutes, {'value1': 5}),
  900 => context.l10n.t(AppStringKeys.groupAdminMinutes, {'value1': 15}),
  3600 => AppStringKeys.groupAdminHour.l10n(context),
  _ => context.l10n.t(AppStringKeys.groupAdminSeconds, {'value1': seconds}),
};

String _reactionSummary(BuildContext context, Map<String, dynamic> reactions) =>
    reactions.type == 'chatAvailableReactionsAll'
    ? AppStringKeys.groupAdminAllReactions.l10n(context)
    : context.l10n.t(AppStringKeys.groupAdminReactionCount, {
        'value1': reactions.objects('reactions')?.length ?? 0,
      });

class ReactionConfigurationView extends StatefulWidget {
  const ReactionConfigurationView({
    super.key,
    required this.chatId,
    required this.initial,
    required this.service,
  });

  final int chatId;
  final Map<String, dynamic> initial;
  final GroupAdministrationService service;

  @override
  State<ReactionConfigurationView> createState() =>
      _ReactionConfigurationViewState();
}

class _ReactionConfigurationViewState extends State<ReactionConfigurationView> {
  static const _emoji = ['👍', '❤️', '🔥', '🎉', '😂', '😮', '😢', '👏'];
  late bool _all = widget.initial.type == 'chatAvailableReactionsAll';
  late final Set<String> _selected = {
    for (final value
        in widget.initial.objects('reactions') ??
            const <Map<String, dynamic>>[])
      if (value.type == 'reactionTypeEmoji') value.str('emoji') ?? '',
  }..remove('');
  late final Set<int> _customSelected = {
    for (final value
        in widget.initial.objects('reactions') ??
            const <Map<String, dynamic>>[])
      if (value.type == 'reactionTypeCustomEmoji')
        if (value.int64('custom_emoji_id') case final int id) id,
  };
  late int _maxReactionCount =
      widget.initial.integer('max_reaction_count')?.clamp(1, 11) ?? 11;
  bool _saving = false;

  Future<void> _addCustomReaction() async {
    final id = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => const ProfileIconPickerView(
          selectedId: 0,
          title: 'Add custom reaction',
          source: ProfileIconSource.status,
        ),
      ),
    );
    if (mounted && id != null && id != 0) {
      setState(() => _customSelected.add(id));
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final value = _all
        ? <String, dynamic>{
            '@type': 'chatAvailableReactionsAll',
            'max_reaction_count': _maxReactionCount,
          }
        : <String, dynamic>{
            '@type': 'chatAvailableReactionsSome',
            'reactions': [
              for (final emoji in _selected)
                {'@type': 'reactionTypeEmoji', 'emoji': emoji},
              for (final id in _customSelected)
                {'@type': 'reactionTypeCustomEmoji', 'custom_emoji_id': id},
            ],
            'max_reaction_count': _maxReactionCount,
          };
    setState(() => _saving = true);
    try {
      await widget.service.setAvailableReactions(widget.chatId, value);
      if (mounted) Navigator.of(context).pop(value);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showToast(context, 'Couldn’t save reactions: $error');
    }
  }

  @override
  Widget build(BuildContext context) => _AdminPage(
    title: 'Available reactions',
    trailing: _AdminSaveButton(onTap: _save, saving: _saving),
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _AdminSection(
          title: 'Mode',
          children: [
            _AdminSwitchRow(
              title: 'Allow all reactions',
              value: _all,
              onChanged: (value) => setState(() => _all = value),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _AdminSection(
          title: 'Per-message limit',
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              child: Column(
                children: [
                  Text(
                    'People can add up to $_maxReactionCount different reactions to one message.',
                    style: AppTextStyle.body(context.colors.textSecondary),
                  ),
                  _AdminDiscreteSlider(
                    value: _maxReactionCount.toDouble(),
                    min: 1,
                    max: 11,
                    onChanged: (value) =>
                        setState(() => _maxReactionCount = value.round()),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (!_all) ...[
          const SizedBox(height: 20),
          _AdminSection(
            title: 'Allowed emoji',
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final emoji in _emoji)
                      GestureDetector(
                        onTap: () => setState(() {
                          if (!_selected.remove(emoji)) _selected.add(emoji);
                        }),
                        child: Container(
                          width: 48,
                          height: 48,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _selected.contains(emoji)
                                ? AppTheme.brand.withValues(alpha: 0.16)
                                : context.colors.searchFill,
                            border: Border.all(
                              color: _selected.contains(emoji)
                                  ? AppTheme.brand
                                  : context.colors.divider,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 25),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _AdminSection(
            title: 'Custom reactions',
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final id in _customSelected)
                      GestureDetector(
                        onTap: () => setState(() => _customSelected.remove(id)),
                        child: Container(
                          width: 48,
                          height: 48,
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: AppTheme.brand.withValues(alpha: 0.14),
                            border: Border.all(color: AppTheme.brand),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: CustomEmojiView(
                            id: id,
                            size: 30,
                            color: context.colors.textPrimary,
                          ),
                        ),
                      ),
                    GestureDetector(
                      onTap: _addCustomReaction,
                      child: Container(
                        width: 48,
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: context.colors.searchFill,
                          border: Border.all(color: context.colors.divider),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: AppIcon(
                          HeroAppIcons.plus,
                          size: 20,
                          color: AppTheme.brand,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ],
    ),
  );
}

class DiscussionGroupPickerView extends StatefulWidget {
  const DiscussionGroupPickerView({
    super.key,
    required this.chatId,
    required this.selectedChatId,
    required this.service,
  });

  final int chatId;
  final int selectedChatId;
  final GroupAdministrationService service;

  @override
  State<DiscussionGroupPickerView> createState() =>
      _DiscussionGroupPickerViewState();
}

class _DiscussionGroupPickerViewState extends State<DiscussionGroupPickerView> {
  final Map<int, String> _titles = {};
  List<int> _ids = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final ids = await widget.service.suitableDiscussionChats();
      await Future.wait([
        for (final id in ids)
          widget.service
              .getChat(id)
              .then((chat) => _titles[id] = chat.str('title') ?? 'Chat $id'),
      ]);
      if (mounted) {
        setState(() {
          _ids = ids;
          _loading = false;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      showToast(context, 'Couldn’t load discussion groups: $error');
    }
  }

  Future<void> _select(int id) async {
    try {
      await widget.service.setDiscussionGroup(widget.chatId, id);
      if (mounted) Navigator.of(context).pop(id);
    } catch (error) {
      if (mounted) showToast(context, 'Couldn’t link discussion group: $error');
    }
  }

  @override
  Widget build(BuildContext context) => _AdminPage(
    title: 'Discussion group',
    child: _loading
        ? const Center(child: AppActivityIndicator())
        : ListView(
            padding: const EdgeInsets.all(14),
            children: [
              _AdminSection(
                title: 'Linked group',
                children: [
                  _AdminChoiceRow(
                    title: 'None',
                    selected: widget.selectedChatId == 0,
                    onTap: () => _select(0),
                  ),
                  for (final id in _ids)
                    _AdminChoiceRow(
                      title: _titles[id] ?? 'Chat $id',
                      selected: widget.selectedChatId == id,
                      onTap: () => _select(id),
                    ),
                ],
              ),
            ],
          ),
  );
}

class ChatInviteLinksAdministrationView extends StatefulWidget {
  const ChatInviteLinksAdministrationView({super.key, required this.chatId});

  final int chatId;

  @override
  State<ChatInviteLinksAdministrationView> createState() =>
      _ChatInviteLinksAdministrationViewState();
}

class _ChatInviteLinksAdministrationViewState
    extends State<ChatInviteLinksAdministrationView> {
  final _service = GroupAdministrationService();
  List<Map<String, dynamic>> _active = const [];
  List<Map<String, dynamic>> _revoked = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final me = await _service.myId();
      var creatorIds = <int>{me};
      try {
        final counts = await _service.inviteLinkCreatorCounts(widget.chatId);
        creatorIds = {
          ...creatorIds,
          for (final count in counts)
            if (count.int64('user_id') case final int id) id,
        };
      } catch (_) {
        // Only owners may enumerate links created by other administrators.
      }
      final activeSets = await Future.wait([
        for (final creatorId in creatorIds)
          _service.inviteLinks(chatId: widget.chatId, creatorUserId: creatorId),
      ]);
      final revokedSets = await Future.wait([
        for (final creatorId in creatorIds)
          _service.inviteLinks(
            chatId: widget.chatId,
            creatorUserId: creatorId,
            revoked: true,
          ),
      ]);
      if (!mounted) return;
      setState(() {
        _active = [for (final links in activeSets) ...links]
          ..sort(
            (a, b) =>
                (b.integer('date') ?? 0).compareTo(a.integer('date') ?? 0),
          );
        _revoked = [for (final links in revokedSets) ...links]
          ..sort(
            (a, b) =>
                (b.integer('date') ?? 0).compareTo(a.integer('date') ?? 0),
          );
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      showToast(context, 'Couldn’t load invite links: $error');
    }
  }

  Future<void> _create() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            ChatInviteLinkEditorView(chatId: widget.chatId, service: _service),
      ),
    );
    if (changed ?? false) await _load();
  }

  Future<void> _edit(Map<String, dynamic> link) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ChatInviteLinkEditorView(
          chatId: widget.chatId,
          service: _service,
          existing: link,
        ),
      ),
    );
    if (changed ?? false) await _load();
  }

  Future<void> _revoke(Map<String, dynamic> link) async {
    final value = link.str('invite_link');
    if (value == null) return;
    final ok = await showAppConfirmDialog(
      context,
      title: 'Revoke this invite link?',
      confirmText: 'Revoke',
    );
    if (!ok) return;
    try {
      await _service.revokeInviteLink(widget.chatId, value);
      await _load();
    } catch (error) {
      if (mounted) showToast(context, 'Couldn’t revoke invite link: $error');
    }
  }

  Future<void> _analytics(Map<String, dynamic> link) async {
    final value = link.str('invite_link');
    if (value == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => InviteLinkAnalyticsView(
          chatId: widget.chatId,
          inviteLink: value,
          service: _service,
        ),
      ),
    );
  }

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) showToast(context, 'Invite link copied');
  }

  @override
  Widget build(BuildContext context) => _AdminPage(
    title: 'Invite links',
    trailing: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _loading ? null : _create,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: AppIcon(
          HeroAppIcons.plus,
          size: 23,
          color: _loading ? context.colors.textTertiary : AppTheme.brand,
        ),
      ),
    ),
    child: _loading
        ? const Center(child: AppActivityIndicator())
        : ListView(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 30),
            children: [
              _AdminSection(
                title: '',
                children: [
                  _AdminNavRow(
                    title: AppStringKeys.groupAdminRefresh.l10n(context),
                    leading: AppIcon(
                      HeroAppIcons.arrowsRotate,
                      size: 19,
                      color: AppTheme.brand,
                    ),
                    onTap: _load,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _AdminSection(
                title: 'Active',
                children: _active.isEmpty
                    ? const [_AdminEmptyRow('No active invite links')]
                    : [for (final link in _active) _inviteRow(link)],
              ),
              if (_revoked.isNotEmpty) ...[
                const SizedBox(height: 20),
                _AdminSection(
                  title: 'Revoked',
                  children: [
                    for (final link in _revoked)
                      _inviteRow(link, revoked: true),
                  ],
                ),
              ],
            ],
          ),
  );

  Widget _inviteRow(Map<String, dynamic> link, {bool revoked = false}) {
    final value = link.str('invite_link') ?? '';
    final name = link.str('name') ?? '';
    final count = link.integer('member_count') ?? 0;
    final pending = link.integer('pending_join_request_count') ?? 0;
    return _AdminNavRow(
      title: name.isEmpty ? value : name,
      value: '$count joined${pending > 0 ? ' · $pending pending' : ''}',
      onTap: revoked ? () => _copy(value) : () => _edit(link),
      leading: GestureDetector(
        onTap: () => _copy(value),
        child: AppIcon(HeroAppIcons.link, size: 20, color: AppTheme.brand),
      ),
      trailing: revoked
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () => _analytics(link),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: AppIcon(
                      HeroAppIcons.tableColumns,
                      size: 18,
                      color: context.colors.textSecondary,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => _revoke(link),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: AppIcon(
                      HeroAppIcons.ban,
                      size: 18,
                      color: Color(0xFFFF3B30),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class ChatInviteLinkEditorView extends StatefulWidget {
  const ChatInviteLinkEditorView({
    super.key,
    required this.chatId,
    required this.service,
    this.existing,
  });

  final int chatId;
  final GroupAdministrationService service;
  final Map<String, dynamic>? existing;

  @override
  State<ChatInviteLinkEditorView> createState() =>
      _ChatInviteLinkEditorViewState();
}

class _ChatInviteLinkEditorViewState extends State<ChatInviteLinkEditorView> {
  late final _name = TextEditingController(
    text: widget.existing?.str('name') ?? '',
  );
  late final _limit = TextEditingController(
    text: '${widget.existing?.integer('member_limit') ?? 0}',
  );
  late int _expiration = widget.existing?.integer('expiration_date') ?? 0;
  late bool _approval =
      widget.existing?.boolean('creates_join_request') ?? false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _limit.dispose();
    super.dispose();
  }

  Future<void> _pickExpiration() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: context.colors.card,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AdminNavRow(
              title: 'Never expires',
              onTap: () => Navigator.of(sheetContext).pop(0),
            ),
            for (final option in const [
              (86400, '1 day'),
              (604800, '1 week'),
              (2592000, '1 month'),
            ])
              _AdminNavRow(
                title: option.$2,
                onTap: () => Navigator.of(sheetContext).pop(now + option.$1),
              ),
          ],
        ),
      ),
    );
    if (selected != null) setState(() => _expiration = selected);
  }

  Future<void> _save() async {
    if (_saving || _name.text.characters.length > 32) return;
    final limit = int.tryParse(_limit.text) ?? 0;
    if (limit < 0 || limit > 99999) {
      showToast(context, 'Member limit must be between 0 and 99999');
      return;
    }
    setState(() => _saving = true);
    try {
      final existing = widget.existing;
      if (existing == null) {
        await widget.service.createInviteLink(
          chatId: widget.chatId,
          name: _name.text,
          expirationDate: _expiration,
          memberLimit: limit,
          createsJoinRequest: _approval,
        );
      } else {
        await widget.service.editInviteLink(
          chatId: widget.chatId,
          inviteLink: existing.str('invite_link') ?? '',
          name: _name.text,
          expirationDate: _expiration,
          memberLimit: limit,
          createsJoinRequest: _approval,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showToast(context, 'Couldn’t save invite link: $error');
    }
  }

  @override
  Widget build(BuildContext context) => _AdminPage(
    title: widget.existing == null ? 'New invite link' : 'Edit invite link',
    trailing: _AdminSaveButton(onTap: _save, saving: _saving),
    child: ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _AdminSection(
          title: 'Link settings',
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: TextField(
                controller: _name,
                maxLength: 32,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  counterText: '',
                  border: InputBorder.none,
                ),
              ),
            ),
            _AdminNavRow(
              title: 'Expiration',
              value: _expiration == 0
                  ? 'Never'
                  : DateTime.fromMillisecondsSinceEpoch(
                      _expiration * 1000,
                    ).toLocal().toString().substring(0, 16),
              onTap: _pickExpiration,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: TextField(
                controller: _limit,
                enabled: !_approval,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Member limit (0 is unlimited)',
                  border: InputBorder.none,
                ),
              ),
            ),
            _AdminSwitchRow(
              title: 'Request administrator approval',
              value: _approval,
              onChanged: (value) => setState(() => _approval = value),
            ),
          ],
        ),
      ],
    ),
  );
}

class InviteLinkAnalyticsView extends StatefulWidget {
  const InviteLinkAnalyticsView({
    super.key,
    required this.chatId,
    required this.inviteLink,
    required this.service,
  });

  final int chatId;
  final String inviteLink;
  final GroupAdministrationService service;

  @override
  State<InviteLinkAnalyticsView> createState() =>
      _InviteLinkAnalyticsViewState();
}

class _InviteLinkAnalyticsViewState extends State<InviteLinkAnalyticsView> {
  List<Map<String, dynamic>> _members = const [];
  final Map<int, String> _names = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final members = await widget.service.inviteLinkMembers(
        widget.chatId,
        widget.inviteLink,
      );
      await Future.wait([
        for (final member in members)
          if (member.int64('user_id') case final int id)
            widget.service
                .getUser(id)
                .then(
                  (user) => _names[id] = _userName(user, id),
                  onError: (_) => _names[id] = 'User $id',
                ),
      ]);
      if (mounted) {
        setState(() {
          _members = members;
          _loading = false;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      showToast(context, 'Couldn’t load invite analytics: $error');
    }
  }

  @override
  Widget build(BuildContext context) => _AdminPage(
    title: 'Invite link analytics',
    child: _loading
        ? const Center(child: AppActivityIndicator())
        : ListView(
            padding: const EdgeInsets.all(14),
            children: [
              _AdminSection(
                title: '${_members.length} joined members',
                children: _members.isEmpty
                    ? const [
                        _AdminEmptyRow('No members joined through this link'),
                      ]
                    : [
                        for (final member in _members)
                          _AdminNavRow(
                            title:
                                _names[member.int64('user_id')] ??
                                'User ${member.int64('user_id') ?? ''}',
                            value:
                                member.boolean('via_chat_folder_invite_link') ==
                                    true
                                ? 'Via shared folder'
                                : _dateLabel(
                                    member.integer('joined_chat_date') ?? 0,
                                  ),
                          ),
                      ],
              ),
            ],
          ),
  );
}

class ChatJoinRequestsAdministrationView extends StatefulWidget {
  const ChatJoinRequestsAdministrationView({super.key, required this.chatId});

  final int chatId;

  @override
  State<ChatJoinRequestsAdministrationView> createState() =>
      _ChatJoinRequestsAdministrationViewState();
}

class _ChatJoinRequestsAdministrationViewState
    extends State<ChatJoinRequestsAdministrationView> {
  final _service = GroupAdministrationService();
  final Map<int, String> _names = {};
  List<Map<String, dynamic>> _requests = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final requests = await _service.joinRequests(widget.chatId);
      await Future.wait([
        for (final request in requests)
          if (request.int64('user_id') case final int id)
            _service
                .getUser(id)
                .then(
                  (user) => _names[id] = _userName(user, id),
                  onError: (_) => _names[id] = 'User $id',
                ),
      ]);
      if (mounted) {
        setState(() {
          _requests = requests;
          _loading = false;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      showToast(context, 'Couldn’t load join requests: $error');
    }
  }

  Future<void> _process(int userId, bool approve) async {
    try {
      await _service.processJoinRequest(
        widget.chatId,
        userId,
        approve: approve,
      );
      if (mounted) {
        setState(
          () => _requests.removeWhere((r) => r.int64('user_id') == userId),
        );
      }
    } catch (error) {
      if (mounted) showToast(context, 'Couldn’t process join request: $error');
    }
  }

  Future<void> _processAll(bool approve) async {
    if (_requests.isEmpty) return;
    try {
      await _service.processAllJoinRequests(widget.chatId, approve: approve);
      if (mounted) setState(() => _requests = const []);
    } catch (error) {
      if (mounted) showToast(context, 'Couldn’t process join requests: $error');
    }
  }

  @override
  Widget build(BuildContext context) => _AdminPage(
    title: 'Join requests',
    child: _loading
        ? const Center(child: AppActivityIndicator())
        : ListView(
            padding: const EdgeInsets.all(14),
            children: [
              if (_requests.isNotEmpty) ...[
                Row(
                  children: [
                    Expanded(
                      child: _AdminActionButton(
                        label: 'Approve all',
                        onTap: () => _processAll(true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _AdminActionButton(
                        label: 'Decline all',
                        destructive: true,
                        onTap: () => _processAll(false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              _AdminSection(
                title: '${_requests.length} pending',
                children: _requests.isEmpty
                    ? const [_AdminEmptyRow('No pending join requests')]
                    : [
                        for (final request in _requests)
                          _joinRequestRow(request),
                      ],
              ),
            ],
          ),
  );

  Widget _joinRequestRow(Map<String, dynamic> request) {
    final id = request.int64('user_id') ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _names[id] ?? 'User $id',
                  style: AppTextStyle.bodyLarge(context.colors.textPrimary),
                ),
                if ((request.str('bio') ?? '').isNotEmpty)
                  Text(
                    request.str('bio')!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.footnote(context.colors.textSecondary),
                  ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _process(id, true),
            child: Padding(
              padding: const EdgeInsets.all(7),
              child: AppIcon(
                HeroAppIcons.circleCheck,
                size: 24,
                color: AppTheme.brand,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => _process(id, false),
            child: const Padding(
              padding: EdgeInsets.all(7),
              child: AppIcon(
                HeroAppIcons.circleXmark,
                size: 24,
                color: Color(0xFFFF3B30),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ForumTopicsAdministrationView extends StatefulWidget {
  const ForumTopicsAdministrationView({super.key, required this.chatId});

  final int chatId;

  @override
  State<ForumTopicsAdministrationView> createState() =>
      _ForumTopicsAdministrationViewState();
}

class _ForumTopicsAdministrationViewState
    extends State<ForumTopicsAdministrationView> {
  static const _colors = [
    0x6FB9F0,
    0xFFD67E,
    0xCB86DB,
    0x8EEE98,
    0xFF93B2,
    0xFB6F5F,
  ];
  final _service = GroupAdministrationService();
  List<Map<String, dynamic>> _topics = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final topics = await _service.forumTopics(widget.chatId);
      if (mounted) {
        setState(() {
          _topics = topics;
          _loading = false;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      showToast(context, 'Couldn’t load forum topics: $error');
    }
  }

  Future<_ForumTopicDraft?> _askTopic(
    String title, {
    required String initialName,
    required int initialColor,
    required int initialCustomEmojiId,
    required bool canChangeColor,
  }) async {
    final controller = TextEditingController(text: initialName);
    var color = initialColor;
    var customEmojiId = initialCustomEmojiId;
    final value = await showGeneralDialog<_ForumTopicDraft>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cancel',
      barrierColor: const Color(0x99000000),
      pageBuilder: (dialogContext, _, _) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => _AdminDialog(
          title: title,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                maxLength: 128,
                decoration: const InputDecoration(hintText: 'Topic name'),
              ),
              const SizedBox(height: 8),
              if (canChangeColor) ...[
                const Text('Icon color'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  children: [
                    for (final candidate in _colors)
                      GestureDetector(
                        onTap: () => setDialogState(() => color = candidate),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF000000 | candidate),
                            border: color == candidate
                                ? Border.all(color: AppTheme.brand, width: 3)
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () async {
                  final id = await Navigator.of(dialogContext).push<int>(
                    MaterialPageRoute(
                      builder: (_) => ProfileIconPickerView(
                        selectedId: customEmojiId,
                        title: 'Topic icon',
                        source: ProfileIconSource.status,
                      ),
                    ),
                  );
                  if (id != null) {
                    setDialogState(() => customEmojiId = id);
                  }
                },
                child: Row(
                  children: [
                    const Expanded(child: Text('Custom emoji icon')),
                    if (customEmojiId == 0)
                      const Text('None')
                    else
                      CustomEmojiView(id: customEmojiId, size: 28),
                    const SizedBox(width: 8),
                    const AppIcon(HeroAppIcons.chevronRight, size: 15),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            _AdminDialogAction(
              label: 'Cancel',
              onTap: () => Navigator.of(dialogContext).pop(),
            ),
            _AdminDialogAction(
              label: 'Save',
              color: AppTheme.brand,
              onTap: () => Navigator.of(dialogContext).pop(
                _ForumTopicDraft(
                  name: controller.text.trim(),
                  color: color,
                  customEmojiId: customEmojiId,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return value;
  }

  Future<void> _create() async {
    final draft = await _askTopic(
      'New topic',
      initialName: '',
      initialColor: _colors[_topics.length % _colors.length],
      initialCustomEmojiId: 0,
      canChangeColor: true,
    );
    if (draft == null || draft.name.isEmpty) return;
    try {
      await _service.createForumTopic(
        chatId: widget.chatId,
        name: draft.name,
        color: draft.color,
        customEmojiId: draft.customEmojiId,
      );
      await _load();
    } catch (error) {
      if (mounted) showToast(context, 'Couldn’t create topic: $error');
    }
  }

  Future<void> _edit(Map<String, dynamic> topic) async {
    final info = topic.obj('info');
    final id = info?.integer('forum_topic_id');
    if (id == null || info?.boolean('is_general') == true) return;
    final icon = info?.obj('icon');
    final draft = await _askTopic(
      'Edit topic',
      initialName: info?.str('name') ?? '',
      initialColor: icon?.integer('color') ?? _colors.first,
      initialCustomEmojiId: icon?.int64('custom_emoji_id') ?? 0,
      canChangeColor: false,
    );
    if (draft == null || draft.name.isEmpty) return;
    try {
      await _service.editForumTopic(
        chatId: widget.chatId,
        forumTopicId: id,
        name: draft.name,
        customEmojiId: draft.customEmojiId,
      );
      await _load();
    } catch (error) {
      if (mounted) showToast(context, 'Couldn’t edit topic: $error');
    }
  }

  Future<void> _delete(Map<String, dynamic> topic) async {
    final info = topic.obj('info');
    final id = info?.integer('forum_topic_id');
    if (id == null || info?.boolean('is_general') == true) return;
    final ok = await showAppConfirmDialog(
      context,
      title: 'Delete “${info?.str('name') ?? 'topic'}” and all messages?',
      confirmText: 'Delete',
    );
    if (!ok) return;
    try {
      await _service.deleteForumTopic(widget.chatId, id);
      await _load();
    } catch (error) {
      if (mounted) showToast(context, 'Couldn’t delete topic: $error');
    }
  }

  Future<void> _togglePinned(Map<String, dynamic> topic) async {
    final id = topic.obj('info')?.integer('forum_topic_id');
    if (id == null) return;
    try {
      await _service.toggleForumTopicPinned(
        widget.chatId,
        id,
        !(topic.boolean('is_pinned') ?? false),
      );
      await _load();
    } catch (error) {
      if (mounted) showToast(context, 'Couldn’t pin topic: $error');
    }
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final pinned = _topics
        .where((topic) => topic.boolean('is_pinned') == true)
        .toList();
    if (oldIndex >= pinned.length || newIndex >= pinned.length) return;
    final previous = List<Map<String, dynamic>>.of(_topics);
    pinned.insert(newIndex, pinned.removeAt(oldIndex));
    final unpinned = _topics.where(
      (topic) => topic.boolean('is_pinned') != true,
    );
    setState(() => _topics = [...pinned, ...unpinned]);
    try {
      await _service.reorderPinnedForumTopics(widget.chatId, [
        for (final topic in pinned)
          if (topic.obj('info')?.integer('forum_topic_id') case final int id)
            id,
      ]);
    } catch (error) {
      if (!mounted) return;
      setState(() => _topics = previous);
      showToast(context, 'Couldn’t reorder pinned topics: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final pinned = _topics
        .where((topic) => topic.boolean('is_pinned') == true)
        .toList();
    final others = _topics
        .where((topic) => topic.boolean('is_pinned') != true)
        .toList();
    return _AdminPage(
      title: 'Forum topics',
      trailing: GestureDetector(
        onTap: _create,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: AppIcon(HeroAppIcons.plus, size: 23, color: AppTheme.brand),
        ),
      ),
      child: _loading
          ? const Center(child: AppActivityIndicator())
          : ListView(
              padding: const EdgeInsets.all(14),
              children: [
                if (pinned.isNotEmpty) ...[
                  Text(
                    'Pinned topics · drag to reorder',
                    style: AppTextStyle.footnote(context.colors.textTertiary),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: context.colors.card,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ReorderableListView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      buildDefaultDragHandles: false,
                      onReorderItem: _reorder,
                      children: [
                        for (var index = 0; index < pinned.length; index++)
                          _topicRow(pinned[index], index: index),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                _AdminSection(
                  title: 'All topics',
                  children: others.isEmpty
                      ? const [_AdminEmptyRow('No other topics')]
                      : [for (final topic in others) _topicRow(topic)],
                ),
              ],
            ),
    );
  }

  Widget _topicRow(Map<String, dynamic> topic, {int? index}) {
    final info = topic.obj('info');
    final pinned = topic.boolean('is_pinned') ?? false;
    final general = info?.boolean('is_general') ?? false;
    return Container(
      key: ValueKey('forum-topic-${info?.integer('forum_topic_id') ?? 0}'),
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _edit(topic),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  info?.str('name') ?? 'Topic',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.bodyLarge(context.colors.textPrimary),
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: () => _togglePinned(topic),
            child: Padding(
              padding: const EdgeInsets.all(7),
              child: AppIcon(
                pinned ? HeroAppIcons.solidStar : HeroAppIcons.star,
                size: 18,
                color: pinned ? AppTheme.brand : context.colors.textTertiary,
              ),
            ),
          ),
          if (!general)
            GestureDetector(
              onTap: () => _delete(topic),
              child: const Padding(
                padding: EdgeInsets.all(7),
                child: AppIcon(
                  HeroAppIcons.trash,
                  size: 18,
                  color: Color(0xFFFF3B30),
                ),
              ),
            ),
          if (index != null)
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.all(7),
                child: AppIcon(
                  HeroAppIcons.grip,
                  size: 18,
                  color: context.colors.textTertiary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ForumTopicDraft {
  const _ForumTopicDraft({
    required this.name,
    required this.color,
    required this.customEmojiId,
  });

  final String name;
  final int color;
  final int customEmojiId;
}

class ChatStatisticsAdministrationView extends StatefulWidget {
  const ChatStatisticsAdministrationView({super.key, required this.chatId});

  final int chatId;

  @override
  State<ChatStatisticsAdministrationView> createState() =>
      _ChatStatisticsAdministrationViewState();
}

class _ChatStatisticsAdministrationViewState
    extends State<ChatStatisticsAdministrationView> {
  final _service = GroupAdministrationService();
  Map<String, dynamic>? _statistics;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final stats = await _service.statistics(
        widget.chatId,
        dark: context.colors.background.computeLuminance() < 0.45,
      );
      if (mounted) {
        setState(() {
          _statistics = stats;
          _loading = false;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      showToast(context, 'Statistics aren’t available: $error');
    }
  }

  @override
  Widget build(BuildContext context) => _AdminPage(
    title: 'Statistics',
    child: _loading
        ? const Center(child: AppActivityIndicator())
        : _statistics == null
        ? const Center(child: Text('Statistics are unavailable for this chat'))
        : ListView(
            padding: const EdgeInsets.all(14),
            children: [
              _AdminSection(
                title: 'Overview',
                children: [
                  for (final entry in _statRows(_statistics!))
                    _AdminNavRow(title: entry.$1, value: entry.$2),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Detailed graph data is loaded from Telegram and summarized here.',
                style: AppTextStyle.footnote(context.colors.textTertiary),
              ),
            ],
          ),
  );

  List<(String, String)> _statRows(Map<String, dynamic> value) {
    String current(String key) {
      final stat = value.obj(key);
      final current = stat?.dbl('current');
      return current == null ? '—' : current.round().toString();
    }

    if (value.type == 'chatStatisticsChannel') {
      return [
        ('Members', current('member_count')),
        ('Average message views', current('mean_message_view_count')),
        ('Average shares', current('mean_message_share_count')),
        ('Average reactions', current('mean_message_reaction_count')),
        (
          'Notifications enabled',
          '${value.dbl('enabled_notifications_percentage')?.toStringAsFixed(1) ?? '—'}%',
        ),
      ];
    }
    return [
      ('Members', current('member_count')),
      ('Messages', current('message_count')),
      ('Viewers', current('viewer_count')),
      ('Senders', current('sender_count')),
    ];
  }
}

class ChatBoostsAdministrationView extends StatefulWidget {
  const ChatBoostsAdministrationView({super.key, required this.chatId});

  final int chatId;

  @override
  State<ChatBoostsAdministrationView> createState() =>
      _ChatBoostsAdministrationViewState();
}

class _ChatBoostsAdministrationViewState
    extends State<ChatBoostsAdministrationView> {
  final _service = GroupAdministrationService();
  Map<String, dynamic>? _status;
  String _link = '';
  List<Map<String, dynamic>> _boosts = const [];
  List<Map<String, dynamic>> _premiumOptions = const [];
  List<Map<String, dynamic>> _starOptions = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait([
        _service.boostStatus(widget.chatId),
        _service.boostLink(widget.chatId),
        _service.boosts(widget.chatId),
        _service.premiumGiveawayOptions(widget.chatId),
        _service.starGiveawayOptions(),
      ]);
      if (!mounted) return;
      setState(() {
        _status = values[0];
        _link = values[1].str('link') ?? '';
        _boosts = values[2].objects('boosts') ?? const [];
        _premiumOptions = values[3].objects('options') ?? const [];
        _starOptions = values[4].objects('options') ?? const [];
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      showToast(context, 'Couldn’t load boosts: $error');
    }
  }

  Future<void> _copyLink() async {
    if (_link.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _link));
    if (mounted) showToast(context, 'Boost link copied');
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return _AdminPage(
      title: 'Boosts and giveaways',
      child: _loading
          ? const Center(child: AppActivityIndicator())
          : ListView(
              padding: const EdgeInsets.all(14),
              children: [
                _AdminSection(
                  title: 'Boost status',
                  children: [
                    _AdminNavRow(
                      title: 'Level',
                      value: '${status?.integer('level') ?? 0}',
                    ),
                    _AdminNavRow(
                      title: 'Boosts',
                      value:
                          '${status?.integer('boost_count') ?? _boosts.length}',
                    ),
                    _AdminNavRow(
                      title: 'Next level',
                      value:
                          '${status?.integer('next_level_boost_count') ?? 0}',
                    ),
                    if (_link.isNotEmpty)
                      _AdminNavRow(
                        title: 'Copy boost link',
                        value: _link,
                        onTap: _copyLink,
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                _AdminSection(
                  title: 'Giveaway entry points',
                  children: [
                    _AdminNavRow(
                      title: 'Premium giveaways',
                      value: '${_premiumOptions.length} purchase options',
                    ),
                    _AdminNavRow(
                      title: 'Star giveaways',
                      value: '${_starOptions.length} purchase options',
                    ),
                    if ((status?.objects('prepaid_giveaways') ?? const [])
                        .isNotEmpty)
                      _AdminNavRow(
                        title: 'Prepaid giveaways',
                        value:
                            '${status?.objects('prepaid_giveaways')?.length ?? 0} ready to launch',
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Purchases are completed by the platform payment flow. Existing prepaid giveaways can be launched after selecting their Telegram payment record.',
                  style: AppTextStyle.footnote(context.colors.textTertiary),
                ),
              ],
            ),
    );
  }
}

class _AdminPage extends StatelessWidget {
  const _AdminPage({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.colors.groupedBackground,
    body: Column(
      children: [
        NavHeader(
          title: title,
          onBack: () => Navigator.of(context).pop(),
          trailing: trailing,
        ),
        Expanded(child: child),
      ],
    ),
  );
}

class _AdminSection extends StatelessWidget {
  const _AdminSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 7),
        child: Text(
          title,
          style: AppTextStyle.footnote(context.colors.textTertiary),
        ),
      ),
      Container(
        decoration: BoxDecoration(
          color: context.colors.card,
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var index = 0; index < children.length; index++) ...[
              if (index > 0) const InsetDivider(leadingInset: 14),
              children[index],
            ],
          ],
        ),
      ),
    ],
  );
}

class _AdminNavRow extends StatelessWidget {
  const _AdminNavRow({
    required this.title,
    this.value,
    this.onTap,
    this.leading,
    this.trailing,
  });

  final String title;
  final String? value;
  final VoidCallback? onTap;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 54),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 10)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.bodyLarge(context.colors.textPrimary),
                  ),
                  if (value != null && value!.isNotEmpty)
                    Text(
                      value!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.footnote(
                        context.colors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else if (onTap != null)
              AppIcon(
                HeroAppIcons.chevronRight,
                size: 15,
                color: context.colors.textTertiary,
              ),
          ],
        ),
      ),
    ),
  );
}

class _AdminSwitchRow extends StatelessWidget {
  const _AdminSwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 54,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: AppTextStyle.bodyLarge(context.colors.textPrimary),
            ),
          ),
          _AdminToggle(value: value, onChanged: onChanged),
        ],
      ),
    ),
  );
}

class _AdminToggle extends StatelessWidget {
  const _AdminToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => onChanged(!value),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      width: 46,
      height: 28,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: value ? AppTheme.brand : context.colors.textTertiary,
        borderRadius: BorderRadius.circular(14),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
            color: Color(0xFFFFFFFF),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 3,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _AdminDiscreteSlider extends StatelessWidget {
  const _AdminDiscreteSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  void _update(double dx, double width) {
    final fraction = (dx / width).clamp(0.0, 1.0);
    onChanged((min + (max - min) * fraction).roundToDouble());
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, constraints) {
      final fraction = ((value - min) / (max - min)).clamp(0.0, 1.0);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) =>
            _update(details.localPosition.dx, constraints.maxWidth),
        onHorizontalDragUpdate: (details) =>
            _update(details.localPosition.dx, constraints.maxWidth),
        child: SizedBox(
          height: 40,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: 4,
                decoration: BoxDecoration(
                  color: context.colors.textTertiary.withValues(alpha: 0.32),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              FractionallySizedBox(
                widthFactor: fraction,
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.brand,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Positioned(
                left: (constraints.maxWidth - 22) * fraction,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: AppTheme.brand,
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(color: Color(0x33000000), blurRadius: 4),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _AdminDialog extends StatelessWidget {
  const _AdminDialog({
    required this.title,
    required this.content,
    required this.actions,
  });

  final String title;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.colors.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: context.colors.divider, width: 0.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x44000000),
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: DefaultTextStyle(
            style: AppTextStyle.body(context.colors.textPrimary),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: AppTextStyle.title(context.colors.textPrimary),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
                    child: content,
                  ),
                ),
                Container(height: 0.5, color: context.colors.divider),
                SizedBox(height: 50, child: Row(children: actions)),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _AdminDialogAction extends StatelessWidget {
  const _AdminDialogAction({
    required this.label,
    required this.onTap,
    this.color,
  });

  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: Text(
          label,
          style: AppTextStyle.bodyLarge(
            color ?? context.colors.textSecondary,
            weight: AppTextWeight.semibold,
          ),
        ),
      ),
    ),
  );
}

class _AdminChoiceRow extends StatelessWidget {
  const _AdminChoiceRow({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _AdminNavRow(
    title: title,
    onTap: onTap,
    trailing: AppIcon(
      selected ? HeroAppIcons.circleCheck : HeroAppIcons.circle,
      size: 21,
      color: selected ? AppTheme.brand : context.colors.textTertiary,
    ),
  );
}

class _AdminSaveButton extends StatelessWidget {
  const _AdminSaveButton({required this.onTap, required this.saving});

  final VoidCallback onTap;
  final bool saving;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: saving ? null : onTap,
    child: Padding(
      padding: const EdgeInsets.all(7),
      child: saving
          ? const AppActivityIndicator(size: 19)
          : Text(
              'Save',
              style: AppTextStyle.bodyLarge(
                AppTheme.brand,
                weight: AppTextWeight.semibold,
              ),
            ),
    ),
  );
}

class _AdminEmptyRow extends StatelessWidget {
  const _AdminEmptyRow(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(18),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: AppTextStyle.body(context.colors.textSecondary),
    ),
  );
}

class _AdminActionButton extends StatelessWidget {
  const _AdminActionButton({
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: destructive
            ? const Color(0xFFFF3B30).withValues(alpha: 0.12)
            : AppTheme.brand.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Text(
        label,
        style: AppTextStyle.body(
          destructive ? const Color(0xFFFF3B30) : AppTheme.brand,
          weight: AppTextWeight.semibold,
        ),
      ),
    ),
  );
}

String _dateLabel(int unix) {
  if (unix <= 0) return '';
  final date = DateTime.fromMillisecondsSinceEpoch(unix * 1000).toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)}';
}

String _userName(Map<String, dynamic> user, int id) {
  final name = '${user.str('first_name') ?? ''} ${user.str('last_name') ?? ''}'
      .trim();
  return name.isEmpty ? 'User $id' : name;
}
