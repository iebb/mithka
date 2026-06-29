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

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
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
  _Option('关闭', 0),
  _Option('1 天', 86400),
  _Option('1 周', 604800),
  _Option('1 个月', 2592000),
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
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(title: '自动删除消息', onBack: () => Navigator.of(context).pop()),
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
                    padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
                    children: [
                      _card(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Text(
                          '新消息将在设定时间后自动从聊天中删除。',
                          style: TextStyle(
                            fontSize: 13,
                            color: c.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _card() {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final o in _options) ...[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _set(o.seconds),
              child: SizedBox(
                height: 52,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text(
                        o.title,
                        style: TextStyle(fontSize: 16, color: c.textPrimary),
                      ),
                      const Spacer(),
                      if (_selected == o.seconds)
                        FaIcon(
                          FontAwesomeIcons.check,
                          size: 18,
                          color: AppTheme.brand,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (o.seconds != _options.last.seconds)
              const InsetDivider(leadingInset: 16),
          ],
        ],
      ),
    );
  }
}
