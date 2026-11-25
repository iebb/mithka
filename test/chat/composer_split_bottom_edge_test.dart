import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/main_tab_view.dart';
import 'package:mithka/app/scaled_app_view.dart';
import 'package:mithka/app/top_corner_cluster.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/chat/composer/chat_input_bar.dart';
import 'package:mithka/components/app_interactive_surface.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// An opened iPhone Duo as the platform reports it, in window points.
const _openedDuo = TopOcclusionData(
  safeTop: 82,
  statusBarBottom: 2,
  windowWidth: 951,
  regions: [Rect.fromLTWH(807, 0, 144, 82)],
);

class _ViewModel extends ChatViewModel {
  _ViewModel() : super(chatId: 1, title: 'Test', markReadOnOpen: false);

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
}

final _imageButton = find.byWidgetPredicate(
  (w) =>
      w is AppInteractiveSurface &&
      w.semanticLabel == AppStrings.t(AppStringKeys.composerImage),
);

void main() {
  for (final s in const [1.0, 0.9487, 1.483]) {
    testWidgets(
      'opened Duo split: the icon row ends level with the tab labels at s=$s',
      (tester) async {
        await _pump(tester, scale: s, split: true);
        final row = tester.getRect(_imageButton);
        expect(row.height, moreOrLessEquals(44 * s));
        final label = tester.getRect(find.text('Messages'));
        expect(row.bottom, moreOrLessEquals(label.bottom, epsilon: 0.5));
        // The glyphs stay above the home indicator (its top is ~13pt up).
        expect(669 - (row.bottom - 10 * s), greaterThan(13));
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }

  testWidgets(
    'without the band the composer keeps the full bottom safe area',
    (tester) async {
      await _pump(tester, scale: 1, split: false);
      final row = tester.getRect(_imageButton);
      // 8pt strip padding plus the reported 34pt inset.
      expect(669 - row.bottom, moreOrLessEquals(42));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required double scale,
  required bool split,
}) async {
  tester.view.physicalSize = const Size(951, 669);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 82, bottom: 34);
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({'liquidGlassBottomBar': false});
  final prefs = await SharedPreferences.getInstance();
  final theme = ThemeController(prefs);
  addTearDown(theme.dispose);
  final accounts = AccountStore(prefs);
  addTearDown(accounts.dispose);
  final vm = _ViewModel();
  addTearDown(vm.dispose);

  final composer = Align(
    alignment: Alignment.bottomCenter,
    child: ChatInputBar(
      vm: vm,
      quickRepliesEnabled: false,
      onStartCall: (_) {},
      onMessageSent: () {},
    ),
  );
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeController>.value(value: theme),
        ChangeNotifierProvider<AccountStore>.value(value: accounts),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppColors.light]),
        builder: (context, child) => ScaledAppView(
          textScale: 1,
          interfaceScale: scale,
          child: Builder(
            builder: (context) => TopOcclusionGeometry(
              data: split
                  ? _openedDuo.inViewScale(ScaledAppView.scaleOf(context))
                  : null,
              child: child!,
            ),
          ),
        ),
        home: Scaffold(
          body: Row(
            children: [
              SizedBox(
                width: 400 / scale,
                child: TopClusterPane(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: mainBottomBarForTesting(
                      selection: 0,
                      onSelect: (_) {},
                      onClearUnread: () {},
                      reserveBottomInset: false,
                    ),
                  ),
                ),
              ),
              Expanded(child: TopClusterPane(child: composer)),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
