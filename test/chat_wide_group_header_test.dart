import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/adaptive_split_layout.dart';
import 'package:mithka/chat/chat_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/app_theme.dart';

void main() {
  test('wide group header policy preserves compact mobile headers', () {
    expect(
      wideGroupHeaderActionsEnabled(
        const Size(500, 700),
        isGroup: true,
        hasContextPaneToggle: false,
        platform: TargetPlatform.macOS,
        isWeb: false,
      ),
      isTrue,
    );
    expect(
      wideGroupHeaderActionsEnabled(
        const Size(1100, 800),
        isGroup: true,
        hasContextPaneToggle: true,
        platform: TargetPlatform.iOS,
        isWeb: false,
      ),
      isTrue,
    );
    expect(
      wideGroupHeaderActionsEnabled(
        const Size(390, 844),
        isGroup: true,
        hasContextPaneToggle: false,
        platform: TargetPlatform.iOS,
        isWeb: false,
      ),
      isFalse,
    );
    expect(
      wideGroupHeaderActionsEnabled(
        const Size(1100, 800),
        isGroup: false,
        hasContextPaneToggle: false,
        platform: TargetPlatform.iOS,
        isWeb: false,
      ),
      isFalse,
    );
  });

  testWidgets('wide group actions expose calls, context toggle, and settings', (
    tester,
  ) async {
    final calls = <bool>[];
    var contextTaps = 0;
    var fullInfoTaps = 0;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
          brightness: Brightness.light,
          extensions: [AppColors.light],
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: WideGroupChatHeaderActions(
              onStartCall: calls.add,
              onToggleContext: () => contextTaps++,
              onOpenFullInfo: () => fullInfoTaps++,
            ),
          ),
        ),
      ),
    );

    final voice = find.byKey(const ValueKey('chatHeaderGroupVoiceCall'));
    final video = find.byKey(const ValueKey('chatHeaderGroupVideoCall'));
    final context = find.byKey(const ValueKey('chatHeaderGroupContextToggle'));
    final info = find.byKey(const ValueKey('chatHeaderFullInfo'));
    expect(voice, findsOneWidget);
    expect(video, findsOneWidget);
    expect(context, findsOneWidget);
    expect(info, findsOneWidget);

    await tester.tap(voice);
    await tester.tap(video);
    await tester.tap(context);
    await tester.tap(info);

    expect(calls, [false, true]);
    expect(contextTaps, 1);
    expect(fullInfoTaps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide group actions can omit unsupported macOS calls', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
          brightness: Brightness.light,
          extensions: [AppColors.light],
        ),
        home: Scaffold(
          body: WideGroupChatHeaderActions(
            showCallActions: false,
            onStartCall: (_) {},
            onToggleContext: () {},
            onOpenFullInfo: () {},
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('chatHeaderGroupVoiceCall')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('chatHeaderGroupVideoCall')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('chatHeaderGroupContextToggle')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('chatHeaderFullInfo')), findsOneWidget);
  });

  testWidgets(
    'full-width chat header leaves no blank gutter above trailing context',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 500);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
            brightness: Brightness.light,
            extensions: [AppColors.light],
          ),
          home: Scaffold(
            body: ChatHeaderTrailingPaneLayout(
              header: SizedBox(
                key: const ValueKey('testFullHeader'),
                height: 56,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: WideGroupChatHeaderActions(
                    onStartCall: (_) {},
                    onToggleContext: () {},
                    onOpenFullInfo: () {},
                  ),
                ),
              ),
              body: const SizedBox(key: ValueKey('testConversationBody')),
              trailingPane: const SizedBox(key: ValueKey('testContextPane')),
              trailingPaneWidth: desktopInfoPaneWidth,
            ),
          ),
        ),
      );

      final header = find.byKey(const ValueKey('chatFullWidthHeader'));
      final body = find.byKey(const ValueKey('chatConversationContent'));
      final pane = find.byKey(const ValueKey('chatTrailingContextPane'));
      final finalAction = find.byKey(const ValueKey('chatHeaderFullInfo'));

      expect(tester.getSize(header).width, 800);
      expect(tester.getBottomRight(finalAction).dx, 800);
      expect(tester.getTopLeft(body).dy, tester.getBottomLeft(header).dy);
      expect(tester.getTopLeft(pane).dy, tester.getBottomLeft(header).dy);
      expect(tester.getTopLeft(pane).dx - tester.getBottomRight(body).dx, 1);
      expect(tester.getSize(pane).width, desktopInfoPaneWidth);
      expect(tester.getBottomRight(pane).dx, 800);
      expect(
        tester.getSize(body).width,
        800 - desktopInfoPaneHandleWidth - desktopInfoPaneWidth,
      );
    },
  );
}
