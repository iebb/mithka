import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../chat/chat_picker_view.dart';
import '../chat/image_edit_view.dart';
import '../components/app_dialog.dart';
import '../components/app_icons.dart';
import '../components/confirm_dialog.dart';
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../media/app_asset_picker.dart';
import '../settings/edit_field_view.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import 'profile_contact_service.dart';
import 'profile_photo_management_view.dart';

class ProfileContactManagementView extends StatefulWidget {
  const ProfileContactManagementView({
    super.key,
    required this.userId,
    this.initialName = '',
  });

  final int userId;
  final String initialName;

  @override
  State<ProfileContactManagementView> createState() =>
      _ProfileContactManagementViewState();
}

class _ProfileContactManagementViewState
    extends State<ProfileContactManagementView> {
  final TdClient _client = TdClient.shared;
  final ProfileContactService _service = const ProfileContactService();
  bool _loading = true;
  bool _busy = false;
  bool _isMe = false;
  bool _isPremium = false;
  bool _isContact = false;
  String _firstName = '';
  String _lastName = '';
  String _phoneNumber = '';
  ProfileContactSnapshot _snapshot = const ProfileContactSnapshot(
    needPhoneNumberPrivacyException: false,
    note: '',
    personalChatId: 0,
    personalPhotoId: 0,
    currentPhotoId: 0,
    publicPhotoId: 0,
  );
  TdFileRef? _personalPhoto;
  TdFileRef? _currentPhoto;
  TdFileRef? _publicPhoto;
  GiftAcceptanceSettings _giftSettings = const GiftAcceptanceSettings(
    showGiftButton: true,
    unlimitedGifts: true,
    limitedGifts: true,
    upgradedGifts: true,
    giftsFromChannels: true,
    premiumSubscription: true,
  );

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _client.query({'@type': 'getMe'}),
        _client.query({'@type': 'getUser', 'user_id': widget.userId}),
        _client.query({'@type': 'getUserFullInfo', 'user_id': widget.userId}),
      ]);
      final user = results[1];
      final full = results[2];
      if (!mounted) return;
      setState(() {
        _isMe = results[0].int64('id') == widget.userId;
        _isPremium = results[0].boolean('is_premium') ?? false;
        _isContact = user.boolean('is_contact') ?? false;
        _firstName = user.str('first_name') ?? '';
        _lastName = user.str('last_name') ?? '';
        _phoneNumber = user.str('phone_number') ?? '';
        _snapshot = ProfileContactSnapshot.fromFullInfo(full);
        _giftSettings = GiftAcceptanceSettings.fromFullInfo(full);
        _personalPhoto = _chatPhotoFile(full.obj('personal_photo'));
        _currentPhoto = _chatPhotoFile(full.obj('photo'));
        _publicPhoto = _chatPhotoFile(full.obj('public_photo'));
      });
    } catch (error) {
      if (mounted) {
        showToast(
          context,
          context.l10n.t(AppStringKeys.profileToolsLoadFailed, {
            'value1': error,
          }),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  TdFileRef? _chatPhotoFile(Map<String, dynamic>? photo) {
    if (photo == null) return null;
    final sizes = photo.objects('sizes') ?? const <Map<String, dynamic>>[];
    if (sizes.isEmpty) return null;
    final largest = sizes.reduce(
      (a, b) => (a.integer('width') ?? 0) >= (b.integer('width') ?? 0) ? a : b,
    );
    return TDParse.fileRef(largest.obj('photo'));
  }

  Future<void> _editContact() async {
    final result = await showGeneralDialog<_ContactEditResult>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cancel',
      barrierColor: Colors.black.withValues(alpha: 0.52),
      transitionDuration: const Duration(milliseconds: 160),
      transitionBuilder: (_, animation, _, child) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
          child: child,
        ),
      ),
      pageBuilder: (context, _, _) => _ContactEditDialog(
        firstName: _firstName,
        lastName: _lastName,
        phoneNumber: _phoneNumber,
        showSharePhone:
            !_isContact || _snapshot.needPhoneNumberPrivacyException,
        privacyExceptionNeeded: _snapshot.needPhoneNumberPrivacyException,
      ),
    );
    if (result == null || result.firstName.trim().isEmpty) return;
    await _run(() async {
      await _service.addOrEdit(
        userId: widget.userId,
        phoneNumber: result.phoneNumber,
        firstName: result.firstName,
        lastName: result.lastName,
        sharePhoneNumber: result.sharePhoneNumber,
      );
      _firstName = result.firstName.trim();
      _lastName = result.lastName.trim();
      _phoneNumber = result.phoneNumber.trim();
      _isContact = true;
    }, success: _isContact ? 'Contact updated' : 'Contact added');
  }

  Future<void> _removeContact() async {
    final confirmed = await confirmDialog(
      context,
      title: AppStrings.t(AppStringKeys.profileContactManagementRemoveContact),
      message: 'This person will be removed from your contact list.',
      confirmText: AppStrings.t(AppStringKeys.chatInfoRemove),
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _run(() async {
      await _service.remove(widget.userId);
      _isContact = false;
    }, success: 'Contact removed');
  }

  Future<void> _sharePhone() async {
    final confirmed = await confirmDialog(
      context,
      title: AppStrings.t(
        AppStringKeys.profileContactManagementShareYourPhoneNumber,
      ),
      message:
          'This shares your current number with this mutual contact and updates the matching privacy exception.',
      confirmText: AppStrings.t(AppStringKeys.topicChatShare),
    );
    if (!confirmed || !mounted) return;
    await _run(
      () => _service.sharePhone(widget.userId),
      success: 'Phone number shared',
    );
  }

  Future<void> _editNote() async {
    final value = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => EditFieldView(
          title: AppStrings.t(
            AppStringKeys.profileContactManagementContactNote,
          ),
          initial: _snapshot.note,
          hint: 'Only you can see this note',
          multiline: true,
          maxLength: 256,
        ),
      ),
    );
    if (value == null) return;
    await _run(() async {
      await _service.setNote(widget.userId, value);
      _snapshot = ProfileContactSnapshot(
        needPhoneNumberPrivacyException:
            _snapshot.needPhoneNumberPrivacyException,
        note: value.trim(),
        personalChatId: _snapshot.personalChatId,
        personalPhotoId: _snapshot.personalPhotoId,
        currentPhotoId: _snapshot.currentPhotoId,
        publicPhotoId: _snapshot.publicPhotoId,
      );
    }, success: value.trim().isEmpty ? 'Note removed' : 'Note saved');
  }

  Future<String?> _pickImage() async {
    final selection = await AppAssetPicker.pickDetailed(
      context,
      type: AppAssetPickerType.image,
      maxAssets: 1,
    );
    if (selection.assets.isEmpty || !mounted) return null;
    final edited = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ImageEditView(
          sourcePath: selection.assets.first.file.path,
          avatar: true,
        ),
      ),
    );
    if (edited == null) return null;
    final file = File(edited);
    return await file.exists() && await file.length() > 0 ? edited : null;
  }

  Future<void> _setPersonalPhoto() async {
    final path = await _pickImage();
    if (path == null) return;
    await _run(
      () => _service.setPersonalPhoto(widget.userId, path),
      success: 'Personal photo updated',
      reload: true,
    );
  }

  Future<void> _deletePersonalPhoto() async {
    await _run(
      () => _service.deletePersonalPhoto(widget.userId),
      success: 'Personal photo removed',
      reload: true,
    );
  }

  Future<void> _suggestPhoto() async {
    final path = await _pickImage();
    if (path == null) return;
    await _run(
      () => _service.suggestPhoto(widget.userId, path),
      success: 'Photo suggestion sent',
    );
  }

  Future<void> _suggestBirthdate() async {
    final value = await showGeneralDialog<_SuggestedBirthdate>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cancel',
      barrierColor: Colors.black.withValues(alpha: 0.52),
      transitionDuration: const Duration(milliseconds: 160),
      transitionBuilder: (_, animation, _, child) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
          child: child,
        ),
      ),
      pageBuilder: (_, _, _) => const _BirthdateDialog(),
    );
    if (value == null) return;
    await _run(
      () => _service.suggestBirthdate(
        widget.userId,
        day: value.day,
        month: value.month,
        year: value.year,
      ),
      success: 'Birthdate suggestion sent',
    );
  }

  Future<void> _choosePersonalChat() async {
    final result = await Navigator.of(context).push<ChatPickerResult>(
      MaterialPageRoute(
        builder: (_) => ChatPickerView(
          title: context.l10n.t(AppStringKeys.profileToolsChooseProfileChat),
        ),
      ),
    );
    if (result == null || !mounted) return;
    await _run(() async {
      await _service.setPersonalChat(result.chat.id);
      _snapshot = ProfileContactSnapshot(
        needPhoneNumberPrivacyException:
            _snapshot.needPhoneNumberPrivacyException,
        note: _snapshot.note,
        personalChatId: result.chat.id,
        personalPhotoId: _snapshot.personalPhotoId,
        currentPhotoId: _snapshot.currentPhotoId,
        publicPhotoId: _snapshot.publicPhotoId,
      );
    }, success: context.l10n.t(AppStringKeys.profileToolsProfileChatUpdated));
  }

  Future<void> _clearPersonalChat() async {
    await _run(() async {
      await _service.setPersonalChat(0);
      _snapshot = ProfileContactSnapshot(
        needPhoneNumberPrivacyException:
            _snapshot.needPhoneNumberPrivacyException,
        note: _snapshot.note,
        personalChatId: 0,
        personalPhotoId: _snapshot.personalPhotoId,
        currentPhotoId: _snapshot.currentPhotoId,
        publicPhotoId: _snapshot.publicPhotoId,
      );
    }, success: context.l10n.t(AppStringKeys.profileToolsProfileChatRemoved));
  }

  Future<void> _updateGiftSettings(GiftAcceptanceSettings value) async {
    if (_busy) return;
    final previous = _giftSettings;
    setState(() {
      _busy = true;
      _giftSettings = value;
    });
    try {
      await _service.setGiftSettings(value);
      if (mounted) {
        showToast(
          context,
          context.l10n.t(AppStringKeys.profileToolsGiftSettingsUpdated),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _giftSettings = previous);
        showToast(
          context,
          context.l10n.t(AppStringKeys.profileToolsActionFailed, {
            'value1': error,
          }),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run(
    Future<void> Function() action, {
    required String success,
    bool reload = false,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      showToast(context, success);
      if (reload) await _load();
    } catch (error) {
      if (mounted) {
        showToast(
          context,
          context.l10n.t(AppStringKeys.profileToolsActionFailed, {
            'value1': error,
          }),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
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
            title: _isMe
                ? context.l10n.t(AppStringKeys.profileToolsTitle)
                : 'Contact tools',
            onBack: () => Navigator.of(context).pop(),
            trailing: _refreshAction(),
          ),
          Expanded(
            child: _loading
                ? const Center(child: AppActivityIndicator(size: 24))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 14, 12, 28),
                    children: [
                      if (_busy)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 10),
                          child: Center(child: AppActivityIndicator(size: 18)),
                        ),
                      if (_isMe) ..._ownProfileRows() else ..._contactRows(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _refreshAction() => Semantics(
    button: true,
    label: context.l10n.t(AppStringKeys.profileToolsRefresh),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _loading || _busy ? null : () => unawaited(_load()),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: AppIcon(
          HeroAppIcons.arrowsRotate,
          size: 19,
          color: _loading || _busy
              ? context.colors.textTertiary
              : context.colors.textPrimary,
        ),
      ),
    ),
  );

  List<Widget> _ownProfileRows() {
    final l10n = context.l10n;
    final premiumRequired = l10n.t(AppStringKeys.profileToolsPremiumRequired);
    return [
      _section(l10n.t(AppStringKeys.profileToolsProfilePhotosSection), [
        _row(
          HeroAppIcons.images,
          l10n.t(AppStringKeys.profileToolsManageProfilePhotos),
          l10n.t(AppStringKeys.profileToolsCurrentPublicPhotoHistory),
          () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const ProfilePhotoManagementView(),
            ),
          ),
        ),
      ]),
      const SizedBox(height: 18),
      _section(l10n.t(AppStringKeys.profileToolsPersonalChatSection), [
        _row(
          HeroAppIcons.comments,
          l10n.t(AppStringKeys.profileToolsChooseProfileChat),
          _snapshot.personalChatId == 0
              ? l10n.t(AppStringKeys.profileToolsShowChatOnProfile)
              : l10n.t(AppStringKeys.profileToolsProfileChatId, {
                  'value1': _snapshot.personalChatId,
                }),
          _choosePersonalChat,
        ),
        if (_snapshot.personalChatId != 0)
          _row(
            HeroAppIcons.xmark,
            l10n.t(AppStringKeys.profileToolsRemoveProfileChat),
            l10n.t(AppStringKeys.profileToolsStopShowingProfileChat),
            _clearPersonalChat,
            destructive: true,
          ),
      ]),
      const SizedBox(height: 18),
      _section(l10n.t(AppStringKeys.profileToolsGiftsSection), [
        _toggleRow(
          l10n.t(AppStringKeys.profileToolsShowGiftButton),
          l10n.t(AppStringKeys.profileToolsKeepGiftActionsVisible),
          _giftSettings.showGiftButton,
          (value) => _updateGiftSettings(
            _giftSettings.copyWith(showGiftButton: value),
          ),
        ),
        _toggleRow(
          l10n.t(AppStringKeys.profileToolsAcceptUnlimitedGifts),
          _isPremium
              ? l10n.t(AppStringKeys.profileToolsRegularGiftsWithoutSupplyLimit)
              : premiumRequired,
          _giftSettings.unlimitedGifts,
          _isPremium
              ? (value) => _updateGiftSettings(
                  _giftSettings.copyWith(unlimitedGifts: value),
                )
              : null,
        ),
        _toggleRow(
          l10n.t(AppStringKeys.profileToolsAcceptLimitedGifts),
          _isPremium
              ? l10n.t(AppStringKeys.profileToolsLimitedGiftsDescription)
              : premiumRequired,
          _giftSettings.limitedGifts,
          _isPremium
              ? (value) => _updateGiftSettings(
                  _giftSettings.copyWith(limitedGifts: value),
                )
              : null,
        ),
        _toggleRow(
          l10n.t(AppStringKeys.profileToolsAcceptUpgradedGifts),
          _isPremium
              ? l10n.t(AppStringKeys.profileToolsAcceptUpgradedGiftsDescription)
              : premiumRequired,
          _giftSettings.upgradedGifts,
          _isPremium
              ? (value) => _updateGiftSettings(
                  _giftSettings.copyWith(upgradedGifts: value),
                )
              : null,
        ),
        _toggleRow(
          l10n.t(AppStringKeys.profileToolsAcceptGiftsFromChannels),
          _isPremium
              ? l10n.t(
                  AppStringKeys.profileToolsAcceptGiftsFromChannelsDescription,
                )
              : premiumRequired,
          _giftSettings.giftsFromChannels,
          _isPremium
              ? (value) => _updateGiftSettings(
                  _giftSettings.copyWith(giftsFromChannels: value),
                )
              : null,
        ),
        _toggleRow(
          l10n.t(AppStringKeys.profileToolsAcceptPremiumGifts),
          _isPremium
              ? l10n.t(AppStringKeys.profileToolsAcceptPremiumGiftsDescription)
              : premiumRequired,
          _giftSettings.premiumSubscription,
          _isPremium
              ? (value) => _updateGiftSettings(
                  _giftSettings.copyWith(premiumSubscription: value),
                )
              : null,
        ),
      ]),
    ];
  }

  List<Widget> _contactRows() => [
    _photoComparison(),
    const SizedBox(height: 18),
    _section('CONTACT', [
      _row(
        _isContact ? HeroAppIcons.penToSquare : HeroAppIcons.userPlus,
        _isContact ? 'Edit contact' : 'Add contact',
        'Name, phone number, and privacy exception',
        _editContact,
      ),
      if (_isContact && _snapshot.needPhoneNumberPrivacyException)
        _row(
          HeroAppIcons.phone,
          'Share my phone number',
          'Add the required phone-number privacy exception',
          _sharePhone,
        ),
      _row(
        HeroAppIcons.font,
        'Private note',
        _snapshot.note.isEmpty ? 'Only you can see it' : _snapshot.note,
        _editNote,
      ),
    ]),
    const SizedBox(height: 18),
    _section('PROFILE SUGGESTIONS', [
      _row(
        HeroAppIcons.camera,
        'Set personal photo',
        'A private photo visible only to you',
        _setPersonalPhoto,
      ),
      if (_snapshot.personalPhotoId != 0)
        _row(
          HeroAppIcons.trash,
          'Remove personal photo',
          'Return to the user\'s own profile photo',
          _deletePersonalPhoto,
          destructive: true,
        ),
      _row(
        HeroAppIcons.image,
        'Suggest profile photo',
        'The user can accept it from the service message',
        _suggestPhoto,
      ),
      _row(
        HeroAppIcons.clock,
        'Suggest birthdate',
        'The user decides whether to apply it',
        _suggestBirthdate,
      ),
    ]),
    if (_isContact) ...[
      const SizedBox(height: 18),
      _section('CONTACT LIST', [
        _row(
          HeroAppIcons.trash,
          'Remove contact',
          'Delete from your Telegram contacts',
          _removeContact,
          destructive: true,
        ),
      ]),
    ],
  ];

  Widget _photoComparison() {
    final colors = context.colors;
    final name = '$_firstName $_lastName'.trim().isNotEmpty
        ? '$_firstName $_lastName'.trim()
        : widget.initialName;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _photoColumn('Personal', name, _personalPhoto),
          _photoColumn('Current', name, _currentPhoto),
          _photoColumn('Public', name, _publicPhoto),
        ],
      ),
    );
  }

  Widget _photoColumn(String label, String name, TdFileRef? photo) => Column(
    children: [
      PhotoAvatar(title: name, photo: photo, size: 58),
      const SizedBox(height: 7),
      Text(label, style: AppTextStyle.caption(context.colors.textSecondary)),
    ],
  );

  Widget _section(String title, List<Widget> rows) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 7),
          child: Text(title, style: AppTextStyle.caption(colors.textSecondary)),
        ),
        Container(
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(14),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                rows[i],
                if (i < rows.length - 1) const InsetDivider(leadingInset: 56),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(
    AppIconData icon,
    String title,
    String subtitle,
    VoidCallback onTap, {
    bool destructive = false,
  }) {
    final colors = context.colors;
    final color = destructive ? const Color(0xFFFF4D4F) : colors.textPrimary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _busy ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            AppIcon(
              icon,
              size: 21,
              color: destructive ? color : AppTheme.brand,
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyle.body(color)),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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

  Widget _toggleRow(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool>? onChanged,
  ) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          AppIcon(HeroAppIcons.star, size: 21, color: AppTheme.brand),
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
          AppSwitch(
            value: value,
            enabled: !_busy && onChanged != null,
            onChanged: onChanged ?? (_) {},
          ),
        ],
      ),
    );
  }
}

class _ContactEditResult {
  const _ContactEditResult({
    required this.firstName,
    required this.lastName,
    required this.phoneNumber,
    required this.sharePhoneNumber,
  });

  final String firstName;
  final String lastName;
  final String phoneNumber;
  final bool sharePhoneNumber;
}

class _ContactEditDialog extends StatefulWidget {
  const _ContactEditDialog({
    required this.firstName,
    required this.lastName,
    required this.phoneNumber,
    required this.showSharePhone,
    required this.privacyExceptionNeeded,
  });

  final String firstName;
  final String lastName;
  final String phoneNumber;
  final bool showSharePhone;
  final bool privacyExceptionNeeded;

  @override
  State<_ContactEditDialog> createState() => _ContactEditDialogState();
}

class _ContactEditDialogState extends State<_ContactEditDialog> {
  late final TextEditingController _first = TextEditingController(
    text: widget.firstName,
  );
  late final TextEditingController _last = TextEditingController(
    text: widget.lastName,
  );
  late final TextEditingController _phone = TextEditingController(
    text: widget.phoneNumber,
  );
  bool _share = false;

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppDialogSurface(
      title: AppStrings.t(AppStringKeys.profileContactManagementContactDetails),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _field(_first, 'First name'),
          const SizedBox(height: 10),
          _field(_last, 'Last name'),
          const SizedBox(height: 10),
          _field(_phone, 'Phone number', phone: true),
          if (widget.showSharePhone) ...[
            const SizedBox(height: 12),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _share = !_share),
              child: Row(
                children: [
                  _CheckBox(value: _share),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.privacyExceptionNeeded
                          ? 'Share my number and add the required privacy exception'
                          : 'Share my phone number',
                      style: AppTextStyle.caption(colors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        AppDialogAction(
          label: AppStrings.t(AppStringKeys.confirmCancel),
          onTap: () => Navigator.of(context).pop(),
        ),
        AppDialogAction(
          label: AppStrings.t(AppStringKeys.accentColorPickerSave),
          primary: true,
          onTap: () {
            if (_first.text.trim().isEmpty) return;
            Navigator.of(context).pop(
              _ContactEditResult(
                firstName: _first.text,
                lastName: _last.text,
                phoneNumber: _phone.text,
                sharePhoneNumber: _share,
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String hint, {
    bool phone = false,
  }) {
    final colors = context.colors;
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.searchFill,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: colors.divider),
      ),
      alignment: Alignment.center,
      child: TextField(
        controller: controller,
        keyboardType: phone ? TextInputType.phone : TextInputType.name,
        style: AppTextStyle.body(colors.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AppTextStyle.body(colors.textTertiary),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          isDense: true,
        ),
      ),
    );
  }
}

class _CheckBox extends StatelessWidget {
  const _CheckBox({required this.value});

  final bool value;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 150),
    width: 22,
    height: 22,
    decoration: BoxDecoration(
      color: value ? AppTheme.brand : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(
        color: value ? AppTheme.brand : context.colors.textTertiary,
      ),
    ),
    alignment: Alignment.center,
    child: value
        ? const AppIcon(HeroAppIcons.check, size: 15, color: Colors.white)
        : null,
  );
}

class _SuggestedBirthdate {
  const _SuggestedBirthdate(this.day, this.month, this.year);

  final int day;
  final int month;
  final int year;
}

class _BirthdateDialog extends StatefulWidget {
  const _BirthdateDialog();

  @override
  State<_BirthdateDialog> createState() => _BirthdateDialogState();
}

class _BirthdateDialogState extends State<_BirthdateDialog> {
  final _day = TextEditingController();
  final _month = TextEditingController();
  final _year = TextEditingController();

  @override
  void dispose() {
    _day.dispose();
    _month.dispose();
    _year.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppDialogSurface(
    title: AppStrings.t(AppStringKeys.profileContactManagementSuggestBirthdate),
    content: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _number(context, _month, 'Month')),
        const SizedBox(width: 8),
        Expanded(child: _number(context, _day, 'Day')),
        const SizedBox(width: 8),
        Expanded(child: _number(context, _year, 'Year')),
      ],
    ),
    actions: [
      AppDialogAction(
        label: AppStrings.t(AppStringKeys.confirmCancel),
        onTap: () => Navigator.of(context).pop(),
      ),
      AppDialogAction(
        label: AppStrings.t(AppStringKeys.stickerStudioShortNameSuggest),
        primary: true,
        onTap: () {
          final day = int.tryParse(_day.text) ?? 0;
          final month = int.tryParse(_month.text) ?? 0;
          final year = int.tryParse(_year.text) ?? 0;
          if (day < 1 || day > 31 || month < 1 || month > 12) return;
          Navigator.of(context).pop(_SuggestedBirthdate(day, month, year));
        },
      ),
    ],
  );

  Widget _number(
    BuildContext context,
    TextEditingController controller,
    String hint,
  ) {
    final colors = context.colors;
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: colors.searchFill,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: colors.divider),
      ),
      alignment: Alignment.center,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        style: AppTextStyle.body(colors.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AppTextStyle.caption(colors.textTertiary),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          isDense: true,
        ),
      ),
    );
  }
}
