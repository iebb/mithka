import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../components/app_icons.dart';
import '../components/confirm_dialog.dart';
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import 'custom_emoji.dart';
import 'sticker_item.dart';
import 'sticker_preview.dart';
import 'sticker_set_management_service.dart';

class StickerSetStudioView extends StatefulWidget {
  const StickerSetStudioView({super.key});

  @override
  State<StickerSetStudioView> createState() => _StickerSetStudioViewState();
}

class _StickerSetStudioViewState extends State<StickerSetStudioView> {
  final _service = StickerSetManagementService();
  List<Map<String, dynamic>> _sets = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final sets = await _service.ownedSets();
      if (mounted) setState(() => _sets = sets);
    } catch (error) {
      if (mounted) {
        showToast(
          context,
          context.l10n.t(AppStringKeys.stickerStudioLoadOwnedFailed, {
            'value1': error,
          }),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const StickerSetCreateView()),
    );
    if (created == true) await _load();
  }

  Future<void> _open(Map<String, dynamic> set) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => StickerSetManageView(setId: set.int64('id') ?? 0),
      ),
    );
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStringKeys.stickerStudioTitle.l10n(context),
            onBack: () => Navigator.of(context).pop(),
            trailing: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _create,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: AppIcon(
                  HeroAppIcons.plus,
                  size: 23,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: AppActivityIndicator(size: 24))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                    children: [
                      _createCard(colors),
                      const SizedBox(height: 10),
                      _StudioRefreshRow(onTap: _load),
                      const SizedBox(height: 14),
                      if (_sets.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            AppStringKeys.stickerStudioEmpty.l10n(context),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                      for (final set in _sets) _setRow(set, colors),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _createCard(AppColors colors) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: _create,
    child: Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppTheme.brand.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Center(
              child: AppIcon(
                HeroAppIcons.wandMagicSparkles,
                size: 21,
                color: AppTheme.brand,
              ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStringKeys.stickerStudioCreate.l10n(context),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  AppStringKeys.stickerStudioCreateSubtitle.l10n(context),
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
              ],
            ),
          ),
          AppIcon(
            HeroAppIcons.chevronRight,
            size: 19,
            color: colors.textTertiary,
          ),
        ],
      ),
    ),
  );

  Widget _setRow(Map<String, dynamic> set, AppColors colors) {
    final type = _setTypeFromTd(set.obj('sticker_type'));
    final cover = TDParse.fileRef(set.obj('thumbnail')?.obj('file'));
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _open(set),
        child: Container(
          constraints: const BoxConstraints(minHeight: 70),
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: colors.searchFill,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: cover == null
                    ? Center(
                        child: AppIcon(
                          type == OwnedStickerSetType.customEmoji
                              ? HeroAppIcons.solidFaceSmile
                              : HeroAppIcons.image,
                          size: 24,
                          color: colors.textTertiary,
                        ),
                      )
                    : TDImage(photo: cover, cornerRadius: 10),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      set.str('title') ??
                          AppStringKeys.stickerStudioUntitled.l10n(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.l10n.t(AppStringKeys.stickerStudioItemCount, {
                        'value1': _typeLabel(context, type),
                        'value2': set.int64('size') ?? 0,
                      }),
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              AppIcon(
                HeroAppIcons.chevronRight,
                size: 18,
                color: colors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StudioRefreshRow extends StatelessWidget {
  const _StudioRefreshRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: AppStringKeys.stickerStudioRefresh.l10n(context),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 40,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppIcon(HeroAppIcons.arrowsRotate, size: 17, color: AppTheme.brand),
            const SizedBox(width: 7),
            Text(
              AppStringKeys.stickerStudioRefresh.l10n(context),
              style: TextStyle(
                color: AppTheme.brand,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    ),
  );
}

class StickerSetCreateView extends StatefulWidget {
  const StickerSetCreateView({super.key});

  @override
  State<StickerSetCreateView> createState() => _StickerSetCreateViewState();
}

class _StickerSetCreateViewState extends State<StickerSetCreateView> {
  final _service = StickerSetManagementService();
  final _title = TextEditingController();
  final _name = TextEditingController();
  OwnedStickerSetType _type = OwnedStickerSetType.regular;
  bool _repainting = false;
  bool _working = false;
  final List<NewStickerDraft> _stickers = [];

  @override
  void dispose() {
    _title.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final maximum = _type == OwnedStickerSetType.customEmoji ? 200 : 120;
    if (_stickers.length >= maximum) {
      showToast(
        context,
        context.l10n.t(AppStringKeys.stickerStudioSetLimit, {
          'value1': maximum,
        }),
      );
      return;
    }
    final draft = await Navigator.of(context).push<NewStickerDraft>(
      MaterialPageRoute(builder: (_) => StickerDraftEditorView(setType: _type)),
    );
    if (draft != null && mounted) setState(() => _stickers.add(draft));
  }

  Future<void> _suggestName() async {
    if (_title.text.trim().isEmpty || _working) return;
    setState(() => _working = true);
    try {
      final value = await _service.suggestedName(_title.text);
      if (mounted) _name.text = value;
    } catch (error) {
      if (mounted) {
        showToast(
          context,
          context.l10n.t(AppStringKeys.stickerStudioSuggestFailed, {
            'value1': error,
          }),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _create() async {
    final title = _title.text.trim();
    if (title.isEmpty || title.length > 64) {
      showToast(context, AppStringKeys.stickerStudioTitleInvalid.l10n(context));
      return;
    }
    if (_stickers.isEmpty) {
      showToast(
        context,
        AppStringKeys.stickerStudioValidationAddSticker.l10n(context),
      );
      return;
    }
    final nameUnavailable = AppStringKeys.stickerStudioNameUnavailable.l10n(
      context,
    );
    setState(() => _working = true);
    try {
      final name = _name.text.trim();
      if (name.isNotEmpty) {
        final check = await _service.checkName(name);
        if (check.type != 'checkStickerSetNameResultOk') {
          throw StateError(nameUnavailable);
        }
      }
      await _service.create(
        title: title,
        name: name,
        type: _type,
        needsRepainting: _repainting,
        stickers: _stickers,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        showToast(
          context,
          context.l10n.t(AppStringKeys.stickerStudioCreateFailed, {
            'value1': error,
          }),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStringKeys.stickerStudioNewSet.l10n(context),
            onBack: () => Navigator.of(context).pop(),
            trailing: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _working ? null : _create,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: _working
                    ? const AppActivityIndicator(size: 19)
                    : AppIcon(
                        HeroAppIcons.check,
                        size: 22,
                        color: AppTheme.brand,
                      ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _section(
                  colors,
                  children: [
                    _field(
                      _title,
                      AppStringKeys.stickerStudioFieldTitle.l10n(context),
                      maxLength: 64,
                    ),
                    Divider(height: 1, color: colors.divider),
                    Row(
                      children: [
                        Expanded(
                          child: _field(
                            _name,
                            AppStringKeys.stickerStudioFieldShortName.l10n(
                              context,
                            ),
                            maxLength: 64,
                          ),
                        ),
                        GestureDetector(
                          onTap: _suggestName,
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Text(
                              AppStringKeys.stickerStudioShortNameSuggest.l10n(
                                context,
                              ),
                              style: TextStyle(
                                color: colors.linkBlue,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _section(
                  colors,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                      child: Text(
                        AppStringKeys.stickerStudioSetType.l10n(context),
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 0.5,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    for (final type in OwnedStickerSetType.values)
                      _choiceRow(
                        colors,
                        label: _typeLabel(context, type),
                        detail: switch (type) {
                          OwnedStickerSetType.regular =>
                            AppStringKeys.stickerStudioTypeRegularDetail.l10n(
                              context,
                            ),
                          OwnedStickerSetType.mask =>
                            AppStringKeys.stickerStudioTypeMaskDetail.l10n(
                              context,
                            ),
                          OwnedStickerSetType.customEmoji =>
                            AppStringKeys.stickerStudioTypeCustomEmojiDetail
                                .l10n(context),
                        },
                        selected: _type == type,
                        onTap: () => setState(() {
                          _type = type;
                          _stickers.clear();
                        }),
                      ),
                    if (_type == OwnedStickerSetType.customEmoji)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => _repainting = !_repainting),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  AppStringKeys.stickerStudioRepaint.l10n(
                                    context,
                                  ),
                                  style: TextStyle(
                                    color: colors.textPrimary,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              _OwnedToggle(
                                value: _repainting,
                                onChanged: (value) =>
                                    setState(() => _repainting = value),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                _section(
                  colors,
                  children: [
                    for (var index = 0; index < _stickers.length; index++)
                      _draftRow(colors, _stickers[index], index),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _add,
                      child: Padding(
                        padding: const EdgeInsets.all(15),
                        child: Row(
                          children: [
                            AppIcon(
                              HeroAppIcons.circlePlus,
                              size: 22,
                              color: AppTheme.brand,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              AppStringKeys.stickerStudioAddSource.l10n(
                                context,
                              ),
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: colors.linkBlue,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  AppStringKeys.stickerStudioSourceSpecNote.l10n(context),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _draftRow(
    AppColors colors,
    NewStickerDraft draft,
    int index,
  ) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => setState(() => _stickers.removeAt(index)),
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.divider, width: 0.5)),
      ),
      child: Row(
        children: [
          _DraftPreview(draft: draft, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  draft.emojis,
                  style: TextStyle(fontSize: 20, color: colors.textPrimary),
                ),
                Text(
                  context.l10n.t(AppStringKeys.stickerStudioFormatFile, {
                    'value1': draft.format.name.toUpperCase(),
                    'value2': draft.path.split(Platform.pathSeparator).last,
                  }),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
              ],
            ),
          ),
          AppIcon(HeroAppIcons.trash, size: 19, color: colors.textSecondary),
        ],
      ),
    ),
  );
}

class StickerSetManageView extends StatefulWidget {
  const StickerSetManageView({super.key, required this.setId});

  final int setId;

  @override
  State<StickerSetManageView> createState() => _StickerSetManageViewState();
}

class _StickerSetManageViewState extends State<StickerSetManageView> {
  final _service = StickerSetManagementService();
  Map<String, dynamic>? _set;
  List<Map<String, dynamic>> _rawStickers = const [];
  List<StickerItem> _stickers = const [];
  bool _loading = true;
  bool _working = false;
  bool _changed = false;

  OwnedStickerSetType get _type => _setTypeFromTd(_set?.obj('sticker_type'));
  String get _name => _set?.str('name') ?? '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final set = await _service.getSet(widget.setId);
      if (!mounted) return;
      setState(() {
        _set = set;
        _rawStickers = set.objects('stickers') ?? const [];
        _stickers = parseStickers(_rawStickers);
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _loading = false);
        showToast(
          context,
          context.l10n.t(AppStringKeys.stickerStudioLoadFailed, {
            'value1': error,
          }),
        );
      }
    }
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await operation();
      _changed = true;
      await _load();
    } catch (error) {
      if (mounted) {
        showToast(
          context,
          context.l10n.t(AppStringKeys.stickerStudioUpdateFailed, {
            'value1': error,
          }),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _add() async {
    final maximum = _type == OwnedStickerSetType.customEmoji ? 200 : 120;
    if (_rawStickers.length >= maximum) {
      showToast(
        context,
        context.l10n.t(AppStringKeys.stickerStudioSetLimit, {
          'value1': maximum,
        }),
      );
      return;
    }
    final draft = await Navigator.of(context).push<NewStickerDraft>(
      MaterialPageRoute(builder: (_) => StickerDraftEditorView(setType: _type)),
    );
    if (draft != null) await _run(() => _service.add(_name, draft));
  }

  Future<void> _rename() async {
    final title = await _askText(
      title: AppStringKeys.stickerStudioSetTitle.l10n(context),
      initial: _set?.str('title') ?? '',
      hint: AppStringKeys.stickerStudioSetTitleHint.l10n(context),
    );
    if (title == null || title.trim().isEmpty || title.trim().length > 64) {
      return;
    }
    await _run(() => _service.setTitle(_name, title));
  }

  Future<void> _setThumbnail() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'webp', 'tgs', 'webm'],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    final format = _formatFromPath(path);
    if (format == null) return;
    await _run(
      () => _service.setThumbnail(name: _name, path: path, format: format),
    );
  }

  Future<void> _delete() async {
    final yes = await confirmDialog(
      context,
      title: AppStringKeys.stickerStudioDeleteTitle.l10n(context),
      message: AppStringKeys.stickerStudioDeleteMessage.l10n(context),
      confirmText: AppStringKeys.stickerStudioDelete.l10n(context),
      destructive: true,
    );
    if (!yes) return;
    setState(() => _working = true);
    try {
      await _service.delete(_name);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        showToast(
          context,
          context.l10n.t(AppStringKeys.stickerStudioDeleteFailed, {
            'value1': error,
          }),
        );
      }
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _stickerActions(int index) async {
    final raw = _rawStickers[index];
    final fileId = raw.obj('sticker')?.int64('id') ?? 0;
    final customEmojiId = raw.obj('full_type')?.int64('custom_emoji_id') ?? 0;
    if (fileId == 0) return;
    final action = await showModalBottomSheet<_StickerAction>(
      context: context,
      backgroundColor: context.colors.card,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _actionTile(
              sheetContext,
              _StickerAction.emojis,
              AppStringKeys.stickerStudioActionEditEmoji.l10n(context),
              HeroAppIcons.solidFaceSmile,
            ),
            _actionTile(
              sheetContext,
              _StickerAction.keywords,
              AppStringKeys.stickerStudioActionEditKeywords.l10n(context),
              HeroAppIcons.magnifyingGlass,
            ),
            if (_type == OwnedStickerSetType.mask)
              _actionTile(
                sheetContext,
                _StickerAction.mask,
                AppStringKeys.stickerStudioActionEditMask.l10n(context),
                HeroAppIcons.objectGroup,
              ),
            if (_type == OwnedStickerSetType.customEmoji && customEmojiId != 0)
              _actionTile(
                sheetContext,
                _StickerAction.thumbnail,
                AppStringKeys.stickerStudioActionUseThumbnail.l10n(context),
                HeroAppIcons.image,
              ),
            _actionTile(
              sheetContext,
              _StickerAction.replace,
              AppStringKeys.stickerStudioActionReplace.l10n(context),
              HeroAppIcons.arrowsRotate,
            ),
            if (index > 0)
              _actionTile(
                sheetContext,
                _StickerAction.up,
                AppStringKeys.stickerStudioActionMoveEarlier.l10n(context),
                HeroAppIcons.arrowUp,
              ),
            if (index < _rawStickers.length - 1)
              _actionTile(
                sheetContext,
                _StickerAction.down,
                AppStringKeys.stickerStudioActionMoveLater.l10n(context),
                HeroAppIcons.arrowDown,
              ),
            _actionTile(
              sheetContext,
              _StickerAction.remove,
              AppStringKeys.stickerStudioActionRemove.l10n(context),
              HeroAppIcons.trash,
              destructive: true,
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _StickerAction.emojis:
        final value = await _askText(
          title: AppStringKeys.stickerStudioFieldMatchingEmoji.l10n(context),
          initial: raw.str('emoji') ?? '',
          hint: AppStringKeys.stickerStudioMatchingEmojiHint.l10n(context),
        );
        if (value != null && value.trim().isNotEmpty) {
          await _run(() => _service.setEmojis(fileId, value));
        }
      case _StickerAction.keywords:
        final value = await _askText(
          title: AppStringKeys.stickerStudioFieldKeywords.l10n(context),
          initial: '',
          hint: AppStringKeys.stickerStudioKeywordsHint.l10n(context),
        );
        if (value != null) {
          await _run(() => _service.setKeywords(fileId, value.split(',')));
        }
      case _StickerAction.mask:
        final placement = await _maskPlacement();
        if (placement != null) {
          await _run(() => _service.setMaskPlacement(fileId, placement));
        }
      case _StickerAction.thumbnail:
        await _run(
          () => _service.setCustomEmojiThumbnail(_name, customEmojiId),
        );
      case _StickerAction.replace:
        final draft = await Navigator.of(context).push<NewStickerDraft>(
          MaterialPageRoute(
            builder: (_) => StickerDraftEditorView(setType: _type),
          ),
        );
        if (draft != null) {
          await _run(() => _service.replace(_name, fileId, draft));
        }
      case _StickerAction.up:
        await _run(() => _service.move(fileId, index - 1));
      case _StickerAction.down:
        await _run(() => _service.move(fileId, index + 1));
      case _StickerAction.remove:
        final yes = await confirmDialog(
          context,
          title: AppStringKeys.stickerStudioRemoveSticker.l10n(context),
          message: AppStringKeys.stickerStudioRemoveMessage.l10n(context),
          confirmText: AppStringKeys.stickerStudioRemove.l10n(context),
          destructive: true,
        );
        if (yes) await _run(() => _service.remove(fileId));
    }
  }

  Widget _actionTile(
    BuildContext sheetContext,
    _StickerAction action,
    String label,
    AppIconData icon, {
    bool destructive = false,
  }) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => Navigator.of(sheetContext).pop(action),
    child: SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            AppIcon(
              icon,
              size: 21,
              color: destructive
                  ? AppTheme.tagRed
                  : sheetContext.colors.textPrimary,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  color: destructive
                      ? AppTheme.tagRed
                      : sheetContext.colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Future<String?> _askText({
    required String title,
    required String initial,
    required String hint,
  }) async {
    final controller = TextEditingController(text: initial);
    final result = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: AppStringKeys.confirmCancel.l10n(context),
      barrierColor: const Color(0x99000000),
      pageBuilder: (dialogContext, _, _) => _OwnedDialog(
        title: title,
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint, border: InputBorder.none),
        ),
        actions: [
          _OwnedDialogAction(
            label: AppStringKeys.confirmCancel.l10n(dialogContext),
            onTap: () => Navigator.of(dialogContext).pop(),
          ),
          _OwnedDialogAction(
            label: AppStringKeys.stickerStudioSave.l10n(dialogContext),
            color: AppTheme.brand,
            onTap: () => Navigator.of(dialogContext).pop(controller.text),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<StickerMaskPlacement?> _maskPlacement() => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const StickerMaskPlacementView()));

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final title =
        _set?.str('title') ?? AppStringKeys.stickerStudioTitle.l10n(context);
    return Scaffold(
      backgroundColor: colors.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: title,
            onBack: () => Navigator.of(context).pop(_changed),
            trailing: _working
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: AppActivityIndicator(size: 18),
                  )
                : GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _add,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: AppIcon(
                        HeroAppIcons.plus,
                        size: 23,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: AppActivityIndicator(size: 24))
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _manageCard(colors),
                      const SizedBox(height: 14),
                      if (_stickers.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(28),
                          child: Text(
                            AppStringKeys.stickerStudioEmptySet.l10n(context),
                            textAlign: TextAlign.center,
                            style: TextStyle(color: colors.textSecondary),
                          ),
                        )
                      else
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 4,
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                              ),
                          itemCount: _stickers.length,
                          itemBuilder: (_, index) => GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _working
                                ? null
                                : () => _stickerActions(index),
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: StickerPreview(
                                    item: _stickers[index],
                                    cornerRadius: 10,
                                  ),
                                ),
                                Positioned(
                                  right: 2,
                                  bottom: 2,
                                  child: Container(
                                    width: 22,
                                    height: 22,
                                    decoration: BoxDecoration(
                                      color: colors.card.withValues(alpha: 0.9),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: AppIcon(
                                        HeroAppIcons.ellipsis,
                                        size: 15,
                                        color: colors.textSecondary,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
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

  Widget _manageCard(AppColors colors) => Container(
    decoration: BoxDecoration(
      color: colors.card,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      children: [
        _manageRow(
          colors,
          AppStringKeys.stickerStudioRename.l10n(context),
          HeroAppIcons.pen,
          _rename,
        ),
        Divider(height: 1, indent: 48, color: colors.divider),
        if (_type != OwnedStickerSetType.customEmoji) ...[
          _manageRow(
            colors,
            AppStringKeys.stickerStudioSetThumbnail.l10n(context),
            HeroAppIcons.image,
            _setThumbnail,
          ),
          Divider(height: 1, indent: 48, color: colors.divider),
          _manageRow(
            colors,
            AppStringKeys.stickerStudioRemoveThumbnail.l10n(context),
            HeroAppIcons.circleMinus,
            () => _run(
              () =>
                  _service.setThumbnail(name: _name, path: null, format: null),
            ),
          ),
          Divider(height: 1, indent: 48, color: colors.divider),
        ] else ...[
          _manageRow(
            colors,
            AppStringKeys.stickerStudioCustomEmojiThumbnailRemove.l10n(context),
            HeroAppIcons.circleMinus,
            () => _run(() => _service.setCustomEmojiThumbnail(_name, 0)),
          ),
          Divider(height: 1, indent: 48, color: colors.divider),
        ],
        _manageRow(
          colors,
          AppStringKeys.stickerStudioDelete.l10n(context),
          HeroAppIcons.trash,
          _delete,
          destructive: true,
        ),
      ],
    ),
  );

  Widget _manageRow(
    AppColors colors,
    String label,
    AppIconData icon,
    VoidCallback onTap, {
    bool destructive = false,
  }) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: _working ? null : onTap,
    child: SizedBox(
      height: 51,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            AppIcon(
              icon,
              size: 20,
              color: destructive ? AppTheme.tagRed : colors.textPrimary,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  color: destructive ? AppTheme.tagRed : colors.textPrimary,
                ),
              ),
            ),
            AppIcon(
              HeroAppIcons.chevronRight,
              size: 17,
              color: colors.textTertiary,
            ),
          ],
        ),
      ),
    ),
  );
}

class StickerDraftEditorView extends StatefulWidget {
  const StickerDraftEditorView({super.key, required this.setType});

  final OwnedStickerSetType setType;

  @override
  State<StickerDraftEditorView> createState() => _StickerDraftEditorViewState();
}

class _StickerDraftEditorViewState extends State<StickerDraftEditorView> {
  final _emojis = TextEditingController(text: '🙂');
  final _keywords = TextEditingController();
  StickerFileFormat _format = StickerFileFormat.webp;
  String? _path;
  StickerMaskPlacement? _mask;
  bool _validating = false;

  @override
  void dispose() {
    _emojis.dispose();
    _keywords.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _format.allowedExtensions,
    );
    final path = result?.files.single.path;
    if (path != null && mounted) setState(() => _path = path);
  }

  Future<void> _done() async {
    final path = _path;
    if (path == null) {
      showToast(
        context,
        AppStringKeys.stickerStudioChooseSourceFirst.l10n(context),
      );
      return;
    }
    final draft = NewStickerDraft(
      path: path,
      format: _format,
      emojis: _emojis.text,
      keywords: _keywords.text.split(','),
      maskPlacement: widget.setType == OwnedStickerSetType.mask
          ? _mask ?? const StickerMaskPlacement(point: StickerMaskPoint.eyes)
          : null,
    );
    setState(() => _validating = true);
    final result = await StickerInputValidator.validate(
      draft,
      setType: widget.setType,
    );
    if (!mounted) return;
    setState(() => _validating = false);
    if (!result.isValid) {
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: AppStringKeys.confirmOk.l10n(context),
        barrierColor: const Color(0x99000000),
        pageBuilder: (dialogContext, _, _) => _OwnedDialog(
          title: AppStringKeys.stickerStudioSourceNeedsChanges.l10n(
            dialogContext,
          ),
          content: Text(result.errors.map((error) => '• $error').join('\n\n')),
          actions: [
            _OwnedDialogAction(
              label: AppStringKeys.confirmOk.l10n(dialogContext),
              color: AppTheme.brand,
              onTap: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        ),
      );
      return;
    }
    Navigator.of(context).pop(draft);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final formats = widget.setType == OwnedStickerSetType.mask
        ? const [StickerFileFormat.webp]
        : StickerFileFormat.values;
    return Scaffold(
      backgroundColor: colors.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStringKeys.stickerStudioSourceTitle.l10n(context),
            onBack: () => Navigator.of(context).pop(),
            trailing: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _validating ? null : _done,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: _validating
                    ? const AppActivityIndicator(size: 19)
                    : AppIcon(
                        HeroAppIcons.check,
                        size: 22,
                        color: AppTheme.brand,
                      ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _section(
                  colors,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          if (_path != null)
                            _DraftPreview(
                              draft: NewStickerDraft(
                                path: _path!,
                                format: _format,
                                emojis: _emojis.text,
                              ),
                              size: 64,
                            )
                          else
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: colors.searchFill,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: AppIcon(
                                  HeroAppIcons.image,
                                  size: 26,
                                  color: colors.textTertiary,
                                ),
                              ),
                            ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              _path == null
                                  ? AppStringKeys.stickerStudioNoFile.l10n(
                                      context,
                                    )
                                  : _path!.split(Platform.pathSeparator).last,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                color: colors.textPrimary,
                              ),
                            ),
                          ),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _pick,
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(
                                AppStringKeys.stickerStudioChoose.l10n(context),
                                style: TextStyle(
                                  color: colors.linkBlue,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _section(
                  colors,
                  children: [
                    for (final format in formats)
                      _choiceRow(
                        colors,
                        label: format.name.toUpperCase(),
                        detail: switch (format) {
                          StickerFileFormat.webp =>
                            AppStringKeys.stickerStudioFormatWebp.l10n(context),
                          StickerFileFormat.tgs =>
                            AppStringKeys.stickerStudioFormatTgs.l10n(context),
                          StickerFileFormat.webm =>
                            AppStringKeys.stickerStudioFormatVideo.l10n(
                              context,
                            ),
                        },
                        selected: _format == format,
                        onTap: () => setState(() {
                          _format = format;
                          _path = null;
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                _section(
                  colors,
                  children: [
                    _field(
                      _emojis,
                      AppStringKeys.stickerStudioFieldMatchingEmoji.l10n(
                        context,
                      ),
                    ),
                    Divider(height: 1, color: colors.divider),
                    _field(
                      _keywords,
                      AppStringKeys.stickerStudioFieldKeywords.l10n(context),
                    ),
                  ],
                ),
                if (widget.setType == OwnedStickerSetType.mask) ...[
                  const SizedBox(height: 14),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () async {
                      final result = await Navigator.of(context)
                          .push<StickerMaskPlacement>(
                            MaterialPageRoute(
                              builder: (_) => const StickerMaskPlacementView(),
                            ),
                          );
                      if (result != null && mounted) {
                        setState(() => _mask = result);
                      }
                    },
                    child: _section(
                      colors,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(15),
                          child: Row(
                            children: [
                              const AppIcon(HeroAppIcons.objectGroup, size: 21),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  context.l10n.t(
                                    AppStringKeys
                                        .stickerStudioMaskPlacementValue,
                                    {
                                      'value1':
                                          (_mask?.point ??
                                                  StickerMaskPoint.eyes)
                                              .name,
                                    },
                                  ),
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: colors.textPrimary,
                                  ),
                                ),
                              ),
                              AppIcon(
                                HeroAppIcons.chevronRight,
                                size: 17,
                                color: colors.textTertiary,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  _format == StickerFileFormat.webm
                      ? AppStringKeys.stickerStudioSourceWebmNote.l10n(context)
                      : AppStringKeys.stickerStudioSourceGenericNote.l10n(
                          context,
                        ),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: colors.textSecondary,
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

class StickerMaskPlacementView extends StatefulWidget {
  const StickerMaskPlacementView({super.key});

  @override
  State<StickerMaskPlacementView> createState() =>
      _StickerMaskPlacementViewState();
}

class _StickerMaskPlacementViewState extends State<StickerMaskPlacementView> {
  StickerMaskPoint _point = StickerMaskPoint.eyes;
  double _x = 0;
  double _y = 0;
  double _scale = 1;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStringKeys.stickerStudioMaskPlacement.l10n(context),
            onBack: () => Navigator.of(context).pop(),
            trailing: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(
                StickerMaskPlacement(
                  point: _point,
                  xShift: _x,
                  yShift: _y,
                  scale: _scale,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: AppIcon(
                  HeroAppIcons.check,
                  size: 22,
                  color: AppTheme.brand,
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _section(
                  colors,
                  children: [
                    for (final point in StickerMaskPoint.values)
                      _choiceRow(
                        colors,
                        label:
                            point.name[0].toUpperCase() +
                            point.name.substring(1),
                        detail: context.l10n.t(
                          AppStringKeys.stickerStudioAnchorMask,
                          {'value1': point.name},
                        ),
                        selected: _point == point,
                        onTap: () => setState(() => _point = point),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                _slider(
                  colors,
                  AppStringKeys.stickerStudioHorizontalShift.l10n(context),
                  _x,
                  -2,
                  2,
                  (value) => _x = value,
                ),
                _slider(
                  colors,
                  AppStringKeys.stickerStudioVerticalShift.l10n(context),
                  _y,
                  -2,
                  2,
                  (value) => _y = value,
                ),
                _slider(
                  colors,
                  AppStringKeys.stickerStudioScale.l10n(context),
                  _scale,
                  0.1,
                  4,
                  (value) => _scale = value,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _slider(
    AppColors colors,
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> update,
  ) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
    decoration: BoxDecoration(
      color: colors.card,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: TextStyle(color: colors.textPrimary)),
            ),
            Text(
              value.toStringAsFixed(2),
              style: TextStyle(color: colors.textSecondary),
            ),
          ],
        ),
        _OwnedSlider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: (next) => setState(() => update(next)),
        ),
      ],
    ),
  );
}

class _OwnedToggle extends StatelessWidget {
  const _OwnedToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => onChanged(!value),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      width: 46,
      height: 28,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: value ? AppTheme.brand : context.colors.textTertiary,
        borderRadius: BorderRadius.circular(14),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
            color: Color(0xFFFFFFFF),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 3,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _OwnedSlider extends StatelessWidget {
  const _OwnedSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  void _update(double dx, double width) {
    final fraction = (dx / width).clamp(0.0, 1.0);
    onChanged(min + (max - min) * fraction);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, constraints) {
      final fraction = max == min
          ? 0.0
          : ((value - min) / (max - min)).clamp(0.0, 1.0);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) =>
            _update(details.localPosition.dx, constraints.maxWidth),
        onHorizontalDragUpdate: (details) =>
            _update(details.localPosition.dx, constraints.maxWidth),
        child: SizedBox(
          height: 38,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: 4,
                decoration: BoxDecoration(
                  color: context.colors.textTertiary.withValues(alpha: 0.32),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              FractionallySizedBox(
                widthFactor: fraction,
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.brand,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Positioned(
                left: (constraints.maxWidth - 22) * fraction,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: AppTheme.brand,
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(color: Color(0x33000000), blurRadius: 4),
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
}

class _OwnedDialog extends StatelessWidget {
  const _OwnedDialog({
    required this.title,
    required this.content,
    required this.actions,
  });

  final String title;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.colors.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: context.colors.divider, width: 0.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x44000000),
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: DefaultTextStyle(
            style: TextStyle(color: context.colors.textPrimary, fontSize: 15),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
                  child: content,
                ),
                Container(height: 0.5, color: context.colors.divider),
                SizedBox(height: 50, child: Row(children: actions)),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _OwnedDialogAction extends StatelessWidget {
  const _OwnedDialogAction({
    required this.label,
    required this.onTap,
    this.color,
  });

  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: color ?? context.colors.textSecondary,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    ),
  );
}

enum _StickerAction {
  emojis,
  keywords,
  mask,
  thumbnail,
  replace,
  up,
  down,
  remove,
}

Widget _section(AppColors colors, {required List<Widget> children}) =>
    Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(children: children),
    );

Widget _field(
  TextEditingController controller,
  String hint, {
  int? maxLength,
}) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
  child: TextField(
    controller: controller,
    maxLength: maxLength,
    decoration: InputDecoration(
      border: InputBorder.none,
      hintText: hint,
      counterText: '',
    ),
  ),
);

Widget _choiceRow(
  AppColors colors, {
  required String label,
  required String detail,
  required bool selected,
  required VoidCallback onTap,
}) => GestureDetector(
  behavior: HitTestBehavior.opaque,
  onTap: onTap,
  child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 15, color: colors.textPrimary),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
            ],
          ),
        ),
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? AppTheme.brand : Colors.transparent,
            border: Border.all(
              color: selected ? AppTheme.brand : colors.textTertiary,
              width: 1.5,
            ),
          ),
          child: selected
              ? const Center(
                  child: AppIcon(
                    HeroAppIcons.check,
                    size: 14,
                    color: Colors.white,
                  ),
                )
              : null,
        ),
      ],
    ),
  ),
);

class _DraftPreview extends StatelessWidget {
  const _DraftPreview({required this.draft, required this.size});

  final NewStickerDraft draft;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: context.colors.searchFill,
      borderRadius: BorderRadius.circular(10),
    ),
    child: draft.format == StickerFileFormat.webp
        ? Image.file(
            File(draft.path),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => _fallback(context),
          )
        : _fallback(context),
  );

  Widget _fallback(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIcon(
          draft.format == StickerFileFormat.webm
              ? HeroAppIcons.video
              : HeroAppIcons.wandMagicSparkles,
          size: size * 0.32,
          color: context.colors.textSecondary,
        ),
        Text(
          draft.format.name.toUpperCase(),
          style: TextStyle(
            fontSize: size * 0.14,
            color: context.colors.textSecondary,
          ),
        ),
      ],
    ),
  );
}

OwnedStickerSetType _setTypeFromTd(Map<String, dynamic>? object) =>
    switch (object?.type) {
      'stickerTypeMask' => OwnedStickerSetType.mask,
      'stickerTypeCustomEmoji' => OwnedStickerSetType.customEmoji,
      _ => OwnedStickerSetType.regular,
    };

String _typeLabel(BuildContext context, OwnedStickerSetType type) =>
    switch (type) {
      OwnedStickerSetType.regular =>
        AppStringKeys.stickerStudioTypeRegular.l10n(context),
      OwnedStickerSetType.mask => AppStringKeys.stickerStudioTypeMask.l10n(
        context,
      ),
      OwnedStickerSetType.customEmoji =>
        AppStringKeys.stickerStudioTypeCustomEmoji.l10n(context),
    };

StickerFileFormat? _formatFromPath(String path) =>
    switch (path.split('.').last.toLowerCase()) {
      'png' || 'webp' => StickerFileFormat.webp,
      'tgs' => StickerFileFormat.tgs,
      'webm' => StickerFileFormat.webm,
      _ => null,
    };
