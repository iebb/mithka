//
//  drawer_controller.dart
//
//  Drives the left-sliding "我" profile drawer, shared across tabs so any tab
//  header's avatar can open it. Port of the Swift `DrawerController`.
//

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

class DrawerController extends ChangeNotifier {
  bool _isOpen = false;
  bool get isOpen => _isOpen;

  void open() {
    _isOpen = true;
    notifyListeners();
  }

  void close() {
    _isOpen = false;
    notifyListeners();
  }
}

/// Tracks per-tab navigation depth so the classic bar hides on pushes.
class TabBarVisibility extends ChangeNotifier {
  final Map<int, int> _depths = {};
  int _chatSuppressions = 0;
  bool _notifyScheduled = false;

  void setDepth(int tab, int depth) {
    if (_depths[tab] == depth) return;
    _depths[tab] = depth;
    _notifyListenersSafely();
  }

  int depth(int tab) => _depths[tab] ?? 0;

  bool get isChatSuppressed => _chatSuppressions > 0;

  void retainChatSuppression() {
    _chatSuppressions++;
    _notifyListenersSafely();
  }

  void releaseChatSuppression() {
    if (_chatSuppressions == 0) return;
    _chatSuppressions--;
    _notifyListenersSafely();
  }

  void _notifyListenersSafely() {
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      notifyListeners();
      return;
    }
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _notifyScheduled = false;
      notifyListeners();
    });
  }
}

/// A [NavigatorObserver] that reports the current stack depth of one tab's
/// Navigator into [TabBarVisibility] (depth 0 = root → show the tab bar).
class TabDepthObserver extends NavigatorObserver {
  TabDepthObserver(this.tab, this.visibility);
  final int tab;
  final TabBarVisibility visibility;
  final List<Route<dynamic>> _pageStack = [];

  void _report() {
    visibility.setDepth(tab, (_pageStack.length - 1).clamp(0, 1 << 20));
  }

  @override
  void didPush(Route route, Route? previousRoute) {
    if (route is PageRoute) _pageStack.add(route);
    _report();
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    if (route is PageRoute) _pageStack.remove(route);
    _report();
  }

  @override
  void didRemove(Route route, Route? previousRoute) {
    if (route is PageRoute) _pageStack.remove(route);
    _report();
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    final index = oldRoute == null ? -1 : _pageStack.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute is PageRoute) {
        _pageStack[index] = newRoute;
      } else {
        _pageStack.removeAt(index);
      }
    } else if (newRoute is PageRoute) {
      _pageStack.add(newRoute);
    }
    _report();
  }
}
