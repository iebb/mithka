import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../theme/app_theme.dart';
import 'custom_emoji.dart';
import 'telegram_ai_service.dart';

Widget _aiTapLabel(
  BuildContext context, {
  required String label,
  required VoidCallback? onTap,
  bool destructive = false,
}) {
  final color = destructive
      ? const Color(0xFFE34B4B)
      : onTap == null
      ? context.colors.textTertiary
      : AppTheme.brand;
  return Semantics(
    button: true,
    enabled: onTap != null,
    label: label,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  );
}

Widget _aiPrimaryButton(
  BuildContext context, {
  required String label,
  required VoidCallback? onTap,
  bool working = false,
}) => Semantics(
  button: true,
  enabled: onTap != null,
  label: label,
  child: GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: onTap == null
            ? AppTheme.brand.withValues(alpha: 0.42)
            : AppTheme.brand,
        borderRadius: BorderRadius.circular(12),
      ),
      child: working
          ? const AppActivityIndicator(size: 20, color: Colors.white)
          : Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
    ),
  ),
);

Widget _aiRow(
  BuildContext context, {
  required String title,
  String? subtitle,
  Widget? leading,
  Widget? trailing,
  VoidCallback? onTap,
  EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
}) {
  final c = context.colors;
  return Semantics(
    button: onTap != null,
    enabled: onTap != null,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            if (leading != null) ...[leading, const SizedBox(width: 11)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 10), trailing],
          ],
        ),
      ),
    ),
  );
}

Widget _aiToggleRow(
  BuildContext context, {
  required String title,
  required bool value,
  required ValueChanged<bool> onChanged,
}) => _aiRow(
  context,
  title: title,
  onTap: () => onChanged(!value),
  trailing: AnimatedContainer(
    duration: const Duration(milliseconds: 180),
    curve: Curves.easeOut,
    width: 46,
    height: 28,
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: value ? AppTheme.brand : context.colors.searchFill,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: context.colors.divider, width: 0.5),
    ),
    child: AnimatedAlign(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      alignment: value ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
      ),
    ),
  ),
);

Future<T?> _aiChoiceSheet<T>(
  BuildContext context, {
  required String title,
  required List<(T, String, String?)> choices,
  required T selected,
}) => showModalBottomSheet<T>(
  context: context,
  backgroundColor: Colors.transparent,
  builder: (sheetContext) {
    final c = sheetContext.colors;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(10),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.78,
        ),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.divider, width: 0.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 15, 16, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: choices.length,
                separatorBuilder: (_, _) =>
                    Divider(height: 1, color: c.divider),
                itemBuilder: (context, index) => KeyedSubtree(
                  key: ValueKey('aiChoice-${choices[index].$1}'),
                  child: _aiRow(
                    sheetContext,
                    title: choices[index].$2,
                    subtitle: choices[index].$3,
                    trailing: choices[index].$1 == selected
                        ? const AppIcon(HeroAppIcons.check, size: 20)
                        : null,
                    onTap: () =>
                        Navigator.of(sheetContext).pop(choices[index].$1),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  },
);

class TelegramAiEditorView extends StatefulWidget {
  const TelegramAiEditorView({
    super.key,
    required this.service,
    required this.source,
  });

  final TelegramAiService service;
  final TelegramAiFormattedText source;

  @override
  State<TelegramAiEditorView> createState() => _TelegramAiEditorViewState();
}

enum _TelegramAiMode { translate, style, fix }

class _TelegramAiEditorViewState extends State<TelegramAiEditorView> {
  static const _languages = <String, String>{
    'en': 'English',
    'ja': '日本語',
    'zh-Hans': '简体中文',
    'zh-Hant': '繁體中文',
    'ko': '한국어',
    'de': 'Deutsch',
    'es': 'Español',
    'fr': 'Français',
  };

  _TelegramAiMode _mode = _TelegramAiMode.style;
  bool _addEmojis = false;
  String _language = '';
  String _style = '';
  bool _working = false;
  TelegramAiFormattedText? _result;

  bool get _canGenerate => switch (_mode) {
    _TelegramAiMode.translate => _language.isNotEmpty,
    _TelegramAiMode.style => _style.isNotEmpty || _addEmojis,
    _TelegramAiMode.fix => true,
  };

  void _changeMode(_TelegramAiMode mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      _result = null;
    });
  }

  Future<void> _generate() async {
    if (_working || !_canGenerate) return;
    if (widget.service.capabilitiesSnapshot?.compositionSupported != true) {
      showToast(
        context,
        AppStrings.t(
          AppStringKeys
              .telegramAiEditorTelegramAIEditorIsUnavailableForThisAccount,
        ),
      );
      return;
    }
    setState(() => _working = true);
    try {
      final result = await widget.service.compose(
        text: widget.source,
        proofread: _mode == _TelegramAiMode.fix,
        translateToLanguageCode: _mode == _TelegramAiMode.translate
            ? _language
            : '',
        styleName: _mode == _TelegramAiMode.style ? _style : '',
        addEmojis: _mode != _TelegramAiMode.fix && _addEmojis,
      );
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.telegramAiEditorRewriteTitle),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: AnimatedBuilder(
              animation: widget.service,
              builder: (context, _) => ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
                children: [
                  _modePicker(),
                  if (_mode != _TelegramAiMode.fix) ...[
                    const SizedBox(height: 12),
                    _modeOptions(),
                  ],
                  const SizedBox(height: 12),
                  _previewCard(),
                  const SizedBox(height: 14),
                  _aiPrimaryButton(
                    context,
                    label: _primaryLabel,
                    onTap: _working
                        ? null
                        : _result != null
                        ? () => Navigator.of(context).pop(_result)
                        : _canGenerate
                        ? _generate
                        : null,
                    working: _working,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String get _primaryLabel {
    if (_result != null) {
      return AppStrings.t(AppStringKeys.composerFormatApply);
    }
    return switch (_mode) {
      _TelegramAiMode.translate => AppStrings.t(
        AppStringKeys.telegramAiEditorTranslate,
      ),
      _TelegramAiMode.style => AppStrings.t(
        _canGenerate
            ? AppStringKeys.telegramAiEditorRewrite
            : AppStringKeys.telegramAiEditorSelectStyle,
      ),
      _TelegramAiMode.fix => AppStrings.t(AppStringKeys.telegramAiEditorFix),
    };
  }

  Widget _previewCard() {
    final c = context.colors;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _previewSection(
            AppStrings.t(AppStringKeys.telegramAiEditorOriginal),
            widget.source.text,
            trailing: _mode == _TelegramAiMode.style
                ? _inlineEmojiToggle()
                : null,
          ),
          if (_result != null) ...[
            Divider(height: 1, color: c.divider),
            _previewSection(
              _mode == _TelegramAiMode.translate && _language.isNotEmpty
                  ? AppStrings.t(AppStringKeys.telegramAiEditorToLanguage, {
                      'value1': _languages[_language] ?? _language,
                    })
                  : AppStrings.t(AppStringKeys.telegramAiEditorResult),
              _result!.text,
            ),
          ],
        ],
      ),
    );
  }

  Widget _previewSection(String label, String value, {Widget? trailing}) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: c.textSecondary,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 7),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 156),
            child: SingleChildScrollView(
              child: SelectableText(
                value,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.38,
                  color: c.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _inlineEmojiToggle() {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: _addEmojis,
      child: GestureDetector(
        key: const ValueKey('telegramAiEmojify'),
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() {
          _addEmojis = !_addEmojis;
          _result = null;
        }),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 2, 0, 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                _addEmojis ? HeroAppIcons.circleCheck : HeroAppIcons.circle,
                size: 18,
                color: _addEmojis ? AppTheme.brand : c.textTertiary,
              ),
              const SizedBox(width: 5),
              Text(
                AppStrings.t(AppStringKeys.telegramAiEditorAddEmoji),
                style: TextStyle(
                  color: _addEmojis ? AppTheme.brand : c.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modePicker() {
    final c = context.colors;
    return Container(
      height: 72,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.textPrimary.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          _modeItem(
            _TelegramAiMode.translate,
            AppStrings.t(AppStringKeys.telegramAiEditorTranslate),
            HeroAppIcons.language,
          ),
          _modeItem(
            _TelegramAiMode.style,
            AppStrings.t(AppStringKeys.telegramAiEditorStyle),
            HeroAppIcons.wandMagicSparkles,
          ),
          _modeItem(
            _TelegramAiMode.fix,
            AppStrings.t(AppStringKeys.telegramAiEditorFix),
            HeroAppIcons.circleCheck,
          ),
        ],
      ),
    );
  }

  Widget _modeItem(_TelegramAiMode mode, String label, AppIconData icon) {
    final c = context.colors;
    final selected = _mode == mode;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        child: GestureDetector(
          key: ValueKey('telegramAiMode-${mode.name}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => _changeMode(mode),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? AppTheme.brand.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppIcon(
                  icon,
                  size: 21,
                  color: selected ? AppTheme.brand : c.textSecondary,
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? AppTheme.brand : c.textSecondary,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _modeOptions() => switch (_mode) {
    _TelegramAiMode.translate => _translationOptions(),
    _TelegramAiMode.style => _styleOptions(),
    _TelegramAiMode.fix => const SizedBox.shrink(),
  };

  Widget _translationOptions() {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.divider, width: 0.5),
      ),
      child: Column(
        children: [
          _aiRow(
            context,
            title: AppStrings.t(AppStringKeys.telegramAiEditorChooseLanguage),
            subtitle: _languages[_language],
            trailing: const AppIcon(HeroAppIcons.chevronRight, size: 18),
            onTap: _chooseLanguage,
          ),
          Divider(height: 1, color: c.divider),
          _aiToggleRow(
            context,
            title: AppStrings.t(AppStringKeys.telegramAiEditorAddEmoji),
            value: _addEmojis,
            onChanged: (value) => setState(() {
              _addEmojis = value;
              _result = null;
            }),
          ),
        ],
      ),
    );
  }

  Widget _styleOptions() {
    final c = context.colors;
    final styles = widget.service.styles;
    final supportsCustomStyles =
        widget.service.capabilitiesSnapshot?.customStylesSupported == true;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.t(AppStringKeys.telegramAiEditorWritingStyle),
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 11),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                if (supportsCustomStyles) ...[
                  _styleChip(
                    key: const ValueKey('telegramAiAddStyle'),
                    label: AppStrings.t(AppStringKeys.imageEditAdd),
                    selected: false,
                    showAdd: true,
                    onTap: _addStyle,
                  ),
                  const SizedBox(width: 8),
                ],
                for (final style in styles) ...[
                  _styleChip(
                    key: ValueKey('telegramAiStyle-${style.name}'),
                    label: style.title,
                    selected: _style == style.name,
                    leading: _styleIcon(style, selected: _style == style.name),
                    onTap: () => setState(() {
                      _style = _style == style.name ? '' : style.name;
                      _result = null;
                    }),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _styleChip({
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
    Widget? leading,
    bool showAdd = false,
  }) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        key: key,
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 36,
          padding: EdgeInsets.symmetric(horizontal: showAdd ? 11 : 13),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.brand.withValues(alpha: 0.12)
                : c.searchFill,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? AppTheme.brand.withValues(alpha: 0.60)
                  : c.divider,
              width: selected ? 1 : 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showAdd) ...[
                AppIcon(HeroAppIcons.plus, size: 15, color: AppTheme.brand),
                const SizedBox(width: 5),
              ] else if (leading != null) ...[
                leading,
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: selected ? AppTheme.brand : c.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _styleIcon(TelegramAiStyle style, {required bool selected}) {
    final color = selected ? AppTheme.brand : context.colors.textSecondary;
    return KeyedSubtree(
      key: ValueKey('telegramAiStyleIcon-${style.name}'),
      child: style.customEmojiId != 0
          ? CustomEmojiView(id: style.customEmojiId, size: 19, color: color)
          : AppIcon(HeroAppIcons.wandMagicSparkles, size: 17, color: color),
    );
  }

  Future<void> _chooseLanguage() async {
    final value = await _aiChoiceSheet<String>(
      context,
      title: AppStrings.t(AppStringKeys.telegramAiEditorChooseLanguage),
      choices: [
        for (final entry in _languages.entries) (entry.key, entry.value, null),
      ],
      selected: _language,
    );
    if (value != null && mounted) {
      setState(() {
        _language = value;
        _result = null;
      });
    }
  }

  Future<void> _addStyle() async {
    final added = await Navigator.of(context).push<TelegramAiStyle>(
      MaterialPageRoute(
        builder: (_) =>
            TelegramAiStylesView(service: widget.service, pickOnAdd: true),
      ),
    );
    if (added != null && mounted) {
      setState(() {
        _style = added.name;
        _result = null;
      });
    }
  }
}

class TelegramAiStylesView extends StatefulWidget {
  const TelegramAiStylesView({
    super.key,
    required this.service,
    this.pickOnAdd = false,
  });

  final TelegramAiService service;
  final bool pickOnAdd;

  @override
  State<TelegramAiStylesView> createState() => _TelegramAiStylesViewState();
}

class _TelegramAiStylesViewState extends State<TelegramAiStylesView> {
  final _search = TextEditingController();
  bool _working = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _createOrEdit([TelegramAiStyle? style]) async {
    final title = TextEditingController(text: style?.title ?? '');
    final prompt = TextEditingController(text: style?.prompt ?? '');
    var showCreator = style?.isCreator ?? false;
    final result = await showModalBottomSheet<(String, String, bool)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final c = context.colors;
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SafeArea(
              top: false,
              child: Container(
                margin: const EdgeInsets.all(10),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: c.divider, width: 0.5),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppStrings.t(
                          style == null
                              ? AppStringKeys.telegramAiEditorCreateStyle
                              : AppStringKeys.telegramAiEditorEditStyle,
                        ),
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: title,
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: AppStrings.t(
                            AppStringKeys.businessSettingsStartPageTitle,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: prompt,
                        minLines: 3,
                        maxLines: 8,
                        decoration: InputDecoration(
                          labelText: AppStrings.t(
                            AppStringKeys.telegramAiEditorStylePrompt,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _aiToggleRow(
                        context,
                        title: AppStrings.t(
                          AppStringKeys.telegramAiEditorShowMeAsCreator,
                        ),
                        value: showCreator,
                        onChanged: (value) =>
                            setSheetState(() => showCreator = value),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          _aiTapLabel(
                            context,
                            label: AppStrings.t(AppStringKeys.confirmCancel),
                            onTap: () => Navigator.of(sheetContext).pop(),
                          ),
                          const SizedBox(width: 6),
                          _aiTapLabel(
                            context,
                            label: AppStrings.t(
                              AppStringKeys.accentColorPickerSave,
                            ),
                            onTap: () => Navigator.of(sheetContext).pop((
                              title.text.trim(),
                              prompt.text.trim(),
                              showCreator,
                            )),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    title.dispose();
    prompt.dispose();
    if (result == null || result.$1.isEmpty || result.$2.isEmpty || !mounted) {
      return;
    }
    TelegramAiStyle? saved;
    await _run(() async {
      if (style == null) {
        saved = await widget.service.createStyle(
          title: result.$1,
          prompt: result.$2,
          showCreator: result.$3,
        );
      } else {
        saved = await widget.service.editStyle(
          name: style.name,
          title: result.$1,
          prompt: result.$2,
          customEmojiId: style.customEmojiId,
          showCreator: result.$3,
        );
      }
    });
    if (saved != null && mounted && widget.pickOnAdd) {
      Navigator.of(context).pop(saved);
    }
  }

  Future<void> _install() async {
    final name = _search.text.trim();
    if (name.isEmpty) return;
    TelegramAiStyle? installed;
    await _run(() async {
      final style = await widget.service.searchStyle(name);
      await widget.service.addStyle(style.name, style: style);
      installed = style;
      _search.clear();
    });
    if (installed != null && mounted && widget.pickOnAdd) {
      Navigator.of(context).pop(installed);
    }
  }

  Future<void> _delete(TelegramAiStyle style) async {
    final confirmed = await _aiChoiceSheet<bool>(
      context,
      title: AppStrings.t(AppStringKeys.passkeysDeleteMessage, {
        'value1': style.title,
      }),
      choices: [
        (false, AppStrings.t(AppStringKeys.telegramAiEditorKeepStyle), null),
        (
          true,
          AppStrings.t(AppStringKeys.telegramAiEditorDeleteStyle),
          AppStrings.t(AppStringKeys.telegramAiEditorCannotBeUndone),
        ),
      ],
      selected: false,
    );
    if (confirmed != true || !mounted) return;
    await _run(
      () => style.isCreator
          ? widget.service.deleteStyle(style.name)
          : widget.service.removeStyle(style.name),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await action();
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.telegramAiEditorAIWritingStyles),
            onBack: () => Navigator.of(context).pop(),
            trailing: _aiTapLabel(
              context,
              label: AppStrings.t(AppStringKeys.chatInfoCreate),
              onTap: _working ? null : _createOrEdit,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: AppStrings.t(
                        AppStringKeys.telegramAiEditorPasteAStyleNameFromALink,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _aiTapLabel(
                  context,
                  label: AppStrings.t(AppStringKeys.imageEditAdd),
                  onTap: _working ? null : _install,
                ),
              ],
            ),
          ),
          Expanded(
            child: AnimatedBuilder(
              animation: widget.service,
              builder: (context, _) {
                final styles = widget.service.styles;
                if (styles.isEmpty) {
                  return Center(
                    child: Text(
                      AppStrings.t(
                        AppStringKeys
                            .telegramAiEditorNoAIWritingStylesAreCurrentlyAvailable,
                      ),
                      style: TextStyle(color: c.textSecondary),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  itemCount: styles.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final style = styles[index];
                    return Container(
                      decoration: BoxDecoration(
                        color: c.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: c.divider, width: 0.5),
                      ),
                      child: _aiRow(
                        context,
                        title: style.title,
                        subtitle: style.prompt.isEmpty
                            ? style.isCustom
                                  ? AppStrings.t(
                                      AppStringKeys.telegramAiEditorCustomStyle,
                                    )
                                  : AppStrings.t(
                                      AppStringKeys
                                          .telegramAiEditorTelegramStyle,
                                    )
                            : style.prompt,
                        onTap: widget.pickOnAdd
                            ? () => Navigator.of(context).pop(style)
                            : style.isCreator
                            ? () => _createOrEdit(style)
                            : null,
                        trailing: style.isCustom && !widget.pickOnAdd
                            ? GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: _working ? null : () => _delete(style),
                                child: const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: AppIcon(HeroAppIcons.trash, size: 19),
                                ),
                              )
                            : null,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
