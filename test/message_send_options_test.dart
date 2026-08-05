import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:mithka/chat/message_send_options.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/app_theme.dart';

void main() {
  test('send options presentation adapts to desktop and landscape iPad', () {
    expect(
      messageSendOptionsUsesCenteredModal(
        const Size(1440, 900),
        TargetPlatform.macOS,
      ),
      isTrue,
    );
    expect(
      messageSendOptionsUsesCenteredModal(
        const Size(820, 1180),
        TargetPlatform.iOS,
      ),
      isFalse,
    );
    expect(
      messageSendOptionsUsesCenteredModal(
        const Size(1180, 820),
        TargetPlatform.iOS,
      ),
      isTrue,
    );
    expect(
      messageSendOptionsUsesCenteredModal(
        const Size(852, 393),
        TargetPlatform.iOS,
      ),
      isFalse,
    );
  });

  test(
    'send options implementation does not use Material sheet or pickers',
    () {
      final source = File(
        'lib/chat/message_send_options.dart',
      ).readAsStringSync();

      expect(source, isNot(contains('package:flutter/material.dart')));
      expect(source, isNot(contains('showModalBottomSheet')));
      expect(source, isNot(contains('showDatePicker')));
      expect(source, isNot(contains('showTimePicker')));
    },
  );

  testWidgets('owned sheets paint through the bottom safe area', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    tester.view.padding = const FakeViewPadding(bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
      tester.view.resetPadding();
      tester.view.resetViewPadding();
    });
    final previousLocale = Intl.defaultLocale;
    Intl.defaultLocale = 'zh_Hans';
    addTearDown(() => Intl.defaultLocale = previousLocale);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hans',
        ),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(393, 852),
            padding: EdgeInsets.only(bottom: 34),
          ),
          child: Builder(
            builder: (context) => GestureDetector(
              key: const ValueKey('openSendOptions'),
              behavior: HitTestBehavior.opaque,
              onTap: () =>
                  showMessageSendOptionsSheet(context, allowWhenOnline: true),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('openSendOptions')));
    await tester.pumpAndSettle();

    final sendSurface = tester.widget<Container>(
      find.byKey(const ValueKey('messageSendOptionsSurface')),
    );
    expect(sendSurface.padding, const EdgeInsets.only(bottom: 34));
    expect(find.text('发送选项'), findsOneWidget);
    expect(find.text('发送时间'), findsOneWidget);

    await tester.tap(find.text('选择日期'));
    await tester.pumpAndSettle();

    final pickerSurface = tester.widget<Container>(
      find.byKey(const ValueKey('ownedSchedulePicker')),
    );
    expect(pickerSurface.padding, const EdgeInsets.only(bottom: 34));
    expect(find.text('选择日期和时间'), findsOneWidget);
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.byType(TimePickerDialog), findsNothing);
  });

  testWidgets('landscape iPad uses a bounded centered send-options modal', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 820);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
      debugDefaultTargetPlatformOverride = null;
    });

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => GestureDetector(
            key: const ValueKey('openSendOptions'),
            behavior: HitTestBehavior.opaque,
            onTap: () => showMessageSendOptionsSheet(context),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('openSendOptions')));
    await tester.pumpAndSettle();

    final frame = find.byKey(const ValueKey('messageSendOptionsModalFrame'));
    expect(frame, findsOneWidget);
    expect(tester.getSize(frame).width, 560);
    expect(
      find.byKey(const ValueKey('messageSendOptionsDragHandle')),
      findsNothing,
    );
    final surface = tester.widget<Container>(
      find.byKey(const ValueKey('messageSendOptionsSurface')),
    );
    expect(surface.padding, EdgeInsets.zero);
    expect(
      (surface.decoration! as BoxDecoration).borderRadius,
      BorderRadius.circular(AppRadius.xl),
    );

    await tester.tap(find.text('Choose date'));
    await tester.pumpAndSettle();
    final pickerFrame = find.byKey(
      const ValueKey('ownedSchedulePickerModalFrame'),
    );
    expect(pickerFrame, findsOneWidget);
    expect(tester.getSize(pickerFrame).width, 480);
    expect(
      find.byKey(const ValueKey('ownedSchedulePickerDragHandle')),
      findsNothing,
    );
    final pickerSurface = tester.widget<Container>(
      find.byKey(const ValueKey('ownedSchedulePicker')),
    );
    expect(pickerSurface.padding, EdgeInsets.zero);
    debugDefaultTargetPlatformOverride = null;
  });
}
