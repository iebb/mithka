//
//  community_edit_view.dart
//
//  Community profile editor modeled on the iOS CommunityEditScreen: change
//  the avatar and the name. Gated by the can_change_info administrator
//  right, which CommunitySummary.canChangeInfo already carries. setCommunity
//  Photo only exists on TDLib builds past the 1.8.68 community merge, so a
//  parse-level error from an older library degrades into an explicit
//  "not supported yet" toast instead of a generic failure.
//
//  Menu visibility only promises the right at route time, so every write
//  re-checks the CURRENT permission at execution, after the field sheet and
//  picker/crop awaits: the summary is shared with the hub and an
//  updateCommunity merge can revoke the right mid-flow. Writes also stay
//  pinned to the client of the account that opened the route — community ids
//  and local files are account-scoped, so a foreground account switch must
//  fail the stale flow instead of re-authoring the edit on the new account.
//  Disposal cancels everything: a disposed editor never writes, mutates the
//  summary, or calls setState.
//

import 'dart:io';

import 'package:flutter/material.dart';

import '../chat/media/image_edit_view.dart';
import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../media/app_asset_picker.dart';
import '../settings/edit_field_view.dart';
import '../tdlib/td_client.dart';
import '../theme/app_theme.dart';
import 'community_models.dart';

/// The hero avatar size used by the profile editor's identity card.
const double _heroAvatarSize = 96;
const double _cameraBadgeSize = 30;

class CommunityEditView extends StatefulWidget {
  const CommunityEditView({
    super.key,
    required this.community,
    @visibleForTesting this.activeClientId,
    @visibleForTesting this.activeSlot,
  });

  final CommunitySummary community;

  /// Live foreground-account probes. Production reads TdClient.shared; the
  /// recording-transport test harness cannot switch that shared client under
  /// a configured proxy, so tests inject a mutable source instead.
  @visibleForTesting
  final int Function()? activeClientId;
  @visibleForTesting
  final int Function()? activeSlot;

  @override
  State<CommunityEditView> createState() => _CommunityEditViewState();
}

class _CommunityEditViewState extends State<CommunityEditView> {
  bool _saving = false;

  // The account that opened this route, captured at mount. Community ids and
  // the cropped local file are account-scoped, so TDLib writes must keep
  // using this client even if the foreground account switches mid-flow.
  late int _accountClientId;
  late int _accountSlot;

  @override
  void initState() {
    super.initState();
    _accountClientId =
        widget.activeClientId?.call() ?? TdClient.shared.activeClientId;
    _accountSlot = widget.activeSlot?.call() ?? TdClient.shared.activeSlot;
  }

  int get _liveActiveClientId =>
      widget.activeClientId?.call() ?? TdClient.shared.activeClientId;
  int get _liveActiveSlot =>
      widget.activeSlot?.call() ?? TdClient.shared.activeSlot;

  void _toast(String message) => showToast(context, message);

  /// TDLib answers an unknown @type with a parse-level error, so this shape
  /// marks a method the pinned native library simply doesn't carry yet.
  bool _isUnsupportedMethod(TdError error) =>
      error.message.contains('Failed to parse JSON object as TDLib request');

  /// Permission and ownership at execution time, after every await. The
  /// shared summary can be revoked by a merge and the foreground account can
  /// have switched; both must stop the write before TDLib sees it.
  bool get _canExecuteWrite =>
      mounted &&
      widget.community.canChangeInfo &&
      widget.community.haveAccess &&
      _liveActiveClientId == _accountClientId &&
      _liveActiveSlot == _accountSlot;

  /// Re-checks the execution boundary and reports the honest failure —
  /// [failureKey] — when it has closed. Permission is enforced here, at
  /// execution, not by menu visibility alone.
  bool _guardWrite(String failureKey) {
    if (_canExecuteWrite) return true;
    if (mounted) _toast(failureKey.l10n(context));
    return false;
  }

  Future<void> _editName() async {
    final value = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => EditFieldView(
          title: AppStringKeys.communityEditNameTitle.l10n(context),
          initial: widget.community.name,
          maxLength: 128,
        ),
      ),
    );
    if (value == null || value.trim().isEmpty) return;
    final name = value.trim();
    if (name == widget.community.name) return;
    if (!mounted) return;
    await _saveName(name);
  }

  @visibleForTesting
  Future<void> saveNameForTesting(String name) => _saveName(name);

  Future<void> _saveName(String name) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      // The field-sheet await is exactly where the right can be revoked and
      // the account can switch, so re-check now, at execution, rather than
      // trusting the menu's route-time snapshot.
      if (!_guardWrite(AppStringKeys.communityEditSaveFailed)) return;
      await _queryForAccount({
        '@type': 'setCommunityName',
        'community_id': widget.community.id,
        'name': name,
      });
      // A disposed editor must not touch the shared summary either.
      if (!mounted) return;
      // The hub receives updateCommunity too, but the summary instance is
      // shared with the view that pushed this page, so update it in place.
      widget.community.name = name;
      setState(() {});
    } on TdError catch (error) {
      if (!mounted) return;
      _toast(
        _isUnsupportedMethod(error)
            ? AppStringKeys.communityEditUnsupported.l10n(context)
            : AppStringKeys.communityEditSaveFailed.l10n(context),
      );
    } catch (_) {
      if (!mounted) return;
      _toast(AppStringKeys.communityEditSaveFailed.l10n(context));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changePhoto() async {
    if (_saving) return;
    try {
      final selection = await AppAssetPicker.pickDetailed(
        context,
        type: AppAssetPickerType.image,
        maxAssets: 1,
      );
      if (selection.assets.isEmpty) return;
      final image = selection.assets.first.file;
      if (!mounted) return;
      // Community photos are static, so animated picks crop to their first
      // frame just like any other image.
      final edited = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => ImageEditView(sourcePath: image.path, avatar: true),
        ),
      );
      if (edited == null) return;
      final file = File(edited);
      if (!await file.exists() || await file.length() == 0) {
        if (!mounted) return;
        _toast(AppStringKeys.editProfileInvalidAvatarFile.l10n(context));
        return;
      }
      if (!mounted) return;
      await _savePhoto(edited);
    } on TdError catch (error) {
      if (!mounted) return;
      _toast(
        _isUnsupportedMethod(error)
            ? AppStringKeys.communityEditUnsupported.l10n(context)
            : AppStringKeys.communityEditPhotoSaveFailed.l10n(context),
      );
    } catch (_) {
      if (!mounted) return;
      _toast(AppStringKeys.communityEditPhotoSaveFailed.l10n(context));
    }
  }

  @visibleForTesting
  Future<void> savePhotoForTesting(String path) => _savePhoto(path);

  Future<void> _savePhoto(String editedPath) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      // Route, asset-picker, crop and filesystem waits all happened before
      // this line; the permission and owner are re-checked here, at
      // execution, so a revoked right or a switched account sends nothing.
      if (!_guardWrite(AppStringKeys.communityEditPhotoSaveFailed)) return;
      await _queryForAccount({
        '@type': 'setCommunityPhoto',
        'community_id': widget.community.id,
        'photo': {
          '@type': 'inputChatPhotoStatic',
          'photo': {'@type': 'inputFileLocal', 'path': editedPath},
        },
      });
      if (!mounted) return;
      _toast(AppStringKeys.communityEditPhotoUpdated.l10n(context));
      // The new photo propagates through updateCommunity; give it a beat
      // like the profile editor does before refreshing.
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (mounted) setState(() {});
    } on TdError catch (error) {
      if (!mounted) return;
      _toast(
        _isUnsupportedMethod(error)
            ? AppStringKeys.communityEditUnsupported.l10n(context)
            : AppStringKeys.communityEditPhotoSaveFailed.l10n(context),
      );
    } catch (_) {
      if (!mounted) return;
      _toast(AppStringKeys.communityEditPhotoSaveFailed.l10n(context));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Sends through the client of the account that opened this route, like
  /// forwardQueryForOwner pins its source. A switched foreground account
  /// fails here instead of writing to the other account; a replaced client
  /// is rejected by TDLib itself.
  Future<Map<String, dynamic>> _queryForAccount(Map<String, dynamic> request) {
    final client = TdClient.shared;
    if (client.clientId(_accountSlot) != _accountClientId) {
      throw StateError('The community editor account is unavailable');
    }
    return client.queryTo(request, _accountClientId);
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPageScaffold(
      title: AppStringKeys.communityEditTitle.l10n(context),
      onBack: () => Navigator.of(context).pop(),
      child: SettingsListView(
        children: [
          _avatarCard(),
          const SizedBox(height: AppSpacing.section),
          const SettingsSectionHeader(AppStringKeys.communityEditSection),
          SettingsCard(
            children: [
              SettingsRow(
                key: const ValueKey('community-edit-name'),
                title: AppStringKeys.communityEditNameLabel.l10n(context),
                value: widget.community.name,
                enabled: !_saving,
                onTap: _editName,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _avatarCard() {
    final c = context.colors;
    return SettingsPanel(
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.section),
          AppInteractiveSurface(
            onTap: _saving ? null : _changePhoto,
            semanticLabel: AppStringKeys.communityEditChangePhoto.l10n(context),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: SizedBox(
              width: _heroAvatarSize,
              height: _heroAvatarSize,
              child: Stack(
                children: [
                  PhotoAvatar(
                    title: widget.community.name,
                    photo: widget.community.photo,
                    size: _heroAvatarSize,
                    square: true,
                  ),
                  if (_saving)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: c.background.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        alignment: Alignment.center,
                        child: const AppActivityIndicator(size: 24),
                      ),
                    )
                  else
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: _cameraBadgeSize,
                        height: _cameraBadgeSize,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppTheme.brand,
                          shape: BoxShape.circle,
                          border: Border.all(color: c.card, width: 2),
                        ),
                        child: const AppIcon(
                          HeroAppIcons.camera,
                          size: AppIconSize.xs,
                          color: Color(0xFFFFFFFF),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Padding(
            padding: AppInsets.row,
            child: Text(
              widget.community.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppTextStyle.display(c.textPrimary),
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Padding(
            padding: AppInsets.row,
            child: Text(
              AppStringKeys.communityEditChangePhotoHint.l10n(context),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.footnote(c.textSecondary),
            ),
          ),
          const SizedBox(height: AppSpacing.section),
        ],
      ),
    );
  }
}
