part of 'chat_list_view.dart';

class _DesktopTitleBarPlusMenuOverlay extends StatelessWidget {
  const _DesktopTitleBarPlusMenuOverlay({
    required this.anchor,
    required this.onDismiss,
    required this.child,
  });

  /// Gap between the button and the menu below it.
  static const _gap = 6.0;

  final Rect anchor;
  final VoidCallback onDismiss;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    // Right-aligned to the button, and only pulled back if that would run the
    // menu off an edge — a button already at the window edge should still get
    // an exactly aligned menu.
    // Must match the width PlusMenu actually renders, which is denser on a
    // pointer — otherwise the menu no longer lines up with its button.
    final width = AppMetric.popupMenuWidth();
    final maxLeft = (screen.width - width).clamp(0.0, double.infinity);
    final left = (anchor.right - width).clamp(0.0, maxLeft);

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            child: const ColoredBox(color: Color(0x14000000)),
          ),
        ),
        Positioned(
          left: left,
          top: anchor.bottom + _gap,
          child: TweenAnimationBuilder<double>(
            duration: AppMotion.duration(context, AppMotion.responsive),
            curve: AppMotion.emphasized,
            tween: Tween(begin: 0, end: 1),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: child,
            ),
            builder: (context, progress, child) => Opacity(
              opacity: progress,
              child: Transform.translate(
                offset: Offset(0, -6 * (1 - progress)),
                child: Transform.scale(
                  alignment: Alignment.topRight,
                  scale: 0.96 + 0.04 * progress,
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Keeps anchored menus mounted through their reverse animation so the
/// barrier, hit testing, and menu surface leave as one coherent motion.
class _AnimatedAnchoredMenuOverlay extends StatefulWidget {
  const _AnimatedAnchoredMenuOverlay({
    required this.visible,
    required this.top,
    required this.onDismiss,
    required this.child,
  });

  final bool visible;
  final double top;
  final VoidCallback onDismiss;
  final Widget child;

  @override
  State<_AnimatedAnchoredMenuOverlay> createState() =>
      _AnimatedAnchoredMenuOverlayState();
}

class _AnimatedAnchoredMenuOverlayState
    extends State<_AnimatedAnchoredMenuOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.responsive,
    reverseDuration: AppMotion.quick,
    value: widget.visible ? 1 : 0,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncDuration();
    if (AppMotion.isReduced(context)) {
      _controller.value = widget.visible ? 1 : 0;
    }
  }

  @override
  void didUpdateWidget(covariant _AnimatedAnchoredMenuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncDuration();
    if (oldWidget.visible == widget.visible) return;
    if (AppMotion.isReduced(context)) {
      _controller.value = widget.visible ? 1 : 0;
    } else if (widget.visible) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  void _syncDuration() {
    _controller.duration = AppMotion.duration(context, AppMotion.responsive);
    _controller.reverseDuration = AppMotion.duration(context, AppMotion.quick);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (context, child) {
          if (_controller.isDismissed) return const SizedBox.shrink();
          final progress = AppMotion.emphasized.transform(_controller.value);
          return IgnorePointer(
            ignoring: _controller.value == 0,
            child: ExcludeSemantics(
              excluding: _controller.value == 0,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onDismiss,
                      child: ColoredBox(
                        color: Colors.black.withValues(
                          alpha: 0.12 * _controller.value,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(top: widget.top, right: 10),
                    child: Align(
                      alignment: Alignment.topRight,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {},
                        child: Opacity(
                          opacity: progress,
                          child: Transform.translate(
                            offset: Offset(0, -8 * (1 - progress)),
                            child: Transform.scale(
                              alignment: Alignment.topRight,
                              scale: 0.94 + 0.06 * progress,
                              child: child,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ChatRowPlaceholder extends StatelessWidget {
  const _ChatRowPlaceholder();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rowHeight = chatListRowExtentFor(context);
    return SizedBox(
      height: rowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: Row(
          children: [
            Container(
              width: AppMetric.avatarSize,
              height: AppMetric.avatarSize,
              decoration: BoxDecoration(
                color: c.searchFill,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FractionallySizedBox(
                    widthFactor: 0.34,
                    child: _PlaceholderBar(height: 16, color: c.searchFill),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  FractionallySizedBox(
                    widthFactor: 0.68,
                    child: _PlaceholderBar(height: 13, color: c.searchFill),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            _PlaceholderBar(width: 44, height: 12, color: c.searchFill),
          ],
        ),
      ),
    );
  }
}

class _CommunityDirectoryView extends StatelessWidget {
  const _CommunityDirectoryView({required this.entries, required this.onOpen});

  final List<CommunityGroupEntry> entries;
  final ValueChanged<CommunityGroupEntry> onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: [
          NavHeader(
            title: AppStringKeys.communityTitle,
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    Navigator.of(context).pop();
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      onOpen(entry);
                    });
                  },
                  child: CommunityChatListRow(entry: entry),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaceholderBar extends StatelessWidget {
  const _PlaceholderBar({
    required this.height,
    required this.color,
    this.width,
  });

  final double? width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(height / 2),
      ),
    );
  }
}

/// Reference-style "+" dropdown of create actions.
class PlusMenu extends StatelessWidget {
  const PlusMenu({
    super.key,
    required this.onSelect,
    this.showCommunities = false,
  });
  final ValueChanged<String> onSelect;
  final bool showCommunities;

  static const _baseItems = [
    (HeroAppIcons.magnifyingGlass, AppStringKeys.topicChatSearch),
    (HeroAppIcons.qrcode, AppStringKeys.chatListScanQrCode),
    (HeroAppIcons.circlePlus, AppStringKeys.chatListCreateGroup),
    (HeroAppIcons.grip, AppStringKeys.chatListCreateChannel),
    (HeroAppIcons.userPlus, AppStringKeys.chatListAddFriendOrGroup),
  ];

  /// Community sits right after search (the user's pinned ordering), ahead
  /// of every create action, and only when the section has content.
  List<(AppIconData, String)> get _items => [
    _baseItems.first,
    if (showCommunities)
      (HeroAppIcons.objectGroup, AppStringKeys.communityTitle),
    ..._baseItems.skip(1),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final inset = AppMetric.popupMenuInset();
    return Material(
      color: Colors.transparent,
      child: Container(
        width: AppMetric.popupMenuWidth(),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          // The card and the empty content area behind it are the same colour
          // in the light theme, so without an edge the menu did not read as a
          // surface at all.
          border: Border.all(color: c.divider, width: 0.75),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in _items)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelect(item.$2),
                child: SizedBox(
                  height: AppMetric.popupMenuRowHeight(),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: inset),
                    child: Row(
                      children: [
                        SizedBox(
                          width: AppMetric.popupMenuIconSlot(),
                          child: AppIcon(
                            item.$1,
                            size: AppMetric.popupMenuIconSlot() - 3,
                            color: c.textPrimary,
                          ),
                        ),
                        SizedBox(width: inset * 0.75),
                        Expanded(
                          child: Text(
                            item.$2.l10n(context),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: AppMetric.popupMenuTextSize(),
                              color: c.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ChatFilterMenu extends StatelessWidget {
  const ChatFilterMenu({
    super.key,
    required this.filters,
    required this.selected,
    required this.onSelect,
  });

  final List<ChatFilterOption> filters;
  final ChatFilterOption selected;
  final ValueChanged<ChatFilterOption> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: Colors.transparent,
      child: Container(
        width: AppMetric.popupMenuWidth(),
        constraints: const BoxConstraints(maxHeight: 360),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ListView.builder(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          itemCount: filters.length,
          itemBuilder: (context, index) {
            final filter = filters[index];
            final selectedFilter = filter.folderId == selected.folderId;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelect(filter),
              child: SizedBox(
                height: AppMetric.popupMenuRowHeight(),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppMetric.popupMenuInset(),
                  ),
                  child: Row(
                    children: [
                      ChatFolderIcon(
                        filter.isAll ? 'All' : filter.iconName,
                        size: AppMetric.popupMenuIconSlot() - 3,
                        color: c.textPrimary,
                      ),
                      SizedBox(width: AppMetric.popupMenuInset() * 0.75),
                      Expanded(
                        child: Text(
                          filter.title.l10n(context),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppMetric.popupMenuTextSize(),
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                      if (selectedFilter)
                        AppIcon(
                          HeroAppIcons.check,
                          size: AppMetric.popupMenuIconSlot() - 4,
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
    );
  }
}

// MARK: - custom swipe row

/// Resolves a pointer-anchored desktop menu without allowing it to escape the
/// visible overlay. The two-pixel offset keeps the pointer clear of the first
/// action while preserving the exact click location as the anchor.
Offset desktopChatContextMenuTopLeft({
  required Offset anchor,
  required Size viewport,
  required Size menuSize,
  double margin = DesktopChatContextMenu.viewportMargin,
}) {
  final requested = anchor + const Offset(2, 2);
  final maxX = math.max(margin, viewport.width - menuSize.width - margin);
  final maxY = math.max(margin, viewport.height - menuSize.height - margin);
  return Offset(
    requested.dx.clamp(margin, maxX).toDouble(),
    requested.dy.clamp(margin, maxY).toDouble(),
  );
}

/// Compact, project-owned context menu used only by native desktop chat rows.
class DesktopChatContextMenu extends StatelessWidget {
  const DesktopChatContextMenu({
    super.key,
    required this.anchor,
    required this.isPinned,
    required this.hasUnread,
    required this.isMuted,
    required this.deleteOrLeaveLabel,
    required this.onDismiss,
    required this.onTogglePin,
    required this.onToggleRead,
    required this.onToggleMute,
    required this.onDeleteOrLeave,
    required this.onArchive,
    this.onOpenSeparateWindow,
  });

  static const double menuWidth = 232;
  static const double rowHeight = 38;
  static const double verticalPadding = 4;
  static const double dividerHeight = 0.5;
  static const double viewportMargin = 8;

  final Offset anchor;
  final bool isPinned;
  final bool hasUnread;
  final bool isMuted;
  final String deleteOrLeaveLabel;
  final VoidCallback onDismiss;
  final VoidCallback onTogglePin;
  final VoidCallback onToggleRead;
  final VoidCallback? onOpenSeparateWindow;
  final VoidCallback onToggleMute;
  final VoidCallback onDeleteOrLeave;
  final VoidCallback onArchive;

  double get _menuHeight =>
      verticalPadding * 2 +
      rowHeight * (onOpenSeparateWindow == null ? 5 : 6) +
      dividerHeight;

  void _select(VoidCallback action) {
    onDismiss();
    action();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        final resolvedWidth = math
            .min(menuWidth, math.max(0.0, viewport.width - viewportMargin * 2))
            .toDouble();
        final menuSize = Size(resolvedWidth, _menuHeight);
        final topLeft = desktopChatContextMenuTopLeft(
          anchor: anchor,
          viewport: viewport,
          menuSize: menuSize,
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              key: const ValueKey('desktop-chat-context-barrier'),
              behavior: HitTestBehavior.opaque,
              onTap: onDismiss,
              onSecondaryTap: onDismiss,
              child: const ColoredBox(color: Colors.transparent),
            ),
            Positioned(
              left: topLeft.dx,
              top: topLeft.dy,
              child: Container(
                key: const ValueKey('desktop-chat-context-menu'),
                width: resolvedWidth,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.card,
                      border: Border.all(color: c.divider, width: 0.5),
                      borderRadius: BorderRadius.circular(AppRadius.control),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: verticalPadding,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _DesktopChatContextMenuItem(
                            key: const ValueKey('desktop-chat-context-pin'),
                            icon: HeroAppIcons.thumbtack,
                            label: isPinned
                                ? AppStringKeys.chatListUnpin
                                : AppStringKeys.chatInfoPin,
                            onTap: () => _select(onTogglePin),
                          ),
                          _DesktopChatContextMenuItem(
                            key: const ValueKey('desktop-chat-context-read'),
                            icon: hasUnread
                                ? HeroAppIcons.circleCheck
                                : HeroAppIcons.eyeSlash,
                            label: hasUnread
                                ? AppStringKeys.channelDirectMessagesMarkRead
                                : AppStringKeys.chatListMarkUnread,
                            onTap: () => _select(onToggleRead),
                          ),
                          if (onOpenSeparateWindow case final openSeparate?)
                            _DesktopChatContextMenuItem(
                              key: const ValueKey(
                                'desktop-chat-context-separate',
                              ),
                              icon: HeroAppIcons.pictureInPicture,
                              label: AppStringKeys.desktopChatOpenSeparate,
                              onTap: () => _select(openSeparate),
                            ),
                          _DesktopChatContextMenuItem(
                            key: const ValueKey('desktop-chat-context-mute'),
                            icon: isMuted
                                ? HeroAppIcons.bell
                                : HeroAppIcons.bellSlash,
                            label: isMuted
                                ? AppStringKeys.chatUnmute
                                : AppStringKeys.callMute,
                            onTap: () => _select(onToggleMute),
                          ),
                          _DesktopChatContextMenuItem(
                            key: const ValueKey('desktop-chat-context-archive'),
                            icon: HeroAppIcons.archiveBox,
                            label: AppStringKeys.chatListArchive,
                            onTap: () => _select(onArchive),
                          ),
                          SizedBox(
                            height: dividerHeight,
                            child: ColoredBox(color: c.divider),
                          ),
                          _DesktopChatContextMenuItem(
                            key: const ValueKey('desktop-chat-context-delete'),
                            icon: HeroAppIcons.trash,
                            label: deleteOrLeaveLabel,
                            color: const Color(0xFFFA5151),
                            onTap: () => _select(onDeleteOrLeave),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DesktopChatContextMenuItem extends StatelessWidget {
  const _DesktopChatContextMenuItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final AppIconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedLabel = label.l10n(context);
    final foreground = color ?? context.colors.textPrimary;
    return AppInteractiveSurface(
      semanticLabel: resolvedLabel,
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: SizedBox(
        height: DesktopChatContextMenu.rowHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Row(
            children: [
              SizedBox(
                width: AppMetric.menuIconSlot,
                child: AppIcon(icon, size: 18, color: foreground),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  resolvedLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    fontSize: AppTextSize.callout,
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SwipeActionItem {
  SwipeActionItem({
    required this.title,
    required this.color,
    required this.onTap,
  });
  final String title;
  final Color color;
  final VoidCallback onTap;
}

/// Wraps a chat row so a left-swipe reveals flush, full-height action blocks.
/// Only one row stays open at a time, coordinated through [openRowId].
class ChatSwipeRow extends StatefulWidget {
  const ChatSwipeRow({
    super.key,
    required this.rowId,
    required this.openRowId,
    required this.onOpenChanged,
    required this.actions,
    required this.onTap,
    required this.child,
    this.onLongPress,
    this.onLongPressAt,
    this.dragReorderEnabled = false,
    this.onDragReorderStart,
    this.onDragReorderMove,
    this.onDragReorderSlot,
    this.onDragReorderEnd,
    this.contentVisible = true,
    this.onSecondaryTapDown,
    this.requiresLongPressDrag = false,
    this.horizontalSwipeEnabled = true,
    this.pressRippleEnabled = true,
    this.suppressEndLongPress = false,
  });

  final int rowId;
  final int? openRowId;
  final ValueChanged<int?> onOpenChanged;
  final List<SwipeActionItem> actions;
  final VoidCallback onTap;
  final Widget child;
  final VoidCallback? onLongPress;

  /// Long-press with the press coordinates, so the host can split the gesture
  /// by hit region (the reference client peeks only from the avatar).
  final void Function(Offset localPosition)? onLongPressAt;

  /// Edit-mode pinned reorder (the reference client's action-mode ItemTouchHelper drag):
  /// when enabled, a long press that moves vertically drags the row over its
  /// pinned neighbours, reporting each crossed slot so the host can swap.
  final bool dragReorderEnabled;

  /// The drag lifted: the host raises an overlay proxy of the row (the reference client
  /// draws the dragged cell above the list through ItemTouchHelper's overdraw
  /// child + elevation) and hides this row's content.
  final void Function(Offset globalTopLeft, Size size)? onDragReorderStart;

  /// The finger moved [dy] pixels vertically from the press origin. Pure
  /// position report — the host drives the proxy from it without rebuilding
  /// the list.
  final void Function(double dy)? onDragReorderMove;

  /// [slots] is signed: +1 one slot down, -1 one slot up, reported once per
  /// crossed row extent.
  final void Function(int slots)? onDragReorderSlot;

  /// The finger came up: the host commits the accumulated swaps here (one
  /// setPinnedChats per drag, like the reference client commits reorderPinnedDialogs on
  /// drop — never per crossed slot).
  final VoidCallback? onDragReorderEnd;

  /// False while the drag proxy draws this row above the list — the row keeps
  /// its slot, size and gesture, only its pixels move to the proxy.
  final bool contentVisible;
  final GestureTapDownCallback? onSecondaryTapDown;
  final bool requiresLongPressDrag;
  final bool horizontalSwipeEnabled;
  final bool pressRippleEnabled;

  /// the reference client's allowMoving split: the long press that OPENS edit mode must
  /// do nothing when the finger lifts (the mode stays); only later presses
  /// toggle membership or drag. The host sets this on the row whose press
  /// opened the mode, for the lifetime of that one gesture.
  final bool suppressEndLongPress;

  @override
  State<ChatSwipeRow> createState() => _ChatSwipeRowState();
}

class _ChatSwipeRowState extends State<ChatSwipeRow>
    with SingleTickerProviderStateMixin {
  static const double _buttonWidth = 80;
  // Created eagerly in initState so the Ticker is bound while the context is
  // active — a lazy `late` initializer would run on first access in dispose()
  // (for never-swiped rows) and crash on a deactivated-ancestor TickerMode lookup.
  late final AnimationController _controller;
  Animation<double>? _animation;
  VoidCallback? _animationListener;
  double _offset = 0;
  double _longPressStartOffset = 0;
  Offset? _pendingLongPressAt;
  double _dragConsumed = 0;
  bool _dragReorderActive = false;
  int? _desktopTouchPointer;
  Offset? _desktopTouchOrigin;
  double _desktopTouchStartOffset = 0;
  VelocityTracker? _desktopTouchVelocity;
  Timer? _desktopTouchLongPressTimer;
  bool _desktopTouchHorizontal = false;
  bool _desktopTouchLongPressTriggered = false;

  double get _totalWidth => widget.actions.length * _buttonWidth;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.responsive,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = AppMotion.duration(context, AppMotion.responsive);
  }

  @override
  void didUpdateWidget(ChatSwipeRow old) {
    super.didUpdateWidget(old);
    final horizontalSwipeWasDisabled =
        old.horizontalSwipeEnabled && !widget.horizontalSwipeEnabled;
    if (horizontalSwipeWasDisabled && widget.openRowId == widget.rowId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            !widget.horizontalSwipeEnabled &&
            widget.openRowId == widget.rowId) {
          widget.onOpenChanged(null);
        }
      });
    }
    // Snap shut when horizontal actions are disabled or another row opens.
    if (_offset != 0 &&
        (horizontalSwipeWasDisabled || widget.openRowId != widget.rowId)) {
      _animateTo(0);
    }
  }

  @override
  void dispose() {
    _desktopTouchLongPressTimer?.cancel();
    _clearAnimation();
    _controller.dispose();
    super.dispose();
  }

  void _clearAnimation() {
    final animation = _animation;
    final listener = _animationListener;
    if (animation != null && listener != null) {
      animation.removeListener(listener);
    }
    _animation = null;
    _animationListener = null;
  }

  void _stopAnimation() {
    _controller.stop();
    _clearAnimation();
  }

  void _animateTo(double target) {
    _stopAnimation();
    if (AppMotion.isReduced(context)) {
      setState(() => _offset = target);
      return;
    }
    final anim = Tween<double>(
      begin: _offset,
      end: target,
    ).animate(CurvedAnimation(parent: _controller, curve: AppMotion.standard));
    void listener() => setState(() => _offset = anim.value);
    _animation = anim;
    _animationListener = listener;
    _controller.reset();
    anim.addListener(listener);
    _controller.forward().whenComplete(() {
      _clearAnimation();
      _offset = target;
    });
  }

  double _rubberBandOffset(double value) {
    if (value >= -_totalWidth && value <= 0) return value;
    if (value < -_totalWidth) {
      final extra = -value - _totalWidth;
      return -_totalWidth - extra * 0.28;
    }
    return value * 0.28;
  }

  void _close() {
    _animateTo(0);
    if (widget.openRowId == widget.rowId) widget.onOpenChanged(null);
  }

  void _handleDragReorderMove(LongPressMoveUpdateDetails details) {
    final dy = details.offsetFromOrigin.dy;
    if (!_dragReorderActive) {
      // A long press that has not moved vertically stays a plain long press;
      // a small threshold makes the drag take over.
      if (dy.abs() < 12) return;
      _dragReorderActive = true;
      _dragConsumed = 0;
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) return;
      widget.onDragReorderStart?.call(box.localToGlobal(Offset.zero), box.size);
    }
    final rowExtent = context.size?.height ?? 0;
    if (rowExtent > 0) {
      // Hysteresis: a slot swaps once the finger has travelled half a row
      // past the last consumed slot, and only one slot per event. Consuming
      // a full row extent per swap keeps the next swap a full row away, so
      // jitter around the midpoint cannot re-fire and cascade the row to the
      // end of the band.
      final residual = dy - _dragConsumed;
      if (residual.abs() > rowExtent / 2) {
        final slots = residual > 0 ? 1 : -1;
        _dragConsumed += slots * rowExtent;
        widget.onDragReorderSlot?.call(slots);
      }
    }
    // The overlay proxy follows the finger; the row itself keeps its slot
    // for the whole drag, so no rebuild interrupts the gesture.
    widget.onDragReorderMove?.call(dy);
  }

  void _endDragReorder() {
    if (!_dragReorderActive) return;
    _dragReorderActive = false;
    widget.onDragReorderEnd?.call();
  }

  void _handleContextRequest() {
    if (_offset != 0) {
      _close();
      return;
    }
    final position = _pendingLongPressAt;
    _pendingLongPressAt = null;
    final longPressAt = widget.onLongPressAt;
    if (longPressAt != null && position != null) {
      longPressAt(position);
      return;
    }
    widget.onLongPress?.call();
  }

  void _handleSecondaryTapDown(TapDownDetails details) {
    if (_offset != 0) _close();
    widget.onSecondaryTapDown?.call(details);
  }

  bool _supportsDesktopTouchGestures(TargetPlatform platform) =>
      widget.onSecondaryTapDown != null &&
      (platform == TargetPlatform.windows || platform == TargetPlatform.linux);

  void _handleDesktopTouchPointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    if (_desktopTouchPointer != null) {
      _cancelDesktopTouchGesture();
      return;
    }
    _desktopTouchPointer = event.pointer;
    _desktopTouchOrigin = event.position;
    _desktopTouchStartOffset = _offset;
    _desktopTouchVelocity = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
    _desktopTouchHorizontal = false;
    _desktopTouchLongPressTriggered = false;
    _desktopTouchLongPressTimer = Timer(
      kLongPressTimeout + const Duration(milliseconds: 30),
      _handleDesktopTouchLongPress,
    );
  }

  void _handleDesktopTouchPointerMove(PointerMoveEvent event) {
    if (_desktopTouchPointer != event.pointer) return;
    _desktopTouchVelocity?.addPosition(event.timeStamp, event.position);
    final origin = _desktopTouchOrigin;
    if (origin == null || _desktopTouchLongPressTriggered) return;
    final travel = event.position - origin;
    if (!_desktopTouchHorizontal) {
      if (travel.dx.abs() < kTouchSlop && travel.dy.abs() < kTouchSlop) return;
      _desktopTouchLongPressTimer?.cancel();
      _desktopTouchLongPressTimer = null;
      if (travel.dy.abs() >= travel.dx.abs() ||
          !widget.horizontalSwipeEnabled ||
          widget.requiresLongPressDrag) {
        _cancelDesktopTouchGesture();
        return;
      }
      _desktopTouchHorizontal = true;
      _stopAnimation();
    }
    setState(() {
      _offset = _rubberBandOffset(_desktopTouchStartOffset + travel.dx);
    });
  }

  void _handleDesktopTouchPointerUp(PointerUpEvent event) {
    if (_desktopTouchPointer != event.pointer) return;
    _desktopTouchLongPressTimer?.cancel();
    _desktopTouchVelocity?.addPosition(event.timeStamp, event.position);
    if (_desktopTouchHorizontal) {
      _settle(_desktopTouchVelocity?.getVelocity().pixelsPerSecond.dx ?? 0);
    }
    _resetDesktopTouchGesture();
  }

  void _handleDesktopTouchPointerCancel(PointerCancelEvent event) {
    if (_desktopTouchPointer != event.pointer) return;
    if (_desktopTouchHorizontal) _animateTo(_desktopTouchStartOffset);
    _resetDesktopTouchGesture();
  }

  void _handleDesktopTouchLongPress() {
    final position = _desktopTouchOrigin;
    if (!mounted || _desktopTouchPointer == null || position == null) return;
    _desktopTouchLongPressTimer = null;
    _desktopTouchLongPressTriggered = true;
    _handleSecondaryTapDown(
      TapDownDetails(globalPosition: position, kind: PointerDeviceKind.touch),
    );
  }

  void _cancelDesktopTouchGesture() {
    if (_desktopTouchHorizontal) _animateTo(_desktopTouchStartOffset);
    _desktopTouchLongPressTimer?.cancel();
    _resetDesktopTouchGesture();
  }

  void _resetDesktopTouchGesture() {
    _desktopTouchLongPressTimer?.cancel();
    _desktopTouchLongPressTimer = null;
    _desktopTouchPointer = null;
    _desktopTouchOrigin = null;
    _desktopTouchVelocity = null;
    _desktopTouchHorizontal = false;
    _desktopTouchLongPressTriggered = false;
  }

  void _settle(double velocity) {
    if (velocity < -520 || (velocity <= 360 && _offset < -_totalWidth * 0.38)) {
      _animateTo(-_totalWidth);
      widget.onOpenChanged(widget.rowId);
    } else {
      _animateTo(0);
      if (widget.openRowId == widget.rowId) widget.onOpenChanged(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final desktopTouchGestures = _supportsDesktopTouchGestures(
      Theme.of(context).platform,
    );
    final horizontalDragEnabled =
        widget.horizontalSwipeEnabled &&
        !widget.requiresLongPressDrag &&
        !desktopTouchGestures;
    final rowGestureRaw = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _offset != 0 ? _close() : widget.onTap(),
      onLongPress:
          desktopTouchGestures ||
              widget.requiresLongPressDrag ||
              widget.onLongPress == null
          ? null
          : _handleContextRequest,
      onSecondaryTapDown: widget.onSecondaryTapDown == null
          ? null
          : _handleSecondaryTapDown,
      onLongPressStart: (details) {
        _stopAnimation();
        _longPressStartOffset = _offset;
        // the reference client splits the row's long press by hit region: the avatar
        // peeks, the body selects. The plain onLongPress callback stays for
        // hosts that did not opt into the split.
        if (!desktopTouchGestures &&
            !widget.requiresLongPressDrag &&
            widget.onLongPress != null &&
            widget.onLongPressAt != null) {
          _pendingLongPressAt = details.localPosition;
        } else {
          _pendingLongPressAt = null;
        }
      },
      // Wired unconditionally: the recognizer keeps the closure from the
      // build that saw the pointer down, but the State's widget is always
      // the latest — the handler re-reads the flags on every event, so a
      // long press that enters edit mode at its deadline can still drag in
      // the same gesture.
      onLongPressMoveUpdate: (details) {
        if (widget.requiresLongPressDrag) {
          setState(() {
            _offset = _rubberBandOffset(
              _longPressStartOffset + details.localOffsetFromOrigin.dx,
            );
          });
        } else if (widget.dragReorderEnabled) {
          _handleDragReorderMove(details);
        }
      },
      onLongPressEnd: (details) {
        if (widget.requiresLongPressDrag) {
          _settle(details.velocity.pixelsPerSecond.dx);
        } else if (_dragReorderActive) {
          _endDragReorder();
        } else if (widget.dragReorderEnabled && !widget.suppressEndLongPress) {
          // A press that never crossed into a drag still owes its long-press
          // behaviour (edit mode: toggle membership) — except the press that
          // opened the mode: lifting it must keep the mode (allowMoving).
          widget.onLongPress?.call();
        }
      },
      onHorizontalDragStart: !horizontalDragEnabled
          ? null
          : (_) => _stopAnimation(),
      onHorizontalDragUpdate: !horizontalDragEnabled
          ? null
          : (details) {
              setState(
                () => _offset = _rubberBandOffset(_offset + details.delta.dx),
              );
            },
      onHorizontalDragEnd: !horizontalDragEnabled
          ? null
          : (details) => _settle(details.primaryVelocity ?? 0),
      child: widget.child,
    );
    final interactiveRow = desktopTouchGestures
        ? Listener(
            onPointerDown: _handleDesktopTouchPointerDown,
            onPointerMove: _handleDesktopTouchPointerMove,
            onPointerUp: _handleDesktopTouchPointerUp,
            onPointerCancel: _handleDesktopTouchPointerCancel,
            child: rowGestureRaw,
          )
        : rowGestureRaw;
    // At rest the row covers the blocks completely, so building them costs one
    // text layout + one paint per action on every row of every list rebuild.
    final actionsRevealed = _offset != 0 || widget.openRowId == widget.rowId;
    final Widget self = ClipRect(
      child: Stack(
        children: [
          // Revealed action blocks behind the row.
          Positioned.fill(
            child: !actionsRevealed
                ? const SizedBox.shrink()
                : Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      width: _totalWidth,
                      child: Row(
                        children: [
                          for (final item in widget.actions)
                            GestureDetector(
                              onTap: () {
                                item.onTap();
                                _close();
                              },
                              child: Container(
                                width: _buttonWidth,
                                color: item.color,
                                alignment: Alignment.center,
                                child: Text(
                                  item.title.l10n(context),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: AppTextSize.body,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
          ),
          // The row, sliding left to uncover the blocks. While an edit-mode
          // reorder drag is live the row's CONTENT moves to the host's
          // overlay proxy (drawn above the whole list, the reference client's
          // ItemTouchHelper overdraw child + elevation); the row keeps its
          // slot, size and gesture here, so the subtree shape never changes
          // mid-drag and the recognizer survives.
          Transform.translate(
            offset: Offset(_offset, 0),
            child: Material(
              type: MaterialType.transparency,
              child: Visibility(
                visible: widget.contentVisible,
                maintainState: true,
                maintainAnimation: true,
                maintainSize: true,
                maintainInteractivity: true,
                child: widget.pressRippleEnabled
                    ? AppPressRipple(child: interactiveRow)
                    : interactiveRow,
              ),
            ),
          ),
        ],
      ),
    );
    return self;
  }
}
