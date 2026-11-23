part of 'chat_input_bar.dart';

/// while [blinking], and holds still otherwise (paused, or reduced motion).

/// while [blinking], and holds still otherwise (paused, or reduced motion).

class _RecordingDot extends StatefulWidget {
  const _RecordingDot({required this.color, required this.blinking});

  final Color color;
  final bool blinking;

  @override
  State<_RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<_RecordingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );
  late final Animation<double> _opacity = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 0.3,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 1,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 0.3,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 1,
    ),
  ]).animate(_controller);

  @override
  void initState() {
    super.initState();
    _syncBlinking();
  }

  @override
  void didUpdateWidget(_RecordingDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.blinking != widget.blinking) _syncBlinking();
  }

  void _syncBlinking() {
    if (widget.blinking) {
      _controller.repeat();
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _opacity,
    child: SizedBox.square(
      dimension: 8,
      child: DecoratedBox(
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    ),
  );
}

class _AiReplyThinkingIndicator extends StatefulWidget {
  const _AiReplyThinkingIndicator({super.key});

  @override
  State<_AiReplyThinkingIndicator> createState() =>
      _AiReplyThinkingIndicatorState();
}

class _AiReplyThinkingIndicatorState extends State<_AiReplyThinkingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _animation,
    builder: (context, _) {
      final pulse = (math.sin(_animation.value * math.pi * 2) + 1) / 2;
      return Transform.scale(
        scale: 0.96 + pulse * 0.05,
        child: SizedBox(
          width: 24,
          height: 24,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.brand.withValues(alpha: 0.10 + pulse * 0.06),
              border: Border.all(
                color: AppTheme.brand.withValues(alpha: 0.24),
                width: 0.75,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                AppIcon(
                  HeroAppIcons.wandMagicSparkles,
                  size: 14,
                  color: AppTheme.brand,
                ),
                Positioned.fill(
                  child: Transform.rotate(
                    key: const ValueKey('composerAiReplyOrbit'),
                    angle: _animation.value * math.pi * 2,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                        width: 5,
                        height: 5,
                        margin: const EdgeInsets.only(top: 1),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.brand,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.brand.withValues(alpha: 0.36),
                              blurRadius: 3,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _RelaySendingOverlay extends StatefulWidget {
  const _RelaySendingOverlay({required this.progress});

  final RichMessageRelayProgress progress;

  @override
  State<_RelaySendingOverlay> createState() => _RelaySendingOverlayState();
}

class _RelaySendingOverlayState extends State<_RelaySendingOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final progress = widget.progress;
    final percent = (progress.fraction * 100).round().clamp(0, 100);
    final label = switch (progress.stage) {
      RichMessageRelayStage.upload => AppStrings.t(
        AppStringKeys.richTextRelayProgressUpload,
        {'value1': progress.mediaIndex, 'value2': progress.mediaCount},
      ),
      RichMessageRelayStage.compose =>
        AppStringKeys.richTextRelayProgressCompose.l10n(context),
      RichMessageRelayStage.waitForMessage =>
        AppStringKeys.richTextRelayProgressWait.l10n(context),
      RichMessageRelayStage.forward =>
        AppStringKeys.richTextRelayProgressForward.l10n(context),
    };
    return Positioned.fill(
      child: AbsorbPointer(
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.24),
          child: Center(
            child: Container(
              width: 210,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: c.divider, width: 0.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _animation,
                    builder: (_, _) => Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var index = 0; index < 3; index++) ...[
                          if (index > 0) const SizedBox(width: 7),
                          _relayProgressDot(index),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 11),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: c.textPrimary,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 9),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: SizedBox(
                      height: 4,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ColoredBox(color: c.divider),
                          FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: progress.fraction,
                            child: ColoredBox(color: AppTheme.brand),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    '${progress.step}/${progress.totalSteps} · $percent%',
                    style: TextStyle(
                      fontSize: 12,
                      color: c.textSecondary,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _relayProgressDot(int index) {
    final phase = (_animation.value - index * 0.16) * math.pi * 2;
    final strength = (math.sin(phase) + 1) / 2;
    return Transform.scale(
      scale: 0.78 + strength * 0.28,
      child: Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          color: AppTheme.brand.withValues(alpha: 0.35 + strength * 0.65),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _LongMessageRichTextPrompt extends StatelessWidget {
  const _LongMessageRichTextPrompt({
    required this.onCancel,
    required this.onConfirm,
  });

  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: SafeArea(
        minimum: const EdgeInsets.all(24),
        child: Container(
          width: math.min(360, MediaQuery.sizeOf(context).width - 48),
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: c.divider, width: 0.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                AppStringKeys.composerLongMessageTitle.l10n(context),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                AppStringKeys.composerLongMessageRichTextPrompt.l10n(context),
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: c.textSecondary,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _LongMessagePromptAction(
                      label: AppStringKeys.countryPickerCancel.l10n(context),
                      onTap: onCancel,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _LongMessagePromptAction(
                      label: AppStringKeys.composerSendAsRichText.l10n(context),
                      onTap: onConfirm,
                      primary: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LongMessagePromptAction extends StatelessWidget {
  const _LongMessagePromptAction({
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: primary ? AppTheme.brand : c.searchFill,
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Text(
          label,
          maxLines: 2,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: primary ? Colors.white : c.textPrimary,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}

enum _ComposerFormatAction {
  quote('textEntityTypeBlockQuote'),
  spoiler('textEntityTypeSpoiler'),
  bold('textEntityTypeBold'),
  italic('textEntityTypeItalic'),
  monospace('textEntityTypeCode'),
  link(''),
  strikethrough('textEntityTypeStrikethrough'),
  underline('textEntityTypeUnderline'),
  codeBlock('textEntityTypePre');

  const _ComposerFormatAction(this.entityType);

  final String entityType;

  String get labelKey => switch (this) {
    quote => AppStringKeys.messageActionQuote,
    spoiler => AppStringKeys.richTextComposerFormatSpoiler,
    bold => AppStringKeys.richTextComposerFormatBold,
    italic => AppStringKeys.richTextComposerFormatItalic,
    monospace => AppStringKeys.composerFormatMonospace,
    link => AppStringKeys.composerFormatLink,
    strikethrough => AppStringKeys.richTextComposerFormatStrikethrough,
    underline => AppStringKeys.richTextComposerFormatUnderline,
    codeBlock => AppStringKeys.composerFormatCodeBlock,
  };
}

class _ComposerFormatMenu extends StatelessWidget {
  const _ComposerFormatMenu({required this.anchor});

  static const _width = 232.0;
  static const _rowHeight = 44.0;
  static const _padding = 8.0;
  static const _borderWidth = 0.5;

  final Offset anchor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final media = MediaQuery.of(context);
    final screen = media.size;
    // Keep the full menu on roomy screens; scroll within the safe viewport
    // when the keyboard or a short window leaves less space than nine rows.
    final naturalHeight =
        _ComposerFormatAction.values.length * _rowHeight +
        (_padding + _borderWidth) * 2;
    final safeTop = math.min(screen.height, media.padding.top + 8);
    final safeBottom = math.max(
      safeTop,
      screen.height -
          math.max(media.padding.bottom, media.viewInsets.bottom) -
          8,
    );
    final safeLeft = math.min(screen.width, media.padding.left + 12);
    final safeRight = math.max(
      safeLeft,
      screen.width - media.padding.right - 12,
    );
    final width = math.min(_width, safeRight - safeLeft);
    final menuHeight = math.min(naturalHeight, safeBottom - safeTop);
    final left = (anchor.dx - width / 2)
        .clamp(safeLeft, safeRight - width)
        .toDouble();
    final below = anchor.dy + 10;
    final preferredTop = below + menuHeight <= safeBottom
        ? below
        : anchor.dy - menuHeight - 10;
    final top = preferredTop.clamp(safeTop, safeBottom - menuHeight).toDouble();
    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          width: width,
          height: menuHeight,
          child: TextFieldTapRegion(
            child: Container(
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: c.divider, width: _borderWidth),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: _padding),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final action in _ComposerFormatAction.values)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => Navigator.of(context).pop(action),
                        child: SizedBox(
                          height: _rowHeight,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              child: Text(
                                action.labelKey.l10n(context),
                                style: TextStyle(
                                  fontSize: 16,
                                  color: c.textPrimary,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ComposerLinkDialog extends StatefulWidget {
  const _ComposerLinkDialog();

  @override
  State<_ComposerLinkDialog> createState() => _ComposerLinkDialogState();
}

class _ComposerLinkDialogState extends State<_ComposerLinkDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Container(
        width: math.min(360, MediaQuery.sizeOf(context).width - 40),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: c.divider, width: 0.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              AppStringKeys.composerFormatLink.l10n(context),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                color: c.searchFill,
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                controller: _controller,
                autofocus: true,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                autocorrect: false,
                enableSuggestions: false,
                onSubmitted: _submit,
                style: TextStyle(fontSize: 16, color: c.textPrimary),
                decoration: InputDecoration(
                  hintText: AppStringKeys.composerFormatLinkPlaceholder.l10n(
                    context,
                  ),
                  hintStyle: TextStyle(color: c.textTertiary),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _dialogAction(
                  context,
                  AppStringKeys.countryPickerCancel,
                  () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 8),
                _dialogAction(
                  context,
                  AppStringKeys.composerFormatApply,
                  () => _submit(_controller.text),
                  primary: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dialogAction(
    BuildContext context,
    String label,
    VoidCallback onTap, {
    bool primary = false,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Text(
          label.l10n(context),
          style: TextStyle(
            fontSize: 15,
            fontWeight: primary ? FontWeight.w600 : FontWeight.w400,
            color: primary ? AppTheme.brand : context.colors.textSecondary,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }

  void _submit(String value) {
    final url = value.trim();
    if (url.isEmpty) return;
    Navigator.of(context).pop(url);
  }
}
