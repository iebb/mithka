import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/config/build_flags.dart';
import 'package:mithka/moments/story_viewer_view.dart';
import 'package:mithka/settings/ghost_mode_controller.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Default-build variant (no `I_DONT_FUCKING_CARE_ABOUT_TOS` define): the
/// story viewer must still report `openStory`. The enabled-build counterpart
/// lives in ghost_mode_story_viewer_enabled_test.dart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (allowTelegramTosViolations) {
    // This file pins the flag-OFF variant; the enabled counterpart lives in
    // ghost_mode_enabled_test.dart / ghost_mode_story_viewer_enabled_test.dart.
    return;
  }

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

  test('flag is off in this variant', () {
    expect(allowTelegramTosViolations, isFalse);
  });

  testWidgets('story viewer reports openStory without ghost mode', (
    tester,
  ) async {
    await tester.pumpWidget(const _Harness(chatId: -10077, storyIds: [11, 12]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    expect(
      requests.where((request) => request['@type'] == 'openStory').length,
      1,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

/// Minimal host: the viewer reads l10n through the default (empty) catalogue,
/// so a bare MaterialApp is enough.
class _Harness extends StatelessWidget {
  const _Harness({required this.chatId, required this.storyIds});

  final int chatId;
  final List<int> storyIds;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: StoryViewerView(chatId: chatId, storyIds: storyIds),
  );
}
