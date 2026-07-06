//
//  checklist_composer_view.dart
//
//  新建清单 — a full-page custom checklist composer (no Material dialog). A title
//  card + a tasks card of borderless rows (add / remove, 1–30), with a brand 发送
//  action. Returns (title, tasks) via Navigator.pop. (Creating checklists needs
//  Telegram Premium.)
//

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../theme/app_theme.dart';

class ChecklistComposerView extends StatefulWidget {
  const ChecklistComposerView({super.key});

  @override
  State<ChecklistComposerView> createState() => _ChecklistComposerViewState();
}

class _ChecklistComposerViewState extends State<ChecklistComposerView> {
  final _title = TextEditingController();
  final List<TextEditingController> _tasks = [TextEditingController()];

  @override
  void initState() {
    super.initState();
    _title.addListener(_refresh);
    for (final t in _tasks) {
      t.addListener(_refresh);
    }
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _title.dispose();
    for (final t in _tasks) {
      t.dispose();
    }
    super.dispose();
  }

  bool get _canSend =>
      _title.text.trim().isNotEmpty &&
      _tasks.any((t) => t.text.trim().isNotEmpty);

  void _addTask() {
    if (_tasks.length >= 30) return;
    setState(() => _tasks.add(TextEditingController()..addListener(_refresh)));
  }

  void _removeTask(int i) {
    if (_tasks.length <= 1) return;
    setState(() {
      _tasks[i].dispose();
      _tasks.removeAt(i);
    });
  }

  void _send() {
    if (!_canSend) return;
    final title = _title.text.trim();
    final tasks = _tasks
        .map((t) => t.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    Navigator.of(context).pop((title, tasks));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(
              AppStringKeys.checklistComposerNewChecklistTitle,
            ),
            onBack: () => Navigator.of(context).pop(),
            trailing: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _send,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  AppStrings.t(AppStringKeys.composerSend),
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
                  _field(
                    _title,
                    AppStrings.t(AppStringKeys.checklistComposerTitleLabel),
                    autofocus: true,
                  ),
                ]),
                const SizedBox(height: 14),
                _card([
                  for (var i = 0; i < _tasks.length; i++) ...[
                    if (i > 0) const InsetDivider(leadingInset: 16),
                    _taskRow(i),
                  ],
                  const InsetDivider(leadingInset: 16),
                  _addRow(),
                ]),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    AppStrings.t(
                      AppStringKeys.checklistComposerPremiumLimitHint,
                    ),
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
  }) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: TextField(
        controller: controller,
        autofocus: autofocus,
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

  Widget _taskRow(int i) {
    final c = context.colors;
    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            AppIcon(HeroAppIcons.circle, size: 18, color: c.textTertiary),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _tasks[i],
                style: TextStyle(fontSize: 16, color: c.textPrimary),
                cursorColor: AppTheme.brand,
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: AppStrings.t(
                    AppStringKeys.checklistComposerTaskLabel,
                    {'value1': i + 1},
                  ),
                  hintStyle: TextStyle(color: c.textTertiary),
                ),
              ),
            ),
            if (_tasks.length > 1)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _removeTask(i),
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: AppIcon(
                    HeroAppIcons.circleMinus,
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
    final disabled = _tasks.length >= 30;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: disabled ? null : _addTask,
      child: SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              AppIcon(
                HeroAppIcons.plus,
                size: 18,
                color: disabled
                    ? AppTheme.brand.withValues(alpha: 0.4)
                    : AppTheme.brand,
              ),
              const SizedBox(width: 8),
              Text(
                AppStrings.t(AppStringKeys.checklistComposerAddTask),
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
