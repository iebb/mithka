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

import 'dart:io';

import 'package:flutter/material.dart';

import '../chat/image_edit_view.dart';
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
  const CommunityEditView({super.key, required this.community});

  final CommunitySummary community;

  @override
  State<CommunityEditView> createState() => _CommunityEditViewState();
}

class _CommunityEditViewState extends State<CommunityEditView> {
  bool _saving = false;

  void _toast(String message) => showToast(context, message);

  /// TDLib answers an unknown @type with a parse-level error, so this shape
  /// marks a method the pinned native library simply doesn't carry yet.
  bool _isUnsupportedMethod(TdError error) =>
      error.message.contains('Failed to parse JSON object as TDLib request');

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
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await TdClient.shared.query({
        '@type': 'setCommunityName',
        'community_id': widget.community.id,
        'name': name,
      });
      // The hub receives updateCommunity too, but the summary instance is
      // shared with the view that pushed this page, so update it in place.
      widget.community.name = name;
      if (mounted) setState(() {});
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
      setState(() => _saving = true);
      await TdClient.shared.query({
        '@type': 'setCommunityPhoto',
        'community_id': widget.community.id,
        'photo': {
          '@type': 'inputChatPhotoStatic',
          'photo': {'@type': 'inputFileLocal', 'path': edited},
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
