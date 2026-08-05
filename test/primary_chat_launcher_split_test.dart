//
//  primary_chat_launcher_split_test.dart
//
//  A conversation opened from a nested screen — search results, a profile,
//  shared media — must land in the desktop split pane. Pushing it as a page
//  covers the navigation rail and the chat list, which is what the desktop
//  layout exists to avoid.
//
//  openChatFromCurrentWindow itself reaches the multi-window plugin, which is
//  unavailable under flutter test, so these cover the decision and the effect
//  it produces.
//

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/chat_deep_link_controller.dart';
import 'package:mithka/app/primary_chat_launcher.dart';

/// Stands in for MainTabView: registers as the deep-link host and records what
/// it is asked to select.
class _RecordingHost {
  final requests = <ChatDeepLinkRequest>[];

  void attach() => ChatDeepLinkController.shared.addListener(_handle);
  void detach() => ChatDeepLinkController.shared.removeListener(_handle);

  void _handle() {
    final request = ChatDeepLinkController.shared.consumePending();
    if (request != null) requests.add(request);
  }
}

/// Runs [body] with [platform] as the target platform.
///
/// The override has to be cleared before the test body returns; addTearDown
/// runs after Flutter asserts that debug variables were left unset.
Future<void> onPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

/// Pumps a root screen with a second screen pushed on top of it, mirroring
/// "search opened over the chat list".
Future<BuildContext> pumpNestedScreen(
  WidgetTester tester, {
  required Size size,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  late BuildContext nested;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (inner) {
                  nested = inner;
                  return const Scaffold(body: Text('nested screen'));
                },
              ),
            ),
            child: const Text('root screen'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('root screen'));
  await tester.pumpAndSettle();
  expect(find.text('nested screen'), findsOneWidget);
  return nested;
}

void main() {
  late _RecordingHost host;

  setUp(() => host = _RecordingHost()..attach());
  tearDown(() {
    host.detach();
    ChatDeepLinkController.shared.consumePending();
  });

  group('prefersSplitPaneChat', () {
    testWidgets('true on a desktop-sized window with a host', (tester) async {
      await onPlatform(TargetPlatform.macOS, () async {
        final context = await pumpNestedScreen(
          tester,
          size: const Size(1440, 900),
        );

        expect(prefersSplitPaneChat(context), isTrue);
      });
    });

    testWidgets('false on a phone-sized window', (tester) async {
      await onPlatform(TargetPlatform.android, () async {
        final context = await pumpNestedScreen(
          tester,
          size: const Size(390, 844),
        );

        expect(
          prefersSplitPaneChat(context),
          isFalse,
          reason: 'without a split pane the conversation is a page of its own',
        );
      });
    });

    testWidgets('false when nothing is listening', (tester) async {
      host.detach();
      await onPlatform(TargetPlatform.macOS, () async {
        final context = await pumpNestedScreen(
          tester,
          size: const Size(1440, 900),
        );

        expect(
          prefersSplitPaneChat(context),
          isFalse,
          reason: 'a request with no host would be dropped silently',
        );
      });
    });
  });

  group('selectChatInSplitPane', () {
    testWidgets('hands the conversation to the host', (tester) async {
      await onPlatform(TargetPlatform.macOS, () async {
        final context = await pumpNestedScreen(
          tester,
          size: const Size(1440, 900),
        );

        selectChatInSplitPane(
          context,
          chatId: 42,
          title: 'Design',
          initialMessageId: 7,
        );
        await tester.pumpAndSettle();

        expect(host.requests, hasLength(1));
        expect(host.requests.single.chatId, 42);
        expect(host.requests.single.title, 'Design');
        expect(host.requests.single.messageId, 7);
      });
    });

    testWidgets('dismisses the screen that asked', (tester) async {
      await onPlatform(TargetPlatform.macOS, () async {
        final context = await pumpNestedScreen(
          tester,
          size: const Size(1440, 900),
        );

        selectChatInSplitPane(context, chatId: 42, title: 'Design');
        await tester.pumpAndSettle();

        expect(find.text('nested screen'), findsNothing);
        expect(
          find.text('root screen'),
          findsOneWidget,
          reason: 'a stacked search page would hide the pane it just filled',
        );
      });
    });
  });
}
