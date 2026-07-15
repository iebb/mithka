import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../chat/location_picker_view.dart';
import '../components/app_icons.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../profile/emoji_status_picker.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';

/// Telegram Business settings which belong to the current account. The data is
/// sourced from `userFullInfo.business_info`, so the editor never relies on a
/// locally cached business profile.
class BusinessSettingsView extends StatefulWidget {
  const BusinessSettingsView({super.key});

  @override
  State<BusinessSettingsView> createState() => _BusinessSettingsViewState();
}

class _BusinessSettingsViewState extends State<BusinessSettingsView> {
  final TdClient _client = TdClient.shared;
  Map<String, dynamic>? _location;
  Map<String, dynamic>? _openingHours;
  Map<String, dynamic>? _startPage;
  int _emojiStatusId = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final me = await _client.query({'@type': 'getMe'});
      final id = me.int64('id');
      if (id == null) return;
      final full = await _client.query({
        '@type': 'getUserFullInfo',
        'user_id': id,
      });
      final business = full.obj('business_info');
      if (!mounted) return;
      setState(() {
        _location = business?.obj('location');
        _openingHours = business?.obj('opening_hours');
        _startPage = business?.obj('start_page');
        _emojiStatusId = TDParse.emojiStatusCustomEmojiId(
          me.obj('emoji_status'),
        );
      });
    } catch (_) {
      // Requests below will surface a useful TDLib error through a toast.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Widget view) async {
    final changed = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => view));
    if (changed == true) await _load();
  }

  String get _locationSummary {
    final address = _location?.str('address')?.trim() ?? '';
    return address.isEmpty
        ? AppStrings.t(AppStringKeys.businessSettingsNotSet)
        : address;
  }

  String get _hoursSummary {
    final hours = _openingHours;
    final intervals = hours?.objects('opening_hours') ?? const [];
    if (hours == null || intervals.isEmpty) {
      return AppStrings.t(AppStringKeys.businessSettingsNotSet);
    }
    if (intervals.length == 1 &&
        intervals.first.integer('start_minute') == 0 &&
        intervals.first.integer('end_minute') == _minutesPerWeek) {
      return AppStrings.t(AppStringKeys.businessSettingsAlwaysOpen);
    }
    return AppStrings.t(AppStringKeys.businessSettingsHoursSet);
  }

  String get _startPageSummary {
    final title = _startPage?.str('title')?.trim() ?? '';
    return title.isEmpty
        ? AppStrings.t(AppStringKeys.businessSettingsNotSet)
        : title;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.businessSettingsTitle),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 18, 12, 24),
                    children: [
                      _sectionLabel(AppStringKeys.businessSettingsProfile),
                      _card([
                        _row(
                          HeroAppIcons.locationDot,
                          const Color(0xFFFF7A2F),
                          AppStringKeys.businessSettingsLocation,
                          _locationSummary,
                          () =>
                              _open(_BusinessLocationView(initial: _location)),
                        ),
                        const InsetDivider(leadingInset: 56),
                        _row(
                          HeroAppIcons.clock,
                          const Color(0xFFFF5B50),
                          AppStringKeys.businessSettingsOpeningHours,
                          _hoursSummary,
                          () => _open(
                            _BusinessOpeningHoursView(initial: _openingHours),
                          ),
                        ),
                        const InsetDivider(leadingInset: 56),
                        _row(
                          HeroAppIcons.message,
                          const Color(0xFF6D73F5),
                          AppStringKeys.businessSettingsStartPage,
                          _startPageSummary,
                          () => _open(
                            _BusinessStartPageView(initial: _startPage),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 22),
                      _sectionLabel(AppStringKeys.businessSettingsTools),
                      _card([
                        _row(
                          HeroAppIcons.link,
                          const Color(0xFF9B63F6),
                          AppStringKeys.businessSettingsChatLinks,
                          AppStrings.t(
                            AppStringKeys.businessSettingsChatLinksSubtitle,
                          ),
                          () => _open(const _BusinessChatLinksView()),
                        ),
                        const InsetDivider(leadingInset: 56),
                        _row(
                          HeroAppIcons.solidStar,
                          const Color(0xFF6D73F5),
                          AppStringKeys.businessSettingsEmojiStatus,
                          _emojiStatusId == 0
                              ? AppStrings.t(
                                  AppStringKeys.businessSettingsNotSet,
                                )
                              : AppStrings.t(
                                  AppStringKeys.businessSettingsEmojiStatusSet,
                                ),
                          () async {
                            await showEmojiStatusPicker(
                              context,
                              currentStatusId: _emojiStatusId,
                            );
                            await _load();
                          },
                        ),
                      ]),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
    child: Text(
      AppStrings.t(title),
      style: TextStyle(fontSize: 13, color: context.colors.textSecondary),
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

  Widget _row(
    AppIconData icon,
    Color iconColor,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 66,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: iconColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: AppIcon(icon, size: 17, color: Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.t(title),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 16, color: c.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: c.textSecondary),
                    ),
                  ],
                ),
              ),
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

const _minutesPerDay = 24 * 60;
const _minutesPerWeek = 7 * _minutesPerDay;

class _BusinessLocationView extends StatefulWidget {
  const _BusinessLocationView({this.initial});

  final Map<String, dynamic>? initial;

  @override
  State<_BusinessLocationView> createState() => _BusinessLocationViewState();
}

class _BusinessLocationViewState extends State<_BusinessLocationView> {
  late final TextEditingController _address = TextEditingController(
    text: widget.initial?.str('address') ?? '',
  );
  double? _latitude;
  double? _longitude;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final point = widget.initial?.obj('location');
    _latitude = point?.dbl('latitude');
    _longitude = point?.dbl('longitude');
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _pickOnMap() async {
    final initial = _latitude != null && _longitude != null
        ? LatLng(_latitude!, _longitude!)
        : await resolveLocationPickerStart();
    if (!mounted) return;
    final selected = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(builder: (_) => LocationPickerView(initial: initial)),
    );
    if (selected != null && mounted) {
      setState(() {
        _latitude = selected.latitude;
        _longitude = selected.longitude;
      });
    }
  }

  Future<void> _save({bool remove = false}) async {
    if (_saving) return;
    final address = _address.text.trim();
    if (!remove && address.isEmpty) {
      showToast(
        context,
        AppStrings.t(AppStringKeys.businessSettingsLocationAddressRequired),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await TdClient.shared.query({
        '@type': 'setBusinessLocation',
        'location': remove
            ? null
            : {
                '@type': 'businessLocation',
                'location': _latitude == null || _longitude == null
                    ? null
                    : {
                        '@type': 'location',
                        'latitude': _latitude,
                        'longitude': _longitude,
                      },
                'address': address,
              },
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.businessSettingsSaveFailed),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          _SaveHeader(
            title: AppStringKeys.businessSettingsLocation,
            saving: _saving,
            onSave: _save,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 18, 12, 24),
              children: [
                _editorCard(
                  child: CupertinoTextField(
                    controller: _address,
                    placeholder: AppStrings.t(
                      AppStringKeys.businessSettingsLocationAddressHint,
                    ),
                    maxLength: 96,
                    padding: const EdgeInsets.all(14),
                    style: TextStyle(fontSize: 16, color: c.textPrimary),
                    placeholderStyle: TextStyle(color: c.textTertiary),
                    decoration: const BoxDecoration(),
                  ),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _pickOnMap,
                  child: _editorCard(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          AppIcon(
                            HeroAppIcons.locationDot,
                            size: 19,
                            color: AppTheme.brand,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _latitude == null
                                  ? AppStrings.t(
                                      AppStringKeys.businessSettingsSetOnMap,
                                    )
                                  : '${_latitude!.toStringAsFixed(5)}, ${_longitude!.toStringAsFixed(5)}',
                              style: TextStyle(
                                fontSize: 16,
                                color: c.textPrimary,
                              ),
                            ),
                          ),
                          AppIcon(
                            HeroAppIcons.chevronRight,
                            size: 17,
                            color: c.textTertiary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (widget.initial != null) ...[
                  const SizedBox(height: 16),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _save(remove: true),
                    child: Center(
                      child: Text(
                        AppStrings.t(
                          AppStringKeys.businessSettingsRemoveLocation,
                        ),
                        style: TextStyle(fontSize: 15, color: AppTheme.tagRed),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BusinessOpeningHoursView extends StatefulWidget {
  const _BusinessOpeningHoursView({this.initial});

  final Map<String, dynamic>? initial;

  @override
  State<_BusinessOpeningHoursView> createState() =>
      _BusinessOpeningHoursViewState();
}

class _BusinessOpeningHoursViewState extends State<_BusinessOpeningHoursView> {
  late final List<_BusinessDayHours> _days;
  final List<_BusinessTimeZone> _zones = List.of(_fallbackTimeZones);
  String _timeZoneId = 'Etc/UTC';
  bool _alwaysOpen = false;
  bool _saving = false;

  static const _dayKeys = [
    AppStringKeys.businessSettingsMonday,
    AppStringKeys.businessSettingsTuesday,
    AppStringKeys.businessSettingsWednesday,
    AppStringKeys.businessSettingsThursday,
    AppStringKeys.businessSettingsFriday,
    AppStringKeys.businessSettingsSaturday,
    AppStringKeys.businessSettingsSunday,
  ];

  @override
  void initState() {
    super.initState();
    _days = List.generate(7, (_) => _BusinessDayHours());
    final initial = widget.initial;
    final intervals = initial?.objects('opening_hours') ?? const [];
    _timeZoneId = initial?.str('time_zone_id') ?? _deviceTimeZoneId();
    _alwaysOpen =
        intervals.length == 1 &&
        intervals.first.integer('start_minute') == 0 &&
        intervals.first.integer('end_minute') == _minutesPerWeek;
    if (!_alwaysOpen) _applyIntervals(intervals);
    _loadTimeZones();
  }

  Future<void> _loadTimeZones() async {
    try {
      final result = await TdClient.shared.query({'@type': 'getTimeZones'});
      final offset = DateTime.now().timeZoneOffset.inSeconds;
      final zones = (result.objects('time_zones') ?? const [])
          .map(
            (zone) => _BusinessTimeZone(
              zone.str('id') ?? '',
              zone.str('name') ?? zone.str('id') ?? '',
              zone.integer('utc_time_offset') ?? 0,
            ),
          )
          .where((zone) => zone.id.isNotEmpty)
          .toList();
      if (!mounted || zones.isEmpty) return;
      setState(() {
        _zones
          ..clear()
          ..addAll(zones);
        if (widget.initial == null) {
          _timeZoneId =
              zones
                  .where((zone) => zone.offset == offset)
                  .map((zone) => zone.id)
                  .firstOrNull ??
              _timeZoneId;
        }
      });
    } catch (_) {}
  }

  void _applyIntervals(List<Map<String, dynamic>> intervals) {
    for (final interval in intervals) {
      final start = interval.integer('start_minute') ?? -1;
      final end = interval.integer('end_minute') ?? -1;
      if (start < 0 || end <= start) continue;
      final day = start ~/ _minutesPerDay;
      if (day < 0 || day > 6) continue;
      final startInDay = start % _minutesPerDay;
      final endInDay = end == _minutesPerWeek
          ? _minutesPerDay
          : end % _minutesPerDay;
      _days[day] = _BusinessDayHours(
        enabled: true,
        start: startInDay,
        end: endInDay == 0 ? _minutesPerDay : endInDay,
      );
    }
  }

  Future<void> _chooseTimeZone() async {
    if (_zones.isEmpty) return;
    final selected = await showCupertinoModalPopup<_BusinessTimeZone>(
      context: context,
      builder: (context) =>
          _TimeZoneSheet(zones: _zones, selected: _timeZoneId),
    );
    if (selected != null && mounted) setState(() => _timeZoneId = selected.id);
  }

  Future<void> _chooseMinute(int day, bool start) async {
    final value = _days[day];
    final current = start ? value.start : value.end;
    final selected = await showCupertinoModalPopup<int>(
      context: context,
      builder: (_) => _MinutePicker(initial: current, isEnd: !start),
    );
    if (selected == null || !mounted) return;
    setState(() {
      final updated = _days[day];
      if (start) {
        updated.start = selected >= updated.end ? updated.end - 30 : selected;
      } else {
        updated.end = selected <= updated.start ? updated.start + 30 : selected;
      }
    });
  }

  Future<void> _save({bool remove = false}) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final intervals = <Map<String, dynamic>>[];
      if (_alwaysOpen) {
        intervals.add({
          '@type': 'businessOpeningHoursInterval',
          'start_minute': 0,
          'end_minute': _minutesPerWeek,
        });
      } else {
        for (var day = 0; day < _days.length; day++) {
          final value = _days[day];
          if (!value.enabled) continue;
          intervals.add({
            '@type': 'businessOpeningHoursInterval',
            'start_minute': day * _minutesPerDay + value.start,
            'end_minute': day * _minutesPerDay + value.end,
          });
        }
      }
      await TdClient.shared.query({
        '@type': 'setBusinessOpeningHours',
        'opening_hours': remove
            ? null
            : {
                '@type': 'businessOpeningHours',
                'time_zone_id': _timeZoneId,
                'opening_hours': intervals,
              },
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.businessSettingsSaveFailed),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          _SaveHeader(
            title: AppStringKeys.businessSettingsOpeningHours,
            saving: _saving,
            onSave: _save,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 18, 12, 24),
              children: [
                _editorCard(
                  child: Column(
                    children: [
                      _hoursRow(
                        AppStrings.t(AppStringKeys.businessSettingsAlwaysOpen),
                        CupertinoSwitch(
                          value: _alwaysOpen,
                          activeTrackColor: AppTheme.brand,
                          onChanged: (value) =>
                              setState(() => _alwaysOpen = value),
                        ),
                      ),
                      const InsetDivider(leadingInset: 14),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _chooseTimeZone,
                        child: _hoursRow(
                          AppStrings.t(AppStringKeys.businessSettingsTimeZone),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _timeZoneId,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: c.textSecondary,
                                ),
                              ),
                              const SizedBox(width: 4),
                              AppIcon(
                                HeroAppIcons.chevronRight,
                                size: 16,
                                color: c.textTertiary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_alwaysOpen) ...[
                  const SizedBox(height: 14),
                  _editorCard(
                    child: Column(
                      children: [
                        for (var day = 0; day < _days.length; day++) ...[
                          _dayRow(day),
                          if (day < _days.length - 1)
                            const InsetDivider(leadingInset: 14),
                        ],
                      ],
                    ),
                  ),
                ],
                if (widget.initial != null) ...[
                  const SizedBox(height: 16),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _save(remove: true),
                    child: Center(
                      child: Text(
                        AppStrings.t(AppStringKeys.businessSettingsRemoveHours),
                        style: TextStyle(fontSize: 15, color: AppTheme.tagRed),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _hoursRow(String title, Widget trailing) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(fontSize: 16, color: context.colors.textPrimary),
          ),
        ),
        trailing,
      ],
    ),
  );

  Widget _dayRow(int day) {
    final c = context.colors;
    final value = _days[day];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(
              AppStrings.t(_dayKeys[day]),
              style: TextStyle(fontSize: 15, color: c.textPrimary),
            ),
          ),
          if (value.enabled) ...[
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _timeButton(
                    _formatMinute(value.start),
                    () => _chooseMinute(day, true),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text('-', style: TextStyle(color: c.textTertiary)),
                  ),
                  _timeButton(
                    _formatMinute(value.end),
                    () => _chooseMinute(day, false),
                  ),
                ],
              ),
            ),
          ] else
            const Spacer(),
          const SizedBox(width: 10),
          CupertinoSwitch(
            value: value.enabled,
            activeTrackColor: AppTheme.brand,
            onChanged: (enabled) => setState(() => value.enabled = enabled),
          ),
        ],
      ),
    );
  }

  Widget _timeButton(String value, VoidCallback onTap) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Text(value, style: TextStyle(fontSize: 15, color: AppTheme.brand)),
    ),
  );
}

class _BusinessStartPageView extends StatefulWidget {
  const _BusinessStartPageView({this.initial});

  final Map<String, dynamic>? initial;

  @override
  State<_BusinessStartPageView> createState() => _BusinessStartPageViewState();
}

class _BusinessStartPageViewState extends State<_BusinessStartPageView> {
  late final TextEditingController _title = TextEditingController(
    text: widget.initial?.str('title') ?? '',
  );
  late final TextEditingController _message = TextEditingController(
    text: widget.initial?.str('message') ?? '',
  );
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _save({bool remove = false}) async {
    if (_saving) return;
    final title = _title.text.trim();
    final message = _message.text.trim();
    if (!remove && title.isEmpty && message.isEmpty) {
      showToast(
        context,
        AppStrings.t(AppStringKeys.businessSettingsStartPageRequired),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await TdClient.shared.query({
        '@type': 'setBusinessStartPage',
        'start_page': remove
            ? null
            : {
                '@type': 'inputBusinessStartPage',
                'title': title,
                'message': message,
                'sticker': null,
              },
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.businessSettingsSaveFailed),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          _SaveHeader(
            title: AppStringKeys.businessSettingsStartPage,
            saving: _saving,
            onSave: _save,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 18, 12, 24),
              children: [
                _fieldLabel(AppStringKeys.businessSettingsStartPageTitle),
                _editorCard(
                  child: CupertinoTextField(
                    controller: _title,
                    maxLength: 64,
                    padding: const EdgeInsets.all(14),
                    placeholder: AppStrings.t(
                      AppStringKeys.businessSettingsStartPageTitleHint,
                    ),
                    style: TextStyle(fontSize: 16, color: c.textPrimary),
                    placeholderStyle: TextStyle(color: c.textTertiary),
                    decoration: const BoxDecoration(),
                  ),
                ),
                const SizedBox(height: 16),
                _fieldLabel(AppStringKeys.businessSettingsStartPageMessage),
                _editorCard(
                  child: CupertinoTextField(
                    controller: _message,
                    maxLength: 512,
                    minLines: 4,
                    maxLines: 7,
                    padding: const EdgeInsets.all(14),
                    placeholder: AppStrings.t(
                      AppStringKeys.businessSettingsStartPageMessageHint,
                    ),
                    style: TextStyle(fontSize: 16, color: c.textPrimary),
                    placeholderStyle: TextStyle(color: c.textTertiary),
                    decoration: const BoxDecoration(),
                  ),
                ),
                if (widget.initial != null) ...[
                  const SizedBox(height: 16),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _save(remove: true),
                    child: Center(
                      child: Text(
                        AppStrings.t(
                          AppStringKeys.businessSettingsRemoveStartPage,
                        ),
                        style: TextStyle(fontSize: 15, color: AppTheme.tagRed),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BusinessChatLinksView extends StatefulWidget {
  const _BusinessChatLinksView();

  @override
  State<_BusinessChatLinksView> createState() => _BusinessChatLinksViewState();
}

class _BusinessChatLinksViewState extends State<_BusinessChatLinksView> {
  List<Map<String, dynamic>> _links = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await TdClient.shared.query({
        '@type': 'getBusinessChatLinks',
      });
      if (mounted) {
        setState(() => _links = result.objects('links') ?? const []);
      }
    } catch (_) {
      if (mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.businessSettingsSaveFailed),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit(Map<String, dynamic>? link) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _BusinessChatLinkEditor(initial: link)),
    );
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.businessSettingsChatLinks),
            onBack: () => Navigator.of(context).pop(),
            trailing: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _edit(null),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: AppIcon(
                  HeroAppIcons.plus,
                  size: 22,
                  color: AppTheme.brand,
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                    ),
                  )
                : _links.isEmpty
                ? Center(
                    child: Text(
                      AppStrings.t(
                        AppStringKeys.businessSettingsChatLinksEmpty,
                      ),
                      style: TextStyle(fontSize: 15, color: c.textSecondary),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 18, 12, 24),
                    itemCount: _links.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, index) {
                      final link = _links[index];
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _edit(link),
                        child: _editorCard(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                AppIcon(
                                  HeroAppIcons.link,
                                  size: 19,
                                  color: AppTheme.brand,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        link.str('title') ?? '',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: c.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        link.str('link') ?? '',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: c.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
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
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _BusinessChatLinkEditor extends StatefulWidget {
  const _BusinessChatLinkEditor({this.initial});

  final Map<String, dynamic>? initial;

  @override
  State<_BusinessChatLinkEditor> createState() =>
      _BusinessChatLinkEditorState();
}

class _BusinessChatLinkEditorState extends State<_BusinessChatLinkEditor> {
  late final TextEditingController _title = TextEditingController(
    text: widget.initial?.str('title') ?? '',
  );
  late final TextEditingController _draft = TextEditingController(
    text: widget.initial?.obj('text')?.str('text') ?? '',
  );
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _draft.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _title.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final info = {
      '@type': 'inputBusinessChatLink',
      'text': {
        '@type': 'formattedText',
        'text': _draft.text.trim(),
        'entities': <Map<String, dynamic>>[],
      },
      'title': _title.text.trim(),
    };
    try {
      final link = widget.initial?.str('link');
      await TdClient.shared.query(
        link == null
            ? {'@type': 'createBusinessChatLink', 'link_info': info}
            : {
                '@type': 'editBusinessChatLink',
                'link': link,
                'link_info': info,
              },
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.businessSettingsSaveFailed),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final link = widget.initial?.str('link');
    if (link == null || _saving) return;
    setState(() => _saving = true);
    try {
      await TdClient.shared.query({
        '@type': 'deleteBusinessChatLink',
        'link': link,
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.businessSettingsSaveFailed),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          _SaveHeader(
            title: AppStringKeys.businessSettingsChatLink,
            saving: _saving,
            onSave: _save,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 18, 12, 24),
              children: [
                _fieldLabel(AppStringKeys.businessSettingsLinkTitle),
                _editorCard(
                  child: CupertinoTextField(
                    controller: _title,
                    maxLength: 32,
                    padding: const EdgeInsets.all(14),
                    placeholder: AppStrings.t(
                      AppStringKeys.businessSettingsLinkTitleHint,
                    ),
                    style: TextStyle(fontSize: 16, color: c.textPrimary),
                    placeholderStyle: TextStyle(color: c.textTertiary),
                    decoration: const BoxDecoration(),
                  ),
                ),
                const SizedBox(height: 16),
                _fieldLabel(AppStringKeys.businessSettingsLinkDraft),
                _editorCard(
                  child: CupertinoTextField(
                    controller: _draft,
                    maxLength: 256,
                    minLines: 3,
                    maxLines: 5,
                    padding: const EdgeInsets.all(14),
                    placeholder: AppStrings.t(
                      AppStringKeys.businessSettingsLinkDraftHint,
                    ),
                    style: TextStyle(fontSize: 16, color: c.textPrimary),
                    placeholderStyle: TextStyle(color: c.textTertiary),
                    decoration: const BoxDecoration(),
                  ),
                ),
                if (widget.initial != null) ...[
                  const SizedBox(height: 16),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _delete,
                    child: Center(
                      child: Text(
                        AppStrings.t(AppStringKeys.businessSettingsDeleteLink),
                        style: TextStyle(fontSize: 15, color: AppTheme.tagRed),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SaveHeader extends StatelessWidget {
  const _SaveHeader({
    required this.title,
    required this.saving,
    required this.onSave,
  });

  final String title;
  final bool saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return NavHeader(
      title: AppStrings.t(title),
      onBack: () => Navigator.of(context).pop(),
      trailing: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: saving ? null : onSave,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                )
              : Text(
                  AppStrings.t(AppStringKeys.addMembersDone),
                  style: TextStyle(fontSize: 16, color: AppTheme.brand),
                ),
        ),
      ),
    );
  }
}

Widget _editorCard({required Widget child}) => Builder(
  builder: (context) => Container(
    decoration: BoxDecoration(
      color: context.colors.card,
      borderRadius: BorderRadius.circular(12),
    ),
    child: child,
  ),
);

Widget _fieldLabel(String value) => Builder(
  builder: (context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
    child: Text(
      AppStrings.t(value),
      style: TextStyle(fontSize: 13, color: context.colors.textSecondary),
    ),
  ),
);

String _formatMinute(int minute) {
  final value = minute.clamp(0, _minutesPerDay);
  final hour = value ~/ 60;
  final rest = value % 60;
  return '${hour.toString().padLeft(2, '0')}:${rest.toString().padLeft(2, '0')}';
}

class _BusinessDayHours {
  _BusinessDayHours({
    this.enabled = false,
    this.start = 9 * 60,
    this.end = 17 * 60,
  });

  bool enabled;
  int start;
  int end;
}

class _BusinessTimeZone {
  const _BusinessTimeZone(this.id, this.name, this.offset);

  final String id;
  final String name;
  final int offset;
}

const _fallbackTimeZones = <_BusinessTimeZone>[
  _BusinessTimeZone('Pacific/Honolulu', 'Honolulu', -10 * 60 * 60),
  _BusinessTimeZone('America/Los_Angeles', 'Los Angeles', -8 * 60 * 60),
  _BusinessTimeZone('America/Denver', 'Denver', -7 * 60 * 60),
  _BusinessTimeZone('America/Chicago', 'Chicago', -6 * 60 * 60),
  _BusinessTimeZone('America/New_York', 'New York', -5 * 60 * 60),
  _BusinessTimeZone('America/Sao_Paulo', 'Sao Paulo', -3 * 60 * 60),
  _BusinessTimeZone('Europe/London', 'London', 0),
  _BusinessTimeZone('Europe/Paris', 'Paris', 1 * 60 * 60),
  _BusinessTimeZone('Europe/Athens', 'Athens', 2 * 60 * 60),
  _BusinessTimeZone('Europe/Moscow', 'Moscow', 3 * 60 * 60),
  _BusinessTimeZone('Asia/Dubai', 'Dubai', 4 * 60 * 60),
  _BusinessTimeZone('Asia/Karachi', 'Karachi', 5 * 60 * 60),
  _BusinessTimeZone('Asia/Dhaka', 'Dhaka', 6 * 60 * 60),
  _BusinessTimeZone('Asia/Bangkok', 'Bangkok', 7 * 60 * 60),
  _BusinessTimeZone('Asia/Shanghai', 'Shanghai', 8 * 60 * 60),
  _BusinessTimeZone('Asia/Hong_Kong', 'Hong Kong', 8 * 60 * 60),
  _BusinessTimeZone('Asia/Tokyo', 'Tokyo', 9 * 60 * 60),
  _BusinessTimeZone('Asia/Seoul', 'Seoul', 9 * 60 * 60),
  _BusinessTimeZone('Australia/Sydney', 'Sydney', 10 * 60 * 60),
  _BusinessTimeZone('Pacific/Auckland', 'Auckland', 12 * 60 * 60),
  _BusinessTimeZone('Etc/UTC', 'UTC', 0),
];

String _deviceTimeZoneId() {
  switch (DateTime.now().timeZoneName) {
    case 'JST':
      return 'Asia/Tokyo';
    case 'KST':
      return 'Asia/Seoul';
    case 'HKT':
      return 'Asia/Hong_Kong';
    case 'SGT':
      return 'Asia/Singapore';
    case 'ICT':
      return 'Asia/Bangkok';
    case 'IST':
      return 'Asia/Kolkata';
    case 'GST':
      return 'Asia/Dubai';
    case 'AEST':
    case 'AEDT':
      return 'Australia/Sydney';
    case 'NZST':
    case 'NZDT':
      return 'Pacific/Auckland';
    case 'PST':
    case 'PDT':
      return 'America/Los_Angeles';
    case 'MST':
    case 'MDT':
      return 'America/Denver';
    case 'CST':
    case 'CDT':
      return 'America/Chicago';
    case 'EST':
    case 'EDT':
      return 'America/New_York';
    case 'BRT':
      return 'America/Sao_Paulo';
    case 'CET':
    case 'CEST':
      return 'Europe/Paris';
    case 'EET':
    case 'EEST':
      return 'Europe/Athens';
    case 'MSK':
      return 'Europe/Moscow';
    case 'GMT':
    case 'UTC':
    default:
      return 'Etc/UTC';
  }
}

class _TimeZoneSheet extends StatelessWidget {
  const _TimeZoneSheet({required this.zones, required this.selected});

  final List<_BusinessTimeZone> zones;
  final String selected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.62,
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          top: false,
          child: ListView.builder(
            itemCount: zones.length,
            itemBuilder: (_, index) {
              final zone = zones[index];
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(zone),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          zone.name,
                          style: TextStyle(fontSize: 16, color: c.textPrimary),
                        ),
                      ),
                      if (zone.id == selected)
                        AppIcon(
                          HeroAppIcons.check,
                          size: 18,
                          color: AppTheme.brand,
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MinutePicker extends StatefulWidget {
  const _MinutePicker({required this.initial, required this.isEnd});

  final int initial;
  final bool isEnd;

  @override
  State<_MinutePicker> createState() => _MinutePickerState();
}

class _MinutePickerState extends State<_MinutePicker> {
  late int _selected = widget.initial;
  late final FixedExtentScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = FixedExtentScrollController(initialItem: _selected ~/ 30);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final count = widget.isEnd ? 49 : 48;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        height: 284,
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
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
                  CupertinoButton(
                    onPressed: () => Navigator.of(context).pop(_selected),
                    child: Text(
                      AppStrings.t(AppStringKeys.addMembersDone),
                      style: TextStyle(color: AppTheme.brand),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: CupertinoPicker(
                  scrollController: _controller,
                  itemExtent: 38,
                  onSelectedItemChanged: (index) => _selected = index * 30,
                  children: [
                    for (var i = 0; i < count; i++)
                      Center(
                        child: Text(
                          _formatMinute(i * 30),
                          style: TextStyle(fontSize: 18, color: c.textPrimary),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
