//
//  edit_profile_view.dart
//
//  编辑资料 — avatar + name / username / phone / birthday / bio / name &
//  profile accent colors, loaded from getMe/getUserFullInfo and saved back via
//  setName / setUsername / setBirthdate / setBio / setAccentColor /
//  setProfileAccentColor. Port of the Swift `EditProfileView`, wired to live
//  TDLib.
//

import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../chat/custom_emoji.dart';
import '../chat/image_edit_view.dart';
import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../media/app_asset_picker.dart';
import '../platform/animated_avatar_preparer.dart';
import '../profile/profile_contact_management_view.dart';
import '../profile/profile_contact_service.dart';
import '../profile/profile_icon_picker_view.dart';
import '../profile/profile_photo_policy.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import 'accent_color_picker_view.dart';
import 'animated_avatar_crop_view.dart';
import 'business_settings_view.dart';
import 'edit_field_view.dart';

class EditProfileView extends StatefulWidget {
  const EditProfileView({
    super.key,
    this.openAvatarPicker = false,
    this.showBackButton = true,
  });

  final bool openAvatarPicker;

  /// False in a detached desktop window, where there is nothing behind this
  /// screen to go back to.
  final bool showBackButton;

  @override
  State<EditProfileView> createState() => _EditProfileViewState();
}

enum _AvatarKind { static, animated }

class _EditProfileViewState extends State<EditProfileView> {
  static const _heroAvatarSize = 92.0;
  static const _photoTileSize = 54.0;
  static const _cameraBadgeSize = 28.0;

  final TdClient _client = TdClient.shared;
  String _firstName = '';
  String _lastName = '';
  String _username = '';
  String _bio = '';
  String _phone = '';
  int _userId = 0;
  int _accentColorId = 0;
  int _profileAccentColorId = -1;
  int _backgroundCustomEmojiId = 0;
  int _profileBackgroundCustomEmojiId = 0;
  int? _bDay, _bMonth, _bYear;
  TdFileRef? _photo;
  List<ProfilePhotoEntry> _photos = const [];
  int _currentPhotoId = 0;
  int _publicPhotoId = 0;
  bool _isPremium = false;
  bool _isBotApi = false;
  bool _loading = true;
  bool _openedAvatarPicker = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final me = await _client.query({'@type': 'getMe'});
      final uid = me.int64('id');
      _userId = uid ?? 0;
      _firstName = me.str('first_name') ?? '';
      _lastName = me.str('last_name') ?? '';
      _username = me.obj('usernames')?.str('editable_username') ?? '';
      _phone = me.str('phone_number') ?? '';
      _accentColorId = me.integer('accent_color_id') ?? 0;
      _profileAccentColorId = me.integer('profile_accent_color_id') ?? -1;
      _backgroundCustomEmojiId = me.int64('background_custom_emoji_id') ?? 0;
      _profileBackgroundCustomEmojiId =
          me.int64('profile_background_custom_emoji_id') ?? 0;
      _isPremium = me.boolean('is_premium') ?? false;
      _isBotApi = await _client.activeAccountUsesBotApi();
      _photo = TDParse.smallPhoto(me.obj('profile_photo'));
      if (uid != null) {
        final full = await _client.query({
          '@type': 'getUserFullInfo',
          'user_id': uid,
        });
        _bio = full.obj('bio')?.str('text') ?? '';
        final bd = full.obj('birthdate');
        if (bd != null) {
          _bDay = bd.integer('day');
          _bMonth = bd.integer('month');
          final y = bd.integer('year') ?? 0;
          _bYear = y == 0 ? null : y;
        }
        final snapshot = ProfileContactSnapshot.fromFullInfo(full);
        _currentPhotoId = snapshot.currentPhotoId;
        _publicPhotoId = snapshot.publicPhotoId;
        await _loadPhotos(uid);
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => _loading = false);
    if (widget.openAvatarPicker && !_openedAvatarPicker) {
      _openedAvatarPicker = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _changeAvatar();
      });
    }
  }

  /// The account's photo stack. An empty list is a normal answer here — it
  /// only means the strip has nothing to draw — so a failure is not surfaced.
  Future<void> _loadPhotos(int userId) async {
    try {
      final response = await _client.query(
        ProfilePhotoEntry.request(userId: userId, limit: 24),
      );
      _photos = ProfilePhotoEntry.listFromResponse(response);
    } catch (_) {
      _photos = const [];
    }
  }

  Future<void> _usePhoto(ProfilePhotoEntry entry) async {
    if (entry.id == _currentPhotoId) return;
    try {
      await _client.query(
        setOwnProfilePhotoRequest(
          photo: previousChatPhoto(entry.id),
          isPublic: false,
        ),
      );
      await _finishAvatarUpdate();
    } catch (_) {
      _toast(AppStrings.t(AppStringKeys.editProfileSaveFailed));
    }
  }

  Future<String?> _edit(
    String title,
    String initial, {
    String prefix = '',
    String hint = '',
    bool multiline = false,
    int? maxLength,
    TextInputType? keyboardType,
  }) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => EditFieldView(
          title: title,
          initial: initial,
          prefix: prefix,
          hint: hint,
          multiline: multiline,
          maxLength: maxLength,
          keyboardType: keyboardType,
        ),
      ),
    );
  }

  Future<void> _setName(String firstName, String lastName) async {
    final first = firstName.trim();
    final last = lastName.trim();
    if (first.isEmpty) return;
    try {
      await _client.query({
        '@type': 'setName',
        'first_name': first,
        'last_name': last,
      });
      setState(() {
        _firstName = first;
        _lastName = last;
      });
    } catch (_) {
      _toast(AppStrings.t(AppStringKeys.editProfileSaveFailed));
    }
  }

  Future<void> _editFirstName() async {
    final result = await _edit(
      AppStrings.t(AppStringKeys.editProfileChangeName),
      _firstName,
      hint: AppStrings.t(AppStringKeys.loginFirstName),
    );
    if (result == null || result.trim().isEmpty) return;
    await _setName(result, _lastName);
  }

  Future<void> _editLastName() async {
    final result = await _edit(
      AppStrings.t(AppStringKeys.loginLastNameOptional),
      _lastName,
      hint: AppStrings.t(AppStringKeys.loginLastNameOptional),
    );
    if (result == null) return;
    await _setName(_firstName, result);
  }

  Future<void> _editUsername() async {
    final value = await _edit(
      AppStrings.t(AppStringKeys.editProfileChangeUsername),
      _username,
      prefix: '@',
      hint: AppStrings.t(AppStringKeys.editProfileSetUsername),
      keyboardType: TextInputType.visiblePassword,
    );
    if (value == null) return;
    try {
      await _client.query({'@type': 'setUsername', 'username': value});
      setState(() => _username = value);
    } catch (_) {
      _toast(AppStrings.t(AppStringKeys.editProfileUsernameUnavailable));
    }
  }

  Future<void> _editBio() async {
    final value = await _edit(
      AppStrings.t(AppStringKeys.editProfileChangeBio),
      _bio,
      hint: AppStrings.t(AppStringKeys.editProfileBioPlaceholder),
      multiline: true,
      maxLength: 70,
    );
    if (value == null) return;
    try {
      await _client.query({'@type': 'setBio', 'bio': value});
      setState(() => _bio = value);
    } catch (_) {
      _toast(AppStrings.t(AppStringKeys.editProfileSaveFailed));
    }
  }

  String get _birthdayText {
    if (_bDay == null || _bMonth == null) {
      return AppStrings.t(AppStringKeys.editProfileTapToSet);
    }
    final base = AppStrings.t(AppStringKeys.profileDetailMonthDayDate, {
      'value1': _bMonth,
      'value2': _bDay,
    });
    return _bYear != null
        ? AppStrings.t(AppStringKeys.profileDetailYearMonthDate, {
            'value1': _bYear,
            'value2': base,
          })
        : base;
  }

  Future<void> _editBirthday() async {
    final result = await showAppCupertinoModalPopup<_BdayResult>(
      context: context,
      builder: (_) => _BirthdayPickerSheet(
        day: _bDay,
        month: _bMonth,
        year: _bYear,
        canClear: _bDay != null,
      ),
    );
    if (result == null) return; // cancelled
    try {
      if (result.clear) {
        // birthdate: null removes it (TDLib setBirthdate).
        await _client.query({'@type': 'setBirthdate', 'birthdate': null});
        setState(() {
          _bDay = null;
          _bMonth = null;
          _bYear = null;
        });
      } else {
        // year 0 = "no year" (month/day only).
        await _client.query({
          '@type': 'setBirthdate',
          'birthdate': {
            '@type': 'birthdate',
            'day': result.day,
            'month': result.month,
            'year': result.year,
          },
        });
        setState(() {
          _bDay = result.day;
          _bMonth = result.month;
          _bYear = result.year == 0 ? null : result.year;
        });
      }
    } catch (_) {
      _toast(AppStrings.t(AppStringKeys.editProfileSaveFailed));
    }
  }

  Future<void> _editNameColor() async {
    final id = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => AccentColorPickerView(
          title: AppStrings.t(AppStringKeys.editProfileNameColor),
          selectedId: _accentColorId,
          footnote: AppStrings.t(AppStringKeys.editProfileNameColorDescription),
        ),
      ),
    );
    if (id == null || id < 0 || id == _accentColorId) return;
    try {
      await _client.query({
        '@type': 'setAccentColor',
        'accent_color_id': id,
        'background_custom_emoji_id': _backgroundCustomEmojiId,
      });
      setState(() => _accentColorId = id);
    } catch (_) {
      _toast(AppStrings.t(AppStringKeys.editProfileSaveFailed));
    }
  }

  Future<void> _editProfileColor() async {
    final id = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => AccentColorPickerView(
          title: AppStrings.t(AppStringKeys.editProfileProfileColor),
          selectedId: _profileAccentColorId,
          allowNone: true,
          footnote: AppStrings.t(
            AppStringKeys.editProfileProfileColorDescription,
          ),
        ),
      ),
    );
    if (id == null || id == _profileAccentColorId) return;
    try {
      await _client.query({
        '@type': 'setProfileAccentColor',
        'profile_accent_color_id': id,
        'profile_background_custom_emoji_id': _profileBackgroundCustomEmojiId,
      });
      setState(() => _profileAccentColorId = id);
    } catch (_) {
      _toast(AppStrings.t(AppStringKeys.editProfileSaveFailed));
    }
  }

  Future<void> _editProfileIcon() async {
    final id = await Navigator.of(context).push<int>(
      AppFadePageRoute<int>(
        pageBuilder: (_, _, _) =>
            ProfileIconPickerView(selectedId: _profileBackgroundCustomEmojiId),
      ),
    );
    if (id == null || id == _profileBackgroundCustomEmojiId) return;
    final colorId = _profileAccentColorId < 0 ? 0 : _profileAccentColorId;
    try {
      await _client.query({
        '@type': 'setProfileAccentColor',
        'profile_accent_color_id': colorId,
        'profile_background_custom_emoji_id': id,
      });
      if (!mounted) return;
      setState(() {
        _profileAccentColorId = colorId;
        _profileBackgroundCustomEmojiId = id;
      });
    } catch (_) {
      _toast(AppStrings.t(AppStringKeys.editProfileSaveFailed));
    }
  }

  Future<void> _changeAvatar() async {
    if (!_isPremium && !_isBotApi) {
      await _changeStaticAvatar();
      return;
    }
    final kind = await _chooseAvatarKind();
    if (kind == null) return;
    switch (kind) {
      case _AvatarKind.static:
        await _changeStaticAvatar();
      case _AvatarKind.animated:
        await _changeAnimatedAvatar();
    }
  }

  Future<_AvatarKind?> _chooseAvatarKind() {
    final c = context.colors;
    return showAppModalSheet<_AvatarKind>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (context) {
        return SafeArea(
          top: false,
          child: SettingsPanel(
            padding: const EdgeInsets.symmetric(vertical: 8),
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      AppStrings.t(AppStringKeys.editProfileChooseAvatarType),
                      style: AppTextStyle.title(
                        c.textPrimary,
                      ).copyWith(fontSize: 17),
                    ),
                  ),
                ),
                _avatarKindTile(
                  context,
                  icon: HeroAppIcons.image,
                  title: AppStringKeys.editProfileStaticAvatar,
                  subtitle: AppStringKeys.editProfileStaticAvatarDescription,
                  onTap: () => Navigator.of(context).pop(_AvatarKind.static),
                ),
                _avatarKindTile(
                  context,
                  icon: HeroAppIcons.video,
                  title: AppStringKeys.editProfileAnimatedAvatar,
                  subtitle: AppStringKeys.editProfileAnimatedAvatarDescription,
                  onTap: () => Navigator.of(context).pop(_AvatarKind.animated),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _avatarKindTile(
    BuildContext context, {
    required AppIconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppTheme.brand.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Center(
                child: AppIcon(icon, size: 21, color: AppTheme.brand),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStrings.t(title),
                    style: AppTextStyle.body(
                      c.textPrimary,
                    ).copyWith(fontWeight: AppTextWeight.semibold),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    AppStrings.t(subtitle),
                    style: AppTextStyle.caption(c.textSecondary),
                  ),
                ],
              ),
            ),
            AppIcon(HeroAppIcons.chevronRight, size: 18, color: c.textTertiary),
          ],
        ),
      ),
    );
  }

  Future<void> _changeStaticAvatar() async {
    try {
      final selection = await AppAssetPicker.pickDetailed(
        context,
        type: AppAssetPickerType.image,
        maxAssets: 1,
        preferLivePhotoVideo: true,
      );
      if (selection.assets.isEmpty) return;
      final selected = selection.assets.first;
      final img = selected.file;
      if (selected.isAnimatedImage || selected.isLivePhoto) {
        await _setAnimatedAvatar(img);
        return;
      }
      if (!mounted) return;
      final edited = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => ImageEditView(sourcePath: img.path, avatar: true),
        ),
      );
      if (edited == null) return;
      final file = File(edited);
      if (!await file.exists() || await file.length() == 0) {
        _toast(AppStrings.t(AppStringKeys.editProfileInvalidAvatarFile));
        return;
      }
      await _client.query({
        '@type': 'setProfilePhoto',
        'photo': {
          '@type': 'inputChatPhotoStatic',
          'photo': {'@type': 'inputFileLocal', 'path': edited},
        },
        'is_public': false,
      });
      await _finishAvatarUpdate();
    } catch (e) {
      _toast(
        AppStrings.t(AppStringKeys.editProfileAvatarUpdateFailed, {
          'value1': e,
        }),
      );
    }
  }

  Future<void> _changeAnimatedAvatar() async {
    if (!_canSetAnimatedAvatar()) return;
    try {
      final selection = await AppAssetPicker.pickDetailed(
        context,
        type: AppAssetPickerType.imageAndVideo,
        maxAssets: 1,
        maxVideoDuration: const Duration(seconds: 10),
        preferLivePhotoVideo: true,
      );
      if (selection.assets.isEmpty) return;
      await _setAnimatedAvatar(selection.assets.first.file);
    } catch (e) {
      _toast(
        AppStrings.t(AppStringKeys.editProfileAvatarUpdateFailed, {
          'value1': e,
        }),
      );
    }
  }

  Future<void> _setAnimatedAvatar(XFile animation) async {
    if (!_canSetAnimatedAvatar()) return;
    try {
      if (!mounted) return;
      final crop = await Navigator.of(context).push<AnimatedAvatarCrop>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => AnimatedAvatarCropView(source: animation),
        ),
      );
      if (crop == null) return;
      final prepared = await AnimatedAvatarPreparer.prepare(
        animation,
        crop: crop,
      );
      final file = File(prepared.path);
      if (!await file.exists() || await file.length() == 0) {
        _toast(AppStrings.t(AppStringKeys.editProfileInvalidAvatarFile));
        return;
      }
      final request = animatedProfilePhotoRequest(
        isPremium: _isPremium || _isBotApi,
        path: prepared.path,
      );
      if (request == null) {
        _toast(
          AppStrings.t(AppStringKeys.editProfileAnimatedAvatarPremiumRequired),
        );
        return;
      }
      await _client.query(request);
      await _finishAvatarUpdate();
    } catch (e) {
      _toast(
        AppStrings.t(AppStringKeys.editProfileAvatarUpdateFailed, {
          'value1': e,
        }),
      );
    }
  }

  bool _canSetAnimatedAvatar() {
    if (_isPremium || _isBotApi) return true;
    _toast(
      AppStrings.t(AppStringKeys.editProfileAnimatedAvatarPremiumRequired),
    );
    return false;
  }

  Future<void> _finishAvatarUpdate() async {
    if (!mounted) return;
    _toast(AppStrings.t(AppStringKeys.editProfileAvatarUpdated));
    // The new photo propagates via updateUser after upload; re-read shortly.
    await Future<void>.delayed(const Duration(milliseconds: 800));
    try {
      final me = await _client.query({'@type': 'getMe'});
      final userId = me.int64('id') ?? _userId;
      final photo = TDParse.smallPhoto(me.obj('profile_photo'));
      final full = await _client.query({
        '@type': 'getUserFullInfo',
        'user_id': userId,
      });
      final snapshot = ProfileContactSnapshot.fromFullInfo(full);
      await _loadPhotos(userId);
      if (!mounted) return;
      setState(() {
        _photo = photo;
        _currentPhotoId = snapshot.currentPhotoId;
        _publicPhotoId = snapshot.publicPhotoId;
      });
    } catch (_) {}
  }

  void _toast(String m) => showToast(context, m);

  @override
  Widget build(BuildContext context) {
    return SettingsPageScaffold(
      title: AppStrings.t(AppStringKeys.editProfileTitle),
      onBack: () => Navigator.of(context).pop(),
      showBackButton: widget.showBackButton,
      child: _loading
          ? const Center(child: AppActivityIndicator(size: 24))
          : SettingsListView(
              children: [
                _identityCard(),
                const SizedBox(height: AppSpacing.section),
                const SettingsSectionHeader(
                  AppStringKeys.editProfileSectionName,
                ),
                SettingsCard(
                  children: [
                    SettingsRow(
                      title: AppStrings.t(AppStringKeys.loginFirstName),
                      value: _firstName.isEmpty
                          ? AppStrings.t(AppStringKeys.editProfileTapToSet)
                          : _firstName,
                      onTap: _editFirstName,
                    ),
                    if (!_isBotApi) ...[
                      const InsetDivider(
                        leadingInset: AppMetric.settingsLeadingInset,
                      ),
                      SettingsRow(
                        title: AppStrings.t(AppStringKeys.editProfileLastName),
                        value: _lastName.isEmpty
                            ? AppStrings.t(AppStringKeys.editProfileTapToSet)
                            : _lastName,
                        onTap: _editLastName,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.section),
                const SettingsSectionHeader(
                  AppStringKeys.editProfileSectionAccount,
                ),
                SettingsCard(
                  children: [
                    SettingsRow(
                      title: AppStrings.t(AppStringKeys.editProfileUsername),
                      value: _username.isEmpty
                          ? AppStrings.t(
                              AppStringKeys.editProfileUsernameUnsetHandle,
                            )
                          : '@$_username',
                      showChevron: !_isBotApi,
                      onTap: _isBotApi ? null : _editUsername,
                    ),
                    if (!_isBotApi) ...[
                      const InsetDivider(
                        leadingInset: AppMetric.settingsLeadingInset,
                      ),
                      // The phone number can only change through an OTP
                      // flow, so this row is a readout, not a control.
                      SettingsRow(
                        title: AppStrings.t(AppStringKeys.editProfilePhone),
                        value: _phone.isEmpty
                            ? AppStrings.t(AppStringKeys.editProfileNotBound)
                            : TDParse.formatPhone(_phone),
                        showChevron: false,
                      ),
                      const InsetDivider(
                        leadingInset: AppMetric.settingsLeadingInset,
                      ),
                      SettingsRow(
                        title: AppStrings.t(
                          AppStringKeys.profileDetailBirthday,
                        ),
                        value: _birthdayText,
                        onTap: _editBirthday,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.section),
                const SettingsSectionHeader(
                  AppStringKeys.editProfileSectionAbout,
                ),
                SettingsCard(
                  children: [
                    SettingsRow(
                      title: AppStrings.t(AppStringKeys.editProfileBio),
                      value: _bio.isEmpty
                          ? AppStrings.t(AppStringKeys.editProfileTapToFillBio)
                          : _bio,
                      onTap: _editBio,
                    ),
                  ],
                ),
                _footnote(
                  AppStrings.t(AppStringKeys.editProfileBioPlaceholder),
                ),
                if (!_isBotApi) ...[
                  const SizedBox(height: AppSpacing.section),
                  const SettingsSectionHeader(
                    AppStringKeys.editProfileSectionAppearance,
                  ),
                  SettingsCard(
                    children: [
                      SettingsRow(
                        title: AppStrings.t(AppStringKeys.editProfileNameColor),
                        value: _accentColorLabel(_accentColorId),
                        trailing: _colorSwatch(_accentColorId),
                        onTap: _editNameColor,
                      ),
                      const InsetDivider(
                        leadingInset: AppMetric.settingsLeadingInset,
                      ),
                      SettingsRow(
                        title: AppStrings.t(
                          AppStringKeys.editProfileProfileColor,
                        ),
                        value: _accentColorLabel(_profileAccentColorId),
                        trailing: _colorSwatch(_profileAccentColorId),
                        onTap: _editProfileColor,
                      ),
                      const InsetDivider(
                        leadingInset: AppMetric.settingsLeadingInset,
                      ),
                      SettingsRow(
                        title: AppStringKeys.editProfileProfileIcon.l10n(
                          context,
                        ),
                        value: _profileBackgroundCustomEmojiId == 0
                            ? AppStrings.t(AppStringKeys.editProfileDefault)
                            : '',
                        trailing: _profileIconSwatch(),
                        onTap: _editProfileIcon,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.section),
                  SettingsCard(
                    children: [
                      SettingsRow(
                        title: AppStrings.t(
                          AppStringKeys.businessSettingsEntry,
                        ),
                        value: AppStrings.t(
                          AppStringKeys.businessSettingsSummary,
                        ),
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const BusinessSettingsView(),
                            ),
                          );
                        },
                      ),
                      const InsetDivider(
                        leadingInset: AppMetric.settingsLeadingInset,
                      ),
                      SettingsRow(
                        title: AppStrings.t(AppStringKeys.profileToolsTitle),
                        value: AppStrings.t(
                          AppStringKeys.profileToolsPhotoChatSummary,
                        ),
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ProfileContactManagementView(
                                userId: _userId,
                                initialName: '$_firstName $_lastName'.trim(),
                              ),
                            ),
                          );
                          if (mounted) await _load();
                        },
                      ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }

  /// Avatar, identity, and the account's photo stack in one card.
  ///
  /// The stack used to be two screens away under Profile tools, so an account
  /// with several photos looked like an account with one. Here every photo is
  /// on the screen you go to when you want to change your photo: tap one to
  /// wear it, tap the leading tile to add a new one.
  Widget _identityCard() {
    final c = context.colors;
    final name = '$_firstName $_lastName'.trim();
    final handle = _username.isEmpty
        ? AppStrings.t(AppStringKeys.editProfileUsernameUnsetHandle)
        : '@$_username';
    return SettingsPanel(
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.section),
          AppInteractiveSurface(
            onTap: _changeAvatar,
            semanticLabel: AppStrings.t(AppStringKeys.editProfileChangeAvatar),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: SizedBox(
              width: _heroAvatarSize,
              height: _heroAvatarSize,
              child: Stack(
                children: [
                  PhotoAvatar(
                    title: name,
                    photo: _photo,
                    size: _heroAvatarSize,
                  ),
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
              name,
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
              handle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.footnote(c.textSecondary),
            ),
          ),
          if (_isBotApi || _photos.isEmpty)
            const SizedBox(height: AppSpacing.section)
          else ...[
            const SizedBox(height: AppSpacing.xl),
            _photoStrip(),
            const SizedBox(height: AppSpacing.xxl),
          ],
        ],
      ),
    );
  }

  Widget _photoStrip() {
    return SizedBox(
      height: _photoTileSize,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: AppInsets.row,
        itemCount: _photos.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
        itemBuilder: (_, index) =>
            index == 0 ? _addPhotoTile() : _photoTile(_photos[index - 1]),
      ),
    );
  }

  Widget _addPhotoTile() {
    final c = context.colors;
    return AppInteractiveSurface(
      onTap: _changeAvatar,
      semanticLabel: AppStrings.t(AppStringKeys.editProfileAddPhoto),
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        width: _photoTileSize,
        height: _photoTileSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppTheme.brand.withValues(alpha: 0.12),
          shape: BoxShape.circle,
          border: Border.all(color: c.divider),
        ),
        child: AppIcon(
          HeroAppIcons.plus,
          size: AppIconSize.lg,
          color: AppTheme.brand,
        ),
      ),
    );
  }

  Widget _photoTile(ProfilePhotoEntry entry) {
    final c = context.colors;
    final isCurrent = entry.id == _currentPhotoId;
    final isPublic = entry.id == _publicPhotoId;
    return AppInteractiveSurface(
      onTap: isCurrent ? null : () => unawaited(_usePhoto(entry)),
      selected: isCurrent,
      semanticLabel: AppStrings.t(
        isCurrent
            ? AppStringKeys.editProfilePhotoCurrent
            : AppStringKeys.profilePhotoSetAsAvatar,
      ),
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: SizedBox(
        width: _photoTileSize,
        height: _photoTileSize,
        child: Stack(
          children: [
            Container(
              width: _photoTileSize,
              height: _photoTileSize,
              padding: EdgeInsets.all(
                isCurrent ? AppMetric.selectedBorder : 0.0,
              ),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isCurrent ? AppTheme.brand : c.divider,
                  width: isCurrent ? AppMetric.selectedBorder : 1,
                ),
              ),
              child: ClipOval(
                child: TDImage(photo: entry.file, cornerRadius: 0),
              ),
            ),
            if (isPublic)
              Positioned(
                right: 0,
                bottom: 0,
                child: Semantics(
                  label: AppStrings.t(AppStringKeys.editProfilePhotoPublic),
                  child: Container(
                    width: AppIconSize.md,
                    height: AppIconSize.md,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.card,
                      shape: BoxShape.circle,
                    ),
                    child: AppIcon(
                      HeroAppIcons.globe,
                      size: AppIconSize.xs - 2,
                      color: c.textSecondary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color? _accentColor(int colorId) =>
      (colorId >= 0 && colorId < kAccentColors.length)
      ? kAccentColors[colorId]
      : null;

  /// An unset accent reads as a word, not an absent swatch, so the row still
  /// says something. [SettingsRow] draws whichever of the two is non-null.
  String _accentColorLabel(int colorId) => _accentColor(colorId) == null
      ? AppStrings.t(AppStringKeys.editProfileDefault)
      : '';

  Widget? _colorSwatch(int colorId) {
    final color = _accentColor(colorId);
    if (color == null) return null;
    return Container(
      width: AppIconSize.xl,
      height: AppIconSize.xl,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget? _profileIconSwatch() {
    if (_profileBackgroundCustomEmojiId == 0) return null;
    return CustomEmojiView(
      id: _profileBackgroundCustomEmojiId,
      size: AppIconSize.add,
      color: context.colors.textPrimary,
    );
  }

  Widget _footnote(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.xxl,
      AppSpacing.md,
      AppSpacing.xxl,
      0,
    ),
    child: Text(text, style: AppTextStyle.caption(context.colors.textTertiary)),
  );
}

/// Result of [_BirthdayPickerSheet]: either a value (year 0 = no year) or clear.
class _BdayResult {
  const _BdayResult.set(this.day, this.month, this.year) : clear = false;
  const _BdayResult.clear() : day = 0, month = 0, year = 0, clear = true;
  final int day, month, year;
  final bool clear;
}

/// A Cupertino month/day(/optional year) wheel picker for the birthday, with a
/// "无年份" (no-year) option and a 清除生日 (clear) action. No Material.
class _BirthdayPickerSheet extends StatefulWidget {
  const _BirthdayPickerSheet({
    this.day,
    this.month,
    this.year,
    required this.canClear,
  });
  final int? day, month, year;
  final bool canClear;

  @override
  State<_BirthdayPickerSheet> createState() => _BirthdayPickerSheetState();
}

class _BirthdayPickerSheetState extends State<_BirthdayPickerSheet> {
  // Max day per month (Feb allows 29 so leap birthdays work without a year).
  static const _maxDays = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

  late int _month = widget.month ?? 1; // 1..12
  late int _day = widget.day ?? 1; // 1..31
  late final List<int> _years; // [thisYear .. 1900]
  late int _yearIdx; // 0 = 无年份, else _years[idx-1]
  late final FixedExtentScrollController _mc, _dc, _yc;

  @override
  void initState() {
    super.initState();
    final thisYear = DateTime.now().year;
    _years = [for (var y = thisYear; y >= 1900; y--) y];
    final hasYear = widget.year != null && widget.year != 0;
    _yearIdx = hasYear ? _years.indexOf(widget.year!) + 1 : 0;
    if (_yearIdx < 0) _yearIdx = 0;
    _mc = FixedExtentScrollController(initialItem: _month - 1);
    _dc = FixedExtentScrollController(initialItem: _day - 1);
    _yc = FixedExtentScrollController(initialItem: _yearIdx);
  }

  @override
  void dispose() {
    _mc.dispose();
    _dc.dispose();
    _yc.dispose();
    super.dispose();
  }

  void _done() {
    final year = _yearIdx == 0 ? 0 : _years[_yearIdx - 1];
    final day = _day.clamp(1, _maxDays[_month - 1]);
    Navigator.of(context).pop(_BdayResult.set(day, _month, year));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final labelStyle = TextStyle(fontSize: 18, color: c.textPrimary);
    return Container(
      height: 332,
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CupertinoButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    AppStrings.t(AppStringKeys.countryPickerCancel),
                    style: TextStyle(color: c.textSecondary),
                  ),
                ),
                Text(
                  AppStrings.t(AppStringKeys.profileDetailBirthday),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                CupertinoButton(
                  onPressed: _done,
                  child: Text(
                    AppStrings.t(AppStringKeys.addMembersDone),
                    style: TextStyle(
                      color: AppTheme.brand,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: _mc,
                      itemExtent: 36,
                      onSelectedItemChanged: (i) =>
                          setState(() => _month = i + 1),
                      children: [
                        for (var m = 1; m <= 12; m++)
                          Center(
                            child: Text(
                              AppStrings.t(
                                AppStringKeys.editProfileBirthMonth,
                                {'value1': m},
                              ),
                              style: labelStyle,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: _dc,
                      itemExtent: 36,
                      onSelectedItemChanged: (i) => _day = i + 1,
                      children: [
                        for (var d = 1; d <= 31; d++)
                          Center(
                            child: Text(
                              AppStrings.t(AppStringKeys.editProfileBirthDay, {
                                'value1': d,
                              }),
                              style: labelStyle,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: CupertinoPicker(
                      scrollController: _yc,
                      itemExtent: 36,
                      onSelectedItemChanged: (i) => _yearIdx = i,
                      children: [
                        Center(
                          child: Text(
                            AppStrings.t(AppStringKeys.editProfileNoBirthYear),
                            style: labelStyle,
                          ),
                        ),
                        for (final y in _years)
                          Center(
                            child: Text(
                              AppStrings.t(AppStringKeys.editProfileBirthYear, {
                                'value1': y,
                              }),
                              style: labelStyle,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (widget.canClear)
              CupertinoButton(
                onPressed: () =>
                    Navigator.of(context).pop(const _BdayResult.clear()),
                child: Text(
                  AppStrings.t(AppStringKeys.editProfileClearBirthday),
                  style: TextStyle(color: AppTheme.tagRed),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
