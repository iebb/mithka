import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_input_bar.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/chat/message_send_options.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/components/app_interactive_surface.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/app_theme.dart';

class _SendSplitButtonViewModel extends ChatViewModel {
  _SendSplitButtonViewModel()
    : super(chatId: 1, title: 'Test', markReadOnOpen: false);

  @override
  void sendTyping() {}

  @override
  void setDraft(
    String value, {
    String? formattedText,
    List<Map<String, dynamic>> entities = const [],
  }) {
    draft = value;
  }

  @override
  Future<bool> prepareMessageSend() async => true;

  @override
  Future<bool> currentUserIsPremium() async => true;

  @override
  Future<bool> sendFormatted(
    String text,
    List<Map<String, dynamic>> entities,
  ) async => true;

  MessageSendConfiguration? selectedConfiguration;

  @override
  void useNextSendConfiguration(MessageSendConfiguration configuration) {
    selectedConfiguration = configuration;
    super.useNextSendConfiguration(configuration);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'desktop composer exposes send options as a visible keyboard control',
    (tester) async {
      final vm = await _pumpComposer(tester, platform: TargetPlatform.macOS);
      await tester.enterText(find.byType(TextField).first, 'hello');
      await tester.pump();

      final primary = find.byKey(const ValueKey('composerSendButton'));
      final options = find.byKey(
        const ValueKey('desktopComposerSendOptionsButton'),
      );
      expect(primary, findsOneWidget);
      expect(options, findsOneWidget);

      final primarySurface = tester.widget<AppInteractiveSurface>(primary);
      expect(primarySurface.onLongPress, isNotNull);
      final optionsSurface = tester.widget<AppInteractiveSurface>(options);
      expect(optionsSurface.semanticLabel, 'Send options');
      expect(optionsSurface.enabled, isTrue);
      expect(optionsSurface.onTap, isNotNull);
      expect(
        find.descendant(
          of: options,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is AppIcon && widget.icon == HeroAppIcons.chevronDown,
          ),
        ),
        findsOneWidget,
      );

      final focusable = tester.widget<FocusableActionDetector>(
        find.descendant(
          of: options,
          matching: find.byType(FocusableActionDetector),
        ),
      );
      expect(focusable.enabled, isTrue);
      expect(
        focusable.shortcuts?.keys,
        contains(
          const SingleActivator(
            LogicalKeyboardKey.enter,
            includeRepeats: false,
          ),
        ),
      );

      await tester.tap(options);
      await tester.pumpAndSettle();
      final menu = find.byKey(const ValueKey('messageSendOptionsContextMenu'));
      expect(menu, findsOneWidget);
      expect(
        find.byKey(const ValueKey('messageSendOptionsSurface')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('messageSendOptionsModalFrame')),
        findsNothing,
      );
      expect(
        tester.getBottomRight(menu).dy,
        lessThan(tester.getTopRight(options).dy),
      );

      await tester.tap(find.text('Send silently'));
      await tester.pump();
      final confirm = find.byKey(const ValueKey('messageSendOptionsConfirm'));
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(vm.selectedConfiguration?.disableNotification, isTrue);
      expect(menu, findsNothing);

      await tester.enterText(find.byType(TextField).first, 'again');
      await tester.pump();
      await tester.tap(options);
      await tester.pumpAndSettle();
      expect(menu, findsOneWidget);

      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(menu, findsNothing);

      await tester.tap(options);
      await tester.pumpAndSettle();
      expect(menu, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(menu, findsNothing);
    },
  );

  testWidgets('mobile composer keeps the circular long-press send control', (
    tester,
  ) async {
    await _pumpComposer(tester, platform: TargetPlatform.iOS);
    await tester.enterText(find.byType(TextField).first, 'hello');
    await tester.pump();

    expect(
      find.byKey(const ValueKey('desktopComposerSendOptionsButton')),
      findsNothing,
    );
    final sendFinder = find.byKey(const ValueKey('composerSendButton'));
    final send = tester.widget<AppInteractiveSurface>(sendFinder);
    expect(send.onLongPress, isNotNull);
    expect(tester.getSize(sendFinder), const Size(44, 44));

    final circularVisual = find.descendant(
      of: sendFinder,
      matching: find.byWidgetPredicate((widget) {
        if (widget is! Container) return false;
        final decoration = widget.decoration;
        return decoration is BoxDecoration &&
            decoration.shape == BoxShape.circle;
      }),
    );
    expect(circularVisual, findsOneWidget);
    expect(tester.getSize(circularVisual), const Size(36, 36));
  });
}

Future<_SendSplitButtonViewModel> _pumpComposer(
  WidgetTester tester, {
  required TargetPlatform platform,
}) async {
  final vm = _SendSplitButtonViewModel();
  addTearDown(vm.dispose);
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
      theme: ThemeData(platform: platform, extensions: [AppColors.light]),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: ChatInputBar(
            vm: vm,
            enterToSend: true,
            quickRepliesEnabled: false,
            onStartCall: (_) {},
            onMessageSent: () {},
          ),
        ),
      ),
    ),
  );
  return vm;
}
