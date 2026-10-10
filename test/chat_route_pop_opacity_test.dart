import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/app_navigator.dart';

/// Collects the alpha of every [OpacityLayer] in the frame's layer tree.
///
/// `RenderOpacity` builds no opacity layer at all when it is handed 1.0, so a
/// missing layer and an alpha of 255 mean the same thing: nothing is being
/// composited through an offscreen buffer.
List<int> _frameOpacities() {
  final alphas = <int>[];
  void visit(Layer? layer) {
    if (layer == null) return;
    if (layer is OpacityLayer) alphas.add(layer.alpha ?? 255);
    if (layer is ContainerLayer) {
      Layer? child = layer.firstChild;
      while (child != null) {
        visit(child);
        child = child.nextSibling;
      }
    }
  }

  visit(RendererBinding.instance.renderViews.single.debugLayer);
  return alphas.where((alpha) => alpha < 255).toList();
}

/// Routes the shell itself is drawn with, so every opacity layer left in a frame
/// belongs to the conversation route under test.
class _NoTransitionBuilder extends PageTransitionsBuilder {
  const _NoTransitionBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T>? route,
    BuildContext? context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

Widget _surface(String label) => ColoredBox(
  color: Color(0xFF101010 + label.length),
  child: Center(child: Text(label)),
);

void main() {
  Future<NavigatorState> pumpShell(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: appNavigatorKey,
        theme: ThemeData(
          pageTransitionsTheme: const PageTransitionsTheme(
            builders: {
              TargetPlatform.android: _NoTransitionBuilder(),
              TargetPlatform.iOS: _NoTransitionBuilder(),
            },
          ),
        ),
        home: _surface('list'),
      ),
    );
    return appNavigatorKey.currentState!;
  }

  testWidgets('a conversation fades in but leaves without an opacity layer', (
    tester,
  ) async {
    final navigator = await pumpShell(tester);
    unawaited(
      navigator.push(
        AppChatPageRoute<void>(builder: (context) => _surface('chat')),
      ),
    );

    // The arrival fade is still a fade: mid-push the page is composited
    // through a partially transparent layer.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(_frameOpacities(), isNotEmpty, reason: 'push frame 1');
    await tester.pump(const Duration(milliseconds: 60));
    expect(_frameOpacities(), isNotEmpty, reason: 'push frame 2');

    await tester.pump(const Duration(milliseconds: 240));
    await tester.pump();
    expect(_frameOpacities(), isEmpty, reason: 'settled push');

    navigator.pop();
    await tester.pump();
    for (var frame = 1; frame <= 8; frame++) {
      await tester.pump(const Duration(milliseconds: 30));
      expect(
        _frameOpacities(),
        isEmpty,
        reason: 'pop frame $frame dimmed the departing page',
      );
    }
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpAndSettle();
  });
}
