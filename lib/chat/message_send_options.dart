import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../theme/app_theme.dart';

class AvailableMessageEffect {
  const AvailableMessageEffect({required this.id, required this.emoji});

  final int id;
  final String emoji;
}

class MessageSendConfiguration {
  const MessageSendConfiguration({
    this.disableNotification = false,
    this.scheduleAt,
    this.sendWhenOnline = false,
    this.repeatPeriod = 0,
    this.effectId = 0,
    this.showCaptionAboveMedia = false,
    this.hasSpoiler = false,
    this.viewOnce = false,
    this.selfDestructSeconds = 0,
  });

  final bool disableNotification;
  final DateTime? scheduleAt;
  final bool sendWhenOnline;
  final int repeatPeriod;
  final int effectId;
  final bool showCaptionAboveMedia;
  final bool hasSpoiler;
  final bool viewOnce;
  final int selfDestructSeconds;

  bool get hasScheduling => scheduleAt != null || sendWhenOnline;

  MessageSendConfiguration copyWith({
    bool? disableNotification,
    DateTime? scheduleAt,
    bool clearScheduleAt = false,
    bool? sendWhenOnline,
    int? repeatPeriod,
    int? effectId,
    bool? showCaptionAboveMedia,
    bool? hasSpoiler,
    bool? viewOnce,
    int? selfDestructSeconds,
  }) => MessageSendConfiguration(
    disableNotification: disableNotification ?? this.disableNotification,
    scheduleAt: clearScheduleAt ? null : scheduleAt ?? this.scheduleAt,
    sendWhenOnline: sendWhenOnline ?? this.sendWhenOnline,
    repeatPeriod: repeatPeriod ?? this.repeatPeriod,
    effectId: effectId ?? this.effectId,
    showCaptionAboveMedia: showCaptionAboveMedia ?? this.showCaptionAboveMedia,
    hasSpoiler: hasSpoiler ?? this.hasSpoiler,
    viewOnce: viewOnce ?? this.viewOnce,
    selfDestructSeconds: selfDestructSeconds ?? this.selfDestructSeconds,
  );

  Map<String, dynamic>? get schedulingState {
    if (sendWhenOnline) {
      return {'@type': 'messageSchedulingStateSendWhenOnline'};
    }
    final date = scheduleAt;
    if (date == null) return null;
    return {
      '@type': 'messageSchedulingStateSendAtDate',
      'send_date': date.millisecondsSinceEpoch ~/ 1000,
      'repeat_period': repeatPeriod,
    };
  }

  Map<String, dynamic>? get selfDestructType {
    if (viewOnce) return {'@type': 'messageSelfDestructTypeImmediately'};
    if (selfDestructSeconds <= 0) return null;
    return {
      '@type': 'messageSelfDestructTypeTimer',
      'self_destruct_time': selfDestructSeconds,
    };
  }

  Map<String, dynamic> messageSendOptions({int paidStarCount = 0}) => {
    '@type': 'messageSendOptions',
    'disable_notification': disableNotification,
    if (paidStarCount > 0) 'paid_message_star_count': paidStarCount,
    'scheduling_state': ?schedulingState,
    if (effectId > 0) 'effect_id': effectId,
  };
}

Future<MessageSendConfiguration?> showMessageSendOptionsSheet(
  BuildContext context, {
  MessageSendConfiguration initial = const MessageSendConfiguration(),
  bool allowWhenOnline = false,
  bool mediaOptions = false,
  List<AvailableMessageEffect> effects = const [],
  VoidCallback? onOpenScheduledMessages,
}) => showGeneralDialog<MessageSendConfiguration>(
  context: context,
  barrierDismissible: true,
  barrierLabel: AppStringKeys.countryPickerCancel.l10n(context),
  barrierColor: const Color(0x99000000),
  transitionDuration: const Duration(milliseconds: 220),
  pageBuilder: (sheetContext, _, _) => Align(
    alignment: Alignment.bottomCenter,
    child: SizedBox(
      width: MediaQuery.sizeOf(sheetContext).width,
      child: _MessageSendOptionsSheet(
        initial: initial,
        allowWhenOnline: allowWhenOnline,
        mediaOptions: mediaOptions,
        effects: effects,
        onOpenScheduledMessages: onOpenScheduledMessages,
      ),
    ),
  ),
  transitionBuilder: (_, animation, _, child) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  },
);

class _MessageSendOptionsSheet extends StatefulWidget {
  const _MessageSendOptionsSheet({
    required this.initial,
    required this.allowWhenOnline,
    required this.mediaOptions,
    required this.effects,
    this.onOpenScheduledMessages,
  });

  final MessageSendConfiguration initial;
  final bool allowWhenOnline;
  final bool mediaOptions;
  final List<AvailableMessageEffect> effects;
  final VoidCallback? onOpenScheduledMessages;

  @override
  State<_MessageSendOptionsSheet> createState() =>
      _MessageSendOptionsSheetState();
}

class _MessageSendOptionsSheetState extends State<_MessageSendOptionsSheet> {
  late MessageSendConfiguration _value = widget.initial;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = _value.scheduleAt ?? now.add(const Duration(hours: 1));
    final selected = await showOwnedSchedulePicker(
      context: context,
      initial: initial.isBefore(now)
          ? now.add(const Duration(minutes: 5))
          : initial,
      firstDate: now,
      lastDate: now.add(const Duration(days: 366)),
    );
    if (!mounted || selected == null || !selected.isAfter(now)) return;
    setState(() {
      _value = _value.copyWith(scheduleAt: selected, sendWhenOnline: false);
    });
  }

  void _schedulePreset(Duration duration) {
    setState(() {
      _value = _value.copyWith(
        scheduleAt: DateTime.now().add(duration),
        sendWhenOnline: false,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Container(
      key: const ValueKey('messageSendOptionsSurface'),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.88,
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: colors.textTertiary.withValues(alpha: 0.34),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            _title(AppStringKeys.messageSendOptionsTitle.l10n(context)),
            _toggle(
              icon: HeroAppIcons.bellSlash,
              title: AppStrings.t(AppStringKeys.messageSendOptionsSendSilently),
              value: _value.disableNotification,
              onChanged: (value) => setState(
                () => _value = _value.copyWith(disableNotification: value),
              ),
            ),
            _section(
              AppStringKeys.messageSendOptionsDeliveryTime.l10n(context),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _choice(
                  AppStringKeys.messageSendOptionsNow.l10n(context),
                  !_value.hasScheduling,
                  () => setState(
                    () => _value = _value.copyWith(
                      clearScheduleAt: true,
                      sendWhenOnline: false,
                      repeatPeriod: 0,
                    ),
                  ),
                ),
                _choice(
                  AppStringKeys.messageSendOptionsInOneHour.l10n(context),
                  false,
                  () => _schedulePreset(const Duration(hours: 1)),
                ),
                _choice(
                  AppStringKeys.messageSendOptionsTomorrow.l10n(context),
                  false,
                  () => _schedulePreset(const Duration(days: 1)),
                ),
                _choice(
                  _value.scheduleAt == null
                      ? AppStringKeys.messageSendOptionsChooseDate.l10n(context)
                      : _formatDate(context, _value.scheduleAt!),
                  _value.scheduleAt != null,
                  _pickDate,
                ),
                if (widget.allowWhenOnline)
                  _choice(
                    AppStringKeys.messageSendOptionsWhenOnline.l10n(context),
                    _value.sendWhenOnline,
                    () => setState(
                      () => _value = _value.copyWith(
                        clearScheduleAt: true,
                        sendWhenOnline: true,
                        repeatPeriod: 0,
                      ),
                    ),
                  ),
              ],
            ),
            if (_value.scheduleAt != null) ...[
              _section(AppStringKeys.messageSendOptionsRepeat.l10n(context)),
              Wrap(
                spacing: 8,
                children: [
                  for (final item in const <(int, String)>[
                    (0, AppStringKeys.messageSendOptionsOnce),
                    (86400, AppStringKeys.messageSendOptionsDaily),
                    (604800, AppStringKeys.messageSendOptionsWeekly),
                    (2592000, AppStringKeys.messageSendOptionsMonthly),
                  ])
                    _choice(
                      item.$2.l10n(context),
                      _value.repeatPeriod == item.$1,
                      () => setState(
                        () => _value = _value.copyWith(repeatPeriod: item.$1),
                      ),
                    ),
                ],
              ),
            ],
            if (widget.mediaOptions) ...[
              _section(AppStringKeys.messageSendOptionsMedia.l10n(context)),
              _toggle(
                icon: HeroAppIcons.alignTop,
                title: AppStrings.t(
                  AppStringKeys.messageSendOptionsCaptionAboveMedia,
                ),
                value: _value.showCaptionAboveMedia,
                onChanged: (value) => setState(
                  () => _value = _value.copyWith(showCaptionAboveMedia: value),
                ),
              ),
              _toggle(
                icon: HeroAppIcons.eyeSlash,
                title: AppStrings.t(
                  AppStringKeys.messageSendOptionsHideWithSpoiler,
                ),
                value: _value.hasSpoiler,
                onChanged: (value) =>
                    setState(() => _value = _value.copyWith(hasSpoiler: value)),
              ),
              _toggle(
                icon: HeroAppIcons.eye,
                title: AppStrings.t(AppStringKeys.messageSendOptionsViewOnce),
                value: _value.viewOnce,
                onChanged: (value) => setState(
                  () => _value = _value.copyWith(
                    viewOnce: value,
                    selfDestructSeconds: 0,
                  ),
                ),
              ),
              if (!_value.viewOnce) ...[
                _section(
                  AppStringKeys.messageSendOptionsSelfDestruct.l10n(context),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final item in <(int, String)>[
                      (0, AppStringKeys.messageSendOptionsOff.l10n(context)),
                      for (final seconds in const [3, 10, 30, 60])
                        (
                          seconds,
                          context.l10n.t(
                            AppStringKeys.messageSendOptionsSeconds,
                            {'value1': seconds},
                          ),
                        ),
                    ])
                      _choice(
                        item.$2,
                        _value.selfDestructSeconds == item.$1,
                        () => setState(
                          () => _value = _value.copyWith(
                            selfDestructSeconds: item.$1,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
            if (widget.effects.isNotEmpty) ...[
              _section(
                AppStringKeys.messageSendOptionsMessageEffect.l10n(context),
              ),
              SizedBox(
                height: 50,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.effects.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final effect = index == 0
                        ? null
                        : widget.effects[index - 1];
                    final selected = _value.effectId == (effect?.id ?? 0);
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(
                        () =>
                            _value = _value.copyWith(effectId: effect?.id ?? 0),
                      ),
                      child: Container(
                        width: 50,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected
                              ? AppTheme.brand.withValues(alpha: 0.14)
                              : colors.card,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected ? AppTheme.brand : colors.divider,
                          ),
                        ),
                        child: effect == null
                            ? AppIcon(
                                HeroAppIcons.xmark,
                                size: 18,
                                color: colors.textSecondary,
                              )
                            : Text(
                                effect.emoji.isEmpty ? '✨' : effect.emoji,
                                style: const TextStyle(fontSize: 23),
                              ),
                      ),
                    );
                  },
                ),
              ),
            ],
            if (widget.onOpenScheduledMessages != null) ...[
              const SizedBox(height: 10),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  Navigator.of(context).pop();
                  widget.onOpenScheduledMessages?.call();
                },
                child: Container(
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    AppStrings.t(
                      AppStringKeys.messageSendOptionsScheduledMessages,
                    ),
                    style: TextStyle(
                      color: AppTheme.brand,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            GestureDetector(
              key: const ValueKey('messageSendOptionsConfirm'),
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(_value),
              child: Container(
                height: 50,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.brand,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  (_value.hasScheduling
                          ? AppStringKeys.messageSendOptionsSchedule
                          : AppStringKeys.composerSend)
                      .l10n(context),
                  style: const TextStyle(
                    color: Color(0xFFFFFFFF),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _title(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
    child: Text(
      text,
      style: TextStyle(
        color: context.colors.textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _section(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 14, 4, 7),
    child: Text(
      text,
      style: TextStyle(
        color: context.colors.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _toggle({
    required AppIconData icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => Container(
    height: 52,
    padding: const EdgeInsets.only(left: 12, right: 4),
    decoration: BoxDecoration(
      color: context.colors.card,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        AppIcon(icon, size: 20, color: AppTheme.brand),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: TextStyle(color: context.colors.textPrimary, fontSize: 15),
          ),
        ),
        AppSwitch(value: value, onChanged: onChanged),
      ],
    ),
  );

  Widget _choice(String label, bool selected, VoidCallback onTap) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppTheme.brand : context.colors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppTheme.brand : context.colors.divider,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? const Color(0xFFFFFFFF)
                  : context.colors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );

  String _formatDate(BuildContext context, DateTime value) => DateFormat.yMd(
    Localizations.localeOf(context).toLanguageTag(),
  ).add_Hm().format(value);
}

Future<DateTime?> showOwnedSchedulePicker({
  required BuildContext context,
  required DateTime initial,
  required DateTime firstDate,
  required DateTime lastDate,
}) {
  return showGeneralDialog<DateTime>(
    context: context,
    barrierDismissible: true,
    barrierLabel: AppStringKeys.countryPickerCancel.l10n(context),
    barrierColor: const Color(0x99000000),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (pickerContext, _, _) => Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        width: MediaQuery.sizeOf(pickerContext).width,
        child: _OwnedSchedulePicker(
          initial: initial,
          firstDate: firstDate,
          lastDate: lastDate,
        ),
      ),
    ),
    transitionBuilder: (_, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.12),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _OwnedSchedulePicker extends StatefulWidget {
  const _OwnedSchedulePicker({
    required this.initial,
    required this.firstDate,
    required this.lastDate,
  });

  final DateTime initial;
  final DateTime firstDate;
  final DateTime lastDate;

  @override
  State<_OwnedSchedulePicker> createState() => _OwnedSchedulePickerState();
}

class _OwnedSchedulePickerState extends State<_OwnedSchedulePicker> {
  late DateTime _selectedDay;
  late DateTime _visibleMonth;
  late int _hour;
  late int _minute;

  @override
  void initState() {
    super.initState();
    final initial = _clampInitial(widget.initial);
    _selectedDay = _dateOnly(initial);
    _visibleMonth = DateTime(initial.year, initial.month);
    _hour = initial.hour;
    _minute = initial.minute;
  }

  DateTime _clampInitial(DateTime value) {
    if (!value.isAfter(widget.firstDate)) {
      return widget.firstDate.add(const Duration(minutes: 5));
    }
    if (value.isAfter(widget.lastDate)) return widget.lastDate;
    return value;
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  DateTime get _value => DateTime(
    _selectedDay.year,
    _selectedDay.month,
    _selectedDay.day,
    _hour,
    _minute,
  );

  bool get _isValid =>
      _value.isAfter(widget.firstDate) && !_value.isAfter(widget.lastDate);

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _dayEnabled(DateTime day) {
    final normalized = _dateOnly(day);
    return !normalized.isBefore(_dateOnly(widget.firstDate)) &&
        !normalized.isAfter(_dateOnly(widget.lastDate));
  }

  bool _sameMonth(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;

  void _changeMonth(int delta) {
    final next = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
    final firstMonth = DateTime(widget.firstDate.year, widget.firstDate.month);
    final lastMonth = DateTime(widget.lastDate.year, widget.lastDate.month);
    if (next.isBefore(firstMonth) || next.isAfter(lastMonth)) return;
    setState(() => _visibleMonth = next);
  }

  void _selectDay(DateTime day) {
    if (!_dayEnabled(day)) return;
    setState(() {
      _selectedDay = day;
      final candidate = _value;
      if (!candidate.isAfter(widget.firstDate)) {
        final earliest = widget.firstDate.add(const Duration(minutes: 5));
        _hour = earliest.hour;
        _minute = earliest.minute;
      }
    });
  }

  void _adjustTime({int hours = 0, int minutes = 0}) {
    final adjusted = DateTime(
      2000,
      1,
      1,
      _hour,
      _minute,
    ).add(Duration(hours: hours, minutes: minutes));
    setState(() {
      _hour = adjusted.hour;
      _minute = adjusted.minute;
    });
  }

  void _submit() {
    if (_isValid) Navigator.of(context).pop(_value);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final monthLabel = DateFormat.yMMMM(locale).format(_visibleMonth);
    return Container(
      key: const ValueKey('ownedSchedulePicker'),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.82,
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 24,
            offset: Offset(0, -4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: c.textTertiary.withValues(alpha: 0.34),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Text(
              AppStringKeys.messageSendOptionsSelectDateAndTime.l10n(context),
              style: AppTextStyle.title(c.textPrimary),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.divider, width: 0.5),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      _OwnedIconButton(
                        icon: HeroAppIcons.chevronLeft,
                        onTap: () => _changeMonth(-1),
                      ),
                      Expanded(
                        child: Text(
                          monthLabel,
                          textAlign: TextAlign.center,
                          style: AppTextStyle.bodyLarge(
                            c.textPrimary,
                            weight: AppTextWeight.semibold,
                          ),
                        ),
                      ),
                      _OwnedIconButton(
                        icon: HeroAppIcons.chevronRight,
                        onTap: () => _changeMonth(1),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _weekdayHeader(locale),
                  const SizedBox(height: 4),
                  _calendarGrid(),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              AppStringKeys.messageSendOptionsTime.l10n(context),
              style: AppTextStyle.caption(
                c.textSecondary,
                weight: AppTextWeight.semibold,
              ),
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                Expanded(
                  child: _OwnedTimeStepper(
                    value: _hour.toString().padLeft(2, '0'),
                    onDecrease: () => _adjustTime(hours: -1),
                    onIncrease: () => _adjustTime(hours: 1),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(':', style: AppTextStyle.title(c.textPrimary)),
                ),
                Expanded(
                  child: _OwnedTimeStepper(
                    value: _minute.toString().padLeft(2, '0'),
                    onDecrease: () => _adjustTime(minutes: -5),
                    onIncrease: () => _adjustTime(minutes: 5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _OwnedPickerAction(
                    label: AppStringKeys.countryPickerCancel.l10n(context),
                    color: c.card,
                    textColor: c.textPrimary,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Opacity(
                    opacity: _isValid ? 1 : 0.42,
                    child: _OwnedPickerAction(
                      key: const ValueKey('ownedSchedulePickerConfirm'),
                      label: AppStringKeys.confirmOk.l10n(context),
                      color: AppTheme.brand,
                      textColor: const Color(0xFFFFFFFF),
                      onTap: _isValid ? _submit : null,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _weekdayHeader(String locale) {
    final c = context.colors;
    final sunday = DateTime(2024, 1, 7);
    return Row(
      children: [
        for (var index = 0; index < 7; index++)
          Expanded(
            child: Text(
              DateFormat.E(locale).format(sunday.add(Duration(days: index))),
              textAlign: TextAlign.center,
              style: AppTextStyle.caption(c.textTertiary),
            ),
          ),
      ],
    );
  }

  Widget _calendarGrid() {
    final first = DateTime(_visibleMonth.year, _visibleMonth.month);
    final leadingDays = first.weekday % 7;
    final firstCell = first.subtract(Duration(days: leadingDays));
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisExtent: 38,
      ),
      itemCount: 42,
      itemBuilder: (context, index) {
        final day = firstCell.add(Duration(days: index));
        final enabled = _dayEnabled(day);
        final inMonth = _sameMonth(day, _visibleMonth);
        final selected = _sameDay(day, _selectedDay);
        final c = context.colors;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? () => _selectDay(day) : null,
          child: Center(
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? AppTheme.brand : const Color(0x00000000),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '${day.day}',
                style: AppTextStyle.body(
                  selected
                      ? const Color(0xFFFFFFFF)
                      : !enabled
                      ? c.textTertiary.withValues(alpha: 0.35)
                      : inMonth
                      ? c.textPrimary
                      : c.textTertiary,
                  weight: selected
                      ? AppTextWeight.semibold
                      : AppTextWeight.regular,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OwnedIconButton extends StatelessWidget {
  const _OwnedIconButton({required this.icon, required this.onTap});

  final AppIconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: SizedBox(
      width: 40,
      height: 40,
      child: Center(
        child: AppIcon(icon, size: 18, color: context.colors.textSecondary),
      ),
    ),
  );
}

class _OwnedTimeStepper extends StatelessWidget {
  const _OwnedTimeStepper({
    required this.value,
    required this.onDecrease,
    required this.onIncrease,
  });

  final String value;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.divider, width: 0.5),
      ),
      child: Row(
        children: [
          _OwnedIconButton(icon: HeroAppIcons.minus, onTap: onDecrease),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: AppTextStyle.bodyLarge(
                c.textPrimary,
                weight: AppTextWeight.semibold,
              ),
            ),
          ),
          _OwnedIconButton(icon: HeroAppIcons.plus, onTap: onIncrease),
        ],
      ),
    );
  }
}

class _OwnedPickerAction extends StatelessWidget {
  const _OwnedPickerAction({
    super.key,
    required this.label,
    required this.color,
    required this.textColor,
    required this.onTap,
  });

  final String label;
  final Color color;
  final Color textColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.divider, width: 0.5),
      ),
      child: Text(
        label,
        style: AppTextStyle.bodyLarge(
          textColor,
          weight: AppTextWeight.semibold,
        ),
      ),
    ),
  );
}
