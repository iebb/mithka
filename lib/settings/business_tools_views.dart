import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../chat/chat_picker_view.dart';
import '../chat/sticker_item.dart';
import '../chat/sticker_preview.dart';
import '../chat/sticker_store.dart';
import '../components/app_icons.dart';
import '../components/confirm_dialog.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import 'business_service.dart';

Future<T?> _businessChoiceSheet<T>(
  BuildContext context, {
  required String title,
  required T selected,
  required List<(T, String)> choices,
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
        ),
        clipBehavior: Clip.antiAlias,
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
              SettingsRow(
                title: choices[index].$2,
                showChevron: false,
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

Widget _businessChoiceRow(
  BuildContext context, {
  required String label,
  required VoidCallback onTap,
}) => GestureDetector(
  behavior: HitTestBehavior.opaque,
  onTap: onTap,
  child: SizedBox(
    height: 52,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: context.colors.textPrimary, fontSize: 15),
            ),
          ),
          AppIcon(
            HeroAppIcons.chevronDown,
            size: 15,
            color: context.colors.textTertiary,
          ),
        ],
      ),
    ),
  ),
);

class BusinessQuickRepliesView extends StatefulWidget {
  const BusinessQuickRepliesView({super.key});

  @override
  State<BusinessQuickRepliesView> createState() =>
      _BusinessQuickRepliesViewState();
}

class BusinessIntroStickerPickerView extends StatefulWidget {
  const BusinessIntroStickerPickerView({super.key});

  @override
  State<BusinessIntroStickerPickerView> createState() =>
      _BusinessIntroStickerPickerViewState();
}

class _BusinessIntroStickerPickerViewState
    extends State<BusinessIntroStickerPickerView> {
  final StickerStore _store = StickerStore.shared;
  int _activePackId = StickerStore.recentPackId;

  @override
  void initState() {
    super.initState();
    _store.addListener(_changed);
    _store.loadIfNeeded();
  }

  @override
  void dispose() {
    _store.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    if (!_store.packs.any((pack) => pack.id == _activePackId) &&
        _store.packs.isNotEmpty) {
      _activePackId = _store.packs.first.id;
    }
    setState(() {});
  }

  void _selectPack(StickerPack pack) {
    setState(() => _activePackId = pack.id);
    if (!pack.loaded) unawaited(_store.loadPack(pack.id));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    StickerPack? active;
    for (final pack in _store.packs) {
      if (pack.id == _activePackId) active = pack;
    }
    final stickers = active?.stickers ?? const <StickerItem>[];
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: 'Greeting Sticker',
            onBack: () => Navigator.of(context).pop(),
          ),
          if (_store.packs.isNotEmpty)
            SizedBox(
              height: 58,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                itemCount: _store.packs.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, index) {
                  final pack = _store.packs[index];
                  final selected = pack.id == _activePackId;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _selectPack(pack),
                    child: Container(
                      width: 42,
                      height: 42,
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppTheme.brand.withValues(alpha: 0.14)
                            : c.card,
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                          color: selected ? AppTheme.brand : c.divider,
                          width: 0.5,
                        ),
                      ),
                      child: pack.cover == null
                          ? AppIcon(
                              HeroAppIcons.clock,
                              size: 18,
                              color: c.textSecondary,
                            )
                          : StickerTabPreview(item: pack.cover!),
                    ),
                  );
                },
              ),
            ),
          Expanded(
            child: _store.loading || (active != null && !active.loaded)
                ? const Center(child: AppActivityIndicator(size: 24))
                : stickers.isEmpty
                ? _emptyState(
                    context,
                    title: 'No stickers in this set',
                    detail: 'Choose another installed sticker set.',
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                        ),
                    itemCount: stickers.length,
                    itemBuilder: (_, index) {
                      final sticker = stickers[index];
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => Navigator.of(context).pop(sticker),
                        child: StickerPreview(item: sticker),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _BusinessQuickRepliesViewState extends State<BusinessQuickRepliesView> {
  final BusinessQuickReplyService _service = BusinessQuickReplyService.shared;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _service.addListener(_changed);
    unawaited(_load());
  }

  @override
  void dispose() {
    _service.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      await _service.loadShortcuts();
    } catch (error) {
      if (mounted) showToast(context, 'Could not load quick replies: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit(BusinessQuickReplyShortcut? shortcut) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => BusinessQuickReplyEditorView(shortcut: shortcut),
      ),
    );
    await _load();
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final items = [..._service.shortcuts];
    final item = items.removeAt(oldIndex);
    items.insert(newIndex, item);
    setState(() {});
    try {
      await _service.reorder([for (final value in items) value.id]);
      await _load();
    } catch (error) {
      if (mounted) {
        showToast(context, 'Could not reorder quick replies: $error');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shortcuts = _service.shortcuts;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: 'Quick Replies',
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
                ? const Center(child: AppActivityIndicator(size: 24))
                : shortcuts.isEmpty
                ? _emptyState(
                    context,
                    title: 'No quick replies',
                    detail:
                        'Create reusable replies, then send them from any private chat.',
                    onTap: () => _edit(null),
                    action: 'Create Quick Reply',
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
                    buildDefaultDragHandles: false,
                    itemCount: shortcuts.length,
                    onReorderItem: _reorder,
                    itemBuilder: (context, index) {
                      final shortcut = shortcuts[index];
                      return Padding(
                        key: ValueKey('quick-reply-${shortcut.id}'),
                        padding: const EdgeInsets.only(bottom: 9),
                        child: _surface(
                          context,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _edit(shortcut),
                            child: SizedBox(
                              height: 68,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                child: Row(
                                  children: [
                                    AppIcon(
                                      HeroAppIcons.message,
                                      size: 20,
                                      color: AppTheme.brand,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '/${shortcut.name}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: c.textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            shortcut.preview.isEmpty
                                                ? '${shortcut.messageCount} messages'
                                                : shortcut.preview,
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
                                    ReorderableDragStartListener(
                                      index: index,
                                      child: Padding(
                                        padding: const EdgeInsets.all(10),
                                        child: AppIcon(
                                          HeroAppIcons.grip,
                                          size: 19,
                                          color: c.textTertiary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
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

class BusinessQuickReplyEditorView extends StatefulWidget {
  const BusinessQuickReplyEditorView({super.key, this.shortcut});

  final BusinessQuickReplyShortcut? shortcut;

  @override
  State<BusinessQuickReplyEditorView> createState() =>
      _BusinessQuickReplyEditorViewState();
}

class _BusinessQuickReplyEditorViewState
    extends State<BusinessQuickReplyEditorView> {
  final BusinessQuickReplyService _service = BusinessQuickReplyService.shared;
  late final TextEditingController _name = TextEditingController(
    text: widget.shortcut?.name ?? '',
  );
  final TextEditingController _firstMessage = TextEditingController();
  bool _loading = false;
  bool _saving = false;
  List<BusinessQuickReplyMessage> _messages = const [];

  @override
  void initState() {
    super.initState();
    if (widget.shortcut != null) unawaited(_loadMessages());
  }

  @override
  void dispose() {
    _name.dispose();
    _firstMessage.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    setState(() => _loading = true);
    try {
      final values = await _service.loadMessages(widget.shortcut!.id);
      if (mounted) setState(() => _messages = values);
    } catch (error) {
      if (mounted) showToast(context, 'Could not load messages: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    final first = _firstMessage.text.trim();
    if (name.isEmpty || (widget.shortcut == null && first.isEmpty)) {
      showToast(context, 'Enter a shortcut name and message');
      return;
    }
    setState(() => _saving = true);
    try {
      await _service.checkName(name);
      if (widget.shortcut == null) {
        await _service.addText(shortcutName: name, text: first);
      } else if (name != widget.shortcut!.name) {
        await _service.rename(widget.shortcut!.id, name);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) showToast(context, 'Could not save quick reply: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addMessage() async {
    final shortcut = widget.shortcut;
    if (shortcut == null) return;
    final currentName = _name.text.trim();
    if (currentName.isEmpty) {
      showToast(context, 'Enter a shortcut name first');
      return;
    }
    final text = await _textEditor(title: 'Add Message');
    if (text == null || text.trim().isEmpty) return;
    try {
      if (currentName != shortcut.name) {
        await _service.checkName(currentName);
        await _service.rename(shortcut.id, currentName);
      }
      await _service.addText(shortcutName: currentName, text: text.trim());
      await _loadMessages();
    } catch (error) {
      if (mounted) showToast(context, 'Could not add message: $error');
    }
  }

  Future<void> _editMessage(BusinessQuickReplyMessage message) async {
    if (!message.canBeEdited) return;
    if (message.contentType != 'messageText') {
      showToast(
        context,
        'This media reply keeps its original media type. Replace it from a media composer.',
      );
      return;
    }
    final text = await _textEditor(
      title: 'Edit Message',
      initial: message.preview,
    );
    if (text == null || text.trim().isEmpty) return;
    try {
      await _service.editText(
        shortcutId: widget.shortcut!.id,
        messageId: message.id,
        text: text.trim(),
      );
      await _loadMessages();
    } catch (error) {
      if (mounted) showToast(context, 'Could not edit message: $error');
    }
  }

  Future<void> _deleteMessage(BusinessQuickReplyMessage message) async {
    final confirmed = await confirmDialog(
      context,
      title: 'Delete Message?',
      message: 'This message will be removed from the quick reply.',
      confirmText: AppStringKeys.chatDelete,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await _service.deleteMessages(widget.shortcut!.id, [message.id]);
      await _loadMessages();
    } catch (error) {
      if (mounted) showToast(context, 'Could not delete message: $error');
    }
  }

  Future<void> _deleteShortcut() async {
    final shortcut = widget.shortcut;
    if (shortcut == null) return;
    final confirmed = await confirmDialog(
      context,
      title: 'Delete Quick Reply?',
      message: '/${shortcut.name} and all of its messages will be deleted.',
      confirmText: AppStringKeys.chatDelete,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await _service.deleteShortcut(shortcut.id);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) showToast(context, 'Could not delete quick reply: $error');
    }
  }

  Future<String?> _textEditor({required String title, String initial = ''}) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => _BusinessTextEditorView(
          title: title,
          initial: initial,
          maxLength: 4096,
          minLines: 5,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final existing = widget.shortcut != null;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: existing ? 'Edit Quick Reply' : 'New Quick Reply',
            onBack: () => Navigator.of(context).pop(),
            trailing: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _saving ? null : _save,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                child: _saving
                    ? const AppActivityIndicator(size: 18)
                    : Text(
                        AppStrings.t(AppStringKeys.addMembersDone),
                        style: TextStyle(fontSize: 16, color: AppTheme.brand),
                      ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 18, 12, 24),
              children: [
                _label(context, 'Shortcut'),
                _surface(
                  context,
                  child: CupertinoTextField(
                    controller: _name,
                    prefix: Padding(
                      padding: const EdgeInsets.only(left: 14),
                      child: Text(
                        '/',
                        style: TextStyle(fontSize: 16, color: c.textSecondary),
                      ),
                    ),
                    maxLength: 32,
                    placeholder: 'shortcut',
                    padding: const EdgeInsets.all(14),
                    style: TextStyle(fontSize: 16, color: c.textPrimary),
                    placeholderStyle: TextStyle(color: c.textTertiary),
                    decoration: const BoxDecoration(),
                  ),
                ),
                if (!existing) ...[
                  const SizedBox(height: 16),
                  _label(context, 'Message'),
                  _surface(
                    context,
                    child: CupertinoTextField(
                      controller: _firstMessage,
                      maxLength: 4096,
                      minLines: 5,
                      maxLines: 10,
                      placeholder: 'Reusable response',
                      padding: const EdgeInsets.all(14),
                      style: TextStyle(fontSize: 16, color: c.textPrimary),
                      placeholderStyle: TextStyle(color: c.textTertiary),
                      decoration: const BoxDecoration(),
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(child: _label(context, 'Messages')),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _addMessage,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 4, 4, 8),
                          child: Text(
                            'Add Message',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppTheme.brand,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: AppActivityIndicator(size: 22)),
                    )
                  else
                    _surface(
                      context,
                      child: Column(
                        children: [
                          for (
                            var index = 0;
                            index < _messages.length;
                            index++
                          ) ...[
                            _messageRow(_messages[index]),
                            if (index < _messages.length - 1)
                              const InsetDivider(leadingInset: 14),
                          ],
                        ],
                      ),
                    ),
                  const SizedBox(height: 22),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _deleteShortcut,
                    child: Center(
                      child: Text(
                        'Delete Quick Reply',
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

  Widget _messageRow(BusinessQuickReplyMessage message) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _editMessage(message),
      onLongPress: () => _deleteMessage(message),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.preview,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, color: c.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message.contentType.replaceFirst('message', ''),
                    style: TextStyle(fontSize: 12, color: c.textSecondary),
                  ),
                ],
              ),
            ),
            AppIcon(
              message.canBeEdited
                  ? HeroAppIcons.penToSquare
                  : HeroAppIcons.lock,
              size: 17,
              color: c.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

/// Chat-surface picker. Selecting a shortcut sends every message in it using
/// TDLib's atomic `sendQuickReplyShortcutMessages` request.
class BusinessQuickReplyPickerView extends StatefulWidget {
  const BusinessQuickReplyPickerView({
    super.key,
    required this.chatId,
    this.chatTitle = '',
  });

  final int chatId;
  final String chatTitle;

  @override
  State<BusinessQuickReplyPickerView> createState() =>
      _BusinessQuickReplyPickerViewState();
}

class _BusinessQuickReplyPickerViewState
    extends State<BusinessQuickReplyPickerView> {
  final BusinessQuickReplyService _service = BusinessQuickReplyService.shared;
  bool _loading = true;
  int? _sendingId;
  String _unavailableReason = '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final capabilities = await BusinessService().capabilities();
      if (!capabilities.supports('businessFeatureQuickReplies')) {
        _unavailableReason =
            'Quick replies are unavailable in this version of Telegram.';
        return;
      }
      if (!capabilities.isPremium) {
        _unavailableReason =
            'Telegram Premium is required to send Business quick replies.';
        return;
      }
      await _service.loadShortcuts();
    } catch (error) {
      if (mounted) showToast(context, 'Could not load quick replies: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send(BusinessQuickReplyShortcut shortcut) async {
    if (_sendingId != null) return;
    setState(() => _sendingId = shortcut.id);
    try {
      await _service.send(widget.chatId, shortcut.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) showToast(context, 'Could not send quick reply: $error');
    } finally {
      if (mounted) setState(() => _sendingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shortcuts = _service.shortcuts;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: widget.chatTitle.isEmpty
                ? 'Quick Replies'
                : 'Reply to ${widget.chatTitle}',
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: _loading
                ? const Center(child: AppActivityIndicator(size: 24))
                : _unavailableReason.isNotEmpty
                ? _emptyState(
                    context,
                    title: 'Quick Replies Unavailable',
                    detail: _unavailableReason,
                  )
                : shortcuts.isEmpty
                ? _emptyState(
                    context,
                    title: 'No quick replies',
                    detail: 'Create one in Settings → Edit Profile → Business.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
                    itemCount: shortcuts.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 9),
                    itemBuilder: (_, index) {
                      final shortcut = shortcuts[index];
                      return _surface(
                        context,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _send(shortcut),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '/${shortcut.name}',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: c.textPrimary,
                                        ),
                                      ),
                                      if (shortcut.preview.isNotEmpty) ...[
                                        const SizedBox(height: 3),
                                        Text(
                                          shortcut.preview,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: c.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                if (_sendingId == shortcut.id)
                                  const AppActivityIndicator(size: 20)
                                else
                                  AppIcon(
                                    HeroAppIcons.paperPlane,
                                    size: 19,
                                    color: AppTheme.brand,
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

class BusinessAutomationView extends StatefulWidget {
  const BusinessAutomationView({super.key});

  @override
  State<BusinessAutomationView> createState() => _BusinessAutomationViewState();
}

class _BusinessAutomationViewState extends State<BusinessAutomationView> {
  final BusinessService _service = BusinessService();
  bool _loading = true;
  Map<String, dynamic>? _businessInfo;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final info = await _service.currentBusinessInfo();
      if (mounted) setState(() => _businessInfo = info);
    } catch (error) {
      if (mounted) showToast(context, 'Could not load automation: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Widget view) async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => view));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final greeting = _businessInfo?.obj('greeting_message_settings');
    final away = _businessInfo?.obj('away_message_settings');
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: 'Automated Messages',
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: _loading
                ? const Center(child: AppActivityIndicator(size: 24))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 18, 12, 24),
                    children: [
                      _surface(
                        context,
                        child: Column(
                          children: [
                            _navigationRow(
                              context,
                              icon: HeroAppIcons.thumbsUp,
                              color: const Color(0xFF19A874),
                              title: 'Greeting Message',
                              subtitle: greeting == null
                                  ? 'Off'
                                  : 'After ${greeting.integer('inactivity_days') ?? 7} inactive days',
                              onTap: () => _open(
                                BusinessGreetingMessageView(initial: greeting),
                              ),
                            ),
                            const InsetDivider(leadingInset: 58),
                            _navigationRow(
                              context,
                              icon: HeroAppIcons.moon,
                              color: const Color(0xFF675CE8),
                              title: 'Away Message',
                              subtitle: away == null ? 'Off' : 'On',
                              onTap: () =>
                                  _open(BusinessAwayMessageView(initial: away)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Automated messages use one of your quick-reply shortcuts and are delivered only to the recipient groups you choose.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class BusinessGreetingMessageView extends StatefulWidget {
  const BusinessGreetingMessageView({super.key, this.initial});

  final Map<String, dynamic>? initial;

  @override
  State<BusinessGreetingMessageView> createState() =>
      _BusinessGreetingMessageViewState();
}

class _BusinessGreetingMessageViewState
    extends State<BusinessGreetingMessageView> {
  final BusinessService _service = BusinessService();
  final BusinessQuickReplyService _replies = BusinessQuickReplyService.shared;
  late bool _enabled = widget.initial != null;
  late int _shortcutId = widget.initial?.integer('shortcut_id') ?? 0;
  late int _days = widget.initial?.integer('inactivity_days') ?? 7;
  late BusinessRecipientsDraft _recipients = BusinessRecipientsDraft.fromJson(
    widget.initial?.obj('recipients'),
  );
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final values = await _replies.loadShortcuts();
      if (_shortcutId == 0 && values.isNotEmpty) _shortcutId = values.first.id;
    } catch (error) {
      if (mounted) showToast(context, 'Could not load quick replies: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving || (_enabled && _shortcutId == 0)) {
      if (_enabled && _shortcutId == 0) {
        showToast(context, 'Create and select a quick reply first');
      }
      return;
    }
    setState(() => _saving = true);
    try {
      await _service.setGreeting(
        enabled: _enabled,
        shortcutId: _shortcutId,
        recipients: _recipients,
        inactivityDays: _days,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) showToast(context, 'Could not save greeting: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _BusinessToolScaffold(
      title: 'Greeting Message',
      saving: _saving,
      onSave: _save,
      child: _loading
          ? const Center(child: AppActivityIndicator(size: 24))
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 18, 12, 24),
              children: [
                _surface(
                  context,
                  child: _switchRow(
                    context,
                    title: 'Send Greeting Message',
                    value: _enabled,
                    onChanged: (value) => setState(() => _enabled = value),
                  ),
                ),
                if (_enabled) ...[
                  const SizedBox(height: 18),
                  _label(context, 'Quick Reply'),
                  _shortcutPicker(
                    context,
                    service: _replies,
                    value: _shortcutId,
                    onChanged: (value) => setState(() => _shortcutId = value),
                  ),
                  const SizedBox(height: 18),
                  _label(context, 'Send after no activity for'),
                  _surface(
                    context,
                    child: _businessChoiceRow(
                      context,
                      label: '$_days days',
                      onTap: () async {
                        final value = await _businessChoiceSheet<int>(
                          context,
                          title: 'Send after no activity for',
                          selected: _days,
                          choices: [
                            for (final days in const [7, 14, 21, 28])
                              (days, '$days days'),
                          ],
                        );
                        if (value != null && mounted) {
                          setState(() => _days = value);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 18),
                  _label(context, 'Recipients'),
                  BusinessRecipientsEditor(
                    value: _recipients,
                    onChanged: (value) => setState(() => _recipients = value),
                  ),
                ],
              ],
            ),
    );
  }
}

class BusinessAwayMessageView extends StatefulWidget {
  const BusinessAwayMessageView({super.key, this.initial});

  final Map<String, dynamic>? initial;

  @override
  State<BusinessAwayMessageView> createState() =>
      _BusinessAwayMessageViewState();
}

class _BusinessAwayMessageViewState extends State<BusinessAwayMessageView> {
  final BusinessService _service = BusinessService();
  final BusinessQuickReplyService _replies = BusinessQuickReplyService.shared;
  late bool _enabled = widget.initial != null;
  late int _shortcutId = widget.initial?.integer('shortcut_id') ?? 0;
  late bool _offlineOnly = widget.initial?.boolean('offline_only') ?? false;
  late BusinessRecipientsDraft _recipients = BusinessRecipientsDraft.fromJson(
    widget.initial?.obj('recipients'),
  );
  late String _scheduleType =
      widget.initial?.obj('schedule')?.type ??
      'businessAwayMessageScheduleAlways';
  late DateTime _start = DateTime.fromMillisecondsSinceEpoch(
    (widget.initial?.obj('schedule')?.integer('start_date') ??
            DateTime.now().millisecondsSinceEpoch ~/ 1000) *
        1000,
  );
  late DateTime _end = DateTime.fromMillisecondsSinceEpoch(
    (widget.initial?.obj('schedule')?.integer('end_date') ??
            DateTime.now()
                    .add(const Duration(days: 7))
                    .millisecondsSinceEpoch ~/
                1000) *
        1000,
  );
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final values = await _replies.loadShortcuts();
      if (_shortcutId == 0 && values.isNotEmpty) _shortcutId = values.first.id;
    } catch (error) {
      if (mounted) showToast(context, 'Could not load quick replies: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic> get _schedule {
    if (_scheduleType == 'businessAwayMessageScheduleCustom') {
      return {
        '@type': _scheduleType,
        'start_date': _start.millisecondsSinceEpoch ~/ 1000,
        'end_date': _end.millisecondsSinceEpoch ~/ 1000,
      };
    }
    return {'@type': _scheduleType};
  }

  Future<void> _save() async {
    if (_saving || (_enabled && _shortcutId == 0)) {
      if (_enabled && _shortcutId == 0) {
        showToast(context, 'Create and select a quick reply first');
      }
      return;
    }
    if (_scheduleType == 'businessAwayMessageScheduleCustom' &&
        !_end.isAfter(_start)) {
      showToast(context, 'The end time must be after the start time');
      return;
    }
    setState(() => _saving = true);
    try {
      await _service.setAway(
        enabled: _enabled,
        shortcutId: _shortcutId,
        recipients: _recipients,
        schedule: _schedule,
        offlineOnly: _offlineOnly,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) showToast(context, 'Could not save away message: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDate(bool start) async {
    final initial = start ? _start : _end;
    final selected = await showCupertinoModalPopup<DateTime>(
      context: context,
      builder: (context) => _BusinessDateTimeSheet(initial: initial),
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (start) {
        _start = selected;
      } else {
        _end = selected;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return _BusinessToolScaffold(
      title: 'Away Message',
      saving: _saving,
      onSave: _save,
      child: _loading
          ? const Center(child: AppActivityIndicator(size: 24))
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 18, 12, 24),
              children: [
                _surface(
                  context,
                  child: _switchRow(
                    context,
                    title: 'Send Away Message',
                    value: _enabled,
                    onChanged: (value) => setState(() => _enabled = value),
                  ),
                ),
                if (_enabled) ...[
                  const SizedBox(height: 18),
                  _label(context, 'Quick Reply'),
                  _shortcutPicker(
                    context,
                    service: _replies,
                    value: _shortcutId,
                    onChanged: (value) => setState(() => _shortcutId = value),
                  ),
                  const SizedBox(height: 18),
                  _label(context, 'Schedule'),
                  _surface(
                    context,
                    child: Column(
                      children: [
                        _radioRow(
                          context,
                          title: 'Always',
                          selected:
                              _scheduleType ==
                              'businessAwayMessageScheduleAlways',
                          onTap: () => setState(
                            () => _scheduleType =
                                'businessAwayMessageScheduleAlways',
                          ),
                        ),
                        const InsetDivider(leadingInset: 14),
                        _radioRow(
                          context,
                          title: 'Outside opening hours',
                          selected:
                              _scheduleType ==
                              'businessAwayMessageScheduleOutsideOfOpeningHours',
                          onTap: () => setState(
                            () => _scheduleType =
                                'businessAwayMessageScheduleOutsideOfOpeningHours',
                          ),
                        ),
                        const InsetDivider(leadingInset: 14),
                        _radioRow(
                          context,
                          title: 'Custom schedule',
                          selected:
                              _scheduleType ==
                              'businessAwayMessageScheduleCustom',
                          onTap: () => setState(
                            () => _scheduleType =
                                'businessAwayMessageScheduleCustom',
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_scheduleType == 'businessAwayMessageScheduleCustom') ...[
                    const SizedBox(height: 10),
                    _surface(
                      context,
                      child: Column(
                        children: [
                          _dateRow(
                            context,
                            title: 'Starts',
                            value: _start,
                            onTap: () => _pickDate(true),
                          ),
                          const InsetDivider(leadingInset: 14),
                          _dateRow(
                            context,
                            title: 'Ends',
                            value: _end,
                            onTap: () => _pickDate(false),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  _surface(
                    context,
                    child: _switchRow(
                      context,
                      title: 'Send only while offline',
                      value: _offlineOnly,
                      onChanged: (value) =>
                          setState(() => _offlineOnly = value),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _label(context, 'Recipients'),
                  BusinessRecipientsEditor(
                    value: _recipients,
                    onChanged: (value) => setState(() => _recipients = value),
                  ),
                ],
              ],
            ),
    );
  }
}

class BusinessConnectedBotView extends StatefulWidget {
  const BusinessConnectedBotView({super.key});

  @override
  State<BusinessConnectedBotView> createState() =>
      _BusinessConnectedBotViewState();
}

class _BusinessConnectedBotViewState extends State<BusinessConnectedBotView> {
  final BusinessService _service = BusinessService();
  final TextEditingController _username = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  int _botUserId = 0;
  String _botName = '';
  String _connectionDetail = '';
  BusinessRecipientsDraft _recipients = const BusinessRecipientsDraft();
  BusinessBotRightsDraft _rights = const BusinessBotRightsDraft();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final info = await _service.connectedBot();
      final bot = info?.obj('bot');
      final id = bot?.int64('bot_user_id') ?? 0;
      Map<String, dynamic>? user;
      if (id != 0) {
        user = await TdClient.shared.query({'@type': 'getUser', 'user_id': id});
      }
      if (!mounted) return;
      setState(() {
        _botUserId = id;
        _botName = user == null ? '' : TDParse.userName(user);
        _username.text =
            _activeUsername(user?.obj('usernames')) ?? _username.text;
        _recipients = BusinessRecipientsDraft.fromJson(bot?.obj('recipients'));
        _rights = BusinessBotRightsDraft.fromJson(bot?.obj('rights'));
        final device = info?.str('device_model') ?? '';
        final location = info?.str('location') ?? '';
        _connectionDetail = [
          device,
          location,
        ].where((value) => value.isNotEmpty).join(' · ');
      });
    } catch (error) {
      if (mounted) showToast(context, 'Could not load connected bot: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _activeUsername(Map<String, dynamic>? usernames) {
    final active = usernames?['active_usernames'];
    if (active is List) {
      return active.whereType<String>().firstOrNull;
    }
    return usernames?.str('editable_username');
  }

  Future<void> _resolve() async {
    if (_username.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final user = await _service.resolveBot(_username.text);
      if (!mounted) return;
      setState(() {
        _botUserId = user.int64('id') ?? 0;
        _botName = TDParse.userName(user);
      });
    } catch (error) {
      if (mounted) showToast(context, 'Bot not found: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_botUserId == 0) {
      await _resolve();
      if (_botUserId == 0) return;
    }
    setState(() => _saving = true);
    try {
      await _service.setConnectedBot(
        botUserId: _botUserId,
        recipients: _recipients,
        rights: _rights,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) showToast(context, 'Could not connect bot: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    if (_botUserId == 0) return;
    final confirmed = await confirmDialog(
      context,
      title: 'Disconnect Bot?',
      message: 'The bot will lose access to the selected business chats.',
      confirmText: 'Disconnect',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _saving = true);
    try {
      await _service.deleteConnectedBot(_botUserId);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) showToast(context, 'Could not disconnect bot: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _BusinessToolScaffold(
      title: 'Connected Bot',
      saving: _saving,
      onSave: _save,
      child: _loading
          ? const Center(child: AppActivityIndicator(size: 24))
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 18, 12, 24),
              children: [
                _label(context, 'Bot Username'),
                _surface(
                  context,
                  child: Row(
                    children: [
                      Expanded(
                        child: CupertinoTextField(
                          controller: _username,
                          prefix: Padding(
                            padding: const EdgeInsets.only(left: 14),
                            child: Text(
                              '@',
                              style: TextStyle(
                                fontSize: 16,
                                color: c.textSecondary,
                              ),
                            ),
                          ),
                          placeholder: 'business_bot',
                          padding: const EdgeInsets.all(14),
                          style: TextStyle(fontSize: 16, color: c.textPrimary),
                          placeholderStyle: TextStyle(color: c.textTertiary),
                          decoration: const BoxDecoration(),
                        ),
                      ),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _resolve,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Text(
                            'Check',
                            style: TextStyle(
                              fontSize: 15,
                              color: AppTheme.brand,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_botName.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    _connectionDetail.isEmpty
                        ? 'Selected: $_botName'
                        : '$_botName · $_connectionDetail',
                    style: TextStyle(fontSize: 13, color: c.textSecondary),
                  ),
                ],
                const SizedBox(height: 18),
                _label(context, 'Chat Access'),
                BusinessRecipientsEditor(
                  value: _recipients,
                  allowExcludedChats: true,
                  onChanged: (value) => setState(() => _recipients = value),
                ),
                const SizedBox(height: 18),
                _label(context, 'Bot Rights'),
                _surface(
                  context,
                  child: Column(
                    children: [
                      for (
                        var index = 0;
                        index < _botRightEntries.length;
                        index++
                      ) ...[
                        _switchRow(
                          context,
                          title: _botRightEntries[index].label,
                          value: _botRightEntries[index].read(_rights),
                          onChanged: (value) => setState(
                            () => _rights = _botRightEntries[index].write(
                              _rights,
                              value,
                            ),
                          ),
                        ),
                        if (index < _botRightEntries.length - 1)
                          const InsetDivider(leadingInset: 14),
                      ],
                    ],
                  ),
                ),
                if (_botUserId != 0) ...[
                  const SizedBox(height: 22),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _delete,
                    child: Center(
                      child: Text(
                        'Disconnect Bot',
                        style: TextStyle(fontSize: 15, color: AppTheme.tagRed),
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class BusinessRecipientsEditor extends StatelessWidget {
  const BusinessRecipientsEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.allowExcludedChats = false,
  });

  final BusinessRecipientsDraft value;
  final ValueChanged<BusinessRecipientsDraft> onChanged;
  final bool allowExcludedChats;

  Future<void> _addChat(BuildContext context, {required bool excluded}) async {
    final chat = await Navigator.of(context).push<ChatSummary>(
      MaterialPageRoute(
        builder: (_) => const ChatPickerView(
          title: 'Choose Private Chat',
          allowChannels: false,
        ),
      ),
    );
    if (chat == null || !context.mounted) return;
    if (chat.peerUserId == null) {
      showToast(context, 'Choose a private chat');
      return;
    }
    if (excluded) {
      onChanged(
        value.copyWith(
          excludedChatIds: {...value.excludedChatIds, chat.id}.toList(),
        ),
      );
    } else {
      onChanged(value.copyWith(chatIds: {...value.chatIds, chat.id}.toList()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return _surface(
      context,
      child: Column(
        children: [
          _switchRow(
            context,
            title: 'Existing chats',
            value: value.selectExistingChats,
            onChanged: (enabled) =>
                onChanged(value.copyWith(selectExistingChats: enabled)),
          ),
          const InsetDivider(leadingInset: 14),
          _switchRow(
            context,
            title: 'New chats',
            value: value.selectNewChats,
            onChanged: (enabled) =>
                onChanged(value.copyWith(selectNewChats: enabled)),
          ),
          const InsetDivider(leadingInset: 14),
          _switchRow(
            context,
            title: 'Contacts',
            value: value.selectContacts,
            onChanged: (enabled) =>
                onChanged(value.copyWith(selectContacts: enabled)),
          ),
          const InsetDivider(leadingInset: 14),
          _switchRow(
            context,
            title: 'Non-contacts',
            value: value.selectNonContacts,
            onChanged: (enabled) =>
                onChanged(value.copyWith(selectNonContacts: enabled)),
          ),
          const InsetDivider(leadingInset: 14),
          _switchRow(
            context,
            title: 'Invert selected chats',
            value: value.excludeSelected,
            onChanged: (enabled) =>
                onChanged(value.copyWith(excludeSelected: enabled)),
          ),
          const InsetDivider(leadingInset: 14),
          _actionRow(
            context,
            title: value.chatIds.isEmpty
                ? 'Add selected chat'
                : '${value.chatIds.length} selected chats',
            onTap: () => _addChat(context, excluded: false),
          ),
          if (value.chatIds.isNotEmpty)
            _idChips(
              context,
              value.chatIds,
              (id) => onChanged(
                value.copyWith(
                  chatIds: value.chatIds.where((item) => item != id).toList(),
                ),
              ),
            ),
          if (allowExcludedChats) ...[
            const InsetDivider(leadingInset: 14),
            _actionRow(
              context,
              title: value.excludedChatIds.isEmpty
                  ? 'Add excluded chat'
                  : '${value.excludedChatIds.length} excluded chats',
              onTap: () => _addChat(context, excluded: true),
            ),
            if (value.excludedChatIds.isNotEmpty)
              _idChips(
                context,
                value.excludedChatIds,
                (id) => onChanged(
                  value.copyWith(
                    excludedChatIds: value.excludedChatIds
                        .where((item) => item != id)
                        .toList(),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _idChips(
    BuildContext context,
    List<int> ids,
    ValueChanged<int> onRemove,
  ) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final id in ids)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onRemove(id),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: c.searchFill,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$id',
                      style: TextStyle(fontSize: 12, color: c.textSecondary),
                    ),
                    const SizedBox(width: 5),
                    AppIcon(
                      HeroAppIcons.xmark,
                      size: 12,
                      color: c.textTertiary,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class BusinessBotChatControlSheet extends StatefulWidget {
  const BusinessBotChatControlSheet({
    super.key,
    required this.chatId,
    required this.botName,
    required this.paused,
  });

  final int chatId;
  final String botName;
  final bool paused;

  @override
  State<BusinessBotChatControlSheet> createState() =>
      _BusinessBotChatControlSheetState();
}

class _BusinessBotChatControlSheetState
    extends State<BusinessBotChatControlSheet> {
  final BusinessService _service = BusinessService();
  late bool _paused = widget.paused;
  bool _saving = false;

  Future<void> _toggle(bool value) async {
    setState(() {
      _paused = value;
      _saving = true;
    });
    try {
      await _service.setBotPausedInChat(widget.chatId, value);
    } catch (error) {
      if (!mounted) return;
      setState(() => _paused = !value);
      showToast(context, 'Could not update bot: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove() async {
    setState(() => _saving = true);
    try {
      await _service.removeBotFromChat(widget.chatId);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) showToast(context, 'Could not remove bot: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.botName,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            _switchRow(
              context,
              title: 'Pause bot in this chat',
              value: _paused,
              onChanged: _saving ? (_) {} : _toggle,
            ),
            const SizedBox(height: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _saving ? null : _remove,
              child: Container(
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.tagRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Remove from this chat',
                  style: TextStyle(fontSize: 15, color: AppTheme.tagRed),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BusinessToolScaffold extends StatelessWidget {
  const _BusinessToolScaffold({
    required this.title,
    required this.saving,
    required this.onSave,
    required this.child,
  });

  final String title;
  final bool saving;
  final VoidCallback onSave;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: title,
            onBack: () => Navigator.of(context).pop(),
            trailing: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: saving ? null : onSave,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                child: saving
                    ? const AppActivityIndicator(size: 18)
                    : Text(
                        AppStrings.t(AppStringKeys.addMembersDone),
                        style: TextStyle(fontSize: 16, color: AppTheme.brand),
                      ),
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _BusinessTextEditorView extends StatefulWidget {
  const _BusinessTextEditorView({
    required this.title,
    required this.initial,
    required this.maxLength,
    required this.minLines,
  });

  final String title;
  final String initial;
  final int maxLength;
  final int minLines;

  @override
  State<_BusinessTextEditorView> createState() =>
      _BusinessTextEditorViewState();
}

class _BusinessTextEditorViewState extends State<_BusinessTextEditorView> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: widget.title,
            onBack: () => Navigator.of(context).pop(),
            trailing: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(_controller.text),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                child: Text(
                  AppStrings.t(AppStringKeys.addMembersDone),
                  style: TextStyle(fontSize: 16, color: AppTheme.brand),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _surface(
                  context,
                  child: CupertinoTextField(
                    controller: _controller,
                    maxLength: widget.maxLength,
                    minLines: widget.minLines,
                    maxLines: 12,
                    autofocus: true,
                    padding: const EdgeInsets.all(14),
                    style: TextStyle(fontSize: 16, color: c.textPrimary),
                    decoration: const BoxDecoration(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BusinessDateTimeSheet extends StatefulWidget {
  const _BusinessDateTimeSheet({required this.initial});

  final DateTime initial;

  @override
  State<_BusinessDateTimeSheet> createState() => _BusinessDateTimeSheetState();
}

class _BusinessDateTimeSheetState extends State<_BusinessDateTimeSheet> {
  late DateTime _selected = widget.initial;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        height: 330,
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
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
                    ),
                  ),
                  CupertinoButton(
                    onPressed: () => Navigator.of(context).pop(_selected),
                    child: Text(AppStrings.t(AppStringKeys.addMembersDone)),
                  ),
                ],
              ),
              Expanded(
                child: CupertinoDatePicker(
                  initialDateTime: widget.initial,
                  minimumDate: DateTime.now().subtract(
                    const Duration(minutes: 1),
                  ),
                  maximumDate: DateTime.now().add(const Duration(days: 366)),
                  use24hFormat: true,
                  onDateTimeChanged: (value) => _selected = value,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _surface(BuildContext context, {required Widget child}) => Container(
  decoration: BoxDecoration(
    color: context.colors.card,
    borderRadius: BorderRadius.circular(12),
  ),
  clipBehavior: Clip.antiAlias,
  child: child,
);

Widget _label(BuildContext context, String value) => Padding(
  padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
  child: Text(
    value,
    style: TextStyle(fontSize: 13, color: context.colors.textSecondary),
  ),
);

Widget _emptyState(
  BuildContext context, {
  required String title,
  required String detail,
  VoidCallback? onTap,
  String action = '',
}) {
  final c = context.colors;
  return Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 34),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(HeroAppIcons.message, size: 42, color: c.textTertiary),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.35,
              color: c.textSecondary,
            ),
          ),
          if (onTap != null && action.isNotEmpty) ...[
            const SizedBox(height: 18),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: Container(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.brand,
                  borderRadius: BorderRadius.circular(21),
                ),
                child: Text(
                  action,
                  style: const TextStyle(fontSize: 15, color: Colors.white),
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

Widget _navigationRow(
  BuildContext context, {
  required AppIconData icon,
  required Color color,
  required String title,
  required String subtitle,
  required VoidCallback onTap,
}) {
  final c = context.colors;
  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: SizedBox(
      height: 68,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            SettingsIconTile(
              icon: icon,
              backgroundColor: color,
              size: 32,
              iconSize: 17,
              radius: 8,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
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
            AppIcon(HeroAppIcons.chevronRight, size: 17, color: c.textTertiary),
          ],
        ),
      ),
    ),
  );
}

Widget _switchRow(
  BuildContext context, {
  required String title,
  required bool value,
  required ValueChanged<bool> onChanged,
}) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
  child: Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: TextStyle(fontSize: 15, color: context.colors.textPrimary),
        ),
      ),
      const SizedBox(width: 12),
      AppSwitch(value: value, onChanged: onChanged),
    ],
  ),
);

Widget _actionRow(
  BuildContext context, {
  required String title,
  required VoidCallback onTap,
}) => GestureDetector(
  behavior: HitTestBehavior.opaque,
  onTap: onTap,
  child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(fontSize: 15, color: AppTheme.brand),
          ),
        ),
        AppIcon(
          HeroAppIcons.plus,
          size: 17,
          color: context.colors.textTertiary,
        ),
      ],
    ),
  ),
);

Widget _radioRow(
  BuildContext context, {
  required String title,
  required bool selected,
  required VoidCallback onTap,
}) => GestureDetector(
  behavior: HitTestBehavior.opaque,
  onTap: onTap,
  child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(fontSize: 15, color: context.colors.textPrimary),
          ),
        ),
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? AppTheme.brand : context.colors.textTertiary,
              width: 1.5,
            ),
          ),
          alignment: Alignment.center,
          child: selected
              ? Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: AppTheme.brand,
                    shape: BoxShape.circle,
                  ),
                )
              : null,
        ),
      ],
    ),
  ),
);

Widget _dateRow(
  BuildContext context, {
  required String title,
  required DateTime value,
  required VoidCallback onTap,
}) => GestureDetector(
  behavior: HitTestBehavior.opaque,
  onTap: onTap,
  child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(fontSize: 15, color: context.colors.textPrimary),
          ),
        ),
        Text(
          '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} '
          '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}',
          style: TextStyle(fontSize: 14, color: context.colors.textSecondary),
        ),
      ],
    ),
  ),
);

Widget _shortcutPicker(
  BuildContext context, {
  required BusinessQuickReplyService service,
  required int value,
  required ValueChanged<int> onChanged,
}) {
  final c = context.colors;
  final shortcuts = service.shortcuts;
  if (shortcuts.isEmpty) {
    return _surface(
      context,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          'No quick replies available',
          style: TextStyle(fontSize: 15, color: c.textSecondary),
        ),
      ),
    );
  }
  final selected = shortcuts.any((item) => item.id == value)
      ? value
      : shortcuts.first.id;
  return _surface(
    context,
    child: _businessChoiceRow(
      context,
      label:
          '/${shortcuts.firstWhere((shortcut) => shortcut.id == selected).name}',
      onTap: () async {
        final next = await _businessChoiceSheet<int>(
          context,
          title: 'Quick Reply',
          selected: selected,
          choices: [
            for (final shortcut in shortcuts)
              (shortcut.id, '/${shortcut.name}'),
          ],
        );
        if (next != null) onChanged(next);
      },
    ),
  );
}

typedef _BusinessRightReader = bool Function(BusinessBotRightsDraft value);
typedef _BusinessRightWriter =
    BusinessBotRightsDraft Function(BusinessBotRightsDraft value, bool enabled);

class _BusinessBotRightEntry {
  const _BusinessBotRightEntry(this.label, this.read, this.write);

  final String label;
  final _BusinessRightReader read;
  final _BusinessRightWriter write;
}

final _botRightEntries = <_BusinessBotRightEntry>[
  _BusinessBotRightEntry(
    'Reply to messages',
    (v) => v.canReply,
    (v, enabled) => v.copyWith(canReply: enabled),
  ),
  _BusinessBotRightEntry(
    'Read messages',
    (v) => v.canReadMessages,
    (v, enabled) => v.copyWith(canReadMessages: enabled),
  ),
  _BusinessBotRightEntry(
    'Delete sent messages',
    (v) => v.canDeleteSentMessages,
    (v, enabled) => v.copyWith(canDeleteSentMessages: enabled),
  ),
  _BusinessBotRightEntry(
    'Delete all messages',
    (v) => v.canDeleteAllMessages,
    (v, enabled) => v.copyWith(canDeleteAllMessages: enabled),
  ),
  _BusinessBotRightEntry(
    'Edit account name',
    (v) => v.canEditName,
    (v, enabled) => v.copyWith(canEditName: enabled),
  ),
  _BusinessBotRightEntry(
    'Edit account bio',
    (v) => v.canEditBio,
    (v, enabled) => v.copyWith(canEditBio: enabled),
  ),
  _BusinessBotRightEntry(
    'Edit profile photo',
    (v) => v.canEditProfilePhoto,
    (v, enabled) => v.copyWith(canEditProfilePhoto: enabled),
  ),
  _BusinessBotRightEntry(
    'Edit username',
    (v) => v.canEditUsername,
    (v, enabled) => v.copyWith(canEditUsername: enabled),
  ),
  _BusinessBotRightEntry(
    'View gifts and Stars',
    (v) => v.canViewGiftsAndStars,
    (v, enabled) => v.copyWith(canViewGiftsAndStars: enabled),
  ),
  _BusinessBotRightEntry(
    'Sell gifts',
    (v) => v.canSellGifts,
    (v, enabled) => v.copyWith(canSellGifts: enabled),
  ),
  _BusinessBotRightEntry(
    'Change gift settings',
    (v) => v.canChangeGiftSettings,
    (v, enabled) => v.copyWith(canChangeGiftSettings: enabled),
  ),
  _BusinessBotRightEntry(
    'Transfer or upgrade gifts',
    (v) => v.canTransferAndUpgradeGifts,
    (v, enabled) => v.copyWith(canTransferAndUpgradeGifts: enabled),
  ),
  _BusinessBotRightEntry(
    'Transfer Stars',
    (v) => v.canTransferStars,
    (v, enabled) => v.copyWith(canTransferStars: enabled),
  ),
  _BusinessBotRightEntry(
    'Manage stories',
    (v) => v.canManageStories,
    (v, enabled) => v.copyWith(canManageStories: enabled),
  ),
];

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
