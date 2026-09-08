import 'dart:async';

import 'package:flutter/widgets.dart';

class ChatPaneController {
  bool Function()? _handleBack;

  bool pop() => _handleBack?.call() ?? false;
}

/// Owns conversation mode changes inside a desktop/tablet detail pane.
/// Replacing a mode must never replace the route that owns the app shell.
class ChatPane extends StatefulWidget {
  const ChatPane({super.key, required this.controller, required this.child});

  final ChatPaneController controller;
  final Widget child;

  static bool replace(
    BuildContext context,
    Widget Function(VoidCallback onBack) builder,
  ) {
    final pane = context.findAncestorStateOfType<_ChatPaneState>();
    if (pane == null) return false;
    pane.replace(builder);
    return true;
  }

  static VoidCallback? registerBackHandler(
    BuildContext context,
    bool Function() handler,
  ) {
    final pane = context.findAncestorStateOfType<_ChatPaneState>();
    if (pane == null) return null;
    pane._childBack = handler;
    return () {
      if (identical(pane._childBack, handler)) pane._childBack = null;
    };
  }

  @override
  State<ChatPane> createState() => _ChatPaneState();
}

class _ChatPaneState extends State<ChatPane> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  Widget? _replacement;
  bool Function()? _childBack;
  late final bool Function() _registeredBack = _pop;

  @override
  void initState() {
    super.initState();
    widget.controller._handleBack = _registeredBack;
  }

  @override
  void dispose() {
    if (identical(widget.controller._handleBack, _registeredBack)) {
      widget.controller._handleBack = null;
    }
    super.dispose();
  }

  bool _pop() {
    final navigator = _navigatorKey.currentState;
    if (navigator != null && navigator.canPop()) {
      unawaited(navigator.maybePop());
      return true;
    }
    if (_childBack?.call() ?? false) return true;
    if (_replacement == null) return false;
    _back();
    return true;
  }

  void _back() => setState(() => _replacement = null);

  void replace(Widget Function(VoidCallback onBack) builder) {
    setState(() => _replacement = builder(_back));
  }

  @override
  Widget build(BuildContext context) => Navigator(
    key: _navigatorKey,
    pages: [_ChatPanePage(child: _replacement ?? widget.child)],
    onDidRemovePage: (_) {},
  );
}

/// Utility routes pushed by a conversation share its pane bounds and retain
/// the conversation underneath, including its selected topic and scroll state.
class _ChatPanePage extends Page<void> {
  const _ChatPanePage({required this.child});

  final Widget child;

  @override
  Route<void> createRoute(BuildContext context) => _ChatPaneRoute(this);
}

class _ChatPaneRoute extends PageRoute<void> {
  _ChatPaneRoute(_ChatPanePage page) : super(settings: page);

  @override
  Duration get transitionDuration => Duration.zero;
  @override
  Color? get barrierColor => null;
  @override
  String? get barrierLabel => null;
  @override
  bool get maintainState => true;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => (settings as _ChatPanePage).child;
}
