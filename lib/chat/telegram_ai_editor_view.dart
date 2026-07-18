import 'dart:async';

import 'package:flutter/material.dart';

import '../components/app_icons.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../theme/app_theme.dart';
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
            for (var index = 0; index < choices.length; index++) ...[
              if (index > 0) Divider(height: 1, color: c.divider),
              _aiRow(
                sheetContext,
                title: choices[index].$2,
                subtitle: choices[index].$3,
                trailing: choices[index].$1 == selected
                    ? const AppIcon(HeroAppIcons.check, size: 20)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(choices[index].$1),
              ),
            ],
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

class _TelegramAiEditorViewState extends State<TelegramAiEditorView> {
  static const _languages = <String, String>{
    '': 'Keep language',
    'en': 'English',
    'ja': 'Japanese',
    'zh-Hans': 'Simplified Chinese',
    'zh-Hant': 'Traditional Chinese',
    'ko': 'Korean',
    'de': 'German',
    'es': 'Spanish',
    'fr': 'French',
  };

  bool _proofread = true;
  bool _addEmojis = false;
  String _language = '';
  String _style = '';
  bool _working = false;
  TelegramAiFormattedText? _result;

  Future<void> _generate() async {
    if (_working) return;
    if (widget.service.capabilitiesSnapshot?.compositionSupported != true) {
      showToast(context, 'Telegram AI Editor is unavailable for this account.');
      return;
    }
    setState(() => _working = true);
    try {
      final result = await widget.service.compose(
        text: widget.source,
        proofread: _proofread,
        translateToLanguageCode: _language,
        styleName: _style,
        addEmojis: _addEmojis,
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
            title: 'Telegram AI Editor',
            onBack: () => Navigator.of(context).pop(),
            trailing: _aiTapLabel(
              context,
              label: 'Apply',
              onTap: _result == null
                  ? null
                  : () => Navigator.of(context).pop(_result),
            ),
          ),
          Expanded(
            child: AnimatedBuilder(
              animation: widget.service,
              builder: (context, _) => ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
                children: [
                  _textCard('Original', widget.source.text),
                  const SizedBox(height: 12),
                  _settingsCard(),
                  const SizedBox(height: 12),
                  if (_result != null) _textCard('Result', _result!.text),
                  if (_result != null) const SizedBox(height: 12),
                  _aiPrimaryButton(
                    context,
                    label: 'Generate privately with Telegram',
                    onTap: _working ? null : _generate,
                    working: _working,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Telegram processes AI Editor requests through Cocoon. '
                    'The AI action is unavailable in Secret Chats and Telegram '
                    'may require Premium after the free allowance.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: c.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _textCard(String title, String value) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: c.textSecondary,
            ),
          ),
          const SizedBox(height: 7),
          SelectableText(
            value,
            style: TextStyle(fontSize: 15, height: 1.38, color: c.textPrimary),
          ),
        ],
      ),
    );
  }

  Widget _settingsCard() {
    final c = context.colors;
    final styles = widget.service.styles;
    final supportsCustomStyles =
        widget.service.capabilitiesSnapshot?.customStylesSupported == true;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.divider, width: 0.5),
      ),
      child: Column(
        children: [
          _aiToggleRow(
            context,
            title: 'Proofread and fix mistakes',
            value: _proofread,
            onChanged: (value) => setState(() => _proofread = value),
          ),
          Divider(height: 1, color: c.divider),
          _aiToggleRow(
            context,
            title: 'Add emoji',
            value: _addEmojis,
            onChanged: (value) => setState(() => _addEmojis = value),
          ),
          Divider(height: 1, color: c.divider),
          _aiRow(
            context,
            title: 'Translate',
            subtitle: _languages[_language],
            trailing: const AppIcon(HeroAppIcons.chevronRight, size: 18),
            onTap: _chooseLanguage,
          ),
          Divider(height: 1, color: c.divider),
          _aiRow(
            context,
            title: 'Writing style',
            subtitle: _style.isEmpty
                ? 'Keep current style'
                : styles
                          .where((item) => item.name == _style)
                          .map((item) => item.title)
                          .firstOrNull ??
                      _style,
            trailing: const AppIcon(HeroAppIcons.chevronRight, size: 18),
            onTap: () => _chooseStyle(styles),
          ),
          if (supportsCustomStyles) ...[
            Divider(height: 1, color: c.divider),
            _aiRow(
              context,
              leading: const AppIcon(HeroAppIcons.wandMagicSparkles, size: 20),
              title: 'Manage custom styles',
              trailing: const AppIcon(HeroAppIcons.chevronRight, size: 18),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => TelegramAiStylesView(service: widget.service),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _chooseLanguage() async {
    final value = await _aiChoiceSheet<String>(
      context,
      title: 'Translate',
      choices: [
        for (final entry in _languages.entries) (entry.key, entry.value, null),
      ],
      selected: _language,
    );
    if (value != null && mounted) setState(() => _language = value);
  }

  Future<void> _chooseStyle(List<TelegramAiStyle> styles) async {
    final value = await _aiChoiceSheet<String>(
      context,
      title: 'Writing style',
      choices: [
        ('', 'Keep current style', null),
        for (final style in styles)
          (style.name, style.title, style.prompt.isEmpty ? null : style.prompt),
      ],
      selected: _style,
    );
    if (value != null && mounted) setState(() => _style = value);
  }
}

class TelegramAiStylesView extends StatefulWidget {
  const TelegramAiStylesView({super.key, required this.service});

  final TelegramAiService service;

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
                        style == null ? 'Create AI style' : 'Edit AI style',
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
                        decoration: const InputDecoration(labelText: 'Title'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: prompt,
                        minLines: 3,
                        maxLines: 8,
                        decoration: const InputDecoration(
                          labelText: 'Style prompt',
                        ),
                      ),
                      const SizedBox(height: 8),
                      _aiToggleRow(
                        context,
                        title: 'Show me as creator',
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
                            label: 'Cancel',
                            onTap: () => Navigator.of(sheetContext).pop(),
                          ),
                          const SizedBox(width: 6),
                          _aiTapLabel(
                            context,
                            label: 'Save',
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
    await _run(() async {
      if (style == null) {
        final created = await widget.service.createStyle(
          title: result.$1,
          prompt: result.$2,
          showCreator: result.$3,
        );
        await widget.service.addStyle(created.name);
      } else {
        await widget.service.editStyle(
          name: style.name,
          title: result.$1,
          prompt: result.$2,
          customEmojiId: style.customEmojiId,
          showCreator: result.$3,
        );
      }
    });
  }

  Future<void> _install() async {
    final name = _search.text.trim();
    if (name.isEmpty) return;
    await _run(() async {
      final style = await widget.service.searchStyle(name);
      await widget.service.addStyle(style.name);
      _search.clear();
    });
  }

  Future<void> _delete(TelegramAiStyle style) async {
    final confirmed = await _aiChoiceSheet<bool>(
      context,
      title: 'Delete “${style.title}”?',
      choices: const [
        (false, 'Keep style', null),
        (true, 'Delete style', 'This cannot be undone.'),
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
            title: 'AI Writing Styles',
            onBack: () => Navigator.of(context).pop(),
            trailing: _aiTapLabel(
              context,
              label: 'Create',
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
                    decoration: const InputDecoration(
                      hintText: 'Paste a style name from a link',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _aiTapLabel(
                  context,
                  label: 'Add',
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
                      'No AI writing styles are currently available.',
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
                                  ? 'Custom style'
                                  : 'Telegram style'
                            : style.prompt,
                        onTap: style.isCreator
                            ? () => _createOrEdit(style)
                            : null,
                        trailing: style.isCustom
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
