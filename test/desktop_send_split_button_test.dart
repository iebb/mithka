import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_input_bar.dart';
import 'package:mithka/chat/chat_view_model.dart';
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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'desktop composer exposes send options as a visible keyboard control',
    (tester) async {
      await _pumpComposer(tester, platform: TargetPlatform.macOS);
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
      expect(
        find.byKey(const ValueKey('messageSendOptionsSurface')),
        findsOneWidget,
      );
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
    final send = tester.widget<GestureDetector>(
      find.byKey(const ValueKey('composerSendButton')),
    );
    expect(send.onLongPress, isNotNull);
    final decoration = (send.child! as Container).decoration! as BoxDecoration;
    expect(decoration.shape, BoxShape.circle);
  });
}

Future<void> _pumpComposer(
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
}
