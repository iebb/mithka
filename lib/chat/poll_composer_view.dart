//
//  poll_composer_view.dart
//
//  Telegram poll composer. The result deliberately mirrors inputMessagePoll so
//  callers can send every server-supported poll mode without rebuilding UI
//  state in the chat view model.
//

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../theme/app_theme.dart';

class PollOptionDraft {
  const PollOptionDraft({required this.text, this.mediaPath});

  final String text;
  final String? mediaPath;
}

class PollComposerResult {
  const PollComposerResult({
    required this.question,
    required this.options,
    this.description = '',
    this.pollMediaPath,
    this.isAnonymous = true,
    this.allowsMultipleAnswers = false,
    this.allowsRevoting = false,
    this.allowAddingOptions = false,
    this.shuffleOptions = false,
    this.hideResultsUntilCloses = false,
    this.isQuiz = false,
    this.correctOptionIndexes = const <int>{},
    this.explanation = '',
    this.openPeriod = 0,
  });

  final String question;
  final List<PollOptionDraft> options;
  final String description;
  final String? pollMediaPath;
  final bool isAnonymous;
  final bool allowsMultipleAnswers;
  final bool allowsRevoting;
  final bool allowAddingOptions;
  final bool shuffleOptions;
  final bool hideResultsUntilCloses;
  final bool isQuiz;
  final Set<int> correctOptionIndexes;
  final String explanation;
  final int openPeriod;
}

class PollComposerView extends StatefulWidget {
  const PollComposerView({super.key, this.maxOptions = 30});

  final int maxOptions;

  @override
  State<PollComposerView> createState() => _PollComposerViewState();
}

class _PollOptionController {
  _PollOptionController() : text = TextEditingController();

  final TextEditingController text;
  String? mediaPath;

  void dispose() => text.dispose();
}

class _PollComposerViewState extends State<PollComposerView> {
  final _question = TextEditingController();
  final _description = TextEditingController();
  final _explanation = TextEditingController();
  final List<_PollOptionController> _options = [
    _PollOptionController(),
    _PollOptionController(),
  ];
  final Set<int> _correct = <int>{};

  String? _pollMediaPath;
  bool _anonymous = true;
  bool _multiple = false;
  bool _revoting = false;
  bool _allowAdding = false;
  bool _shuffle = false;
  bool _hideResults = false;
  bool _quiz = false;
  int _openPeriod = 0;

  int get _maxOptions => widget.maxOptions.clamp(2, 100);

  @override
  void initState() {
    super.initState();
    _question.addListener(_refresh);
    for (final option in _options) {
      option.text.addListener(_refresh);
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _question.dispose();
    _description.dispose();
    _explanation.dispose();
    for (final option in _options) {
      option.dispose();
    }
    super.dispose();
  }

  List<int> get _nonEmptyIndexes => [
    for (var index = 0; index < _options.length; index++)
      if (_options[index].text.text.trim().isNotEmpty) index,
  ];

  bool get _canSend {
    final nonEmpty = _nonEmptyIndexes;
    if (_question.text.trim().isEmpty || nonEmpty.length < 2) return false;
    if (!_quiz) return true;
    return _correct.any(nonEmpty.contains);
  }

  void _addOption() {
    if (_options.length >= _maxOptions) return;
    final option = _PollOptionController();
    option.text.addListener(_refresh);
    setState(() => _options.add(option));
  }

  void _removeOption(int index) {
    if (_options.length <= 2) return;
    setState(() {
      _options.removeAt(index).dispose();
      final shifted = <int>{};
      for (final correct in _correct) {
        if (correct < index) shifted.add(correct);
        if (correct > index) shifted.add(correct - 1);
      }
      _correct
        ..clear()
        ..addAll(shifted);
    });
  }

  Future<String?> _pickMedia() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    return image?.path;
  }

  Future<void> _pickPollMedia() async {
    final path = await _pickMedia();
    if (!mounted || path == null) return;
    setState(() => _pollMediaPath = path);
  }

  Future<void> _pickOptionMedia(int index) async {
    final path = await _pickMedia();
    if (!mounted || path == null || index >= _options.length) return;
    setState(() => _options[index].mediaPath = path);
  }

  void _setQuiz(bool value) {
    setState(() {
      _quiz = value;
      if (value) {
        _multiple = false;
        _allowAdding = false;
      } else {
        _correct.clear();
      }
    });
  }

  void _toggleCorrect(int index) {
    if (!_quiz) return;
    setState(() {
      if (_correct.contains(index)) {
        _correct.remove(index);
      } else {
        _correct.add(index);
      }
    });
  }

  void _send() {
    if (!_canSend) return;
    final oldToNew = <int, int>{};
    final options = <PollOptionDraft>[];
    for (var index = 0; index < _options.length; index++) {
      final text = _options[index].text.text.trim();
      if (text.isEmpty) continue;
      oldToNew[index] = options.length;
      options.add(
        PollOptionDraft(text: text, mediaPath: _options[index].mediaPath),
      );
    }
    Navigator.of(context).pop(
      PollComposerResult(
        question: _question.text.trim(),
        description: _description.text.trim(),
        options: options,
        pollMediaPath: _pollMediaPath,
        isAnonymous: _anonymous,
        allowsMultipleAnswers: !_quiz && _multiple,
        allowsRevoting: _revoting,
        allowAddingOptions: !_quiz && _allowAdding,
        shuffleOptions: _shuffle,
        hideResultsUntilCloses: _hideResults,
        isQuiz: _quiz,
        correctOptionIndexes: {for (final index in _correct) ?oldToNew[index]},
        explanation: _quiz ? _explanation.text.trim() : '',
        openPeriod: _openPeriod,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.pollComposerCreatePollTitle),
            onBack: () => Navigator.of(context).pop(),
            trailing: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _canSend ? _send : null,
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
                    _question,
                    AppStrings.t(AppStringKeys.pollComposerQuestionRequired),
                    autofocus: true,
                    multiline: true,
                  ),
                  const InsetDivider(leadingInset: 16),
                  _field(
                    _description,
                    'Description (optional)',
                    multiline: true,
                  ),
                  const InsetDivider(leadingInset: 16),
                  _mediaRow(
                    title: _pollMediaPath == null
                        ? 'Add poll media'
                        : 'Poll media attached',
                    path: _pollMediaPath,
                    onTap: _pickPollMedia,
                    onRemove: _pollMediaPath == null
                        ? null
                        : () => setState(() => _pollMediaPath = null),
                  ),
                ]),
                const SizedBox(height: 14),
                _card([
                  for (var index = 0; index < _options.length; index++) ...[
                    if (index > 0) const InsetDivider(leadingInset: 16),
                    _optionRow(index),
                  ],
                  const InsetDivider(leadingInset: 16),
                  _addRow(),
                ]),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    AppStrings.t(AppStringKeys.pollComposerModeAndOptionLimit, {
                      'value1': AppStrings.t(
                        _quiz
                            ? AppStringKeys.pollComposerQuiz
                            : _multiple
                            ? AppStringKeys.pollComposerMultipleAnswers
                            : AppStringKeys.pollComposerSingleChoice,
                      ),
                      'value2': _maxOptions,
                    }),
                    style: TextStyle(fontSize: 13, color: c.textSecondary),
                  ),
                ),
                const SizedBox(height: 14),
                _card([
                  _toggleRow('Quiz mode', _quiz, _setQuiz),
                  const InsetDivider(leadingInset: 16),
                  _toggleRow(
                    'Multiple answers',
                    _multiple,
                    _quiz ? null : (value) => setState(() => _multiple = value),
                  ),
                  const InsetDivider(leadingInset: 16),
                  _toggleRow(
                    'Anonymous voting',
                    _anonymous,
                    (value) => setState(() {
                      _anonymous = value;
                      if (value) _allowAdding = false;
                    }),
                  ),
                  const InsetDivider(leadingInset: 16),
                  _toggleRow(
                    'Allow revoting',
                    _revoting,
                    (value) => setState(() => _revoting = value),
                  ),
                  const InsetDivider(leadingInset: 16),
                  _toggleRow(
                    'Allow people to add options',
                    _allowAdding,
                    _quiz || _anonymous
                        ? null
                        : (value) => setState(() => _allowAdding = value),
                  ),
                  const InsetDivider(leadingInset: 16),
                  _toggleRow(
                    'Shuffle options',
                    _shuffle,
                    (value) => setState(() => _shuffle = value),
                  ),
                  const InsetDivider(leadingInset: 16),
                  _toggleRow(
                    'Hide results until poll closes',
                    _hideResults,
                    (value) => setState(() => _hideResults = value),
                  ),
                  const InsetDivider(leadingInset: 16),
                  _durationRow(),
                ]),
                if (_quiz) ...[
                  const SizedBox(height: 14),
                  _card([
                    _field(
                      _explanation,
                      'Explanation shown after an incorrect answer',
                      multiline: true,
                    ),
                  ]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(List<Widget> children) => Container(
    decoration: BoxDecoration(color: context.colors.card),
    child: Column(children: children),
  );

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

  Widget _optionRow(int index) {
    final c = context.colors;
    final option = _options[index];
    final isCorrect = _correct.contains(index);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 9, 10, 9),
      child: Row(
        children: [
          if (_quiz) ...[
            GestureDetector(
              key: ValueKey('pollCorrect-$index'),
              behavior: HitTestBehavior.opaque,
              onTap: () => _toggleCorrect(index),
              child: Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isCorrect ? AppTheme.brand : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isCorrect ? AppTheme.brand : c.textTertiary,
                  ),
                ),
                child: isCorrect
                    ? const AppIcon(
                        HeroAppIcons.check,
                        size: 14,
                        color: Colors.white,
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 10),
          ],
          if (option.mediaPath != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: Image.file(
                File(option.mediaPath!),
                width: 38,
                height: 38,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: TextField(
              controller: option.text,
              maxLength: 100,
              buildCounter:
                  (
                    _, {
                    required currentLength,
                    required isFocused,
                    maxLength,
                  }) => null,
              style: TextStyle(fontSize: 16, color: c.textPrimary),
              cursorColor: AppTheme.brand,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: AppStrings.t(AppStringKeys.pollComposerOptionLabel, {
                  'value1': index + 1,
                }),
                hintStyle: TextStyle(color: c.textTertiary),
              ),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => option.mediaPath == null
                ? _pickOptionMedia(index)
                : setState(() => option.mediaPath = null),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: AppIcon(
                option.mediaPath == null
                    ? HeroAppIcons.image
                    : HeroAppIcons.circleXmark,
                size: 19,
                color: c.textSecondary,
              ),
            ),
          ),
          if (_options.length > 2)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _removeOption(index),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: AppIcon(
                  HeroAppIcons.circleMinus,
                  size: 20,
                  color: AppTheme.tagRed.withValues(alpha: 0.8),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _addRow() {
    final disabled = _options.length >= _maxOptions;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: disabled ? null : _addOption,
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
                AppStrings.t(AppStringKeys.pollComposerAddOption),
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

  Widget _toggleRow(String title, bool value, ValueChanged<bool>? onChanged) {
    final c = context.colors;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  color: onChanged == null ? c.textTertiary : c.textPrimary,
                ),
              ),
            ),
            AppSwitch(
              value: value,
              enabled: onChanged != null,
              onChanged: onChanged ?? (_) {},
            ),
          ],
        ),
      ),
    );
  }

  Widget _durationRow() {
    final c = context.colors;
    const values = <(int, String)>[
      (0, 'No timer'),
      (300, '5 minutes'),
      (3600, '1 hour'),
      (86400, '1 day'),
      (604800, '1 week'),
    ];
    final selected = values.firstWhere((value) => value.$1 == _openPeriod);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              AppStrings.t(AppStringKeys.pollComposerClosePollAutomatically),
              style: TextStyle(fontSize: 15, color: c.textPrimary),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () async {
              final value = await _showDurationPicker(values);
              if (mounted && value != null) {
                setState(() => _openPeriod = value);
              }
            },
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 11),
              decoration: BoxDecoration(
                color: c.searchFill,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.divider, width: 0.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    selected.$2,
                    style: TextStyle(fontSize: 14, color: c.textPrimary),
                  ),
                  const SizedBox(width: 7),
                  AppIcon(
                    HeroAppIcons.chevronDown,
                    size: 14,
                    color: c.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<int?> _showDurationPicker(List<(int, String)> values) =>
      showModalBottomSheet<int>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) {
          final c = sheetContext.colors;
          return SafeArea(
            top: false,
            child: Container(
              margin: const EdgeInsets.all(10),
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 20,
                    offset: Offset(0, 7),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 2, 8, 10),
                    child: Text(
                      AppStrings.t(
                        AppStringKeys.pollComposerClosePollAutomatically,
                      ),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  for (final value in values)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(sheetContext).pop(value.$1),
                      child: SizedBox(
                        height: 48,
                        child: Row(
                          children: [
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                value.$2,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: c.textPrimary,
                                ),
                              ),
                            ),
                            if (value.$1 == _openPeriod)
                              AppIcon(
                                HeroAppIcons.check,
                                size: 18,
                                color: AppTheme.brand,
                              ),
                            const SizedBox(width: 8),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      );

  Widget _mediaRow({
    required String title,
    required String? path,
    required VoidCallback onTap,
    required VoidCallback? onRemove,
  }) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            if (path != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Image.file(
                  File(path),
                  width: 38,
                  height: 38,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 10),
            ] else ...[
              AppIcon(HeroAppIcons.image, size: 20, color: AppTheme.brand),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                title,
                style: TextStyle(fontSize: 15, color: c.textPrimary),
              ),
            ),
            if (onRemove != null)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onRemove,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: AppIcon(
                    HeroAppIcons.circleXmark,
                    size: 19,
                    color: c.textTertiary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
