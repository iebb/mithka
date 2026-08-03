import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/desktop_utility_window.dart';
import 'package:mithka/profile/adaptive_profile_launcher.dart';

void main() {
  testWidgets(
    'desktop profile launcher requests a user-profile utility window',
    (tester) async {
      DesktopUtilityWindowArguments? request;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => openAdaptiveUserProfile(
                context,
                userId: 42,
                name: 'Ada',
                platform: TargetPlatform.macOS,
                desktopWindowsSupported: true,
                desktopWindowOpener: (arguments) async {
                  request = arguments;
                  return true;
                },
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pump();

      expect(request?.kind, DesktopUtilityWindowKind.userProfile);
      expect(request?.userId, 42);
      expect(request?.title, 'Ada');
      expect(request?.accountSlot, 0);
    },
  );

  testWidgets('profile launcher preserves caller fallback off desktop', (
    tester,
  ) async {
    var fallbackCalls = 0;
    var desktopCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => openAdaptiveUserProfile(
              context,
              userId: 7,
              name: 'Grace',
              platform: TargetPlatform.iOS,
              desktopWindowsSupported: true,
              desktopWindowOpener: (_) async {
                desktopCalls++;
                return true;
              },
              openFallback: () => fallbackCalls++,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump();

    expect(desktopCalls, 0);
    expect(fallbackCalls, 1);
  });

  testWidgets('desktop window failure falls back without replacing contract', (
    tester,
  ) async {
    var fallbackCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => openAdaptiveUserProfile(
              context,
              userId: 7,
              name: 'Grace',
              platform: TargetPlatform.windows,
              desktopWindowsSupported: true,
              desktopWindowOpener: (_) async => false,
              openFallback: () => fallbackCalls++,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump();

    expect(fallbackCalls, 1);
  });
}
