import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mithka/call/call_manager.dart';
import 'package:mithka/call/call_media_engine.dart';
import 'package:mithka/call/call_screen.dart';

/// Retained focused regression from the removed `call_screen_test.dart` suite
/// (master pruned it during the test reduction): the native video surface is a
/// tgcalls engine capability, not a property of the mobile form factor. On a
/// mobile host whose engine is unavailable (HarmonyOS today) the placeholder
/// glyph must stay instead of mounting a platform view nothing renders into.
void main() {
  testWidgets(
    'a mobile host without the call engine keeps the placeholder view',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final manager = CallManager(engine: NoopCallMediaEngine());
      addTearDown(manager.dispose);

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        manager.call = ActiveCall(
          callId: 50,
          peerUserId: 13,
          peerName: 'Capability contact',
          isOutgoing: true,
          isVideo: true,
          phase: CallPhase.active,
          startedAt: DateTime.now(),
        );
        manager.isVideoEnabled = true;

        await tester.pumpWidget(
          MaterialApp(
            home: AnimatedBuilder(
              animation: manager,
              builder: (context, child) => CallScreen(manager: manager),
            ),
          ),
        );

        expect(manager.supportsMediaCalls, isFalse);
        // Local preview falls back to the glyph instead of a platform view.
        expect(find.byKey(const Key('callLocalPreview')), findsOneWidget);
        expect(find.byType(AndroidView), findsNothing);
        expect(find.byType(UiKitView), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
