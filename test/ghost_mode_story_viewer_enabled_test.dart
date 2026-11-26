import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/config/build_flags.dart';
import 'package:mithka/moments/story_viewer_view.dart';
import 'package:mithka/settings/privacy_security/ghost_mode_controller.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Enabled-build variant: run with
/// `flutter test --dart-define=I_DONT_FUCKING_CARE_ABOUT_TOS=true
/// test/ghost_mode_story_viewer_enabled_test.dart`. Every test self-skips
/// when the define is absent so the default CI run stays green.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final updates = StreamController<Map<String, dynamic>>.broadcast();
  final requests = <Map<String, dynamic>>[];

  setUpAll(() {
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (_) async => <String, dynamic>{'@type': 'error'},
        send: (request) async => requests.add(request),
        updates: updates.stream,
      ),
    );
  });

  setUp(() async {
    requests.clear();
    SharedPreferences.setMockInitialValues({});
    GhostModeController.shared.initialize(
      await SharedPreferences.getInstance(),
    );
  });

  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  if (!allowTelegramTosViolations) {
    test('skipped: this file requires I_DONT_FUCKING_CARE_ABOUT_TOS', () {
      expect(allowTelegramTosViolations, isFalse);
    });
    return;
  }

  testWidgets('story viewer withholds openStory while ghost mode intercepts', (
    tester,
  ) async {
    await GhostModeController.shared.setGlobalEnabled(true);
    await GhostModeController.shared.setChatException(
      -10077,
      GhostChatException.forceBlock,
    );

    await tester.pumpWidget(
      const MaterialApp(home: StoryViewerView(chatId: -10077, storyIds: [11])),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    expect(
      requests.where((request) => request['@type'] == 'openStory'),
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await GhostModeController.shared.setGlobalEnabled(false);
    await GhostModeController.shared.setChatException(
      -10077,
      GhostChatException.defaultState,
    );
  });

  testWidgets('story viewer reports openStory in a force-allow chat', (
    tester,
  ) async {
    await GhostModeController.shared.setGlobalEnabled(true);
    await GhostModeController.shared.setChatException(
      -10077,
      GhostChatException.forceAllow,
    );

    await tester.pumpWidget(
      const MaterialApp(home: StoryViewerView(chatId: -10077, storyIds: [11])),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    expect(
      requests
          .where((request) => request['@type'] == 'openStory')
          .single['story_id'],
      11,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await GhostModeController.shared.setGlobalEnabled(false);
    await GhostModeController.shared.setChatException(
      -10077,
      GhostChatException.defaultState,
    );
  });

  testWidgets('dimension off resumes openStory reports', (tester) async {
    await GhostModeController.shared.setGlobalEnabled(true);
    await GhostModeController.shared.setBlockStoryReads(false);

    await tester.pumpWidget(
      const MaterialApp(home: StoryViewerView(chatId: -10077, storyIds: [11])),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    expect(
      requests.where((request) => request['@type'] == 'openStory'),
      isNotEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await GhostModeController.shared.setGlobalEnabled(false);
    await GhostModeController.shared.setBlockStoryReads(true);
  });
}
