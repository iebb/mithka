import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:mithka_video_player/mithka_video_player.dart';
import 'package:mithka_video_player_fvp/mithka_video_player_fvp.dart';
import 'package:video_player/video_player.dart';

import 'example_sources.dart';

export 'example_sources.dart' show sampleVideo;

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  MithkaFvpBackend.ensureInitialized();

  final child = await MithkaDesktopVideoWindows.initialize(arguments);
  if (child != null) {
    runApp(ExampleWindow(arguments: child));
    return;
  }
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => WidgetsApp(
    color: _Palette.canvas,
    debugShowCheckedModeBanner: false,
    title: 'Mithka Video Player',
    pageRouteBuilder: _buildPageRoute,
    home: const _ExampleHome(),
  );
}

class _ExampleHome extends StatefulWidget {
  const _ExampleHome();

  @override
  State<_ExampleHome> createState() => _ExampleHomeState();
}

class _ExampleHomeState extends State<_ExampleHome> {
  final _playerKey = GlobalKey();
  // A stable identity prevents unrelated parent rebuilds from replacing the
  // controller created by this factory.
  // ignore: prefer_function_declarations_over_variables
  late final MithkaVideoControllerBuilder _controllerBuilder = (source) =>
      source.createController(
        videoPlayerOptionsOverride: _playerOwnedLifecycleOptions,
      );
  late final _ownedController = const MithkaVideoSource.network(
    sampleVideo,
  ).createController(videoPlayerOptionsOverride: _playerOwnedLifecycleOptions);
  ExampleSourceMode _mode = ExampleSourceMode.network;
  bool _fullscreen = false;
  bool _customChrome = false;
  int _lastStatusSecond = -1;
  String _status = 'Paused — select the player and press Space to begin';

  @override
  void dispose() {
    unawaited(_ownedController.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = _buildPlayer();
    if (_fullscreen) {
      return ColoredBox(
        color: _Palette.black,
        child: SafeArea(child: player),
      );
    }

    return ColoredBox(
      color: _Palette.canvas,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: constraints.maxWidth >= 760 ? 40 : 18,
              vertical: constraints.maxWidth >= 760 ? 32 : 18,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: DefaultTextStyle(
                  style: const TextStyle(
                    color: _Palette.text,
                    fontSize: 15,
                    height: 1.4,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _Header(),
                      const SizedBox(height: 24),
                      _SourceSelector(
                        selected: _mode,
                        onSelected: (mode) {
                          if (isExampleSourceAvailable(mode, isWeb: kIsWeb)) {
                            setState(() {
                              _mode = mode;
                              _lastStatusSecond = -1;
                              _status = mode.description;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 18),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: _Palette.panel,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: _Palette.border),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x52000000),
                              blurRadius: 28,
                              offset: Offset(0, 14),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(17),
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: player,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _PlayerFooter(
                        status: _status,
                        customChrome: _customChrome,
                        windowEnabled:
                            mithkaSupportsDesktopVideoWindows &&
                            _mode != ExampleSourceMode.asset,
                        onToggleChrome: () =>
                            setState(() => _customChrome = !_customChrome),
                        onOpenWindow: () => unawaited(_openWindow()),
                      ),
                      const SizedBox(height: 28),
                      const _ShortcutReference(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlayer() => MithkaVideoPlayer(
    key: _playerKey,
    source: sourceForExampleMode(_mode),
    controller: _mode == ExampleSourceMode.ownedController
        ? _ownedController
        : null,
    controllerBuilder: _mode == ExampleSourceMode.controllerBuilder
        ? _controllerBuilder
        : null,
    width: 1280,
    height: 720,
    autoplay: false,
    isFullscreen: _fullscreen,
    accentColor: _Palette.accent,
    chromeStyle: const MithkaVideoChromeStyle(
      foregroundColor: _Palette.text,
      transportBackgroundColor: Color(0xE6151920),
      primaryTransportBackgroundColor: Color(0xF20C0E12),
      transportBorderColor: Color(0x73FFFFFF),
      focusColor: _Palette.accent,
      hoverColor: Color(0x2861D6C8),
    ),
    interactionMode: _customChrome
        ? MithkaVideoInteractionMode.delegateToChrome
        : MithkaVideoInteractionMode.builtIn,
    chromeBuilder: _customChrome
        ? (context, scope) => _ExampleCustomChrome(scope: scope)
        : null,
    topTrailingBuilder: _customChrome
        ? null
        : (context, scope) => _ExampleTopTrailingActions(scope: scope),
    onClose: _fullscreen ? _toggleFullscreen : null,
    onToggleFullscreen: _toggleFullscreen,
    onPrevious: () => setState(() => _status = 'Previous requested'),
    onNext: () => setState(() => _status = 'Next requested'),
    onReady: (_) {
      if (mounted) setState(() => _status = 'Ready');
    },
    onEnded: () {
      if (mounted) setState(() => _status = 'Playback completed');
    },
    onPositionChanged: (position) {
      final second = position.inSeconds;
      if (!mounted || second == _lastStatusSecond || second % 5 != 0) return;
      _lastStatusSecond = second;
      setState(() => _status = 'Playing at ${_format(position)}');
    },
  );

  void _toggleFullscreen() => setState(() => _fullscreen = !_fullscreen);

  Future<void> _openWindow() async {
    if (!mithkaSupportsDesktopVideoWindows) return;
    final uri = _mode == ExampleSourceMode.file
        ? Uri.file(configuredFileVideo)
        : Uri.parse(sampleVideo);
    final id = await MithkaDesktopVideoWindows.instance.open(
      MithkaDesktopVideoWindowArguments(
        uri: uri,
        title: '${_mode.label} video',
        width: 1280,
        height: 720,
        muted: false,
      ),
      onClosed: () {
        if (mounted) setState(() => _status = 'Desktop window closed');
      },
    );
    if (mounted) {
      setState(() {
        _status = id == null
            ? 'This platform cannot create independent windows'
            : 'Opened independent window $id — open more to test concurrency';
      });
    }
  }
}

final _playerOwnedLifecycleOptions = VideoPlayerOptions(
  mixWithOthers: true,
  allowBackgroundPlayback: true,
);

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Mithka Video Player',
        style: TextStyle(
          color: _Palette.text,
          fontSize: 30,
          height: 1.12,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.7,
        ),
      ),
      const SizedBox(height: 8),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: const Text(
          'A responsive, keyboard-accessible player surface for mobile, web, '
          'tablet and desktop. Resize this window and try each ownership mode.',
          style: TextStyle(color: _Palette.subtle, fontSize: 15),
        ),
      ),
    ],
  );
}

class _SourceSelector extends StatelessWidget {
  const _SourceSelector({required this.selected, required this.onSelected});

  final ExampleSourceMode selected;
  final ValueChanged<ExampleSourceMode> onSelected;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'SOURCE AND OWNERSHIP',
        style: TextStyle(
          color: _Palette.subtle,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
      const SizedBox(height: 9),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final mode in ExampleSourceMode.values)
            _DemoButton(
              label: mode.label,
              selected: mode == selected,
              enabled: isExampleSourceAvailable(mode, isWeb: kIsWeb),
              onPressed: () => onSelected(mode),
            ),
        ],
      ),
      const SizedBox(height: 9),
      Text(
        selected.description,
        style: const TextStyle(color: _Palette.subtle, fontSize: 13),
      ),
    ],
  );
}

class _PlayerFooter extends StatelessWidget {
  const _PlayerFooter({
    required this.status,
    required this.customChrome,
    required this.windowEnabled,
    required this.onToggleChrome,
    required this.onOpenWindow,
  });

  final String status;
  final bool customChrome;
  final bool windowEnabled;
  final VoidCallback onToggleChrome;
  final VoidCallback onOpenWindow;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 12,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      DecoratedBox(
        decoration: BoxDecoration(
          color: _Palette.panel,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _Palette.border),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            status,
            style: const TextStyle(color: _Palette.subtle, fontSize: 12),
          ),
        ),
      ),
      _DemoButton(
        label: customChrome ? 'Use built-in chrome' : 'Use custom chrome',
        onPressed: onToggleChrome,
      ),
      _DemoButton(
        label: 'Open independent window',
        enabled: windowEnabled,
        onPressed: onOpenWindow,
      ),
    ],
  );
}

class _ExampleCustomChrome extends StatelessWidget {
  const _ExampleCustomChrome({required this.scope});

  final MithkaVideoChromeScope scope;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: scope.actions.toggleControls,
      onDoubleTapDown: (details) {
        final fraction = constraints.maxWidth <= 0
            ? 0.5
            : details.localPosition.dx / constraints.maxWidth;
        if (fraction < 0.4) {
          unawaited(scope.actions.seekBy(const Duration(seconds: -10)));
        } else if (fraction > 0.6) {
          unawaited(scope.actions.seekBy(const Duration(seconds: 10)));
        } else {
          unawaited(scope.actions.togglePlayback());
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: scope.snapshot.controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 160),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x18000000),
                      Color(0x00000000),
                      Color(0xB0000000),
                    ],
                    stops: [0, 0.52, 1],
                  ),
                ),
              ),
            ),
          ),
          IgnorePointer(
            ignoring: !scope.snapshot.controlsVisible,
            child: AnimatedOpacity(
              opacity: scope.snapshot.controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 160),
              child: Center(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (scope.previous != null)
                      _DemoButton(
                        label: scope.labels.previous,
                        onPressed: scope.previous!,
                      ),
                    _DemoButton(
                      label: scope.snapshot.value.isPlaying
                          ? scope.labels.pause
                          : scope.labels.play,
                      selected: true,
                      onPressed: () =>
                          unawaited(scope.actions.togglePlayback()),
                    ),
                    if (scope.next != null)
                      _DemoButton(
                        label: scope.labels.next,
                        onPressed: scope.next!,
                      ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 12,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: scope.snapshot.controlsVisible ? 1 : 0,
                duration: const Duration(milliseconds: 160),
                child: Text(
                  '${_format(scope.snapshot.displayPosition)} / '
                  '${_format(scope.snapshot.value.duration)}',
                  style: const TextStyle(
                    color: _Palette.text,
                    fontSize: 12,
                    fontFeatures: [FontFeature.tabularFigures()],
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

class _ExampleTopTrailingActions extends StatefulWidget {
  const _ExampleTopTrailingActions({required this.scope});

  final MithkaVideoChromeScope scope;

  @override
  State<_ExampleTopTrailingActions> createState() =>
      _ExampleTopTrailingActionsState();
}

class _ExampleTopTrailingActionsState
    extends State<_ExampleTopTrailingActions> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scope = widget.scope;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: _DemoButton(
            label: _expanded ? 'Close player actions' : 'Player actions',
            selected: _expanded,
            onPressed: () => setState(() => _expanded = !_expanded),
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: 190,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xF2151920),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x73FFFFFF)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x99000000),
                    blurRadius: 18,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DemoButton(
                      label: scope.snapshot.value.volume == 0
                          ? 'Restore audio'
                          : 'Mute audio',
                      onPressed: () => unawaited(scope.actions.toggleMute()),
                    ),
                    const SizedBox(height: 6),
                    _DemoButton(
                      label: 'Hide controls',
                      onPressed: () {
                        setState(() => _expanded = false);
                        scope.actions.hideControls();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ShortcutReference extends StatelessWidget {
  const _ShortcutReference();

  static const _shortcuts = <(String, String)>[
    ('Space / K', 'Play or pause'),
    ('J / L', 'Seek backward or forward'),
    ('← / →', 'Seek backward or forward'),
    ('↑ / ↓', 'Adjust volume'),
    ('M', 'Mute or restore volume'),
    ('F', 'Toggle fullscreen'),
    ('Escape', 'Close the player or leave fullscreen'),
  ];

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: _Palette.panel,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _Palette.border),
    ),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'KEYBOARD',
            style: TextStyle(
              color: _Palette.subtle,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 22,
            runSpacing: 10,
            children: [
              for (final shortcut in _shortcuts)
                SizedBox(
                  width: 250,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 88,
                        child: Text(
                          shortcut.$1,
                          style: const TextStyle(
                            color: _Palette.text,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          shortcut.$2,
                          style: const TextStyle(
                            color: _Palette.subtle,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _DemoButton extends StatefulWidget {
  const _DemoButton({
    required this.label,
    required this.onPressed,
    this.enabled = true,
    this.selected = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool enabled;
  final bool selected;

  @override
  State<_DemoButton> createState() => _DemoButtonState();
}

class _DemoButtonState extends State<_DemoButton> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final interactive = widget.enabled && (_hovered || _focused);
    final background = widget.selected
        ? _Palette.accent
        : interactive
        ? _Palette.panelHover
        : _Palette.panel;
    final foreground = widget.enabled
        ? widget.selected
              ? _Palette.black
              : _Palette.text
        : _Palette.disabled;
    return Semantics(
      button: true,
      enabled: widget.enabled,
      selected: widget.selected,
      label: widget.label,
      child: FocusableActionDetector(
        enabled: widget.enabled,
        mouseCursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? widget.onPressed : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: _focused
                    ? _Palette.accent
                    : widget.selected
                    ? _Palette.accent
                    : _Palette.border,
                width: _focused ? 2 : 1,
              ),
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                color: foreground,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ExampleWindow extends StatelessWidget {
  const ExampleWindow({super.key, required this.arguments});

  final MithkaDesktopVideoWindowArguments arguments;

  @override
  Widget build(BuildContext context) => WidgetsApp(
    color: _Palette.black,
    debugShowCheckedModeBanner: false,
    title: arguments.title,
    pageRouteBuilder: _buildPageRoute,
    home: MithkaDesktopVideoWindowHost(
      initialArguments: arguments,
      builder: (context, arguments) =>
          _ExampleWindowPlayer(arguments: arguments),
    ),
  );
}

PageRoute<T> _buildPageRoute<T>(
  RouteSettings settings,
  WidgetBuilder builder,
) => PageRouteBuilder<T>(
  settings: settings,
  pageBuilder: (context, animation, secondaryAnimation) => builder(context),
);

class _ExampleWindowPlayer extends StatelessWidget {
  const _ExampleWindowPlayer({required this.arguments});

  final MithkaDesktopVideoWindowArguments arguments;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: MithkaDesktopVideoWindows.currentWindowFullscreen,
    builder: (context, fullscreen, _) => ColoredBox(
      color: _Palette.black,
      child: MithkaVideoPlayer(
        source: MithkaVideoSource.uri(arguments.uri),
        width: arguments.width,
        height: arguments.height,
        initialMuted: arguments.muted,
        autofocus: true,
        isFullscreen: fullscreen,
        onClose: MithkaDesktopVideoWindows.closeCurrentWindow,
        onFullscreenChanged: (value) => unawaited(
          MithkaDesktopVideoWindows.setCurrentWindowFullscreen(value),
        ),
      ),
    ),
  );
}

String _format(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60);
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

abstract final class _Palette {
  static const canvas = Color(0xFF0C0E12);
  static const panel = Color(0xFF151920);
  static const panelHover = Color(0xFF202631);
  static const border = Color(0xFF2A303A);
  static const text = Color(0xFFF3F6FA);
  static const subtle = Color(0xFFA1AAB8);
  static const disabled = Color(0xFF626A76);
  static const accent = Color(0xFF61D6C8);
  static const black = Color(0xFF000000);
}
