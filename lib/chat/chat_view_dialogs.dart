part of 'chat_view.dart';

// ignore: unused_element

class ReactionUsersSheetFrame extends StatelessWidget {
  const ReactionUsersSheetFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final centered = appModalUsesCenteredPresentation(
      MediaQuery.sizeOf(context),
    );
    final height = math.min(MediaQuery.sizeOf(context).height * 0.62, 560.0);
    final content = SizedBox(
      height: height,
      width: double.infinity,
      child: Column(
        children: [
          if (centered)
            const SizedBox(height: 8)
          else ...[
            const SizedBox(height: 10),
            Container(
              key: reactionUsersDragHandleKey,
              width: 42,
              height: 5,
              decoration: BoxDecoration(
                color: c.divider,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Expanded(child: child),
        ],
      ),
    );
    if (centered) {
      return ColoredBox(
        key: reactionUsersCenteredFrameKey,
        color: c.card,
        child: content,
      );
    }
    return SafeArea(
      top: false,
      child: Align(
        key: reactionUsersTouchFrameKey,
        alignment: Alignment.bottomCenter,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          child: ColoredBox(color: c.card, child: content),
        ),
      ),
    );
  }
}

@visibleForTesting
bool protectedContentRequiresMobileSelectionClear({
  required bool hasProtectedContent,
  required bool hasSelectionKey,
}) => hasProtectedContent && hasSelectionKey;

@visibleForTesting
bool selectionAreaContainsGlobalTextPosition({
  required GlobalKey<SelectionAreaState> selectionAreaKey,
  required Offset globalPosition,
}) {
  final root = selectionAreaKey.currentContext?.findRenderObject();
  if (root is! RenderBox ||
      !root.attached ||
      !root.hasSize ||
      !(Offset.zero & root.size).contains(root.globalToLocal(globalPosition))) {
    return false;
  }

  bool visibleWithinSelectionArea(RenderParagraph paragraph) {
    RenderObject? current = paragraph;
    while (current != null) {
      if (current case final RenderBox box when box.hasSize) {
        final localPosition = box.globalToLocal(globalPosition);
        if (!(Offset.zero & box.size).contains(localPosition)) return false;
      }
      if (identical(current, root)) return true;
      current = current.parent;
    }
    return false;
  }

  var contains = false;
  void visit(RenderObject child) {
    if (contains || !child.attached) return;
    if (child case final RenderParagraph paragraph
        when paragraph.hasSize &&
            paragraph.registrar != null &&
            visibleWithinSelectionArea(paragraph)) {
      final localPosition = paragraph.globalToLocal(globalPosition);
      if ((Offset.zero & paragraph.size).contains(localPosition)) {
        contains = true;
        return;
      }
    }
    child.visitChildren(visit);
  }

  if (root case final RenderParagraph paragraph
      when paragraph.hasSize &&
          paragraph.registrar != null &&
          visibleWithinSelectionArea(paragraph)) {
    final localPosition = paragraph.globalToLocal(globalPosition);
    contains = (Offset.zero & paragraph.size).contains(localPosition);
  }
  if (!contains) root.visitChildren(visit);
  return contains;
}

// ignore: unused_element

class ChatActionOverlayGestureLayer extends StatelessWidget {
  const ChatActionOverlayGestureLayer({
    super.key,
    required this.selectionAreaKey,
    required this.child,
  });

  final GlobalKey<SelectionAreaState>? selectionAreaKey;
  final Widget child;

  @override
  Widget build(BuildContext context) => _MessageSelectionHitTestPassthrough(
    key: const ValueKey('message-action-overlay-gesture-layer'),
    selectionAreaKey: isDesktopTargetPlatform(Theme.of(context).platform)
        ? null
        : selectionAreaKey,
    child: child,
  );
}

class _MessageSelectionHitTestPassthrough
    extends SingleChildRenderObjectWidget {
  const _MessageSelectionHitTestPassthrough({
    super.key,
    required this.selectionAreaKey,
    required super.child,
  });

  final GlobalKey<SelectionAreaState>? selectionAreaKey;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMessageSelectionHitTestPassthrough(selectionAreaKey);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMessageSelectionHitTestPassthrough renderObject,
  ) {
    renderObject.selectionAreaKey = selectionAreaKey;
  }
}

class _RenderMessageSelectionHitTestPassthrough extends RenderProxyBox {
  _RenderMessageSelectionHitTestPassthrough(this.selectionAreaKey);

  GlobalKey<SelectionAreaState>? selectionAreaKey;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final key = selectionAreaKey;
    if (key != null &&
        selectionAreaContainsGlobalTextPosition(
          selectionAreaKey: key,
          globalPosition: localToGlobal(position),
        )) {
      // Keep the visible overlay controls first, then add only the selected
      // text region underneath. Letting the Stack hit-test the whole transcript
      // would also admit its scroll and swipe-to-reply recognizers while the
      // action menu is open.
      final overlayHit = super.hitTest(result, position: position);
      final selectionRoot = key.currentContext?.findRenderObject();
      if (selectionRoot is RenderBox &&
          selectionRoot.attached &&
          selectionRoot.hasSize) {
        final globalToOverlay = Matrix4.tryInvert(getTransformTo(null));
        if (globalToOverlay == null) return overlayHit;
        final selectionToOverlay = globalToOverlay
          ..multiply(selectionRoot.getTransformTo(null));
        final selectionHit = result.addWithPaintTransform(
          transform: selectionToOverlay,
          position: position,
          hitTest: (result, localPosition) =>
              selectionRoot.hitTest(result, position: localPosition),
        );
        return overlayHit || selectionHit;
      }
      return overlayHit;
    }
    return super.hitTest(result, position: position);
  }
}

@visibleForTesting
bool chatTranscriptBoundaryChanged({
  required int previousCount,
  required int currentCount,
  required int? previousNewestMessageId,
  required int? currentNewestMessageId,
  required int? previousOldestMessageId,
  required int? currentOldestMessageId,
  required bool hasBufferedLiveMessages,
}) =>
    previousCount != currentCount ||
    previousNewestMessageId != currentNewestMessageId ||
    previousOldestMessageId != currentOldestMessageId ||
    hasBufferedLiveMessages;

class _MessageDeleteOptions {
  const _MessageDeleteOptions({
    required this.deleteMessage,
    required this.reportSpam,
    required this.blockSender,
    required this.deleteAllFromSender,
  });

  final bool deleteMessage;
  final bool reportSpam;
  final bool blockSender;
  final bool deleteAllFromSender;

  bool get hasAny =>
      deleteMessage || reportSpam || blockSender || deleteAllFromSender;
}

class _UnreadSummarySession {
  const _UnreadSummarySession(this.service, {this.onDispose});

  final UnreadChatSummaryService service;
  final VoidCallback? onDispose;

  Future<UnreadChatSummary> summarize(
    UnreadChatRangeSnapshot snapshot, {
    UnreadChatSummaryProgressCallback? onProgress,
    UnreadChatSummaryDraftCallback? onDraft,
  }) => service.summarize(snapshot, onProgress: onProgress, onDraft: onDraft);

  void dispose() => onDispose?.call();
}

class _ChecklistDialogButton extends StatelessWidget {
  const _ChecklistDialogButton({
    required this.label,
    required this.foreground,
    required this.onTap,
    this.fill,
  });

  final String label;
  final Color foreground;
  final VoidCallback? onTap;
  final Color? fill;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      height: 38,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(19),
      ),
      child: Text(
        label.l10n(context),
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    ),
  );
}

class _MessageDeleteOptionsDialog extends StatefulWidget {
  const _MessageDeleteOptionsDialog({
    required this.canActOnSender,
    required this.canDeleteAllFromSender,
    required this.senderName,
  });

  final bool canActOnSender;
  final bool canDeleteAllFromSender;
  final String senderName;

  @override
  State<_MessageDeleteOptionsDialog> createState() =>
      _MessageDeleteOptionsDialogState();
}

class _MessageDeleteOptionsDialogState
    extends State<_MessageDeleteOptionsDialog> {
  bool _deleteMessage = true;
  bool _reportSpam = false;
  bool _blockSender = false;
  bool _deleteAllFromSender = false;

  _MessageDeleteOptions get _options => _MessageDeleteOptions(
    deleteMessage: _deleteMessage,
    reportSpam: _reportSpam,
    blockSender: _blockSender,
    deleteAllFromSender: _deleteAllFromSender,
  );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final options = _options;
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: math.min(MediaQuery.sizeOf(context).width - 40, 420),
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 26,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                AppStringKeys.chatDeleteSingleMessageQuestion.l10n(context),
                style: TextStyle(
                  fontSize: 19,
                  height: 1.28,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 22),
              _optionRow(
                label: AppStringKeys.chatDeleteOptionDeleteMessage.l10n(
                  context,
                ),
                value: _deleteMessage,
                onTap: () => setState(() => _deleteMessage = !_deleteMessage),
              ),
              if (widget.canActOnSender) ...[
                _optionRow(
                  label: AppStringKeys.chatDeleteOptionReportSpam.l10n(context),
                  value: _reportSpam,
                  onTap: () => setState(() => _reportSpam = !_reportSpam),
                ),
                _optionRow(
                  label: AppStringKeys.chatDeleteOptionBlockSender.l10n(
                    context,
                  ),
                  value: _blockSender,
                  onTap: () => setState(() => _blockSender = !_blockSender),
                ),
                if (widget.canDeleteAllFromSender)
                  _optionRow(
                    label: AppStrings.t(
                      AppStringKeys.chatDeleteOptionDeleteAllFromSender,
                      {'value1': widget.senderName},
                    ),
                    value: _deleteAllFromSender,
                    onTap: () => setState(
                      () => _deleteAllFromSender = !_deleteAllFromSender,
                    ),
                  ),
              ],
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _dialogButton(
                    label: AppStringKeys.countryPickerCancel.l10n(context),
                    color: c.textSecondary,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 10),
                  _dialogButton(
                    label: AppStringKeys.chatDelete.l10n(context),
                    color: options.hasAny
                        ? const Color(0xFFFF6961)
                        : c.textTertiary,
                    onTap: options.hasAny
                        ? () => Navigator.of(context).pop(options)
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _optionRow({
    required String label,
    required bool value,
    required VoidCallback onTap,
  }) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: value ? AppTheme.brand : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color: value ? AppTheme.brand : c.textTertiary,
                  width: 2,
                ),
              ),
              child: value
                  ? const AppIcon(
                      HeroAppIcons.check,
                      size: 17,
                      color: Colors.white,
                    )
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 17,
                  height: 1.25,
                  color: c.textPrimary,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dialogButton({
    required String label,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: color,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}

enum _MediaEditAction { edit, replace, delete }

class _MediaEditActionDialog extends StatelessWidget {
  const _MediaEditActionDialog({required this.mediaLabel});

  final String mediaLabel;

  @override
  Widget build(BuildContext context) {
    return _ChatEditChoiceDialog<_MediaEditAction>(
      title: mediaLabel,
      choices: const [
        (
          value: _MediaEditAction.edit,
          icon: HeroAppIcons.penToSquare,
          label: AppStringKeys.messageActionEdit,
          destructive: false,
        ),
        (
          value: _MediaEditAction.replace,
          icon: HeroAppIcons.images,
          label: AppStringKeys.chatMediaReplace,
          destructive: false,
        ),
        (
          value: _MediaEditAction.delete,
          icon: HeroAppIcons.trash,
          label: AppStringKeys.chatMediaDelete,
          destructive: true,
        ),
      ],
    );
  }
}

typedef _ChatEditChoice<T> = ({
  T value,
  AppIconData icon,
  String label,
  bool destructive,
});

class _ChatEditChoiceDialog<T> extends StatelessWidget {
  const _ChatEditChoiceDialog({required this.title, required this.choices});

  final String title;
  final List<_ChatEditChoice<T>> choices;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Container(
        width: math.min(MediaQuery.sizeOf(context).width - 40, 360),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
              child: Text(
                title.l10n(context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            for (final choice in choices)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(choice.value),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      AppIcon(
                        choice.icon,
                        size: 22,
                        color: choice.destructive
                            ? const Color(0xFFFF6961)
                            : c.textSecondary,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          choice.label.l10n(context),
                          style: TextStyle(
                            color: choice.destructive
                                ? const Color(0xFFFF6961)
                                : c.textPrimary,
                            fontSize: 16,
                            decoration: TextDecoration.none,
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
    );
  }
}

// ignore: unused_element

// ignore: unused_element

// ignore: unused_element

class ChatViewExitController {
  VoidCallback? _prepareExit;

  /// Registers the currently visible chat and returns a matching detacher.
  VoidCallback register(VoidCallback prepareExit) {
    _prepareExit = prepareExit;
    return () {
      if (identical(_prepareExit, prepareExit)) _prepareExit = null;
    };
  }

  void prepareExit() => _prepareExit?.call();
}

// ignore: unused_element

// ignore: unused_element

// ignore: unused_element

class _MessageTextSelectionDialog extends StatefulWidget {
  const _MessageTextSelectionDialog({
    required this.text,
    required this.onTranslate,
    required this.onAddToBlocklist,
  });

  final String text;
  final Future<String?> Function(String text)? onTranslate;
  final ValueChanged<String> onAddToBlocklist;

  @override
  State<_MessageTextSelectionDialog> createState() =>
      _MessageTextSelectionDialogState();
}

class _ReactionUsersSheet extends StatefulWidget {
  const _ReactionUsersSheet({
    required this.viewModel,
    required this.message,
    required this.initialReaction,
    required this.reportPermission,
    required this.onOpenSender,
    required this.onReportSender,
  });

  final ChatViewModel viewModel;
  final ChatMessage message;
  final MessageReaction initialReaction;

  /// `messageProperties.can_report_reactions` for [message], resolved when the
  /// sheet opens. Hidden until true and never resurrected by a late answer.
  final Future<bool> reportPermission;
  final ValueChanged<MessageReactionUser> onOpenSender;
  final ValueChanged<MessageReactionUser> onReportSender;

  @override
  State<_ReactionUsersSheet> createState() => _ReactionUsersSheetState();
}

enum _ReactionUserAction { report }

class _ReactionUsersSheetState extends State<_ReactionUsersSheet> {
  late MessageReaction _selected;
  final Map<String, Future<List<MessageReactionUser>>> _loads = {};
  bool _allowReport = false;

  @override
  void initState() {
    super.initState();
    final initialKey = _reactionKey(widget.initialReaction);
    _selected = widget.message.reactions.firstWhere(
      (reaction) => _reactionKey(reaction) == initialKey,
      orElse: () => widget.message.reactions.first,
    );
    unawaited(_loadReportPermission());
  }

  Future<void> _loadReportPermission() async {
    final allowed = await widget.reportPermission;
    if (!mounted || !allowed) return;
    setState(() => _allowReport = true);
  }

  Future<List<MessageReactionUser>> _load(MessageReaction reaction) {
    final key = _reactionKey(reaction);
    return _loads.putIfAbsent(
      key,
      () => widget.viewModel.reactionUsers(widget.message, reaction),
    );
  }

  String _reactionKey(MessageReaction reaction) => reaction.customEmojiId != 0
      ? 'custom:${reaction.customEmojiId}'
      : 'emoji:${reaction.emoji ?? ''}';

  bool _canReport(MessageReactionUser user) =>
      _allowReport && !user.isDeleted && user.senderId != widget.viewModel.meId;

  void _retrySelected() {
    _loads.remove(_reactionKey(_selected));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ReactionUsersSheetFrame(
      child: Column(
        children: [
          _reactionTabs(c),
          Divider(height: 1, thickness: 0.5, color: c.divider),
          Expanded(child: _reactionUsers(c)),
        ],
      ),
    );
  }

  Widget _reactionTabs(AppColors c) {
    return SizedBox(
      height: 52,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final reaction in widget.message.reactions)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _reactionTab(c, reaction),
              ),
          ],
        ),
      ),
    );
  }

  Widget _reactionTab(AppColors c, MessageReaction reaction) {
    final selected = _reactionKey(reaction) == _reactionKey(_selected);
    final foreground = selected ? Colors.white : c.textSecondary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _selected = reaction),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? AppTheme.brand : c.searchFill,
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _reactionGlyph(reaction, selected ? Colors.white : c.textSecondary),
            const SizedBox(width: 7),
            Text(
              '${reaction.count}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reactionUsers(AppColors c) {
    return FutureBuilder<List<MessageReactionUser>>(
      future: _load(_selected),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(
            child: Text(
              AppStrings.t(AppStringKeys.contactsLoading),
              style: TextStyle(fontSize: 14, color: c.textSecondary),
            ),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    AppStrings.t(AppStringKeys.chatReactionUsersLoadFailed),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: c.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    key: const ValueKey('reaction-users-retry'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _retrySelected,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: c.searchFill,
                        borderRadius: BorderRadius.circular(AppRadius.control),
                      ),
                      child: Text(
                        AppStrings.t(AppStringKeys.chatReactionUsersRetry),
                        style: TextStyle(fontSize: 14, color: c.textPrimary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        final users = snapshot.data ?? const <MessageReactionUser>[];
        if (users.isEmpty) {
          return Center(
            child: Text(
              AppStrings.t(AppStringKeys.sharedMediaEmpty),
              style: TextStyle(fontSize: 14, color: c.textSecondary),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 6),
          itemCount: users.length,
          itemBuilder: (context, index) => _reactionUserRow(c, users[index]),
        );
      },
    );
  }

  Widget _reactionUserRow(AppColors c, MessageReactionUser user) {
    final time = DateText.listLabel(user.date);
    final reportable = _canReport(user);
    final row = Padding(
      padding: EdgeInsets.fromLTRB(18, 9, reportable ? 6 : 18, 9),
      child: Row(
        children: [
          PhotoAvatar(title: user.title, photo: user.photo, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              user.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 17, color: c.textPrimary),
            ),
          ),
          if (time.isNotEmpty) ...[
            const SizedBox(width: 10),
            Text(time, style: TextStyle(fontSize: 12, color: c.textTertiary)),
          ],
          if (reportable)
            GestureDetector(
              key: ValueKey('reactionUserReport-${user.senderId}'),
              behavior: HitTestBehavior.opaque,
              onTap: () => unawaited(_showUserActions(user)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                child: AppIcon(
                  HeroAppIcons.ellipsisVertical,
                  size: 18,
                  color: c.textTertiary,
                ),
              ),
            ),
        ],
      ),
    );
    if (user.isDeleted) return row;
    return GestureDetector(
      key: ValueKey('reactionUser-${user.senderId}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onOpenSender(user),
      child: row,
    );
  }

  Future<void> _showUserActions(MessageReactionUser user) async {
    final action = await showAppModalSheet<_ReactionUserAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: SettingsCard(
          margin: const EdgeInsets.all(10),
          children: [
            SettingsRow(
              key: const ValueKey('reaction-user-report-action'),
              leading: const AppIcon(HeroAppIcons.triangleExclamation),
              title: AppStrings.t(AppStringKeys.chatReactionReportAction),
              titleColor: AppTheme.tagRed,
              showChevron: false,
              onTap: () =>
                  Navigator.of(sheetContext).pop(_ReactionUserAction.report),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action != _ReactionUserAction.report) return;
    widget.onReportSender(user);
  }

  Widget _reactionGlyph(MessageReaction reaction, Color color) {
    if (reaction.customEmojiId != 0) {
      return CustomEmojiView(
        id: reaction.customEmojiId,
        size: 18,
        color: color,
      );
    }
    return Text(reaction.emoji ?? '', style: const TextStyle(fontSize: 16));
  }
}

class _MessageTextSelectionDialogState
    extends State<_MessageTextSelectionDialog> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  String? _translation;
  bool _translating = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.text);
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.text.length,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String get _selectedText {
    final selection = _controller.selection;
    if (!selection.isValid || selection.isCollapsed) {
      return _controller.text.trim();
    }
    return selection.textInside(_controller.text).trim();
  }

  void _copySelection() {
    final selected = _selectedText;
    if (selected.isEmpty) return;
    Clipboard.setData(ClipboardData(text: selected));
    showToast(context, AppStringKeys.topicPostContentCopied);
  }

  Future<void> _translateSelection() async {
    final selected = _selectedText;
    final translate = widget.onTranslate;
    if (selected.isEmpty || _translating || translate == null) return;
    setState(() => _translating = true);
    final translated = await translate(selected);
    if (!mounted) return;
    setState(() {
      final isEmpty = translated == null || translated.trim().isEmpty;
      _translation = isEmpty ? null : translated;
      _translating = false;
    });
  }

  void _addSelectionToBlocklist() {
    final selected = _selectedText;
    if (selected.isEmpty) return;
    widget.onAddToBlocklist(selected);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final screen = MediaQuery.sizeOf(context);
    return SafeArea(
      child: Material(
        type: MaterialType.transparency,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 560,
                maxHeight: screen.height * 0.72,
              ),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: c.divider, width: 0.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.28),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 16, 12, 13),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              AppStringKeys.messageActionSelectText.l10n(
                                context,
                              ),
                              style: TextStyle(
                                color: c.textPrimary,
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => Navigator.of(context).pop(),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: AppIcon(
                                HeroAppIcons.xmark,
                                color: c.textSecondary,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(height: 0.5, color: c.divider),
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(28, 22, 28, 20),
                        child: Scrollbar(
                          child: SingleChildScrollView(
                            child: TextField(
                              controller: _controller,
                              focusNode: _focusNode,
                              readOnly: true,
                              autofocus: true,
                              maxLines: null,
                              keyboardType: TextInputType.multiline,
                              contextMenuBuilder: (_, _) =>
                                  const SizedBox.shrink(),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                isCollapsed: true,
                              ),
                              style: TextStyle(
                                fontSize: 32,
                                height: 1.35,
                                color: c.textPrimary,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_translation != null) ...[
                      Container(height: 0.5, color: c.divider),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 132),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(28, 16, 28, 16),
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: SelectableText(
                              _translation!,
                              style: TextStyle(
                                color: c.textPrimary,
                                fontSize: 17,
                                height: 1.4,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    Container(height: 0.5, color: c.divider),
                    SizedBox(
                      height: 76,
                      child: Row(
                        children: [
                          Expanded(
                            child: _TextSelectionAction(
                              icon: HeroAppIcons.file,
                              label: AppStringKeys.messageActionCopy,
                              onTap: _copySelection,
                            ),
                          ),
                          if (widget.onTranslate != null)
                            Expanded(
                              child: _TextSelectionAction(
                                icon: HeroAppIcons.language,
                                label: AppStringKeys.messageActionTranslate,
                                onTap: _translating
                                    ? null
                                    : _translateSelection,
                              ),
                            ),
                          Expanded(
                            child: _TextSelectionAction(
                              icon: HeroAppIcons.filter,
                              label: AppStringKeys.messageActionBlockKeyword,
                              onTap: _addSelectionToBlocklist,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TextSelectionAction extends StatelessWidget {
  const _TextSelectionAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final AppIconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onTap != null;
    final color = enabled ? c.textPrimary : c.textTertiary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AppIcon(icon, size: 22, color: color),
          const SizedBox(height: 7),
          Text(
            label.l10n(context),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 12,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}

extension _ChatViewDialogs on _ChatViewState {
  /// Shared forward-to-chat flow (the reference client parity): the picker only chooses

  /// the recipient, then the target chat opens with the forward pending in

  /// its composer as a reply-style preview panel. Send happens there.

  Future<void> _openForwardPicker({
    required List<ChatMessage> messages,
    required bool protectedCopy,
  }) async {
    final accountClientId = _vm.accountClientIdForForwarding;
    final result = await Navigator.of(context).push<ChatPickerResult>(
      MaterialPageRoute(
        builder: (_) => ChatPickerView(
          title: AppStringKeys.chatForwardToTitle,
          showForwardOptions: true,
          accountSlot: _vm.accountSlot,
        ),
      ),
    );
    if (result == null || !mounted) return;
    final target = result.chat;
    if (target.id == _vm.chatId) {
      // Forwarding to the same chat keeps the user here; the composer holds
      // the pending forward instead of a new transcript.
      _vm.adoptForwardHandoff(
        ForwardMessagesHandoff(
          fromChatId: _vm.chatId,
          messages: messages,
          accountSlot: _vm.accountSlot,
          clientId: accountClientId,
          hasCaption: forwardSelectionHasCaption(messages),
          markdownOffer: _forwardMarkdownOffer([
            for (final message in messages) message.id,
          ]),
          protectedCopy: protectedCopy,
        ),
      );
      _exitSelection();
      return;
    }
    ChatDeepLinkController.shared.openChat(
      chatId: target.id,
      title: target.title,
      accountSlot: _vm.accountSlot,
      forwardHandoff: ForwardMessagesHandoff(
        fromChatId: _vm.chatId,
        messages: messages,
        accountSlot: _vm.accountSlot,
        clientId: accountClientId,
        hasCaption: forwardSelectionHasCaption(messages),
        markdownOffer: _forwardMarkdownOffer([
          for (final message in messages) message.id,
        ]),
        protectedCopy: protectedCopy,
      ),
    );
    _exitSelection();
  }

  /// Tapping the pending-forward banner opens the forward options sheet:

  /// hide sender / remove caption (independent toggles with the caption→copy

  /// rule), render markdown, change recipient, apply, cancel.

  Future<void> _showComposerForwardOptions() async {
    final forward = _vm.pendingForward;
    if (forward == null) return;
    final result = await showAppModalSheet<ForwardOptionsResult>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => ForwardOptionsHost(
        onForwardOptionsChanged: () => _vm.notifyForwardOptionsChanged(),
        child: ForwardOptionsSheet(forward: forward),
      ),
    );
    if (result == null || !mounted) return;
    if (result is ForwardOptionsApply) return;
    if (result is ForwardOptionsCancel) {
      _vm.clearPendingForward();
      return;
    }
    if (result is ForwardOptionsChangeRecipient) {
      await _openForwardPicker(
        messages: forward.messages,
        protectedCopy: forward.protectedCopy,
      );
    }
  }

  /// Tapping the reply banner opens the reply options sheet: quote a range,

  /// carry the reply into another chat, or drop it.

  Future<void> _showComposerReplyOptions() async {
    final target = _vm.replyTo;
    if (target == null) return;
    final canQuote = _vm.canQuoteText && canQuoteMessageText(target);
    final canReplyInAnotherChat = await _vm.canReplyInAnotherChat(target);
    if (!mounted) return;
    final limit = await _vm.messageQuoteLengthLimit();
    if (!mounted) return;
    final result = await showAppModalSheet<ComposerReplyOptionsResult>(
      context: context,
      backgroundColor: Colors.transparent,
      // The preview's selection handles drag inside the sheet; the
      // drag-to-dismiss recognizer would fight them ("stuck" handle drags).
      enableDrag: false,
      builder: (_) => ComposerReplyOptionsSheet(
        message: target,
        canQuote: canQuote,
        canReplyInAnotherChat: canReplyInAnotherChat,
        quoteLengthLimit: limit,
        initialQuote: _vm.replyQuote,
      ),
    );
    if (result == null || !mounted) return;
    if (result is ComposerReplyOptionsRemove) {
      _vm.setReply(null);
      return;
    }
    if (result is ComposerReplyOptionsQuote) {
      final current =
          _vm.messages.where((m) => m.id == target.id).firstOrNull ?? target;
      _vm.setReply(current, quote: result.quote);
      return;
    }
    if (result is ComposerReplyOptionsAnotherChat) {
      await _replyInAnotherChat(target, quoteParam: result.quote);
      return;
    }
    // Apply: the reply stays as it is (the sheet may have cleared its quote
    // locally; nothing to commit).
  }
}
