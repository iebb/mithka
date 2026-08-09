//
//  auto_delete_view.dart
//
//  自动删除消息 — the default message auto-delete timer. A pushed screen with one
//  white card of radio rows (关闭 / 1 天 / 1 周 / 1 个月); the row matching the
//  current default carries a brand checkmark. Reads via
//  getDefaultMessageAutoDeleteTime and writes via setDefaultMessageAutoDeleteTime.
//  Port of the Swift `AutoDeleteView`.
//

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../theme/app_theme.dart';

/// One radio choice: a display title and its auto-delete duration in seconds
/// (0 = off).
class _Option {
  const _Option(this.title, this.seconds);
  final String title;
  final int seconds;
}

const List<_Option> _options = [
  _Option(AppStringKeys.chatInfoAutoDeleteOff, 0),
  _Option(AppStringKeys.autoDeleteAfterOneDay, 86400),
  _Option(AppStringKeys.autoDeleteAfterOneWeek, 604800),
  _Option(AppStringKeys.autoDeleteAfterOneMonth, 2592000),
];

class AutoDeleteView extends StatefulWidget {
  const AutoDeleteView({super.key});

  @override
  State<AutoDeleteView> createState() => _AutoDeleteViewState();
}

class _AutoDeleteViewState extends State<AutoDeleteView> {
  final TdClient _client = TdClient.shared;
  int _selected = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// getDefaultMessageAutoDeleteTime → messageAutoDeleteTime{ time }. `time` may
  /// sit at the top level or nested under message_auto_delete_time; snap unknown
  /// values to 关闭.
  Future<void> _load() async {
    try {
      final res = await _client.query({
        '@type': 'getDefaultMessageAutoDeleteTime',
      });
      final seconds =
          res.integer('time') ??
          res.obj('message_auto_delete_time')?.integer('time') ??
          0;
      final known = _options.map((o) => o.seconds).contains(seconds);
      if (mounted) setState(() => _selected = known ? seconds : 0);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _set(int seconds) {
    if (seconds == _selected) return;
    setState(() => _selected = seconds);
    _client.send({
      '@type': 'setDefaultMessageAutoDeleteTime',
      'message_auto_delete_time': {
        '@type': 'messageAutoDeleteTime',
        'time': seconds,
      },
    });
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPageScaffold(
      title: AppStringKeys.chatInfoAutoDeleteMessages,
      onBack: () => Navigator.of(context).pop(),
      child: _loading
          ? const Center(child: AppActivityIndicator(size: 24))
          : SettingsListView(
              children: [
                _card(),
                SettingsNote(
                  text: AppStrings.t(AppStringKeys.autoDeleteDescription),
                ),
              ],
            ),
    );
  }

  Widget _card() {
    return SettingsCard.rows(
      dividerInset: AppMetric.settingsTextDividerInset,
      rows: [
        for (final option in _options)
          SettingsRow(
            title: option.title,
            showChevron: false,
            onTap: () => _set(option.seconds),
            trailing: _selected == option.seconds
                ? const AppIcon(HeroAppIcons.check, size: 18)
                : null,
          ),
      ],
    );
  }
}
