import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../chat/image_edit_view.dart';
import '../components/app_icons.dart';
import '../components/confirm_dialog.dart';
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../media/app_asset_picker.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import 'profile_contact_service.dart';

class ProfilePhotoManagementView extends StatefulWidget {
  const ProfilePhotoManagementView({super.key});

  @override
  State<ProfilePhotoManagementView> createState() =>
      _ProfilePhotoManagementViewState();
}

class _ProfilePhotoManagementViewState
    extends State<ProfilePhotoManagementView> {
  final TdClient _client = TdClient.shared;
  bool _loading = true;
  int _currentPhotoId = 0;
  int _publicPhotoId = 0;
  List<_ProfilePhotoEntry> _photos = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final me = await _client.query({'@type': 'getMe'});
      final userId = me.int64('id') ?? 0;
      final results = await Future.wait([
        _client.query({'@type': 'getUserFullInfo', 'user_id': userId}),
        _client.query({
          '@type': 'getUserProfilePhotos',
          'user_id': userId,
          'offset': 0,
          'limit': 100,
        }),
      ]);
      final snapshot = ProfileContactSnapshot.fromFullInfo(results[0]);
      final photos = <_ProfilePhotoEntry>[];
      for (final photo
          in results[1].objects('photos') ?? const <Map<String, dynamic>>[]) {
        final entry = _ProfilePhotoEntry.fromChatPhoto(photo);
        if (entry != null) photos.add(entry);
      }
      if (!mounted) return;
      setState(() {
        _currentPhotoId = snapshot.currentPhotoId;
        _publicPhotoId = snapshot.publicPhotoId;
        _photos = photos;
      });
    } catch (error) {
      if (mounted) {
        showToast(
          context,
          AppStrings.t(
            AppStringKeys.profilePhotoManagementCouldNotLoadProfilePhotosValue1,
            {'value1': error},
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickNew({required bool isPublic}) async {
    final selection = await AppAssetPicker.pickDetailed(
      context,
      type: AppAssetPickerType.image,
      maxAssets: 1,
    );
    if (selection.assets.isEmpty) return;
    try {
      if (!mounted) return;
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
        if (!mounted) return;
        showToast(
          context,
          AppStrings.t(AppStringKeys.editProfileInvalidAvatarFile),
        );
        return;
      }
      await _client.query(
        setOwnProfilePhotoRequest(
          photo: localStaticChatPhoto(edited),
          isPublic: isPublic,
        ),
      );
      if (!mounted) return;
      showToast(
        context,
        isPublic ? 'Public photo updated' : 'Profile photo updated',
      );
      await _load();
    } catch (error) {
      if (mounted) {
        showToast(
          context,
          AppStrings.t(
            AppStringKeys.profilePhotoManagementCouldNotUpdatePhotoValue1,
            {'value1': error},
          ),
        );
      }
    }
  }

  Future<void> _usePrevious(
    _ProfilePhotoEntry entry, {
    required bool isPublic,
  }) async {
    try {
      await _client.query(
        setOwnProfilePhotoRequest(
          photo: previousChatPhoto(entry.id),
          isPublic: isPublic,
        ),
      );
      if (!mounted) return;
      showToast(
        context,
        isPublic ? 'Public photo updated' : 'Profile photo updated',
      );
      await _load();
    } catch (error) {
      if (mounted) {
        showToast(
          context,
          AppStrings.t(
            AppStringKeys.profilePhotoManagementCouldNotUpdatePhotoValue1,
            {'value1': error},
          ),
        );
      }
    }
  }

  Future<void> _delete(_ProfilePhotoEntry entry) async {
    final confirmed = await confirmDialog(
      context,
      title: AppStrings.t(AppStringKeys.profilePhotoDeleteTitle),
      message: 'This removes the photo from your profile history.',
      confirmText: AppStrings.t(AppStringKeys.chatDelete),
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await _client.query(deleteOwnProfilePhotoRequest(entry.id));
      if (!mounted) return;
      setState(() => _photos = _photos.where((p) => p.id != entry.id).toList());
    } catch (error) {
      if (mounted) {
        showToast(
          context,
          AppStrings.t(
            AppStringKeys.profilePhotoManagementCouldNotDeletePhotoValue1,
            {'value1': error},
          ),
        );
      }
    }
  }

  Future<void> _showActions(_ProfilePhotoEntry entry) async {
    final action = await showModalBottomSheet<_PhotoAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _PhotoActionSheet(
        isCurrent: entry.id == _currentPhotoId,
        isPublic: entry.id == _publicPhotoId,
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _PhotoAction.useCurrent:
        await _usePrevious(entry, isPublic: false);
      case _PhotoAction.usePublic:
        await _usePrevious(entry, isPublic: true);
      case _PhotoAction.delete:
        await _delete(entry);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(
              AppStringKeys.profilePhotoManagementProfilePhotos,
            ),
            onBack: () => Navigator.of(context).pop(),
            trailing: _refreshAction(),
          ),
          Expanded(
            child: _loading
                ? const Center(child: AppActivityIndicator(size: 24))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 14, 12, 28),
                    children: [
                      _actionCard(),
                      const SizedBox(height: 18),
                      Text(
                        AppStrings.t(
                          AppStringKeys.profilePhotoManagementPhotoHistory,
                        ).toUpperCase(),
                        style: AppTextStyle.caption(colors.textSecondary),
                      ),
                      const SizedBox(height: 8),
                      if (_photos.isEmpty)
                        _emptyCard()
                      else
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                mainAxisSpacing: 4,
                                crossAxisSpacing: 4,
                              ),
                          itemCount: _photos.length,
                          itemBuilder: (context, index) =>
                              _photoTile(_photos[index]),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _refreshAction() => Semantics(
    button: true,
    label: AppStrings.t(
      AppStringKeys.profilePhotoManagementRefreshProfilePhotos,
    ),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _loading ? null : () => unawaited(_load()),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: AppIcon(
          HeroAppIcons.arrowsRotate,
          size: 19,
          color: _loading
              ? context.colors.textTertiary
              : context.colors.textPrimary,
        ),
      ),
    ),
  );

  Widget _actionCard() {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _actionRow(
            HeroAppIcons.circleUser,
            'Set profile photo',
            'Visible according to your profile-photo privacy rules',
            () => _pickNew(isPublic: false),
          ),
          const InsetDivider(leadingInset: 56),
          _actionRow(
            HeroAppIcons.globe,
            'Set public photo',
            'Shown to people who cannot see your main photo',
            () => _pickNew(isPublic: true),
          ),
        ],
      ),
    );
  }

  Widget _actionRow(
    AppIconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    final colors = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            AppIcon(icon, size: 22, color: AppTheme.brand),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyle.body(colors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTextStyle.caption(colors.textSecondary),
                  ),
                ],
              ),
            ),
            AppIcon(
              HeroAppIcons.chevronRight,
              size: 16,
              color: colors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyCard() => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: context.colors.card,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text(
      AppStrings.t(AppStringKeys.profilePhotoManagementNoProfilePhotosYet),
      textAlign: TextAlign.center,
      style: AppTextStyle.body(context.colors.textSecondary),
    ),
  );

  Widget _photoTile(_ProfilePhotoEntry entry) {
    final badges = <Widget>[];
    if (entry.id == _currentPhotoId) badges.add(_badge('Current'));
    if (entry.id == _publicPhotoId) badges.add(_badge('Public'));
    return GestureDetector(
      onTap: () => _showActions(entry),
      onLongPress: () => _showActions(entry),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            TDImage(photo: entry.file, cornerRadius: 0),
            if (badges.isNotEmpty)
              Positioned(
                left: 5,
                right: 5,
                bottom: 5,
                child: Wrap(spacing: 4, runSpacing: 3, children: badges),
              ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.62),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _ProfilePhotoEntry {
  const _ProfilePhotoEntry({required this.id, required this.file});

  static _ProfilePhotoEntry? fromChatPhoto(Map<String, dynamic> photo) {
    final id = photo.int64('id') ?? 0;
    final sizes = photo.objects('sizes') ?? const <Map<String, dynamic>>[];
    if (id == 0 || sizes.isEmpty) return null;
    final largest = sizes.reduce(
      (a, b) => (a.integer('width') ?? 0) >= (b.integer('width') ?? 0) ? a : b,
    );
    final file = TDParse.fileRef(largest.obj('photo'));
    if (file == null) return null;
    return _ProfilePhotoEntry(id: id, file: file);
  }

  final int id;
  final TdFileRef file;
}

enum _PhotoAction { useCurrent, usePublic, delete }

class _PhotoActionSheet extends StatelessWidget {
  const _PhotoActionSheet({required this.isCurrent, required this.isPublic});

  final bool isCurrent;
  final bool isPublic;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(14),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isCurrent)
              _row(
                context,
                HeroAppIcons.circleUser,
                'Use as current photo',
                _PhotoAction.useCurrent,
              ),
            if (!isCurrent && !isPublic) const InsetDivider(leadingInset: 56),
            if (!isPublic)
              _row(
                context,
                HeroAppIcons.globe,
                'Use as public photo',
                _PhotoAction.usePublic,
              ),
            if (!isCurrent || !isPublic) const InsetDivider(leadingInset: 56),
            _row(
              context,
              HeroAppIcons.trash,
              'Delete from history',
              _PhotoAction.delete,
              destructive: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    AppIconData icon,
    String label,
    _PhotoAction result, {
    bool destructive = false,
  }) {
    final color = destructive
        ? const Color(0xFFFF4D4F)
        : context.colors.textPrimary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).pop(result),
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              AppIcon(icon, size: 21, color: color),
              const SizedBox(width: 16),
              Text(label, style: AppTextStyle.body(color)),
            ],
          ),
        ),
      ),
    );
  }
}
