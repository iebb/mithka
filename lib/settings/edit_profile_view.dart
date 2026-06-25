//
//  edit_profile_view.dart
//
//  编辑资料 — avatar + name / username / phone / birthday / bio / name &
//  profile accent colors, loaded from getMe/getUserFullInfo and saved back via
//  setName / setUsername / setBirthdate / setBio / setAccentColor /
//  setProfileAccentColor. Port of the Swift `EditProfileView`, wired to live
//  TDLib.
//

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../components/toast.dart';
import 'package:image_picker/image_picker.dart';

import '../chat/image_edit_view.dart';
import '../components/photo_avatar.dart';
import '../components/sf_symbols.dart';
import '../components/ui_components.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import 'accent_color_picker_view.dart';
import 'edit_field_view.dart';

class EditProfileView extends StatefulWidget {
  const EditProfileView({super.key});

  @override
  State<EditProfileView> createState() => _EditProfileViewState();
}

class _EditProfileViewState extends State<EditProfileView> {
  final TdClient _client = TdClient.shared;
  String _firstName = '';
  String _lastName = '';
  String _username = '';
  String _bio = '';
  String _phone = '';
  int _accentColorId = 0;
  int _profileAccentColorId = -1;
  int? _bDay, _bMonth, _bYear;
  TdFileRef? _photo;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final me = await _client.query({'@type': 'getMe'});
      final uid = me.int64('id');
      _firstName = me.str('first_name') ?? '';
      _lastName = me.str('last_name') ?? '';
      _username = me.obj('usernames')?.str('editable_username') ?? '';
      _phone = me.str('phone_number') ?? '';
      _accentColorId = me.integer('accent_color_id') ?? 0;
      _profileAccentColorId = me.integer('profile_accent_color_id') ?? -1;
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
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  String get _displayName => '$_firstName $_lastName'.trim();

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

  Future<void> _editName() async {
    final result = await _edit('修改名字', _displayName, hint: '名字');
    if (result == null || result.isEmpty) return;
    final parts = result.split(RegExp(r'\s+'));
    final first = parts.first;
    final last = parts.skip(1).join(' ');
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
      _toast('保存失败');
    }
  }

  Future<void> _editUsername() async {
    final value = await _edit(
      '修改用户名',
      _username,
      prefix: '@',
      hint: '设置用户名',
      keyboardType: TextInputType.visiblePassword,
    );
    if (value == null) return;
    try {
      await _client.query({'@type': 'setUsername', 'username': value});
      setState(() => _username = value);
    } catch (_) {
      _toast('用户名不可用');
    }
  }

  Future<void> _editBio() async {
    final value = await _edit(
      '修改简介',
      _bio,
      hint: '介绍一下自己',
      multiline: true,
      maxLength: 70,
    );
    if (value == null) return;
    try {
      await _client.query({'@type': 'setBio', 'bio': value});
      setState(() => _bio = value);
    } catch (_) {
      _toast('保存失败');
    }
  }

  String get _birthdayText {
    if (_bDay == null || _bMonth == null) return '点击设置';
    final base = '$_bMonth月$_bDay日';
    return _bYear != null ? '$_bYear年$base' : base;
  }

  Future<void> _editBirthday() async {
    final result = await showCupertinoModalPopup<_BdayResult>(
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
      _toast('保存失败');
    }
  }

  Future<void> _editNameColor() async {
    final id = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => AccentColorPickerView(
          title: '名字颜色',
          selectedId: _accentColorId,
          footnote: '用于你的名字和消息边栏的颜色。',
        ),
      ),
    );
    if (id == null || id < 0 || id == _accentColorId) return;
    try {
      await _client.query({
        '@type': 'setAccentColor',
        'accent_color_id': id,
        'background_custom_emoji_id': 0,
      });
      setState(() => _accentColorId = id);
    } catch (_) {
      _toast('保存失败');
    }
  }

  Future<void> _editProfileColor() async {
    final id = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => AccentColorPickerView(
          title: '资料颜色',
          selectedId: _profileAccentColorId,
          allowNone: true,
          footnote: '用于你的个人资料页背景的颜色。',
        ),
      ),
    );
    if (id == null || id == _profileAccentColorId) return;
    try {
      await _client.query({
        '@type': 'setProfileAccentColor',
        'profile_accent_color_id': id,
        'profile_background_custom_emoji_id': 0,
      });
      setState(() => _profileAccentColorId = id);
    } catch (_) {
      _toast('保存失败');
    }
  }

  Future<void> _changeAvatar() async {
    try {
      final img = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
      );
      if (img == null) return;
      if (!mounted) return;
      final edited = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => ImageEditView(sourcePath: img.path, avatar: true),
        ),
      );
      if (edited == null) return;
      await _client.query({
        '@type': 'setProfilePhoto',
        'photo': {
          '@type': 'inputChatPhotoStatic',
          'photo': {'@type': 'inputFileLocal', 'path': edited},
        },
      });
      if (!mounted) return;
      _toast('头像已更新');
      // The new photo propagates via updateUser after upload; re-read shortly.
      await Future<void>.delayed(const Duration(milliseconds: 800));
      final me = await _client.query({'@type': 'getMe'});
      if (mounted) {
        setState(() => _photo = TDParse.smallPhoto(me.obj('profile_photo')));
      }
    } catch (_) {
      _toast('更换头像失败');
    }
  }

  void _toast(String m) => showToast(context, m);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(title: '编辑资料', onBack: () => Navigator.of(context).pop()),
          Expanded(
            child: _loading
                ? const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 18, 12, 24),
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _changeAvatar,
                        child: Column(
                          children: [
                            Center(
                              child: PhotoAvatar(
                                title: _displayName,
                                photo: _photo,
                                size: 88,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Center(
                              child: Text(
                                '更换头像',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppTheme.brand,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      _field(
                        '名字',
                        _displayName.isEmpty ? '点击设置' : _displayName,
                        _editName,
                      ),
                      _field(
                        '用户名',
                        _username.isEmpty ? '@未设置' : '@$_username',
                        _editUsername,
                      ),
                      _readonlyField(
                        '电话',
                        _phone.isEmpty ? '未绑定' : TDParse.formatPhone(_phone),
                      ),
                      _field(
                        '生日',
                        _birthdayText,
                        _editBirthday,
                        faded: _bDay == null,
                      ),
                      _field(
                        '简介',
                        _bio.isEmpty ? '点击填写简介' : _bio,
                        _editBio,
                        faded: _bio.isEmpty,
                      ),
                      _colorField('名字颜色', _accentColorId, _editNameColor),
                      _colorField(
                        '资料颜色',
                        _profileAccentColorId,
                        _editProfileColor,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    String label,
    String value,
    VoidCallback onTap, {
    bool faded = false,
  }) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              child: Text(
                label,
                style: TextStyle(fontSize: 15, color: c.textSecondary),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  color: faded ? c.textTertiary : c.textPrimary,
                ),
              ),
            ),
            Icon(sfIcon('chevron.right'), size: 14, color: c.textTertiary),
          ],
        ),
      ),
    );
  }

  /// A non-editable row (no chevron, no tap) — used for the phone number, which
  /// can only be changed through an OTP verification flow.
  Widget _readonlyField(String label, String value) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: TextStyle(fontSize: 15, color: c.textSecondary),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 16, color: c.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  /// A row whose value is a color swatch (name / profile accent color).
  Widget _colorField(String label, int colorId, VoidCallback onTap) {
    final c = context.colors;
    final color = (colorId >= 0 && colorId < kAccentColors.length)
        ? kAccentColors[colorId]
        : null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              child: Text(
                label,
                style: TextStyle(fontSize: 15, color: c.textSecondary),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: color == null
                  ? Text(
                      '默认',
                      style: TextStyle(fontSize: 16, color: c.textTertiary),
                    )
                  : const SizedBox.shrink(),
            ),
            if (color != null)
              Container(
                width: 24,
                height: 24,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            Icon(sfIcon('chevron.right'), size: 14, color: c.textTertiary),
          ],
        ),
      ),
    );
  }
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
                  child: Text('取消', style: TextStyle(color: c.textSecondary)),
                ),
                Text(
                  '生日',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                CupertinoButton(
                  onPressed: _done,
                  child: Text(
                    '完成',
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
                          Center(child: Text('$m月', style: labelStyle)),
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
                          Center(child: Text('$d日', style: labelStyle)),
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
                        Center(child: Text('无年份', style: labelStyle)),
                        for (final y in _years)
                          Center(child: Text('$y年', style: labelStyle)),
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
                child: Text('清除生日', style: TextStyle(color: AppTheme.tagRed)),
              ),
          ],
        ),
      ),
    );
  }
}
