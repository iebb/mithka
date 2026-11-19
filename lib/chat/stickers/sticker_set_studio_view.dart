//
//  sticker_set_studio_view.dart
//
//  Sticker Studio — the owned sticker / mask / custom-emoji set editor,
//  following Telegram-iOS interaction conventions:
//
//  * StickerSetStudioView: owned sets list (thumbnail, title, type · count).
//  * StickerSetCreateView: type → stickers → metadata, with per-sticker
//    inline editing of a draft, live short-name availability, and a Done
//    (publish) action.
//  * StickerSetManageView: manage screen with an edit mode (delete badges),
//    long-press drag reordering of the sticker grid, the per-sticker action
//    sheet (with move-earlier/later kept as the non-drag reorder fallback),
//    mask badges and custom-emoji association shown on each cell.
//  * StickerDraftEditorView: one sticker source (file, format, emoji,
//    keywords, mask placement).
//  * StickerMaskPlacementView: mask point, shifts, and scale.
//

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../components/app_icons.dart';
import '../../components/confirm_dialog.dart';
import '../../components/photo_avatar.dart';
import '../../components/toast.dart';
import '../../components/ui_components.dart';
import '../../l10n/app_localizations.dart';
import '../../tdlib/json_helpers.dart';
import '../../tdlib/td_models.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_theme.dart';
import 'custom_emoji.dart';
import 'sticker_item.dart';
import 'sticker_preview.dart';
import 'sticker_reorder_grid.dart';
import 'sticker_set_management_service.dart';
import 'sticker_studio_controls.dart';

/// The studio root: owned sets list plus the create entry.
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
        borderRadius: BorderRadius.circular(AppRadius.card),
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
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: colors.searchFill,
                  borderRadius: BorderRadius.circular(AppRadius.control),
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

// ---------------------------------------------------------------------------
// Create flow
// ---------------------------------------------------------------------------

enum _NameCheckState { idle, checking, available, unavailable }

class StickerSetCreateView extends StatefulWidget {
  const StickerSetCreateView({super.key, this.service});

  /// Overrides the TDLib-backed service (used by tests to inject a fake).
  final StickerSetManagementService? service;

  @override
  State<StickerSetCreateView> createState() => _StickerSetCreateViewState();
}

class _StickerSetCreateViewState extends State<StickerSetCreateView> {
  late final StickerSetManagementService _service =
      widget.service ?? StickerSetManagementService.forActiveAccount();
  final _title = TextEditingController();
  final _name = TextEditingController();
  OwnedStickerSetType _type = OwnedStickerSetType.regular;
  bool _repainting = false;
  bool _working = false;
  final List<NewStickerDraft> _stickers = [];

  _NameCheckState _nameState = _NameCheckState.idle;
  int _nameCheckGeneration = 0;

  @override
  void initState() {
    super.initState();
    _name.addListener(_scheduleNameCheck);
  }

  @override
  void dispose() {
    _name.removeListener(_scheduleNameCheck);
    _title.dispose();
    _name.dispose();
    super.dispose();
  }

  bool get _customEmoji => _type == OwnedStickerSetType.customEmoji;

  int get _maximum => _customEmoji ? 200 : 120;

  Future<void> _add() async {
    if (_stickers.length >= _maximum) {
      showToast(
        context,
        context.l10n.t(AppStringKeys.stickerStudioSetLimit, {
          'value1': _maximum,
        }),
      );
      return;
    }
    final draft = await Navigator.of(context).push<NewStickerDraft>(
      MaterialPageRoute(builder: (_) => StickerDraftEditorView(setType: _type)),
    );
    if (draft != null && mounted) setState(() => _stickers.add(draft));
  }

  Future<void> _editDraft(int index) async {
    final draft = await Navigator.of(context).push<NewStickerDraft>(
      MaterialPageRoute(
        builder: (_) =>
            StickerDraftEditorView(setType: _type, initial: _stickers[index]),
      ),
    );
    if (draft != null && mounted) setState(() => _stickers[index] = draft);
  }

  void _scheduleNameCheck() {
    if (_working) return;
    final name = _name.text.trim();
    _nameCheckGeneration += 1;
    if (name.isEmpty) {
      setState(() => _nameState = _NameCheckState.idle);
      return;
    }
    setState(() => _nameState = _NameCheckState.checking);
    final generation = _nameCheckGeneration;
    Future<void>.delayed(const Duration(milliseconds: 420), () {
      if (!mounted || generation != _nameCheckGeneration) return;
      unawaited(_checkName(name, generation));
    });
  }

  Future<void> _checkName(String name, int generation) async {
    try {
      final check = await _service.checkName(name);
      if (!mounted || generation != _nameCheckGeneration) return;
      setState(() {
        _nameState = check.type == 'checkStickerSetNameResultOk'
            ? _NameCheckState.available
            : _NameCheckState.unavailable;
      });
    } catch (_) {
      if (!mounted || generation != _nameCheckGeneration) return;
      setState(() => _nameState = _NameCheckState.idle);
    }
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
    if (_nameState == _NameCheckState.unavailable) {
      showToast(
        context,
        AppStringKeys.stickerStudioNameUnavailable.l10n(context),
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
                    : Text(
                        AppStringKeys.stickerStudioDone.l10n(context),
                        style: TextStyle(
                          color: AppTheme.brand,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
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
                      StickerStudioChoiceRow(
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
                    if (_customEmoji)
                      Padding(
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
                            StickerStudioToggle(
                              value: _repainting,
                              onChanged: (value) =>
                                  setState(() => _repainting = value),
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
                    // Widgets-layer reorder machinery (no Material list
                    // chrome): the app supplies the drag proxy, the delayed
                    // long-press listener matches the manage grid's gesture.
                    ReorderableList(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      onReorderItem: (oldIndex, newIndex) => setState(
                        () => _stickers.insert(
                          newIndex,
                          _stickers.removeAt(oldIndex),
                        ),
                      ),
                      proxyDecorator: _draftProxyDecorator,
                      itemBuilder: (context, index) => _draftRow(
                        colors,
                        _stickers[index],
                        index,
                        key: ObjectKey(_stickers[index]),
                      ),
                      itemCount: _stickers.length,
                    ),
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
                if (_stickers.length > 1) ...[
                  const SizedBox(height: 10),
                  Text(
                    AppStringKeys.stickerStudioReorderHint.l10n(context),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                  ),
                ],
                const SizedBox(height: 14),
                _section(
                  colors,
                  children: [
                    stickerStudioField(
                      _title,
                      AppStringKeys.stickerStudioFieldTitle.l10n(context),
                      maxLength: 64,
                    ),
                    Divider(height: 1, color: colors.divider),
                    Row(
                      children: [
                        Expanded(
                          child: stickerStudioField(
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
                    if (_nameState != _NameCheckState.idle)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 2, 14, 12),
                        child: _nameStatus(colors),
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

  Widget _nameStatus(AppColors colors) {
    if (_nameState == _NameCheckState.checking) {
      return Text(
        AppStringKeys.stickerStudioNameChecking.l10n(context),
        style: TextStyle(fontSize: 12, color: colors.textSecondary),
      );
    }
    final available = _nameState == _NameCheckState.available;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIcon(
          available ? HeroAppIcons.check : HeroAppIcons.circleXmark,
          size: 14,
          color: available ? AppTheme.cloverGreen : AppTheme.tagRed,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            available
                ? AppStringKeys.stickerStudioNameAvailable.l10n(context)
                : AppStringKeys.stickerStudioNameUnavailable.l10n(context),
            style: TextStyle(
              fontSize: 12,
              color: available ? AppTheme.cloverGreen : AppTheme.tagRed,
            ),
          ),
        ),
      ],
    );
  }

  /// One draft row: tap to edit the source and its emoji/keywords, trash to
  /// remove, long-press to reorder (the widgets-layer delayed drag listener,
  /// the same gesture the manage grid uses).
  Widget _draftRow(
    AppColors colors,
    NewStickerDraft draft,
    int index, {
    required Key key,
  }) => ReorderableDelayedDragStartListener(
    key: key,
    index: index,
    enabled: !_working,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _working ? null : () => _editDraft(index),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.divider, width: 0.5)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              StickerDraftPreview(draft: draft, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      draft.emojis,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 20, color: colors.textPrimary),
                    ),
                    Text(
                      context.l10n.t(AppStringKeys.stickerStudioFormatFile, {
                        'value1': draft.format.name.toUpperCase(),
                        'value2': draft.path.split(Platform.pathSeparator).last,
                      }),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _working ? null : () => setState(() => _remove(index)),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: AppIcon(
                    HeroAppIcons.trash,
                    size: 19,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  /// The owned drag proxy for draft rows: the row itself, lifted with the
  /// studio's card surface and the grid feedback's shadow, so the create
  /// flow and the manage grid show one drag language. No Material elevation.
  Widget _draftProxyDecorator(
    Widget child,
    int index,
    Animation<double> animation,
  ) => AnimatedBuilder(
    animation: animation,
    builder: (context, row) {
      final border = BorderRadius.circular(12);
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: border,
          boxShadow: [
            BoxShadow(
              color: const Color(
                0x55000000,
              ).withValues(alpha: 0.55 * animation.value),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: border,
          child: ColoredBox(
            color: context.colors.card,
            child: ScaleTransition(
              scale: Tween<double>(begin: 1, end: 1.04).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOut),
              ),
              child: row,
            ),
          ),
        ),
      );
    },
    child: child,
  );

  void _remove(int index) {
    if (index < 0 || index >= _stickers.length) return;
    _stickers.removeAt(index);
  }
}

// ---------------------------------------------------------------------------
// Manage screen
// ---------------------------------------------------------------------------

class StickerSetManageView extends StatefulWidget {
  const StickerSetManageView({super.key, required this.setId, this.service});

  final int setId;

  /// Overrides the TDLib-backed service (used by tests to inject a fake).
  final StickerSetManagementService? service;

  @override
  State<StickerSetManageView> createState() => _StickerSetManageViewState();
}

class _StickerSetManageViewState extends State<StickerSetManageView> {
  late final StickerSetManagementService _service =
      widget.service ?? StickerSetManagementService.forActiveAccount();
  final _gridViewportKey = GlobalKey(debugLabel: 'studio-grid-viewport');
  final _scrollController = ScrollController();

  Map<String, dynamic>? _set;
  List<Map<String, dynamic>> _rawStickers = const [];
  List<StickerItem> _stickers = const [];
  bool _loading = true;
  bool _working = false;
  bool _changed = false;
  bool _editMode = false;

  /// Sticker file ids picked in edit mode for a batch delete.
  final Set<int> _selectedFileIds = {};

  OwnedStickerSetType get _type => _setTypeFromTd(_set?.obj('sticker_type'));
  String get _name => _set?.str('name') ?? '';
  int get _maximum => _type == OwnedStickerSetType.customEmoji ? 200 : 120;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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
    if (_rawStickers.length >= _maximum) {
      showToast(
        context,
        context.l10n.t(AppStringKeys.stickerStudioSetLimit, {
          'value1': _maximum,
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

  /// The shareable set link (t.me/addstickers/«name», or /addemoji/ for
  /// custom-emoji sets). Empty until the set exists — the create flow has no
  /// link to preview, which is why only the manage screen shows it.
  String get _setLink {
    if (_name.isEmpty) return '';
    final prefix = _type == OwnedStickerSetType.customEmoji
        ? AppStringKeys.stickerStudioLinkPrefixEmoji.l10n(context)
        : AppStringKeys.stickerStudioLinkPrefixStickers.l10n(context);
    return 'https://$prefix$_name';
  }

  /// Opens the set's t.me link the way the repo opens external links
  /// (url_launcher directly, see auth/terms_sheet.dart), keeping the studio
  /// clear of the chat-link stack.
  Future<void> _openSetLink() async {
    final link = _setLink;
    if (link.isEmpty) return;
    final uri = Uri.tryParse(link);
    if (uri == null || !uri.isScheme('https')) {
      _toastLinkInvalid();
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) _toastLinkInvalid();
  }

  Future<void> _copySetLink() async {
    final link = _setLink;
    if (link.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: link));
    if (mounted) {
      showToast(context, context.l10n.t(AppStringKeys.stickerStudioLinkCopied));
    }
  }

  void _toastLinkInvalid() {
    if (!mounted) return;
    showToast(context, context.l10n.t(AppStringKeys.stickerStudioLinkInvalid));
  }

  /// Edit-mode batch delete: one confirmation, then the picked stickers are
  /// removed serially (TDLib has no bulk remove). A failed removal does not
  /// forfeit the rest — the loop continues so remaining selections are still
  /// deleted, and the failures are reported (which sticker file ids failed
  /// and the error) instead of a bare count. The service is pinned to the
  /// account that loaded the set, so a foreground account switch during the
  /// confirmation or between removals fails closed instead of sending the
  /// selected ids to another account.
  Future<void> _removeSelected() async {
    if (_selectedFileIds.isEmpty || _working) return;
    final count = _selectedFileIds.length;
    final yes = await confirmDialog(
      context,
      title: context.l10n.t(AppStringKeys.stickerStudioRemoveSelectedTitle, {
        'value1': count,
      }),
      message: context.l10n.t(
        AppStringKeys.stickerStudioRemoveSelectedMessage,
        {'value1': count},
      ),
      confirmText: AppStringKeys.stickerStudioRemove.l10n(context),
      destructive: true,
    );
    if (!yes) return;
    setState(() => _working = true);
    final picked = _selectedFileIds.toList();
    try {
      final result = await _service.removeSelected(picked);
      _changed = true;
      _selectedFileIds
        ..clear()
        ..addAll(result.failures.map((failure) => failure.fileId));
      await _load();
      if (mounted && result.failures.isNotEmpty) {
        showToast(
          context,
          context.l10n.t(AppStringKeys.stickerStudioRemoveSelectedFailed, {
            'value1': result.removed.length,
            'value2': picked.length,
          }),
        );
      }
    } catch (error) {
      // The owning account went away mid-batch: nothing further is sent.
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

  /// Tapping a cell in edit mode toggles its picked state instead of opening
  /// the action sheet.
  void _toggleCellSelection(int index) {
    final fileId = _stickerFileId(index);
    if (fileId == 0) return;
    setState(() {
      if (!_selectedFileIds.remove(fileId)) _selectedFileIds.add(fileId);
    });
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

  /// Drag-drop reorder: one setStickerPositionInSet call moves the dragged
  /// sticker to its new 0-based position, then the set reloads to confirm the
  /// server-side order.
  Future<void> _reorder(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex || _working) return;
    final fileId = _stickerFileId(oldIndex);
    if (fileId == 0) return;
    await _run(() => _service.move(fileId, newIndex));
  }

  Map<String, dynamic> _rawAt(int index) =>
      index >= 0 && index < _rawStickers.length
      ? _rawStickers[index]
      : const <String, dynamic>{};

  int _stickerFileId(int index) =>
      _rawAt(index).obj('sticker')?.int64('id') ?? 0;

  Future<void> _stickerActions(int index) async {
    final raw = _rawAt(index);
    final fileId = raw.obj('sticker')?.int64('id') ?? 0;
    final customEmojiId = raw.obj('full_type')?.int64('custom_emoji_id') ?? 0;
    if (fileId == 0) return;
    final action = await showAppModalSheet<_StickerAction>(
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
            if (_type != OwnedStickerSetType.customEmoji &&
                _formatFromTd(raw.obj('format')?.type) != null)
              // Telegram iOS picks the set's thumbnail straight from the
              // grid; TDLib accepts an inputFileId, so no re-upload.
              _actionTile(
                sheetContext,
                _StickerAction.thumbnailFromFile,
                AppStringKeys.stickerStudioActionUseThumbnail.l10n(context),
                HeroAppIcons.image,
              ),
            _actionTile(
              sheetContext,
              _StickerAction.link,
              AppStringKeys.stickerStudioOpenLink.l10n(context),
              HeroAppIcons.arrowTopRight,
            ),
            _actionTile(
              sheetContext,
              _StickerAction.replace,
              AppStringKeys.stickerStudioActionReplace.l10n(context),
              HeroAppIcons.arrowsRotate,
            ),
            // The non-drag reorder fallback: still reachable when dragging is
            // disabled, and the a11y-reachable equivalent of the drag.
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
          initial: _keywordsOf(raw),
          hint: AppStringKeys.stickerStudioKeywordsHint.l10n(context),
        );
        if (value != null) {
          await _run(() => _service.setKeywords(fileId, value.split(',')));
        }
      case _StickerAction.mask:
        final placement = await _maskPlacement(initial: _placementFrom(raw));
        if (placement != null) {
          await _run(() => _service.setMaskPlacement(fileId, placement));
        }
      case _StickerAction.thumbnail:
        await _run(
          () => _service.setCustomEmojiThumbnail(_name, customEmojiId),
        );
      case _StickerAction.thumbnailFromFile:
        final format = _formatFromTd(raw.obj('format')?.type);
        if (format != null) {
          await _run(
            () => _service.setThumbnailFromFileId(_name, fileId, format),
          );
        }
      case _StickerAction.link:
        await _openSetLink();
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
        await _confirmRemove(index);
    }
  }

  Future<void> _confirmRemove(int index) async {
    final fileId = _stickerFileId(index);
    if (fileId == 0) return;
    final yes = await confirmDialog(
      context,
      title: AppStringKeys.stickerStudioRemoveSticker.l10n(context),
      message: AppStringKeys.stickerStudioRemoveMessage.l10n(context),
      confirmText: AppStringKeys.stickerStudioRemove.l10n(context),
      destructive: true,
    );
    if (yes) await _run(() => _service.remove(fileId));
  }

  String _keywordsOf(Map<String, dynamic> raw) =>
      (raw['keywords'] as List? ?? const []).cast<String>().join(',');

  StickerMaskPlacement? _placementFrom(Map<String, dynamic> raw) {
    final mask = raw.obj('full_type')?.obj('mask_position');
    if (mask == null) return null;
    final point = switch (mask.obj('point')?.type) {
      'maskPointForehead' => StickerMaskPoint.forehead,
      'maskPointEyes' => StickerMaskPoint.eyes,
      'maskPointMouth' => StickerMaskPoint.mouth,
      'maskPointChin' => StickerMaskPoint.chin,
      _ => null,
    };
    if (point == null) return null;
    return StickerMaskPlacement(
      point: point,
      xShift: mask.dbl('x_shift') ?? 0,
      yShift: mask.dbl('y_shift') ?? 0,
      scale: mask.dbl('scale') ?? 1,
    );
  }

  Future<StickerMaskPlacement?> _maskPlacement({
    StickerMaskPlacement? initial,
  }) => Navigator.of(context).push<StickerMaskPlacement>(
    MaterialPageRoute(
      builder: (_) => StickerMaskPlacementView(initial: initial),
    ),
  );

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
      pageBuilder: (dialogContext, _, _) => StickerStudioDialog(
        title: title,
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint, border: InputBorder.none),
        ),
        actions: [
          StickerStudioDialogAction(
            label: AppStringKeys.confirmCancel.l10n(dialogContext),
            onTap: () => Navigator.of(dialogContext).pop(),
          ),
          StickerStudioDialogAction(
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

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final title =
        _set?.str('title') ?? AppStringKeys.stickerStudioTitle.l10n(context);
    final reducedMotion = AppMotion.isReduced(context);
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
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() {
                          _editMode = !_editMode;
                          if (!_editMode) _selectedFileIds.clear();
                        }),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            _editMode
                                ? AppStringKeys.stickerStudioDone.l10n(context)
                                : AppStringKeys.messageActionEdit.l10n(context),
                            style: TextStyle(
                              color: AppTheme.brand,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      GestureDetector(
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
                    ],
                  ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: AppActivityIndicator(size: 24))
                // A shrinkWrap grid under a ListView gets unbounded height and
                // lays out every cell, mounting a decoder per sticker up front.
                : CustomScrollView(
                    key: _gridViewportKey,
                    controller: _scrollController,
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        sliver: SliverToBoxAdapter(child: _manageCard(colors)),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 14)),
                      if (_stickers.isEmpty)
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          sliver: SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.all(28),
                              child: Text(
                                AppStringKeys.stickerStudioEmptySet.l10n(
                                  context,
                                ),
                                textAlign: TextAlign.center,
                                style: TextStyle(color: colors.textSecondary),
                              ),
                            ),
                          ),
                        )
                      else ...[
                        if (!reducedMotion && _stickers.length > 1)
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
                            sliver: SliverToBoxAdapter(
                              child: Text(
                                AppStringKeys.stickerStudioReorderHint.l10n(
                                  context,
                                ),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          sliver: StickerReorderGridSliver(
                            itemCount: _stickers.length,
                            reorderableCount: _stickers.length,
                            dragEnabled: !_working && !_editMode,
                            scrollController: _scrollController,
                            viewportKey: _gridViewportKey,
                            onReorder: _reorder,
                            cellBuilder: (context, index) =>
                                _stickerCell(context, index, colors),
                          ),
                        ),
                        if (_editMode)
                          SliverToBoxAdapter(child: _selectionToolbar(colors)),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// One sticker cell: preview, the associated emoji (custom emoji sets show
  /// the emoji each sticker stands in for), the mask-position badge for mask
  /// sets, and in edit mode a delete badge instead of the action ellipsis.
  Widget _stickerCell(BuildContext context, int index, AppColors colors) {
    final sticker = _stickers[index];
    final raw = _rawAt(index);
    final emoji = raw.str('emoji') ?? sticker.emoji;
    final mask = _type == OwnedStickerSetType.mask ? _placementFrom(raw) : null;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final selected = _selectedFileIds.contains(_stickerFileId(index));
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _working
          ? null
          : _editMode
          ? () => _toggleCellSelection(index)
          : () => _stickerActions(index),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: StickerPreview(item: sticker, cornerRadius: 10),
          ),
          // Edit-mode pick state: a dimmed scrim plus the check mark, so a
          // picked cell reads at a glance before the batch delete.
          if (_editMode && selected) Positioned.fill(child: _pickScrim(colors)),
          if (emoji.isNotEmpty)
            Positioned(
              left: rtl ? null : 3,
              right: rtl ? 3 : null,
              top: 3,
              child: Container(
                key: ValueKey('studio-sticker-emoji-$index'),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: colors.card.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  emoji.characters.first,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          if (mask != null)
            Positioned(
              left: rtl ? 3 : null,
              right: rtl ? null : 3,
              top: 3,
              child: Container(
                key: ValueKey('studio-sticker-mask-$index'),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.card.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  context.l10n.t(AppStringKeys.stickerStudioMaskBadge, {
                    'value1': mask.point.name,
                  }),
                  style: TextStyle(fontSize: 9, color: colors.textSecondary),
                ),
              ),
            ),
          Positioned(
            right: 2,
            bottom: 2,
            child: _editMode
                ? (selected
                      ? Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: AppTheme.brand,
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: AppIcon(
                              HeroAppIcons.check,
                              size: 13,
                              color: Color(0xFFFFFFFF),
                            ),
                          ),
                        )
                      : _deleteBadge(index))
                : Container(
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
    );
  }

  Widget _pickScrim(AppColors colors) => ColoredBox(
    key: const ValueKey('studio-cell-scrim'),
    color: AppTheme.brand.withValues(alpha: 0.25),
  );

  /// The batch-delete bar shown below the grid while picking cells.
  Widget _selectionToolbar(AppColors colors) {
    final count = _selectedFileIds.length;
    return Padding(
      key: const ValueKey('studio-selection-toolbar'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              count == 0
                  ? AppStringKeys.stickerStudioSelectHint.l10n(context)
                  : context.l10n.t(AppStringKeys.stickerStudioSelectedCount, {
                      'value1': count,
                    }),
              style: TextStyle(fontSize: 13, color: colors.textSecondary),
            ),
          ),
          if (count > 0)
            GestureDetector(
              key: const ValueKey('studio-selection-delete'),
              behavior: HitTestBehavior.opaque,
              onTap: _working ? null : _removeSelected,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.tagRed,
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                child: Text(
                  AppStringKeys.stickerStudioRemove.l10n(context),
                  style: const TextStyle(
                    color: Color(0xFFFFFFFF),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _deleteBadge(int index) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: _working ? null : () => _confirmRemove(index),
    child: Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(color: AppTheme.tagRed, shape: BoxShape.circle),
      child: const Center(
        child: AppIcon(HeroAppIcons.minus, size: 13, color: Color(0xFFFFFFFF)),
      ),
    ),
  );

  Widget _manageCard(AppColors colors) => Container(
    decoration: BoxDecoration(
      color: colors.card,
      borderRadius: BorderRadius.circular(AppRadius.card),
    ),
    child: Column(
      children: [
        if (_setLink.isNotEmpty) ...[
          _linkRow(colors),
          Divider(height: 1, indent: 48, color: colors.divider),
        ],
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

  /// The shareable set link row: the t.me address, tap to copy, and the
  /// open-link affordance — Telegram iOS shows the link on the manage screen
  /// and offers it in the per-sticker sheet.
  Widget _linkRow(AppColors colors) {
    final link = _setLink;
    return GestureDetector(
      key: const ValueKey('studio-set-link-row'),
      behavior: HitTestBehavior.opaque,
      onTap: _working ? null : _copySetLink,
      child: SizedBox(
        height: 51,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              AppIcon(HeroAppIcons.link, size: 20, color: colors.textPrimary),
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  link.replaceFirst('https://', ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, color: colors.linkBlue),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _working ? null : _openSetLink,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: AppIcon(
                    HeroAppIcons.arrowTopRight,
                    size: 18,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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

// ---------------------------------------------------------------------------
// Draft editor
// ---------------------------------------------------------------------------

class StickerDraftEditorView extends StatefulWidget {
  const StickerDraftEditorView({
    super.key,
    required this.setType,
    this.initial,
  });

  final OwnedStickerSetType setType;

  /// Set when editing an existing draft from the create flow.
  final NewStickerDraft? initial;

  @override
  State<StickerDraftEditorView> createState() => _StickerDraftEditorViewState();
}

class _StickerDraftEditorViewState extends State<StickerDraftEditorView> {
  late final TextEditingController _emojis = TextEditingController(
    text: widget.initial?.emojis ?? '🙂',
  );
  late final TextEditingController _keywords = TextEditingController(
    text: widget.initial?.keywords.join(',') ?? '',
  );
  late StickerFileFormat _format =
      widget.initial?.format ?? StickerFileFormat.webp;
  late String? _path = widget.initial?.path;
  late StickerMaskPlacement? _mask = widget.initial?.maskPlacement;
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
        pageBuilder: (dialogContext, _, _) => StickerStudioDialog(
          title: AppStringKeys.stickerStudioSourceNeedsChanges.l10n(
            dialogContext,
          ),
          content: Text(result.errors.map((error) => '• $error').join('\n\n')),
          actions: [
            StickerStudioDialogAction(
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
                            StickerDraftPreview(
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
                                borderRadius: BorderRadius.circular(
                                  AppRadius.card,
                                ),
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
                      StickerStudioChoiceRow(
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
                    stickerStudioField(
                      _emojis,
                      AppStringKeys.stickerStudioFieldMatchingEmoji.l10n(
                        context,
                      ),
                    ),
                    Divider(height: 1, color: colors.divider),
                    stickerStudioField(
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
                              builder: (_) =>
                                  StickerMaskPlacementView(initial: _mask),
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

// ---------------------------------------------------------------------------
// Mask placement
// ---------------------------------------------------------------------------

class StickerMaskPlacementView extends StatefulWidget {
  const StickerMaskPlacementView({super.key, this.initial});

  final StickerMaskPlacement? initial;

  @override
  State<StickerMaskPlacementView> createState() =>
      _StickerMaskPlacementViewState();
}

class _StickerMaskPlacementViewState extends State<StickerMaskPlacementView> {
  late StickerMaskPoint _point = widget.initial?.point ?? StickerMaskPoint.eyes;
  late double _x = widget.initial?.xShift ?? 0;
  late double _y = widget.initial?.yShift ?? 0;
  late double _scale = widget.initial?.scale ?? 1;

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
                StickerStudioSection(
                  children: [
                    for (final point in StickerMaskPoint.values)
                      StickerStudioChoiceRow(
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
                StickerStudioValueRow(
                  label: AppStringKeys.stickerStudioHorizontalShift.l10n(
                    context,
                  ),
                  value: _x,
                  min: -2,
                  max: 2,
                  onChanged: (value) => setState(() => _x = value),
                ),
                StickerStudioValueRow(
                  label: AppStringKeys.stickerStudioVerticalShift.l10n(context),
                  value: _y,
                  min: -2,
                  max: 2,
                  onChanged: (value) => setState(() => _y = value),
                ),
                StickerStudioValueRow(
                  label: AppStringKeys.stickerStudioScale.l10n(context),
                  value: _scale,
                  min: 0.1,
                  max: 4,
                  onChanged: (value) => setState(() => _scale = value),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _StickerAction {
  emojis,
  keywords,
  mask,
  thumbnail,
  thumbnailFromFile,
  link,
  replace,
  up,
  down,
  remove,
}

/// The raw TDLib sticker's `format` (@type) → the studio's format enum.
StickerFileFormat? _formatFromTd(String? type) => switch (type) {
  'stickerFormatWebp' => StickerFileFormat.webp,
  'stickerFormatTgs' => StickerFileFormat.tgs,
  'stickerFormatWebm' => StickerFileFormat.webm,
  _ => null,
};

Widget _section(AppColors colors, {required List<Widget> children}) =>
    StickerStudioSection(children: children);

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
