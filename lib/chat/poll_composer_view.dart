//
//  poll_composer_view.dart
//
//  发起投票 — a full-page custom poll composer (no Material dialog). A question
//  card + an options card of borderless rows (add / remove, 2–10), with a brand
//  发送 action in the header. Returns (question, options) via Navigator.pop.
//

import 'package:flutter/material.dart';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../components/ui_components.dart';
import '../theme/app_theme.dart';

class PollComposerView extends StatefulWidget {
  const PollComposerView({super.key});

  @override
  State<PollComposerView> createState() => _PollComposerViewState();
}

class _PollComposerViewState extends State<PollComposerView> {
  final _question = TextEditingController();
  final List<TextEditingController> _options = [
    TextEditingController(),
    TextEditingController(),
  ];

  @override
  void initState() {
    super.initState();
    _question.addListener(_refresh);
    for (final o in _options) {
      o.addListener(_refresh);
    }
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _question.dispose();
    for (final o in _options) {
      o.dispose();
    }
    super.dispose();
  }

  bool get _canSend =>
      _question.text.trim().isNotEmpty &&
      _options.where((o) => o.text.trim().isNotEmpty).length >= 2;

  void _addOption() {
    if (_options.length >= 10) return;
    setState(
      () => _options.add(TextEditingController()..addListener(_refresh)),
    );
  }

  void _removeOption(int i) {
    if (_options.length <= 2) return;
    setState(() {
      _options[i].dispose();
      _options.removeAt(i);
    });
  }

  void _send() {
    if (!_canSend) return;
    final q = _question.text.trim();
    final opts = _options
        .map((o) => o.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    Navigator.of(context).pop((q, opts));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: '发起投票',
            onBack: () => Navigator.of(context).pop(),
            trailing: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _send,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '发送',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _canSend
                        ? AppTheme.brand
                        : AppTheme.brand.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 14),
              children: [
                _card([
                  _field(_question, '请输入问题', autofocus: true, multiline: true),
                ]),
                const SizedBox(height: 14),
                _card([
                  for (var i = 0; i < _options.length; i++) ...[
                    if (i > 0) const InsetDivider(leadingInset: 16),
                    _optionRow(i),
                  ],
                  const InsetDivider(leadingInset: 16),
                  _addRow(),
                ]),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    '单选 · 最多 10 个选项',
                    style: TextStyle(fontSize: 13, color: c.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(List<Widget> children) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(color: c.card),
      child: Column(children: children),
    );
  }

  Widget _field(
    TextEditingController controller,
    String hint, {
    bool autofocus = false,
    bool multiline = false,
  }) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        maxLines: multiline ? 3 : 1,
        minLines: 1,
        style: TextStyle(fontSize: 16, color: c.textPrimary),
        cursorColor: AppTheme.brand,
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          hintText: hint,
          hintStyle: TextStyle(color: c.textTertiary),
        ),
      ),
    );
  }

  Widget _optionRow(int i) {
    final c = context.colors;
    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _options[i],
                style: TextStyle(fontSize: 16, color: c.textPrimary),
                cursorColor: AppTheme.brand,
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: '选项 ${i + 1}',
                  hintStyle: TextStyle(color: c.textTertiary),
                ),
              ),
            ),
            if (_options.length > 2)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _removeOption(i),
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: FaIcon(
                    FontAwesomeIcons.circleMinus,
                    size: 20,
                    color: AppTheme.tagRed.withValues(alpha: 0.8),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _addRow() {
    final disabled = _options.length >= 10;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: disabled ? null : _addOption,
      child: SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              FaIcon(
                FontAwesomeIcons.plus,
                size: 18,
                color: disabled
                    ? AppTheme.brand.withValues(alpha: 0.4)
                    : AppTheme.brand,
              ),
              const SizedBox(width: 8),
              Text(
                '添加选项',
                style: TextStyle(
                  fontSize: 16,
                  color: disabled
                      ? AppTheme.brand.withValues(alpha: 0.4)
                      : AppTheme.brand,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
