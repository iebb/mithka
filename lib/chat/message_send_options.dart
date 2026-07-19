import 'package:flutter/material.dart';
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
}) => showModalBottomSheet<MessageSendConfiguration>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _MessageSendOptionsSheet(
    initial: initial,
    allowWhenOnline: allowWhenOnline,
    mediaOptions: mediaOptions,
    effects: effects,
    onOpenScheduledMessages: onOpenScheduledMessages,
  ),
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
    final date = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 366)),
      initialDate: initial.isBefore(now) ? now : initial,
    );
    if (!mounted || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (!mounted || time == null) return;
    final selected = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (!selected.isAfter(now)) return;
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
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        ),
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
              _title('Send options'),
              _toggle(
                icon: HeroAppIcons.bellSlash,
                title: AppStrings.t(
                  AppStringKeys.messageSendOptionsSendSilently,
                ),
                value: _value.disableNotification,
                onChanged: (value) => setState(
                  () => _value = _value.copyWith(disableNotification: value),
                ),
              ),
              _section('Delivery time'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _choice(
                    'Now',
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
                    'In 1 hour',
                    false,
                    () => _schedulePreset(const Duration(hours: 1)),
                  ),
                  _choice(
                    'Tomorrow',
                    false,
                    () => _schedulePreset(const Duration(days: 1)),
                  ),
                  _choice(
                    _value.scheduleAt == null
                        ? 'Choose date'
                        : _formatDate(_value.scheduleAt!),
                    _value.scheduleAt != null,
                    _pickDate,
                  ),
                  if (widget.allowWhenOnline)
                    _choice(
                      'When online',
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
                _section('Repeat'),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final item in const <(int, String)>[
                      (0, 'Once'),
                      (86400, 'Daily'),
                      (604800, 'Weekly'),
                      (2592000, 'Monthly'),
                    ])
                      _choice(
                        item.$2,
                        _value.repeatPeriod == item.$1,
                        () => setState(
                          () => _value = _value.copyWith(repeatPeriod: item.$1),
                        ),
                      ),
                  ],
                ),
              ],
              if (widget.mediaOptions) ...[
                _section('Media'),
                _toggle(
                  icon: HeroAppIcons.alignTop,
                  title: AppStrings.t(
                    AppStringKeys.messageSendOptionsCaptionAboveMedia,
                  ),
                  value: _value.showCaptionAboveMedia,
                  onChanged: (value) => setState(
                    () =>
                        _value = _value.copyWith(showCaptionAboveMedia: value),
                  ),
                ),
                _toggle(
                  icon: HeroAppIcons.eyeSlash,
                  title: AppStrings.t(
                    AppStringKeys.messageSendOptionsHideWithSpoiler,
                  ),
                  value: _value.hasSpoiler,
                  onChanged: (value) => setState(
                    () => _value = _value.copyWith(hasSpoiler: value),
                  ),
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
                  _section('Self-destruct'),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final item in const <(int, String)>[
                        (0, 'Off'),
                        (3, '3 sec'),
                        (10, '10 sec'),
                        (30, '30 sec'),
                        (60, '1 min'),
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
                _section('Message effect'),
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
                          () => _value = _value.copyWith(
                            effectId: effect?.id ?? 0,
                          ),
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
                    _value.hasScheduling ? 'Schedule' : 'Send',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
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
              color: selected ? Colors.white : context.colors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );

  String _formatDate(DateTime value) =>
      '${value.month}/${value.day} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}
