part of 'rich_text_composer_view.dart';

extension on _RichBlockKind {
  String get labelKey => switch (this) {
    _RichBlockKind.paragraph => AppStringKeys.richTextBlockParagraph,
    _RichBlockKind.heading => AppStringKeys.richTextBlockHeading,
    _RichBlockKind.preformatted => AppStringKeys.richTextBlockPreformatted,
    _RichBlockKind.footer => AppStringKeys.richTextBlockFooter,
    _RichBlockKind.divider => AppStringKeys.richTextBlockDivider,
    _RichBlockKind.mathematicalExpression =>
      AppStringKeys.richTextBlockMathematicalExpression,
    _RichBlockKind.anchor => AppStringKeys.richTextBlockAnchor,
    _RichBlockKind.list => AppStringKeys.richTextBlockList,
    _RichBlockKind.blockQuotation => AppStringKeys.richTextBlockBlockQuotation,
    _RichBlockKind.pullQuotation => AppStringKeys.richTextBlockPullQuotation,
    _RichBlockKind.collage => AppStringKeys.richTextBlockCollage,
    _RichBlockKind.slideshow => AppStringKeys.richTextBlockSlideshow,
    _RichBlockKind.table => AppStringKeys.richTextBlockTable,
    _RichBlockKind.buttonRow => AppStringKeys.richTextBlockButtonRow,
    _RichBlockKind.details => AppStringKeys.richTextBlockDetails,
    _RichBlockKind.map => AppStringKeys.richTextBlockMap,
    _RichBlockKind.animation => AppStringKeys.richTextBlockAnimation,
    _RichBlockKind.audio => AppStringKeys.richTextBlockAudio,
    _RichBlockKind.photo => AppStringKeys.richTextBlockPhoto,
    _RichBlockKind.video => AppStringKeys.richTextBlockVideo,
    _RichBlockKind.voiceNote => AppStringKeys.richTextBlockVoiceNote,
    _RichBlockKind.thinking => AppStringKeys.richTextBlockThinking,
    _RichBlockKind.document => AppStringKeys.topicPostContentFile,
  };

  AppIconData get icon => switch (this) {
    _RichBlockKind.paragraph => HeroAppIcons.font,
    _RichBlockKind.heading => HeroAppIcons.hashtag,
    _RichBlockKind.preformatted => HeroAppIcons.code,
    _RichBlockKind.footer => HeroAppIcons.bars,
    _RichBlockKind.divider => HeroAppIcons.minus,
    _RichBlockKind.mathematicalExpression => HeroAppIcons.code,
    _RichBlockKind.anchor => HeroAppIcons.link,
    _RichBlockKind.list => HeroAppIcons.listCheck,
    _RichBlockKind.blockQuotation => HeroAppIcons.quoteLeft,
    _RichBlockKind.pullQuotation => HeroAppIcons.quoteLeft,
    _RichBlockKind.collage => HeroAppIcons.images,
    _RichBlockKind.slideshow => HeroAppIcons.tableColumns,
    _RichBlockKind.table => HeroAppIcons.tableCells,
    _RichBlockKind.buttonRow => HeroAppIcons.link,
    _RichBlockKind.details => HeroAppIcons.bars,
    _RichBlockKind.map => HeroAppIcons.locationPin,
    _RichBlockKind.animation => HeroAppIcons.gif,
    _RichBlockKind.audio => HeroAppIcons.music,
    _RichBlockKind.photo => HeroAppIcons.image,
    _RichBlockKind.video => HeroAppIcons.play,
    _RichBlockKind.voiceNote => HeroAppIcons.microphone,
    _RichBlockKind.thinking => HeroAppIcons.comments,
    _RichBlockKind.document => HeroAppIcons.file,
  };
}

extension on _RichButtonAlignment {
  String get tdType => switch (this) {
    _RichButtonAlignment.left => 'pageBlockHorizontalAlignmentLeft',
    _RichButtonAlignment.center => 'pageBlockHorizontalAlignmentCenter',
    _RichButtonAlignment.right => 'pageBlockHorizontalAlignmentRight',
  };

  String get labelKey => switch (this) {
    _RichButtonAlignment.left => AppStringKeys.richTextTableAlignLeft,
    _RichButtonAlignment.center => AppStringKeys.richTextTableAlignCenter,
    _RichButtonAlignment.right => AppStringKeys.richTextTableAlignRight,
  };

  AppIconData get icon => switch (this) {
    _RichButtonAlignment.left => HeroAppIcons.alignLeft,
    _RichButtonAlignment.center => HeroAppIcons.alignCenter,
    _RichButtonAlignment.right => HeroAppIcons.alignRight,
  };
}

extension on _RichButtonStyle {
  String get tdType => switch (this) {
    _RichButtonStyle.standard => 'buttonStyleDefault',
    _RichButtonStyle.primary => 'buttonStylePrimary',
    _RichButtonStyle.success => 'buttonStyleSuccess',
    _RichButtonStyle.danger => 'buttonStyleDanger',
  };

  String get labelKey => switch (this) {
    _RichButtonStyle.standard =>
      AppStringKeys.richTextComposerButtonStyleDefault,
    _RichButtonStyle.primary =>
      AppStringKeys.richTextComposerButtonStylePrimary,
    _RichButtonStyle.success =>
      AppStringKeys.richTextComposerButtonStyleSuccess,
    _RichButtonStyle.danger => AppStringKeys.richTextComposerButtonStyleDanger,
  };
}

class _RichTableActionsMenu extends StatefulWidget {
  const _RichTableActionsMenu({
    required this.anchor,
    required this.canAddColumn,
    required this.canRemoveRow,
    required this.canRemoveColumn,
    required this.onTableAction,
  });

  final Offset anchor;
  final bool canAddColumn;
  final bool canRemoveRow;
  final bool canRemoveColumn;
  final ValueChanged<_RichTableMenuAction> onTableAction;

  @override
  State<_RichTableActionsMenu> createState() => _RichTableActionsMenuState();
}

class _RichTableActionsMenuState extends State<_RichTableActionsMenu> {
  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screen = media.size;
    final menuWidth = math.min(390.0, screen.width - 24);
    final maxHeight = math.min(
      360.0,
      screen.height - media.padding.top - media.padding.bottom - 20,
    );
    final left = (widget.anchor.dx - menuWidth / 2)
        .clamp(12.0, math.max(12.0, screen.width - menuWidth - 12))
        .toDouble();
    final safeTop = media.padding.top + 8;
    final top = (widget.anchor.dy - 42)
        .clamp(safeTop, math.max(safeTop, screen.height - maxHeight - 12))
        .toDouble();

    return SizedBox.expand(
      child: Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            width: menuWidth,
            height: maxHeight,
            child: TextFieldTapRegion(child: _tableActionsPanel()),
          ),
        ],
      ),
    );
  }

  Widget _tableActionsPanel() {
    return _RichContextMenuSurface(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _tableActionRow(
            _RichTableMenuAction.addRowAbove,
            AppStringKeys.richTextTableAddRowAbove,
            const _RichTableInsertIcon(HeroAppIcons.arrowUp),
          ),
          _tableActionRow(
            _RichTableMenuAction.addRowBelow,
            AppStringKeys.richTextTableAddRowBelow,
            const _RichTableInsertIcon(HeroAppIcons.arrowDown),
          ),
          _tableActionRow(
            _RichTableMenuAction.addColumnLeft,
            AppStringKeys.richTextTableAddColumnLeft,
            const _RichTableInsertIcon(HeroAppIcons.arrowLeft),
            enabled: widget.canAddColumn,
          ),
          _tableActionRow(
            _RichTableMenuAction.addColumnRight,
            AppStringKeys.richTextTableAddColumnRight,
            const _RichTableInsertIcon(HeroAppIcons.arrowRight),
            enabled: widget.canAddColumn,
          ),
          const _RichContextMenuDivider(),
          _tableActionRow(
            _RichTableMenuAction.removeRow,
            AppStringKeys.richTextComposerRemoveRow,
            _menuIcon(HeroAppIcons.trash),
            enabled: widget.canRemoveRow,
            destructive: true,
          ),
          _tableActionRow(
            _RichTableMenuAction.removeColumn,
            AppStringKeys.richTextComposerRemoveColumn,
            _menuIcon(HeroAppIcons.trash),
            enabled: widget.canRemoveColumn,
            destructive: true,
          ),
          _tableActionRow(
            _RichTableMenuAction.removeTable,
            AppStringKeys.richTextComposerRemoveTable,
            _menuIcon(HeroAppIcons.trash),
            destructive: true,
          ),
        ],
      ),
    );
  }

  Widget _menuIcon(AppIconData icon) =>
      AppIcon(icon, size: 21, color: context.colors.textPrimary);

  Widget _tableActionRow(
    _RichTableMenuAction action,
    String labelKey,
    Widget leading, {
    bool enabled = true,
    bool checked = false,
    bool destructive = false,
  }) {
    return _RichContextMenuRow(
      label: labelKey.l10n(context),
      leading: leading,
      trailing: checked
          ? AppIcon(HeroAppIcons.check, size: 20, color: AppTheme.brand)
          : null,
      enabled: enabled,
      destructive: destructive,
      onTap: enabled ? () => widget.onTableAction(action) : null,
    );
  }
}

class _RichContextMenuSurface extends StatelessWidget {
  const _RichContextMenuSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.divider, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _RichContextMenuRow extends StatelessWidget {
  const _RichContextMenuRow({
    required this.label,
    this.leading,
    this.trailing,
    this.onTap,
    this.enabled = true,
    this.destructive = false,
  });

  final String label;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final active = enabled && onTap != null;
    final color = !active
        ? c.textTertiary
        : destructive
        ? const Color(0xFFFF5A52)
        : c.textPrimary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: active ? onTap : null,
      child: Container(
        height: 48,
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            if (leading case final leading?) ...[
              SizedBox(width: 26, child: Center(child: leading)),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 16,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            if (trailing case final trailing?) ...[
              const SizedBox(width: 10),
              trailing,
            ],
          ],
        ),
      ),
    );
  }
}

class _RichContextMenuDivider extends StatelessWidget {
  const _RichContextMenuDivider();

  @override
  Widget build(BuildContext context) => Container(
    height: 0.5,
    margin: const EdgeInsets.symmetric(vertical: 4),
    color: context.colors.divider,
  );
}

class _RichTableInsertIcon extends StatelessWidget {
  const _RichTableInsertIcon(this.direction);

  final AppIconData direction;

  @override
  Widget build(BuildContext context) {
    final color = context.colors.textPrimary;
    return SizedBox(
      width: 26,
      height: 26,
      child: Stack(
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: AppIcon(direction, size: 21, color: color),
          ),
          Positioned(
            right: 0,
            bottom: -1,
            child: Text(
              '+',
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                height: 1,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _RichInlineFormatAction {
  spoiler('textEntityTypeSpoiler'),
  bold('textEntityTypeBold'),
  italic('textEntityTypeItalic'),
  monospace('textEntityTypeCode'),
  link(''),
  strikethrough('textEntityTypeStrikethrough'),
  underline('textEntityTypeUnderline');

  const _RichInlineFormatAction(this.entityType);
  final String entityType;
  String get selectionEntityType => switch (this) {
    link => 'textEntityTypeTextUrl',
    _ => entityType,
  };

  String get labelKey => switch (this) {
    spoiler => AppStringKeys.richTextComposerFormatSpoiler,
    bold => AppStringKeys.richTextComposerFormatBold,
    italic => AppStringKeys.richTextComposerFormatItalic,
    monospace => AppStringKeys.richTextComposerFormatCode,
    link => AppStringKeys.composerFormatLink,
    strikethrough => AppStringKeys.richTextComposerFormatStrikethrough,
    underline => AppStringKeys.richTextComposerFormatUnderline,
  };
}

enum _RichBlockAction { moveUp, moveDown, delete }

class _RichBlockActionMenu extends StatelessWidget {
  const _RichBlockActionMenu({
    required this.anchor,
    required this.canMoveUp,
    required this.canMoveDown,
  });

  final Offset anchor;
  final bool canMoveUp;
  final bool canMoveDown;

  @override
  Widget build(BuildContext context) {
    return _RichAnchoredMenu(
      anchor: anchor,
      width: 184,
      maxHeight: 150,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RichMenuRow(
            label: AppStringKeys.richTextComposerMoveUp.l10n(context),
            onTap: canMoveUp
                ? () => Navigator.of(context).pop(_RichBlockAction.moveUp)
                : null,
          ),
          _RichMenuRow(
            label: AppStringKeys.richTextComposerMoveDown.l10n(context),
            onTap: canMoveDown
                ? () => Navigator.of(context).pop(_RichBlockAction.moveDown)
                : null,
          ),
          _RichMenuRow(
            label: AppStringKeys.richTextComposerRemoveBlock.l10n(context),
            destructive: true,
            onTap: () => Navigator.of(context).pop(_RichBlockAction.delete),
          ),
        ],
      ),
    );
  }
}

class _RichInlineFormatMenu extends StatelessWidget {
  const _RichInlineFormatMenu({
    required this.anchor,
    required this.appliedFormats,
  });
  final Offset anchor;
  final Set<_RichInlineFormatAction> appliedFormats;

  @override
  Widget build(BuildContext context) {
    return _RichAnchoredMenu(
      anchor: anchor,
      width: 232,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final action in _RichInlineFormatAction.values)
            _RichMenuRow(
              key: ValueKey('rich-format-${action.name}'),
              label: action.labelKey.l10n(context),
              checked: appliedFormats.contains(action),
              onTap: () => Navigator.of(context).pop(action),
            ),
        ],
      ),
    );
  }
}

class _RichBlockInsertMenu extends StatelessWidget {
  const _RichBlockInsertMenu({required this.anchor});
  final Offset anchor;

  @override
  Widget build(BuildContext context) {
    final kinds = _RichBlockKind.values
        .where(
          (kind) =>
              kind != _RichBlockKind.document &&
              kind != _RichBlockKind.thinking,
        )
        .toList(growable: false);
    final menuWidth = math.min(360.0, MediaQuery.sizeOf(context).width - 24);
    return _RichAnchoredMenu(
      anchor: anchor,
      width: menuWidth,
      maxHeight: 520,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: Text(
              AppStringKeys.richTextComposerInsert.l10n(context),
              style: AppTextStyle.callout(
                context.colors.textSecondary,
                weight: AppTextWeight.semibold,
              ),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              child: Wrap(
                children: [
                  for (final kind in kinds)
                    SizedBox(
                      width: (menuWidth - 12) / 2,
                      child: _RichMenuRow(
                        key: ValueKey('rich-insert-${kind.name}'),
                        icon: kind.icon,
                        label: kind.labelKey.l10n(context),
                        compact: true,
                        onTap: () => Navigator.of(context).pop(kind),
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
}

class _RichAnchoredMenu extends StatelessWidget {
  const _RichAnchoredMenu({
    required this.anchor,
    required this.width,
    required this.child,
    this.maxHeight = 440,
  });

  final Offset anchor;
  final double width;
  final double maxHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final media = MediaQuery.of(context);
    final screen = media.size;
    final left = (anchor.dx - width / 2)
        .clamp(12.0, math.max(12.0, screen.width - width - 12))
        .toDouble();
    final top = (anchor.dy - maxHeight - 10)
        .clamp(
          media.padding.top + 8,
          math.max(media.padding.top + 8, screen.height - maxHeight - 12),
        )
        .toDouble();
    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          width: width,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: c.divider, width: 0.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: child,
            ),
          ),
        ),
      ],
    );
  }
}

class _RichMenuRow extends StatelessWidget {
  const _RichMenuRow({
    super.key,
    required this.label,
    this.onTap,
    this.compact = false,
    this.destructive = false,
    this.icon,
    this.checked = false,
  });
  final String label;
  final VoidCallback? onTap;
  final bool compact;
  final bool destructive;
  final AppIconData? icon;
  final bool checked;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: compact ? 48 : 44,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 18),
            child: Row(
              children: [
                if (icon case final icon?) ...[
                  AppIcon(
                    icon,
                    size: 18,
                    color: onTap == null
                        ? context.colors.textTertiary
                        : AppTheme.brand,
                  ),
                  const SizedBox(width: 9),
                ],
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compact ? 14 : 16,
                      fontWeight: AppTextWeight.regular,
                      color: onTap == null
                          ? context.colors.textTertiary
                          : destructive
                          ? const Color(0xFFFF5A52)
                          : context.colors.textPrimary,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                if (checked) ...[
                  const SizedBox(width: 8),
                  AppIcon(HeroAppIcons.check, size: 19, color: AppTheme.brand),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RichValueDialog extends StatefulWidget {
  const _RichValueDialog({required this.title, required this.hint});
  final String title;
  final String hint;

  @override
  State<_RichValueDialog> createState() => _RichValueDialogState();
}

class _RichValueDialogState extends State<_RichValueDialog> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Container(
        width: math.min(360, MediaQuery.sizeOf(context).width - 40),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title.l10n(context),
              style: AppTextStyle.title(c.textPrimary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              onSubmitted: _submit,
              style: AppTextStyle.body(c.textPrimary),
              decoration: InputDecoration(
                filled: true,
                fillColor: c.searchFill,
                border: InputBorder.none,
                hintText: widget.hint.l10n(context),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _submit(controller.text),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    AppStringKeys.composerFormatApply.l10n(context),
                    style: AppTextStyle.callout(
                      AppTheme.brand,
                      weight: AppTextWeight.semibold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _submit(String value) {
    if (value.trim().isEmpty) return;
    Navigator.of(context).pop(value.trim());
  }
}
