//
//  composer_panel_scroll_dismiss_test.dart
//
//  Scrolling the transcript must fold the composer's open panels the same way
//  the OS folds the text keyboard on drag. The view model exposes a dismiss
//  tick the input bar syncs from, exactly like the composer focus tick.
//

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_input_bar.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_bindings.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // The media panel opens real stores; give the client a synthetic registry
    // whose queries answer with empty sets so no store throws into the zone.
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    final supportDir = await Directory.systemTemp.createTemp(
      'mithka_composer_dismiss',
    );
    addTearDown(() {
      if (supportDir.existsSync()) supportDir.deleteSync(recursive: true);
    });
    TdClient.shared.prepareForTesting(
      prefs: prefs,
      supportDir: supportDir.path,
      bindings: _FakeBindings(),
      queryOverride: (request, clientId) async => switch (request['@type']) {
        'getOption' => {'@type': 'optionValueBoolean', 'value': false},
        'getInstalledStickerSets' => {'@type': 'stickerSets', 'sets': []},
        'getRecentStickers' => {
          '@type': 'stickers',
          'stickers': <Map<String, dynamic>>[],
        },
        'getSavedAnimations' => {
          '@type': 'animations',
          'animations': <Map<String, dynamic>>[],
        },
        _ => {'@type': 'ok'},
      },
    );
    final slot = TdClient.shared.addSlot();
    final clientId = TdClient.shared.clientId(slot);
    TdClient.shared.debugSetActiveAccountForTesting(slot, clientId ?? 0);
  });

  test('dismissComposerPanels bumps the tick and notifies', () {
    final vm = ChatViewModel(chatId: 1, title: 'Test', markReadOnOpen: false);
    addTearDown(vm.dispose);

    var notifications = 0;
    vm.addListener(() => notifications++);
    final before = vm.composerDismissTick;

    expect(notifications, 0);
    vm.dismissComposerPanels();

    expect(vm.composerDismissTick, before + 1);
    expect(notifications, 1);
  });

  testWidgets('an open media panel collapses when the vm dismisses', (
    tester,
  ) async {
    final vm = await _pumpComposer(tester);
    final icon = find.byIcon(HeroAppIcons.solidFaceSmile.data).first;

    expect(find.byKey(const ValueKey('mediaKindSegments')), findsNothing);
    await tester.tap(icon);
    await tester.pump();
    expect(find.byKey(const ValueKey('mediaKindSegments')), findsOneWidget);

    vm.dismissComposerPanels();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const ValueKey('mediaKindSegments')), findsNothing);
  });
}

Future<ChatViewModel> _pumpComposer(WidgetTester tester) async {
  final vm = ChatViewModel(chatId: 1, title: 'Test', markReadOnOpen: false);
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
      theme: ThemeData(
        platform: TargetPlatform.android,
        extensions: [AppColors.light],
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: ChatInputBar(
            vm: vm,
            quickRepliesEnabled: false,
            onStartCall: (_) {},
            onMessageSent: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return vm;
}

/// Synthetic tdjson bindings: lets [TdClient.prepareForTesting] register a
/// client without loading the pinned shared library.
class _FakeBindings implements TdBindings {
  int _nextClientId = 100;

  @override
  int createClientId() => _nextClientId++;

  @override
  void send(int clientId, String request) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
