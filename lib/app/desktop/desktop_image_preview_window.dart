import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';

import '../../chat/media/full_image_viewer.dart' show ImageViewerMessageActions;
import '../../chat/media/image_edit_view.dart';
import '../../components/app_icons.dart';
import '../../components/app_interactive_surface.dart';
import '../../components/ui_components.dart';
import '../../l10n/app_localizations.dart';
import '../../media/media_metadata.dart';
import '../../media/media_metadata_dialog.dart';
import '../../platform/desktop_clipboard_images.dart';
import '../../platform/keyboard_modifiers.dart';
import '../../platform/ohos_support.dart';
import '../../tdlib/td_image_loader.dart';
import '../../tdlib/td_models.dart';
import '../../theme/app_theme.dart';
import '../../theme/platform_font_defaults.dart';
import 'desktop_image_preview_window_models.dart';
import 'desktop_image_preview_window_stub.dart'
    if (dart.library.io) 'desktop_image_preview_window_io.dart'
    as implementation;
import 'desktop_media_window_registry.dart';

export 'desktop_image_preview_window_models.dart';

/// Most images one independent preview window carries at launch.
const int desktopImagePreviewWindowMaxItems = 64;

/// The bounded slice of a gallery that opens in an independent window.
///
/// Galleries such as Moments, comments and Shared Media hand over every photo
/// in the chat. Keeping only the first [maxItems] and clamping the tapped
/// index into them opened a different image whenever the tapped photo sat
/// past that limit, so the slice is centred on the tapped photo instead.
@visibleForTesting
({int first, int initialIndex, int count}) desktopImagePreviewWindowSlice(
  int length,
  int startIndex, {
  int maxItems = desktopImagePreviewWindowMaxItems,
}) {
  final selected = startIndex.clamp(0, length - 1);
  final count = length < maxItems ? length : maxItems;
  final first = (selected - count ~/ 2).clamp(0, length - count);
  return (first: first, initialIndex: selected - first, count: count);
}

class DesktopImagePreviewWindowService {
  DesktopImagePreviewWindowService._();

  static final DesktopImagePreviewWindowService instance =
      DesktopImagePreviewWindowService._();

  /// Lets widget tests of chat galleries keep the in-app viewer on desktop
  /// hosts, where the native window plugin never answers.
  @visibleForTesting
  bool? debugSupportedOverride;

  bool get isSupported =>
      debugSupportedOverride ??
      implementation.supportsDesktopImagePreviewWindows;

  /// Keeps one window per image, so opening the same one again raises that
  /// window instead of stacking a duplicate on top of it.
  final DesktopMediaWindowRegistry _windows = DesktopMediaWindowRegistry();

  /// Message actions of the open previews, by session. The message ids stay
  /// here; a preview window only sends back its session and gallery index.
  final Map<String, _PreviewActionSession> _sessions = {};
  final Random _random = Random.secure();
  int _sessionCount = 0;

  Future<void> broadcastBrightness(bool dark) =>
      implementation.broadcastDesktopImagePreviewBrightness(dark);

  /// Opens [images] in an independent window. [metadata] and the message ids
  /// in [messageActions] line up with [images], as in the in-app viewer.
  Future<bool> open(
    List<TdFileRef> images, {
    int startIndex = 0,
    required bool dark,
    List<MediaMetadata?> metadata = const [],
    ImageViewerMessageActions? messageActions,
  }) async {
    if (!isSupported || images.isEmpty) return false;
    final slice = desktopImagePreviewWindowSlice(images.length, startIndex);
    T? at<T>(List<T?> source, int index) =>
        index < source.length ? source[index] : null;
    final range = [for (var i = 0; i < slice.count; i++) slice.first + i];
    final safeImages = [for (final i in range) images[i]];
    final safeMetadata = [for (final i in range) at(metadata, i)];
    final messageIds = [
      for (final i in range)
        at(messageActions?.messageIds ?? const <int?>[], i),
    ];
    final initialIndex = slice.initialIndex;
    int? originWindowId;
    if (messageActions != null && messageIds.any((id) => id != null)) {
      originWindowId = await implementation
          .currentDesktopImagePreviewOriginWindowId();
    }
    final hasActions = originWindowId != null;
    // A preview with chat actions and one without them are different windows.
    final windowKey = (safeImages[initialIndex].id, hasActions);
    if (_windows.isOpening(windowKey)) return true;
    final existing = _windows.windowFor(windowKey);
    if (existing != null) {
      if (await implementation.focusDesktopImagePreviewWindow(existing)) {
        return true;
      }
      _windows.forget(windowKey);
    }
    String? sessionId;
    if (hasActions) {
      await _pruneSessions();
      implementation.setDesktopImagePreviewActionHandler(_handleAction);
      sessionId =
          'image-${++_sessionCount}-${_random.nextInt(1 << 32).toRadixString(36)}';
      _sessions[sessionId] = _PreviewActionSession(
        messageIds: messageIds,
        onViewInChat: messageActions!.onViewInChat,
        onReply: messageActions.onReply,
      );
    }
    final arguments = DesktopImagePreviewWindowArguments(
      title: AppStrings.t(AppStringKeys.imagePreviewTitle),
      localeTag: Intl.getCurrentLocale(),
      dark: dark,
      startIndex: initialIndex,
      canReply: hasActions && messageActions?.onReply != null,
      actionSession: sessionId,
      originWindowId: originWindowId,
      items: [
        for (var index = 0; index < safeImages.length; index++)
          DesktopImagePreviewItemArguments(
            path: normalizeDesktopImagePath(safeImages[index].localPath),
            // Keep launch IPC bounded. Other images resolve by path update.
            miniThumb: index == initialIndex
                ? safeImages[index].miniThumb
                : null,
            metadata: safeMetadata[index],
            hasMessage: hasActions && messageIds[index] != null,
          ),
      ],
    );
    _windows.beginOpening(windowKey);
    int? windowId;
    try {
      windowId = await implementation.openDesktopImagePreviewWindow(arguments);
    } finally {
      _windows.finishOpening(windowKey, windowId: windowId);
    }
    if (windowId == null) {
      _sessions.remove(sessionId);
      return false;
    }
    _sessions[sessionId]?.windowId = windowId;
    unawaited(_resolveAndPublish(windowId, safeImages));
    return true;
  }

  /// Drops the actions of previews that were closed, so their chat callbacks
  /// are not kept alive for the rest of the app session.
  Future<void> _pruneSessions() async {
    if (_sessions.isEmpty) return;
    final active = await implementation.activeDesktopImagePreviewWindowIds();
    _sessions.removeWhere(
      (_, session) =>
          session.windowId != null && !active.contains(session.windowId),
    );
  }

  Future<bool> _handleAction(
    int fromWindowId,
    DesktopImagePreviewActionRequest request,
  ) async {
    final session = _sessions[request.session];
    // Only the window the session was created for may use it.
    if (session == null || session.windowId != fromWindowId) return false;
    if (request.index >= session.messageIds.length) return false;
    final messageId = session.messageIds[request.index];
    final action = switch (request.action) {
      DesktopImagePreviewAction.viewInChat => session.onViewInChat,
      DesktopImagePreviewAction.reply => session.onReply,
    };
    if (messageId == null || action == null) return false;
    await implementation.focusCurrentDesktopImagePreviewOrigin();
    try {
      await action(messageId);
    } on Object {
      return false;
    }
    return true;
  }

  Future<void> _resolveAndPublish(int windowId, List<TdFileRef> images) async {
    for (var index = 0; index < images.length; index++) {
      final path = await TdFileCenter.shared.pathFor(images[index]);
      if (path == null) continue;
      await implementation.publishDesktopImagePreviewPath(
        windowId,
        index,
        path,
      );
    }
  }
}

class _PreviewActionSession {
  _PreviewActionSession({
    required this.messageIds,
    required this.onViewInChat,
    required this.onReply,
  });

  final List<int?> messageIds;
  final Future<void> Function(int messageId) onViewInChat;
  final Future<void> Function(int messageId)? onReply;
  int? windowId;
}

class DesktopImagePreviewWindowApp extends StatelessWidget {
  const DesktopImagePreviewWindowApp({super.key, required this.arguments});

  final DesktopImagePreviewWindowArguments arguments;

  @override
  Widget build(BuildContext context) {
    final systemLocale = ui.PlatformDispatcher.instance.locale;
    final rawLocale = AppLocalizations.localeFromTag(arguments.localeTag);
    final locale = AppLocalizations.resolve(
      rawLocale ?? AppLocalizations.fallbackLocale,
    );
    final typographyLocale = PlatformFontDefaults.effectiveTypographyLocale(
      appLocale: rawLocale ?? locale,
      systemLocale: systemLocale,
    );
    final families = PlatformFontDefaults.effectiveFontChain(
      appLocale: rawLocale ?? locale,
      systemLocale: systemLocale,
    );
    return WidgetsApp(
      color: const Color(0xFF0C0D0F),
      debugShowCheckedModeBanner: false,
      title: arguments.title,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      builder: (context, child) => DefaultTextStyle.merge(
        style: TextStyle(
          fontFamily: families.isEmpty ? null : families.first,
          fontFamilyFallback: families.length > 1
              ? families.skip(1).toList()
              : null,
          locale: typographyLocale,
        ),
        child: child ?? const SizedBox.shrink(),
      ),
      pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
        settings: settings,
        pageBuilder: (context, _, _) => builder(context),
      ),
      home: _DesktopImagePreview(arguments: arguments),
    );
  }
}

class _DesktopImagePreview extends StatefulWidget {
  const _DesktopImagePreview({required this.arguments});

  final DesktopImagePreviewWindowArguments arguments;

  @override
  State<_DesktopImagePreview> createState() => _DesktopImagePreviewState();
}

class _DesktopImagePreviewState extends State<_DesktopImagePreview> {
  final TransformationController _transformation = TransformationController();
  StreamSubscription<DesktopImagePreviewPathUpdate>? _pathSubscription;
  StreamSubscription<bool>? _brightnessSubscription;
  late List<DesktopImagePreviewItemArguments> _items;
  late int _index;
  late bool _dark;
  double _scale = 1;
  int _quarterTurns = 0;
  bool _showMore = false;
  String? _status;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _items = List.of(widget.arguments.items);
    _index = widget.arguments.startIndex.clamp(0, _items.length - 1);
    _dark = widget.arguments.dark;
    _transformation.addListener(_handleTransformationChanged);
    _pathSubscription = implementation.desktopImagePreviewPathUpdates.listen((
      update,
    ) {
      if (!mounted || update.index >= _items.length) return;
      final current = _items[update.index];
      if (current.path == update.path) return;
      setState(() {
        _items[update.index] = current.withPath(update.path);
      });
    });
    _brightnessSubscription = implementation
        .desktopImagePreviewBrightnessUpdates
        .listen((dark) {
          if (mounted && dark != _dark) setState(() => _dark = dark);
        });
  }

  @override
  void didUpdateWidget(covariant _DesktopImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.arguments.dark != oldWidget.arguments.dark) {
      _dark = widget.arguments.dark;
    }
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    unawaited(_pathSubscription?.cancel());
    unawaited(_brightnessSubscription?.cancel());
    implementation.detachDesktopImagePreviewBridgeIfIdle();
    _transformation.removeListener(_handleTransformationChanged);
    _transformation.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent || keyboardModifiersPressed()) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      unawaited(implementation.closeCurrentDesktopImagePreviewWindow());
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.digit0) {
      _resetTransform();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _move(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _move(1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _move(int delta) {
    final next = (_index + delta).clamp(0, _items.length - 1);
    if (next == _index) return;
    setState(() {
      _index = next;
      _quarterTurns = 0;
      _showMore = false;
    });
    _setScale(1);
  }

  void _toggleZoom() {
    _setScale(_scale > 1.01 ? 1 : 2);
  }

  void _handleTransformationChanged() {
    final next = _transformation.value.getMaxScaleOnAxis().clamp(0.5, 5.0);
    if (!mounted || (next - _scale).abs() < 0.01) return;
    setState(() => _scale = next);
  }

  void _setScale(double value) {
    final safe = value.clamp(0.5, 5.0);
    _transformation.value = Matrix4.diagonal3Values(safe, safe, 1);
  }

  void _resetTransform() {
    setState(() {
      _quarterTurns = 0;
      _showMore = false;
    });
    _setScale(1);
  }

  void _rotate() {
    setState(() {
      _quarterTurns = (_quarterTurns + 1) % 4;
      _showMore = false;
    });
  }

  Future<void> _editCurrentImage() async {
    final path = _items[_index].path;
    if (path == null) return;
    final result = await Navigator.of(context).push<ImageEditResult>(
      PageRouteBuilder<ImageEditResult>(
        pageBuilder: (context, _, _) => Theme(
          data: _theme(),
          child: ImageEditView(sourcePath: path),
        ),
      ),
    );
    if (!mounted || result == null) return;
    final editedPath = normalizeDesktopImagePath(result.path);
    if (editedPath == null) return;
    setState(() {
      _items[_index] = _items[_index].withPath(editedPath);
      _quarterTurns = 0;
      _showMore = false;
    });
    _setScale(1);
  }

  Future<void> _saveCurrentImage() async {
    final path = _items[_index].path;
    if (path == null) return;
    try {
      final source = File(path);
      final bytes = await source.readAsBytes();
      final fileName = source.uri.pathSegments.isEmpty
          ? 'image.png'
          : source.uri.pathSegments.last;
      final extension = fileName.contains('.')
          ? fileName.split('.').last.toLowerCase()
          : 'png';
      final selected = await FilePicker.platform.saveFile(
        dialogTitle: widget.arguments.title,
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: [extension],
        bytes: bytes,
      );
      if (selected == null) return;
      if (!isMobilePlatform) {
        await File(selected).writeAsBytes(bytes, flush: true);
      }
      _showStatus(AppStrings.t(AppStringKeys.accentColorPickerSave));
    } on Object {
      _showStatus(AppStrings.t(AppStringKeys.sharedMediaCacheDeleteFailed));
    }
  }

  Future<void> _copyCurrent() async {
    final path = _items[_index].path;
    if (path == null) return;
    if (Platform.isMacOS) {
      final copied = await DesktopClipboardImageService.copyImageFile(
        File(path),
      );
      if (!mounted) return;
      _showStatus(
        AppStrings.t(
          copied
              ? AppStringKeys.qrScannerCopied
              : AppStringKeys.messageActionCopyImageFailed,
        ),
      );
    } else {
      await Clipboard.setData(ClipboardData(text: path));
      if (!mounted) return;
      _showStatus(AppStrings.t(AppStringKeys.qrScannerCopied));
    }
    if (mounted) setState(() => _showMore = false);
  }

  bool get _currentHasMessage =>
      widget.arguments.hasMessageActions && _items[_index].hasMessage;

  /// Asks the opening window to run [action] on the current image's message,
  /// then closes this preview so the chat it jumped to is in view.
  Future<void> _runMessageAction(DesktopImagePreviewAction action) async {
    final session = widget.arguments.actionSession;
    final origin = widget.arguments.originWindowId;
    setState(() => _showMore = false);
    if (session == null || origin == null) return;
    final done = await implementation.requestDesktopImagePreviewAction(
      origin,
      DesktopImagePreviewActionRequest(
        session: session,
        action: action,
        index: _index,
      ),
    );
    if (!mounted) return;
    if (done) {
      await implementation.closeCurrentDesktopImagePreviewWindow();
    } else {
      _showStatus(AppStrings.t(AppStringKeys.chatInputBarActionFailed));
    }
  }

  Future<void> _showCurrentInfo() async {
    final metadata = _items[_index].metadata;
    setState(() => _showMore = false);
    if (metadata == null) return;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: AppStrings.t(AppStringKeys.mediaMetadataTitle),
      barrierColor: const Color(0x85000000),
      pageBuilder: (_, _, _) => Theme(
        data: _theme(),
        child: MediaMetadataDialog(metadata: metadata),
      ),
    );
  }

  ThemeData _theme() {
    final colors = _dark ? AppColors.dark : AppColors.light;
    return ThemeData(
      brightness: _dark ? Brightness.dark : Brightness.light,
      useMaterial3: true,
      scaffoldBackgroundColor: colors.background,
      extensions: [colors],
    );
  }

  void _showStatus(String message) {
    _statusTimer?.cancel();
    if (mounted) setState(() => _status = message);
    _statusTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _status = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _theme(),
      child: Focus(
        autofocus: true,
        onKeyEvent: _handleKey,
        child: ColoredBox(
          color: _dark ? const Color(0xFF0C0D0F) : const Color(0xFFF0F1F3),
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: _toggleZoom,
                  child: InteractiveViewer(
                    transformationController: _transformation,
                    minScale: 0.75,
                    maxScale: 5,
                    trackpadScrollCausesScale: true,
                    child: Center(
                      child: RotatedBox(
                        quarterTurns: _quarterTurns,
                        child: _image(),
                      ),
                    ),
                  ),
                ),
              ),
              if (_items.length > 1) ...[
                Positioned(
                  left: 12,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _GalleryArrow(
                      key: const ValueKey('desktop-image-previous'),
                      icon: HeroAppIcons.chevronLeft,
                      label: AppStrings.t(
                        AppStringKeys.videoPlayerPreviousVideo,
                      ),
                      enabled: _index > 0,
                      onTap: () => _move(-1),
                    ),
                  ),
                ),
                Positioned(
                  right: 12,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _GalleryArrow(
                      key: const ValueKey('desktop-image-next'),
                      icon: HeroAppIcons.chevronRight,
                      label: AppStrings.t(AppStringKeys.videoPlayerNextVideo),
                      enabled: _index < _items.length - 1,
                      onTap: () => _move(1),
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xB816171A),
                        borderRadius: BorderRadius.circular(AppRadius.card),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        child: Text(
                          '${_index + 1} / ${_items.length}',
                          style: const TextStyle(
                            color: Color(0xFFFFFFFF),
                            fontSize: 12,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              if (_status case final status?)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 66,
                  child: Center(
                    child: _PreviewStatus(message: status, dark: _dark),
                  ),
                ),
              if (_showMore)
                Positioned(
                  right: 12,
                  bottom: 62,
                  child: _PreviewMoreMenu(
                    dark: _dark,
                    onViewInChat: _currentHasMessage
                        ? () => _runMessageAction(
                            DesktopImagePreviewAction.viewInChat,
                          )
                        : null,
                    onReply: _currentHasMessage && widget.arguments.canReply
                        ? () =>
                              _runMessageAction(DesktopImagePreviewAction.reply)
                        : null,
                    onInfo: _items[_index].metadata != null
                        ? _showCurrentInfo
                        : null,
                    onCopy: _copyCurrent,
                    onClose:
                        implementation.closeCurrentDesktopImagePreviewWindow,
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _PreviewToolbar(
                  dark: _dark,
                  scale: _scale,
                  canSave: _items[_index].path != null,
                  canEdit: _items[_index].path != null,
                  onZoomOut: () => _setScale(_scale - 0.25),
                  onZoomIn: () => _setScale(_scale + 0.25),
                  onReset: _resetTransform,
                  onRotate: _rotate,
                  onEdit: _editCurrentImage,
                  onSave: _saveCurrentImage,
                  onMore: () => setState(() => _showMore = !_showMore),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _image() {
    final item = _items[_index];
    final path = item.path;
    if (path != null) {
      return Image.file(
        File(path),
        key: ValueKey('$_index-$path'),
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => _placeholder(item),
      );
    }
    return _placeholder(item);
  }

  Widget _placeholder(DesktopImagePreviewItemArguments item) {
    final miniThumb = item.miniThumb;
    if (miniThumb != null && miniThumb.isNotEmpty) {
      return Image.memory(
        miniThumb,
        fit: BoxFit.contain,
        gaplessPlayback: true,
      );
    }
    return const AppActivityIndicator(size: 24, color: Color(0xFFFFFFFF));
  }
}

class _PreviewToolbar extends StatelessWidget {
  const _PreviewToolbar({
    required this.dark,
    required this.scale,
    required this.canSave,
    required this.canEdit,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onReset,
    required this.onRotate,
    required this.onEdit,
    required this.onSave,
    required this.onMore,
  });

  final bool dark;
  final double scale;
  final bool canSave;
  final bool canEdit;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onReset;
  final VoidCallback onRotate;
  final VoidCallback onEdit;
  final VoidCallback onSave;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final foreground = dark ? const Color(0xFFE8E9EB) : const Color(0xFF282B30);
    final disabled = dark ? const Color(0xFF66686C) : const Color(0xFFA9ADB4);
    final divider = dark ? const Color(0xFF34363A) : const Color(0xFFD7D9DE);
    final unavailable = AppStrings.t(
      AppStringKeys.businessSettingsThisBusinessFeatureIsUnavailableInThisBuild,
    );
    return Container(
      key: const ValueKey('desktop-image-preview-toolbar'),
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: dark ? const Color(0xF21A1B1E) : const Color(0xFAF7F8FA),
        border: Border(top: BorderSide(color: divider)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _PreviewToolbarButton(
                  key: const ValueKey('desktop-image-preview-zoom-out'),
                  icon: HeroAppIcons.minus,
                  label:
                      '${AppStrings.t(AppStringKeys.richTextComposerMapZoom)} -',
                  foreground: foreground,
                  disabled: disabled,
                  onTap: onZoomOut,
                ),
                SizedBox(
                  width: 50,
                  child: Text(
                    '${(scale * 100).round()}%',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 13,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                _PreviewToolbarButton(
                  key: const ValueKey('desktop-image-preview-zoom-in'),
                  icon: HeroAppIcons.plus,
                  label:
                      '${AppStrings.t(AppStringKeys.richTextComposerMapZoom)} +',
                  foreground: foreground,
                  disabled: disabled,
                  onTap: onZoomIn,
                ),
                _PreviewTextButton(
                  key: const ValueKey('desktop-image-preview-reset'),
                  label: '1:1',
                  foreground: foreground,
                  onTap: onReset,
                ),
                _PreviewToolbarDivider(color: divider),
                _PreviewToolbarButton(
                  key: const ValueKey('desktop-image-preview-rotate'),
                  icon: HeroAppIcons.rotateRight,
                  label: AppStrings.t(AppStringKeys.imageEditRotate),
                  foreground: foreground,
                  disabled: disabled,
                  onTap: onRotate,
                ),
                _PreviewToolbarButton(
                  key: const ValueKey('desktop-image-preview-edit'),
                  icon: HeroAppIcons.pen,
                  label: AppStrings.t(AppStringKeys.imageEditTitle),
                  foreground: foreground,
                  disabled: disabled,
                  enabled: canEdit,
                  disabledReason: unavailable,
                  onTap: onEdit,
                ),
                _PreviewToolbarButton(
                  key: const ValueKey('desktop-image-preview-translate'),
                  icon: HeroAppIcons.language,
                  label: AppStrings.t(AppStringKeys.messageActionTranslate),
                  foreground: foreground,
                  disabled: disabled,
                  enabled: false,
                  disabledReason: unavailable,
                  onTap: () {},
                ),
                _PreviewToolbarButton(
                  key: const ValueKey('desktop-image-preview-ocr'),
                  icon: HeroAppIcons.font,
                  label: 'OCR',
                  foreground: foreground,
                  disabled: disabled,
                  enabled: false,
                  disabledReason: unavailable,
                  onTap: () {},
                ),
                _PreviewToolbarButton(
                  key: const ValueKey('desktop-image-preview-share'),
                  icon: HeroAppIcons.share,
                  label: AppStrings.t(AppStringKeys.topicChatShare),
                  foreground: foreground,
                  disabled: disabled,
                  enabled: false,
                  disabledReason: unavailable,
                  onTap: () {},
                ),
                _PreviewToolbarButton(
                  key: const ValueKey('desktop-image-preview-save'),
                  icon: HeroAppIcons.download,
                  label: AppStrings.t(AppStringKeys.accentColorPickerSave),
                  foreground: foreground,
                  disabled: disabled,
                  enabled: canSave,
                  onTap: onSave,
                ),
                _PreviewToolbarButton(
                  key: const ValueKey('desktop-image-preview-more'),
                  icon: HeroAppIcons.ellipsis,
                  label: AppStrings.t(AppStringKeys.momentsMore),
                  foreground: foreground,
                  disabled: disabled,
                  onTap: onMore,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewToolbarButton extends StatelessWidget {
  const _PreviewToolbarButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    required this.foreground,
    required this.disabled,
    this.enabled = true,
    this.disabledReason,
  });

  final AppIconData icon;
  final String label;
  final VoidCallback onTap;
  final Color foreground;
  final Color disabled;
  final bool enabled;
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    final tooltip = enabled ? label : (disabledReason ?? label);
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      hint: enabled ? null : disabledReason,
      child: Tooltip(
        message: tooltip,
        child: AppInteractiveSurface(
          semanticLabel: label,
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: SizedBox(
            width: 34,
            height: 38,
            child: Center(
              child: AppIcon(
                icon,
                size: 19,
                color: enabled ? foreground : disabled,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewTextButton extends StatelessWidget {
  const _PreviewTextButton({
    super.key,
    required this.label,
    required this.foreground,
    required this.onTap,
  });

  final String label;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppInteractiveSurface(
    semanticLabel: label,
    onTap: onTap,
    borderRadius: BorderRadius.circular(AppRadius.md),
    child: SizedBox(
      width: 36,
      height: 38,
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: foreground,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    ),
  );
}

class _PreviewToolbarDivider extends StatelessWidget {
  const _PreviewToolbarDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 12,
    height: 24,
    child: Center(
      child: SizedBox(width: 1, height: 20, child: ColoredBox(color: color)),
    ),
  );
}

class _PreviewMoreMenu extends StatelessWidget {
  const _PreviewMoreMenu({
    required this.dark,
    required this.onCopy,
    required this.onClose,
    this.onViewInChat,
    this.onReply,
    this.onInfo,
  });

  final bool dark;
  final VoidCallback onCopy;
  final VoidCallback onClose;

  /// Null hides the entry: the image has no message, or no media facts.
  final VoidCallback? onViewInChat;
  final VoidCallback? onReply;
  final VoidCallback? onInfo;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('desktop-image-preview-more-menu'),
    width: 172,
    padding: const EdgeInsets.symmetric(vertical: 5),
    decoration: BoxDecoration(
      color: dark ? const Color(0xF5222327) : const Color(0xFAFCFCFD),
      borderRadius: BorderRadius.circular(AppRadius.control),
      border: Border.all(
        color: dark ? const Color(0xFF3B3D42) : const Color(0xFFD7D9DE),
      ),
      boxShadow: [
        BoxShadow(
          color: dark ? const Color(0x66000000) : const Color(0x33000000),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onViewInChat case final onTap?)
          _PreviewMoreAction(
            icon: HeroAppIcons.arrowRight,
            label: AppStrings.t(AppStringKeys.messageViewInChat),
            dark: dark,
            onTap: onTap,
          ),
        if (onReply case final onTap?)
          _PreviewMoreAction(
            icon: HeroAppIcons.quoteLeft,
            label: AppStrings.t(AppStringKeys.chatInputBarReply),
            dark: dark,
            onTap: onTap,
          ),
        if (onInfo case final onTap?)
          _PreviewMoreAction(
            icon: HeroAppIcons.circleInfo,
            label: AppStrings.t(AppStringKeys.mediaMetadataViewInfo),
            dark: dark,
            onTap: onTap,
          ),
        _PreviewMoreAction(
          icon: HeroAppIcons.clipboard,
          label: AppStrings.t(
            Platform.isMacOS
                ? AppStringKeys.messageActionCopyImage
                : AppStringKeys.messageActionCopy,
          ),
          dark: dark,
          onTap: onCopy,
        ),
        _PreviewMoreAction(
          icon: HeroAppIcons.xmark,
          label: AppStrings.t(AppStringKeys.musicPlayerClose),
          dark: dark,
          onTap: onClose,
        ),
      ],
    ),
  );
}

class _PreviewMoreAction extends StatelessWidget {
  const _PreviewMoreAction({
    required this.icon,
    required this.label,
    required this.dark,
    required this.onTap,
  });

  final AppIconData icon;
  final String label;
  final bool dark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppInteractiveSurface(
    semanticLabel: label,
    onTap: onTap,
    child: SizedBox(
      height: 36,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11),
        child: Row(
          children: [
            AppIcon(
              icon,
              size: 16,
              color: dark ? const Color(0xFFCACCD0) : const Color(0xFF545861),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: dark
                      ? const Color(0xFFE8E9EB)
                      : const Color(0xFF24272D),
                  fontSize: 13,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PreviewStatus extends StatelessWidget {
  const _PreviewStatus({required this.message, required this.dark});

  final String message;
  final bool dark;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: dark ? const Color(0xE6222327) : const Color(0xF2FFFFFF),
      borderRadius: BorderRadius.circular(AppRadius.control),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Text(
        message,
        style: TextStyle(
          color: dark ? const Color(0xFFFFFFFF) : const Color(0xFF24272D),
          fontSize: 12,
          decoration: TextDecoration.none,
        ),
      ),
    ),
  );
}

class _GalleryArrow extends StatelessWidget {
  const _GalleryArrow({
    super.key,
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final AppIconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: enabled,
    label: label,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: enabled ? 1 : 0.28,
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0xB816171A),
            shape: BoxShape.circle,
          ),
          child: AppIcon(icon, size: 18, color: const Color(0xFFFFFFFF)),
        ),
      ),
    ),
  );
}
