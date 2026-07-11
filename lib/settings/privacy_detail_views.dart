//
//  privacy_detail_views.dart
//
//  Real-TDLib detail screens behind 隐私与安全: a privacy-rule chooser
//  (getUserPrivacySettingRules / setUserPrivacySettingRules), active sessions
//  (getActiveSessions / terminateSession) and the block list
//  (getBlockedMessageSenders / setMessageSenderBlockList).
//

import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../chat/chat_picker_view.dart';
import '../chat/image_edit_view.dart';
import '../components/app_icons.dart';
import '../components/confirm_dialog.dart';
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../media/app_asset_picker.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import 'keyword_blocker.dart';
import 'privacy_rule_options.dart';
import 'qr_login_scanner_view.dart';

// MARK: - Privacy rule chooser (所有人 / 我的联系人 / 没有人)

class PrivacyRuleView extends StatefulWidget {
  const PrivacyRuleView({
    super.key,
    required this.title,
    required this.setting,
  });
  final String title;
  final String setting; // e.g. userPrivacySettingShowStatus

  @override
  State<PrivacyRuleView> createState() => _PrivacyRuleViewState();
}

class _PrivacyRuleViewState extends State<PrivacyRuleView> {
  final TdClient _client = TdClient.shared;
  PrivacyRuleSelection _selection = const PrivacyRuleSelection(
    visibility: PrivacyVisibilityOption.everyone,
  );
  final List<_PrivacyException> _allowExceptions = [];
  final List<_PrivacyException> _restrictExceptions = [];
  Map<String, dynamic>? _publicPhoto;
  TdFileRef? _publicPhotoRef;
  PrivacyVisibilityOption _phoneDiscovery = PrivacyVisibilityOption.everyone;
  PrivacyVisibilityOption _peerToPeerCalls = PrivacyVisibilityOption.everyone;
  bool _showReadDate = true;
  bool _loading = true;

  static const _labels = [
    AppStringKeys.privacyVisibilityEveryone,
    AppStringKeys.privacyVisibilityContacts,
    AppStringKeys.privacyVisibilityNobody,
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await _client.query({
        '@type': 'getUserPrivacySettingRules',
        'setting': {'@type': widget.setting},
      });
      final rules = res.objects('rules') ?? const <Map<String, dynamic>>[];
      _selection = PrivacyRuleSelection.fromRules(rules);
      await _loadExceptions();
      if (_isProfilePhoto) await _loadPublicPhoto();
      if (_isPhoneNumber) {
        _phoneDiscovery = await _loadAuxiliaryVisibility(
          'userPrivacySettingAllowFindingByPhoneNumber',
        );
      }
      if (_isCalls) {
        _peerToPeerCalls = await _loadAuxiliaryVisibility(
          'userPrivacySettingAllowPeerToPeerCalls',
        );
      }
      if (_isLastSeen) {
        final settings = await _client.query({
          '@type': 'getReadDatePrivacySettings',
        });
        _showReadDate = settings.boolean('show_read_date') ?? true;
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  bool get _isProfilePhoto =>
      widget.setting == 'userPrivacySettingShowProfilePhoto';
  bool get _isPhoneNumber =>
      widget.setting == 'userPrivacySettingShowPhoneNumber';
  bool get _isCalls => widget.setting == 'userPrivacySettingAllowCalls';
  bool get _isLastSeen => widget.setting == 'userPrivacySettingShowStatus';

  Future<PrivacyVisibilityOption> _loadAuxiliaryVisibility(
    String setting,
  ) async {
    final result = await _client.query({
      '@type': 'getUserPrivacySettingRules',
      'setting': {'@type': setting},
    });
    return privacyVisibilityFromRules(
      result.objects('rules') ?? const <Map<String, dynamic>>[],
    );
  }

  Future<void> _setAuxiliaryVisibility(
    String setting,
    PrivacyVisibilityOption visibility,
  ) async {
    try {
      await _client.query({
        '@type': 'setUserPrivacySettingRules',
        'setting': {'@type': setting},
        'rules': {
          '@type': 'userPrivacySettingRules',
          'rules': [
            {'@type': visibility.ruleType},
          ],
        },
      });
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    }
  }

  Future<void> _setPhoneDiscovery(PrivacyVisibilityOption visibility) async {
    setState(() => _phoneDiscovery = visibility);
    await _setAuxiliaryVisibility(
      'userPrivacySettingAllowFindingByPhoneNumber',
      visibility,
    );
  }

  Future<void> _openPeerToPeerCalls() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => const PrivacyRuleView(
          title: AppStringKeys.privacyPeerToPeerCalls,
          setting: 'userPrivacySettingAllowPeerToPeerCalls',
        ),
      ),
    );
    try {
      final visibility = await _loadAuxiliaryVisibility(
        'userPrivacySettingAllowPeerToPeerCalls',
      );
      if (mounted) setState(() => _peerToPeerCalls = visibility);
    } catch (_) {}
  }

  Future<void> _setShowReadDate(bool value) async {
    setState(() => _showReadDate = value);
    try {
      await _client.query({
        '@type': 'setReadDatePrivacySettings',
        'settings': {
          '@type': 'readDatePrivacySettings',
          'show_read_date': value,
        },
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _showReadDate = !value);
      showToast(context, error.toString());
    }
  }

  Future<void> _select(int v) async {
    final visibility = PrivacyVisibilityOption.values[v];
    setState(() {
      _selection = _selection.copyWith(
        visibility: visibility,
        allowUserIds: visibility == PrivacyVisibilityOption.everyone
            ? <int>{}
            : null,
        allowChatIds: visibility == PrivacyVisibilityOption.everyone
            ? <int>{}
            : null,
        restrictUserIds: visibility == PrivacyVisibilityOption.nobody
            ? <int>{}
            : null,
        restrictChatIds: visibility == PrivacyVisibilityOption.nobody
            ? <int>{}
            : null,
      );
      if (visibility == PrivacyVisibilityOption.everyone) {
        _allowExceptions.clear();
      }
      if (visibility == PrivacyVisibilityOption.nobody) {
        _restrictExceptions.clear();
      }
    });
    await _saveRules();
  }

  Future<void> _saveRules() async {
    try {
      await _client.query({
        '@type': 'setUserPrivacySettingRules',
        'setting': {'@type': widget.setting},
        'rules': {
          '@type': 'userPrivacySettingRules',
          'rules': _selection.toRules(),
        },
      });
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    }
  }

  Future<void> _loadExceptions() async {
    _allowExceptions
      ..clear()
      ..addAll(
        await _resolveExceptions(
          _selection.allowUserIds,
          _selection.allowChatIds,
        ),
      );
    _restrictExceptions
      ..clear()
      ..addAll(
        await _resolveExceptions(
          _selection.restrictUserIds,
          _selection.restrictChatIds,
        ),
      );
  }

  Future<List<_PrivacyException>> _resolveExceptions(
    Set<int> userIds,
    Set<int> chatIds,
  ) async {
    final entries = <_PrivacyException>[];
    for (final id in userIds) {
      try {
        final user = await _client.query({'@type': 'getUser', 'user_id': id});
        entries.add(
          _PrivacyException(
            id: id,
            isUser: true,
            title: TDParse.userName(user),
            photo: TDParse.smallPhoto(user.obj('profile_photo')),
          ),
        );
      } catch (_) {
        entries.add(_PrivacyException(id: id, isUser: true, title: '$id'));
      }
    }
    for (final id in chatIds) {
      try {
        final chat = await _client.query({'@type': 'getChat', 'chat_id': id});
        entries.add(
          _PrivacyException(
            id: id,
            isUser: false,
            title: chat.str('title') ?? '$id',
            photo: TDParse.smallPhoto(chat.obj('photo')),
          ),
        );
      } catch (_) {
        entries.add(_PrivacyException(id: id, isUser: false, title: '$id'));
      }
    }
    entries.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );
    return entries;
  }

  Future<void> _addException({required bool allow}) async {
    final chat = await Navigator.of(context).push<ChatSummary>(
      MaterialPageRoute(
        builder: (_) => const ChatPickerView(
          title: AppStringKeys.privacyAddUsers,
          allowChannels: false,
        ),
      ),
    );
    if (chat == null || !mounted) return;
    final isUser = chat.peerUserId != null;
    if (!isUser && chat.kind != ChatKind.group) return;
    final id = chat.peerUserId ?? chat.id;
    final entry = _PrivacyException(
      id: id,
      isUser: isUser,
      title: chat.title,
      photo: chat.photo,
    );
    final allowUsers = {..._selection.allowUserIds};
    final allowChats = {..._selection.allowChatIds};
    final restrictUsers = {..._selection.restrictUserIds};
    final restrictChats = {..._selection.restrictChatIds};
    if (isUser) {
      (allow ? allowUsers : restrictUsers).add(id);
      (allow ? restrictUsers : allowUsers).remove(id);
    } else {
      (allow ? allowChats : restrictChats).add(id);
      (allow ? restrictChats : allowChats).remove(id);
    }
    setState(() {
      _selection = _selection.copyWith(
        allowUserIds: allowUsers,
        allowChatIds: allowChats,
        restrictUserIds: restrictUsers,
        restrictChatIds: restrictChats,
      );
      _allowExceptions.removeWhere((e) => e.sameTarget(entry));
      _restrictExceptions.removeWhere((e) => e.sameTarget(entry));
      (allow ? _allowExceptions : _restrictExceptions).add(entry);
    });
    await _saveRules();
  }

  Future<void> _removeException(
    _PrivacyException entry, {
    required bool allow,
  }) async {
    final allowUsers = {..._selection.allowUserIds};
    final allowChats = {..._selection.allowChatIds};
    final restrictUsers = {..._selection.restrictUserIds};
    final restrictChats = {..._selection.restrictChatIds};
    final target = entry.isUser
        ? (allow ? allowUsers : restrictUsers)
        : (allow ? allowChats : restrictChats);
    target.remove(entry.id);
    setState(() {
      _selection = _selection.copyWith(
        allowUserIds: allowUsers,
        allowChatIds: allowChats,
        restrictUserIds: restrictUsers,
        restrictChatIds: restrictChats,
      );
      (allow ? _allowExceptions : _restrictExceptions).remove(entry);
    });
    await _saveRules();
  }

  Future<void> _loadPublicPhoto() async {
    final me = await _client.query({'@type': 'getMe'});
    final userId = me.int64('id');
    if (userId == null) return;
    final full = await _client.query({
      '@type': 'getUserFullInfo',
      'user_id': userId,
    });
    _setPublicPhoto(full.obj('public_photo'));
  }

  void _setPublicPhoto(Map<String, dynamic>? photo) {
    _publicPhoto = photo;
    final sizes = photo?.objects('sizes') ?? const <Map<String, dynamic>>[];
    if (sizes.isEmpty) {
      _publicPhotoRef = null;
      return;
    }
    final sorted = [...sizes]
      ..sort(
        (a, b) => (a.integer('width') ?? 0).compareTo(b.integer('width') ?? 0),
      );
    _publicPhotoRef = TDParse.fileRef(
      sorted.first.obj('photo'),
      miniThumb: TDParse.decodeMiniThumb(photo?.obj('minithumbnail')),
    );
  }

  Future<void> _updatePublicPhoto() async {
    try {
      final images = await AppAssetPicker.pick(
        context,
        type: AppAssetPickerType.image,
        maxAssets: 1,
      );
      if (images.isEmpty || !mounted) return;
      final image = images.first;
      final edited = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => ImageEditView(sourcePath: image.path, avatar: true),
        ),
      );
      if (edited == null) return;
      final file = File(edited);
      if (!await file.exists() || await file.length() == 0) return;
      await _client.query({
        '@type': 'setProfilePhoto',
        'photo': {
          '@type': 'inputChatPhotoStatic',
          'photo': {'@type': 'inputFileLocal', 'path': edited},
        },
        'is_public': true,
      });
      await Future<void>.delayed(const Duration(milliseconds: 800));
      await _loadPublicPhoto();
      if (mounted) {
        setState(() {});
        showToast(
          context,
          AppStrings.t(AppStringKeys.privacyPublicPhotoUpdated),
        );
      }
    } catch (error) {
      if (mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.privacyPublicPhotoUpdateFailed, {
            'value1': error,
          }),
        );
      }
    }
  }

  Future<void> _removePublicPhoto() async {
    final id = _publicPhoto?.int64('id');
    if (id == null) return;
    final confirmed = await confirmDialog(
      context,
      title: AppStringKeys.privacyRemovePublicPhoto,
      message: AppStringKeys.privacyRemovePublicPhotoQuestion,
      confirmText: AppStringKeys.privacyRemovePublicPhoto,
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await _client.query({
        '@type': 'deleteProfilePhoto',
        'profile_photo_id': id,
      });
      if (!mounted) return;
      setState(() => _setPublicPhoto(null));
      showToast(context, AppStrings.t(AppStringKeys.privacyPublicPhotoRemoved));
    } catch (error) {
      if (mounted) showToast(context, error.toString());
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
            title: widget.title,
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
                  if (_isProfilePhoto)
                    _privacySectionLabel(
                      AppStrings.t(AppStringKeys.privacyWhoCanSeeProfilePhoto),
                    ),
                  _card([
                    for (var i = 0; i < _labels.length; i++) ...[
                      _visibilityRow(i),
                      if (i < _labels.length - 1)
                        const InsetDivider(leadingInset: 16),
                    ],
                  ]),
                  if (_isProfilePhoto) ...[
                    _hint(
                      AppStrings.t(
                        AppStringKeys.privacyProfilePhotoVisibilityHint,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  _privacySectionLabel(
                    AppStrings.t(AppStringKeys.privacyAddExceptions),
                  ),
                  _card([
                    if (_selection.visibility !=
                        PrivacyVisibilityOption.everyone) ...[
                      _exceptionGroup(
                        label: AppStringKeys.privacyAlwaysShareWith,
                        entries: _allowExceptions,
                        allow: true,
                      ),
                    ],
                    if (_selection.visibility ==
                            PrivacyVisibilityOption.contacts &&
                        _allowExceptions.isNotEmpty &&
                        _restrictExceptions.isNotEmpty)
                      const InsetDivider(leadingInset: 16),
                    if (_selection.visibility != PrivacyVisibilityOption.nobody)
                      _exceptionGroup(
                        label: AppStringKeys.privacyNeverShareWith,
                        entries: _restrictExceptions,
                        allow: false,
                      ),
                  ]),
                  _hint(AppStrings.t(AppStringKeys.privacyExceptionsHint)),
                  if (_isPhoneNumber &&
                      _selection.visibility ==
                          PrivacyVisibilityOption.nobody) ...[
                    const SizedBox(height: 14),
                    _privacySectionLabel(
                      AppStrings.t(AppStringKeys.privacyWhoCanFindByPhone),
                    ),
                    _card([
                      _auxiliaryVisibilityRow(
                        label: AppStringKeys.privacyVisibilityEveryone,
                        value: PrivacyVisibilityOption.everyone,
                        selected: _phoneDiscovery,
                        onTap: _setPhoneDiscovery,
                      ),
                      const InsetDivider(leadingInset: 16),
                      _auxiliaryVisibilityRow(
                        label: AppStringKeys.privacyVisibilityContacts,
                        value: PrivacyVisibilityOption.contacts,
                        selected: _phoneDiscovery,
                        onTap: _setPhoneDiscovery,
                      ),
                    ]),
                    _hint(
                      AppStrings.t(AppStringKeys.privacyPhoneDiscoveryHint),
                    ),
                  ],
                  if (_isCalls) ...[
                    const SizedBox(height: 14),
                    _card([
                      _navigationAction(
                        label: AppStringKeys.privacyPeerToPeerCalls,
                        value: _peerToPeerCalls.labelKey,
                        onTap: _openPeerToPeerCalls,
                      ),
                    ]),
                    _hint(AppStrings.t(AppStringKeys.privacyPeerToPeerHint)),
                  ],
                  if (_isLastSeen &&
                      (_selection.visibility !=
                              PrivacyVisibilityOption.everyone ||
                          _selection.restrictUserIds.isNotEmpty ||
                          _selection.restrictChatIds.isNotEmpty)) ...[
                    const SizedBox(height: 14),
                    _card([
                      _toggleAction(
                        label: AppStringKeys.privacyShowReadDate,
                        value: _showReadDate,
                        onChanged: _setShowReadDate,
                      ),
                    ]),
                    _hint(AppStrings.t(AppStringKeys.privacyShowReadDateHint)),
                  ],
                  if (_isProfilePhoto && _needsPublicPhoto) ...[
                    const SizedBox(height: 14),
                    _card([
                      _publicPhotoAction(),
                      if (_publicPhoto != null) ...[
                        const InsetDivider(leadingInset: 56),
                        _removePublicPhotoAction(),
                      ],
                    ]),
                    _hint(AppStrings.t(AppStringKeys.privacyPublicPhotoHint)),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  bool get _needsPublicPhoto =>
      _selection.visibility != PrivacyVisibilityOption.everyone ||
      _selection.restrictUserIds.isNotEmpty ||
      _selection.restrictChatIds.isNotEmpty;

  Widget _visibilityRow(int index) {
    final c = context.colors;
    final selected =
        _selection.visibility == PrivacyVisibilityOption.values[index];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _select(index),
      child: SizedBox(
        height: 54,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                AppStrings.t(_labels[index]),
                style: TextStyle(fontSize: 16, color: c.textPrimary),
              ),
              const Spacer(),
              Container(
                width: 23,
                height: 23,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? AppTheme.brand : c.textTertiary,
                    width: selected ? 2.5 : 2,
                  ),
                ),
                child: selected
                    ? Center(
                        child: Container(
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            color: AppTheme.brand,
                            shape: BoxShape.circle,
                          ),
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _exceptionGroup({
    required String label,
    required List<_PrivacyException> entries,
    required bool allow,
  }) {
    final c = context.colors;
    return Column(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _addException(allow: allow),
          child: SizedBox(
            height: 56,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      AppStrings.t(label),
                      style: TextStyle(fontSize: 16, color: c.textPrimary),
                    ),
                  ),
                  Text(
                    entries.isEmpty
                        ? AppStrings.t(AppStringKeys.privacyAddUsers)
                        : '${entries.length}',
                    style: TextStyle(fontSize: 16, color: AppTheme.brand),
                  ),
                  const SizedBox(width: 5),
                  AppIcon(
                    HeroAppIcons.chevronRight,
                    size: 14,
                    color: c.textTertiary,
                  ),
                ],
              ),
            ),
          ),
        ),
        for (final entry in entries) ...[
          const InsetDivider(leadingInset: 56),
          SizedBox(
            height: 54,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 10, 0),
              child: Row(
                children: [
                  PhotoAvatar(
                    title: entry.title,
                    photo: entry.photo,
                    size: 34,
                    square: !entry.isUser,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, color: c.textPrimary),
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _removeException(entry, allow: allow),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: AppIcon(
                        HeroAppIcons.xmark,
                        size: 18,
                        color: c.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _auxiliaryVisibilityRow({
    required String label,
    required PrivacyVisibilityOption value,
    required PrivacyVisibilityOption selected,
    required ValueChanged<PrivacyVisibilityOption> onTap,
  }) {
    final c = context.colors;
    final isSelected = selected == value;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTap(value),
      child: SizedBox(
        height: 54,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                AppStrings.t(label),
                style: TextStyle(fontSize: 16, color: c.textPrimary),
              ),
              const Spacer(),
              Container(
                width: 23,
                height: 23,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? AppTheme.brand : c.textTertiary,
                    width: isSelected ? 2.5 : 2,
                  ),
                ),
                child: isSelected
                    ? Center(
                        child: Container(
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            color: AppTheme.brand,
                            shape: BoxShape.circle,
                          ),
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navigationAction({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  AppStrings.t(label),
                  style: TextStyle(fontSize: 16, color: c.textPrimary),
                ),
              ),
              Text(
                AppStrings.t(value),
                style: TextStyle(fontSize: 14, color: c.textSecondary),
              ),
              const SizedBox(width: 5),
              AppIcon(
                HeroAppIcons.chevronRight,
                size: 14,
                color: c.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toggleAction({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final c = context.colors;
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                AppStrings.t(label),
                style: TextStyle(fontSize: 16, color: c.textPrimary),
              ),
            ),
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

  Widget _publicPhotoAction() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _updatePublicPhoto,
      child: SizedBox(
        height: 58,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              AppIcon(HeroAppIcons.camera, size: 24, color: AppTheme.brand),
              const SizedBox(width: 14),
              Text(
                AppStrings.t(AppStringKeys.privacyUpdatePublicPhoto),
                style: TextStyle(fontSize: 16, color: AppTheme.brand),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _removePublicPhotoAction() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _removePublicPhoto,
      child: SizedBox(
        height: 58,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              PhotoAvatar(
                title: AppStrings.t(AppStringKeys.privacyProfilePhoto),
                photo: _publicPhotoRef,
                size: 34,
              ),
              const SizedBox(width: 10),
              Text(
                AppStrings.t(AppStringKeys.privacyRemovePublicPhoto),
                style: const TextStyle(fontSize: 16, color: Color(0xffe53935)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _privacySectionLabel(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 7),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: TextStyle(
          color: AppTheme.brand,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );

  Widget _hint(String text) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Text(
        text,
        style: TextStyle(fontSize: 13, height: 1.35, color: c.textTertiary),
      ),
    );
  }

  Widget _card(List<Widget> children) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _PrivacyException {
  const _PrivacyException({
    required this.id,
    required this.isUser,
    required this.title,
    this.photo,
  });

  final int id;
  final bool isUser;
  final String title;
  final TdFileRef? photo;

  bool sameTarget(_PrivacyException other) =>
      id == other.id && isUser == other.isUser;
}

// MARK: - Active sessions

class ActiveSessionsView extends StatefulWidget {
  const ActiveSessionsView({super.key});

  @override
  State<ActiveSessionsView> createState() => _ActiveSessionsViewState();
}

class _ActiveSessionsViewState extends State<ActiveSessionsView> {
  final TdClient _client = TdClient.shared;
  Map<String, dynamic>? _current;
  List<Map<String, dynamic>> _others = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final res = await _client.query({'@type': 'getActiveSessions'});
      final sessions =
          res.objects('sessions') ?? const <Map<String, dynamic>>[];
      _current = null;
      _others = [];
      for (final s in sessions) {
        if (s.boolean('is_current') ?? false) {
          _current = s;
        } else {
          _others.add(s);
        }
      }
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _terminate(Map<String, dynamic> session) async {
    final id = session.int64('id');
    if (id == null) return;
    final ok = await confirmDialog(
      context,
      title: AppStringKeys.privacyTerminateSessionQuestion,
      message: AppStrings.t(AppStringKeys.privacyTerminateSessionMessage, {
        'value1': _sessionTitle(session),
      }),
      confirmText: AppStringKeys.privacyTerminateSession,
      destructive: true,
    );
    if (!ok) return;
    try {
      await _client.query({'@type': 'terminateSession', 'session_id': id});
      setState(() => _others.removeWhere((s) => s.int64('id') == id));
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    }
  }

  Future<void> _terminateAll() async {
    final ok = await confirmDialog(
      context,
      title: AppStringKeys.privacyTerminateAllOtherSessions,
      confirmText: AppStringKeys.privacyTerminateAllOtherSessions,
      destructive: true,
    );
    if (!ok) return;
    try {
      await _client.query({'@type': 'terminateAllOtherSessions'});
      setState(() => _others = []);
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    }
  }

  Future<void> _scanLoginQr() async {
    final accepted = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const QrLoginScannerView()));
    if (accepted == true && mounted) {
      await _load();
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
            title: AppStrings.t(AppStringKeys.privacyLoggedInDevices),
            onBack: () => Navigator.of(context).pop(),
            trailing: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _scanLoginQr,
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: AppIcon(
                  HeroAppIcons.qrcode,
                  size: 24,
                  color: c.textPrimary,
                ),
              ),
            ),
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
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _scanLoginQr,
                      child: SizedBox(
                        height: 54,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              AppIcon(
                                HeroAppIcons.qrcode,
                                size: 22,
                                color: AppTheme.brand,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  AppStrings.t(
                                    AppStringKeys.privacyScanLoginQr,
                                  ),
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: c.textPrimary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              AppIcon(
                                HeroAppIcons.chevronRight,
                                size: 14,
                                color: c.textTertiary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  if (_current != null) ...[
                    _sectionLabel(
                      AppStrings.t(AppStringKeys.privacyCurrentDevice),
                    ),
                    _card([_sessionRow(_current!, current: true)]),
                    const SizedBox(height: 14),
                  ],
                  if (_others.isNotEmpty) ...[
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _terminateAll,
                      child: _card([
                        SizedBox(
                          height: 50,
                          child: Center(
                            child: Text(
                              AppStrings.t(
                                AppStringKeys.privacyTerminateAllOtherSessions,
                              ),
                              style: TextStyle(
                                fontSize: 16,
                                color: AppTheme.tagRed,
                              ),
                            ),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    _sectionLabel(
                      AppStrings.t(AppStringKeys.privacyOtherDevices),
                    ),
                    _card([
                      for (var i = 0; i < _others.length; i++) ...[
                        _sessionRow(_others[i]),
                        if (i < _others.length - 1)
                          const InsetDivider(leadingInset: 16),
                      ],
                    ]),
                  ] else ...[
                    _sectionLabel(
                      AppStrings.t(AppStringKeys.privacyOtherDevices),
                    ),
                    _card([
                      SizedBox(
                        height: 74,
                        child: Center(
                          child: Text(
                            AppStrings.t(AppStringKeys.privacyNoOtherDevices),
                            style: TextStyle(
                              fontSize: 14,
                              color: c.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ]),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String t) => Padding(
    padding: const EdgeInsets.only(left: 16, bottom: 6),
    child: Text(
      t,
      style: TextStyle(fontSize: 13, color: context.colors.textTertiary),
    ),
  );

  Widget _card(List<Widget> children) => Container(
    decoration: BoxDecoration(
      color: context.colors.card,
      borderRadius: BorderRadius.circular(12),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(children: children),
  );

  Widget _sessionRow(Map<String, dynamic> s, {bool current = false}) {
    final c = context.colors;
    final app = _sessionTitle(s);
    final device = s.str('device_model') ?? '';
    final platform = s.str('platform') ?? '';
    final location = s.str('location') ?? '';
    final subtitle = [
      device,
      platform,
      location,
    ].where((e) => e.isNotEmpty).join(' · ');
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: current ? null : () => _terminate(s),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    app,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: c.textPrimary,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: c.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
            if (!current)
              Text(
                AppStrings.t(AppStringKeys.privacyTerminateSession),
                style: TextStyle(fontSize: 14, color: AppTheme.tagRed),
              ),
          ],
        ),
      ),
    );
  }

  String _sessionTitle(Map<String, dynamic> session) {
    final app = session.str('application_name') ?? '';
    return app.isEmpty ? AppStrings.t(AppStringKeys.privacyDeviceApp) : app;
  }
}

// MARK: - Block list

class BlockedUsersView extends StatefulWidget {
  const BlockedUsersView({super.key});

  @override
  State<BlockedUsersView> createState() => _BlockedUsersViewState();
}

class _BlockedUsersViewState extends State<BlockedUsersView> {
  final TdClient _client = TdClient.shared;
  List<Contact> _blocked = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await _client.query({
        '@type': 'getBlockedMessageSenders',
        'block_list': {'@type': 'blockListMain'},
        'offset': 0,
        'limit': 100,
      });
      final senders = res.objects('senders') ?? const <Map<String, dynamic>>[];
      final loaded = <Contact>[];
      for (final s in senders) {
        final uid = s.int64('user_id');
        if (uid == null) continue;
        try {
          final user = await _client.query({
            '@type': 'getUser',
            'user_id': uid,
          });
          loaded.add(
            Contact(
              id: uid,
              name: TDParse.userName(user),
              username: user.obj('usernames')?.str('editable_username'),
              statusText: '',
              photo: TDParse.smallPhoto(user.obj('profile_photo')),
            ),
          );
        } catch (_) {}
      }
      _blocked = loaded;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _unblock(Contact u) async {
    try {
      await _client.query({
        '@type': 'setMessageSenderBlockList',
        'sender_id': {'@type': 'messageSenderUser', 'user_id': u.id},
        'block_list': null,
      });
      KeywordBlocker.shared.removeBlockedSender(u.id);
      setState(() => _blocked.removeWhere((x) => x.id == u.id));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.privacyBlockedUsers),
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
          else if (_blocked.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  AppStrings.t(AppStringKeys.privacyBlockedUsersEmpty),
                  style: TextStyle(fontSize: 14, color: c.textSecondary),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: _blocked.length,
                itemBuilder: (context, i) => _row(_blocked[i]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(Contact u) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.background,
        border: Border(bottom: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: Row(
        children: [
          PhotoAvatar(title: u.name, photo: u.photo, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              u.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 16, color: c.textPrimary),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _unblock(u),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.brand),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                AppStrings.t(AppStringKeys.privacyUnblock),
                style: TextStyle(fontSize: 13, color: AppTheme.brand),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
