import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/gallery_send_mode_sheet.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/app_theme.dart';

void main() {
  testWidgets('gallery sheet offers media and original file modes', (
    tester,
  ) async {
    GallerySendMode? selected;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'Hans'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppColors.light]),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: GestureDetector(
                key: const ValueKey('openGallerySendMode'),
                behavior: HitTestBehavior.opaque,
                onTap: () async {
                  selected = await showGallerySendModeSheet(context);
                },
                child: const SizedBox(width: 80, height: 44),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('openGallerySendMode')));
    await tester.pumpAndSettle();

    expect(find.text('作为图片或视频发送'), findsOneWidget);
    expect(find.text('作为文件发送'), findsOneWidget);
    expect(find.text('从相册选择并发送原始文件'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('gallerySendAsFile')));
    await tester.pumpAndSettle();
    expect(selected, GallerySendMode.file);
  });
}
