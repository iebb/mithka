import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/global_theme_view.dart';
import 'package:mithka/theme/telegram_cloud_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows cached community themes before refresh completes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = ThemeController(prefs)
      ..synchronizeInstalledCloudThemes([_theme('Cached', 'Cached Theme')]);
    final refresh = Completer<List<TelegramCloudTheme>>();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: _themeTestApp(
          GlobalThemeView(themeService: _ControlledThemeService(refresh)),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Cached Theme'), findsOneWidget);
    expect(find.text('Loading themes…'), findsNothing);

    refresh.complete(controller.installedCloudThemes);
    await tester.pumpAndSettle();
  });

  testWidgets('successful refresh replaces and persists the cached set', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = ThemeController(prefs)
      ..synchronizeInstalledCloudThemes([_theme('Cached', 'Cached Theme')]);
    final refresh = Completer<List<TelegramCloudTheme>>();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: _themeTestApp(
          GlobalThemeView(themeService: _ControlledThemeService(refresh)),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Cached Theme'), findsOneWidget);

    refresh.complete([_theme('Fresh', 'Fresh Theme')]);
    await tester.pumpAndSettle();

    expect(find.text('Cached Theme'), findsNothing);
    expect(find.text('Fresh Theme'), findsOneWidget);
    final restored = ThemeController(prefs);
    expect(restored.installedCloudThemes.map((theme) => theme.slug), ['Fresh']);
  });

  testWidgets(
    'an external newer cache update wins over an older page refresh',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = ThemeController(prefs)
        ..synchronizeInstalledCloudThemes([_theme('Cached', 'Cached Theme')]);
      final refresh = Completer<List<TelegramCloudTheme>>();

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: controller,
          child: _themeTestApp(
            GlobalThemeView(themeService: _ControlledThemeService(refresh)),
          ),
        ),
      );
      await tester.pump();

      controller.synchronizeInstalledCloudThemes([
        _theme('External', 'Newer External Theme'),
      ]);
      await tester.pump();
      expect(find.text('Newer External Theme'), findsOneWidget);

      refresh.complete([_theme('Stale', 'Older Page Result')]);
      await tester.pumpAndSettle();

      expect(find.text('Older Page Result'), findsNothing);
      expect(controller.installedCloudThemes.single.slug, 'External');
    },
  );

  testWidgets('failed refresh retains the displayed and persisted cache', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = ThemeController(prefs)
      ..synchronizeInstalledCloudThemes([_theme('Cached', 'Cached Theme')]);
    final service = TelegramCloudThemeService(
      query: (_) => Future.error(StateError('offline')),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: _themeTestApp(GlobalThemeView(themeService: service)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cached Theme'), findsOneWidget);
    expect(controller.installedCloudThemes.single.slug, 'Cached');
    final restored = ThemeController(prefs);
    expect(restored.installedCloudThemes.single.slug, 'Cached');
  });

  testWidgets(
    'mounted account switch swaps cache and rejects the prior refresh',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = ThemeController(prefs, initialAccountUserId: 11)
        ..synchronizeInstalledCloudThemes([
          _theme('CachedA', 'Cached Account A'),
        ]);
      final accountARefresh = Completer<List<TelegramCloudTheme>>();
      final accountBRefresh = Completer<List<TelegramCloudTheme>>();
      final service = _QueuedThemeService([accountARefresh, accountBRefresh]);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: controller,
          child: _themeTestApp(GlobalThemeView(themeService: service)),
        ),
      );
      await tester.pump();
      expect(find.text('Cached Account A'), findsOneWidget);
      expect(service.requestCount, 1);

      controller.setActiveAccountSlot(1, userId: 22);
      await tester.pump();

      expect(find.text('Cached Account A'), findsNothing);
      expect(find.text('No community themes installed'), findsOneWidget);
      expect(controller.installedCloudThemes, isEmpty);
      expect(service.requestCount, 2);

      accountARefresh.complete([_theme('StaleA', 'Stale Account A')]);
      await tester.pump();
      expect(find.text('Stale Account A'), findsNothing);
      expect(controller.installedCloudThemes, isEmpty);

      accountBRefresh.complete([_theme('FreshB', 'Fresh Account B')]);
      await tester.pumpAndSettle();
      expect(find.text('Fresh Account B'), findsOneWidget);

      final restoredA = ThemeController(prefs, initialAccountUserId: 11);
      final restoredB = ThemeController(
        prefs,
        initialAccountSlot: 1,
        initialAccountUserId: 22,
      );
      expect(restoredA.installedCloudThemes.single.slug, 'CachedA');
      expect(restoredB.installedCloudThemes.single.slug, 'FreshB');
    },
  );

  testWidgets('separates official and community themes', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final service = TelegramCloudThemeService(
      query: (request) async {
        if (request['@type'] == 'getInstalledCloudThemes') {
          return {
            '@type': 'installedCloudThemes',
            'themes': const [
              {'slug': 'MountainSolitude', 'title': 'Mountain Solitude'},
              {'slug': 'SepiaBlues', 'title': 'Sepia Blues'},
              {'slug': 'wechatify_dark', 'title': 'WeChatify Dark'},
            ],
          };
        }
        final text = request['text'] as Map<String, dynamic>;
        final slug = Uri.parse(text['text'] as String).pathSegments.last;
        return _previewFor(slug);
      },
    );

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ThemeController(prefs),
        child: WidgetsApp(
          color: const Color(0xFF0099FF),
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [AppLocalizations.delegate],
          onGenerateRoute: (_) => PageRouteBuilder<void>(
            pageBuilder: (_, _, _) => GlobalThemeView(themeService: service),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Official'), findsOneWidget);
    expect(find.text('Customize'), findsNothing);
    expect(find.text('Community'), findsOneWidget);
    for (final title in ['Classic', 'Day', 'Dark', 'Night']) {
      expect(find.text(title), findsOneWidget);
    }
    for (final title in [
      'Mountain Solitude',
      'Sepia Blues',
      'WeChatify Dark',
    ]) {
      expect(find.text(title), findsOneWidget);
    }
    expect(
      find.byKey(const ValueKey('global-theme-brightness-picker')),
      findsOneWidget,
    );
    for (final slug in ['MountainSolitude', 'SepiaBlues', 'wechatify_dark']) {
      expect(
        find.byKey(ValueKey('global-theme-wallpaper-$slug')),
        findsOneWidget,
      );
    }

    await tester.tap(find.text('Classic'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('global-theme-color-grid')),
      findsOneWidget,
    );
    for (var index = 0; index < 8; index++) {
      expect(
        find.byKey(ValueKey('global-theme-semantic-swatch-$index')),
        findsOneWidget,
      );
    }
    expect(
      find.byKey(const ValueKey('global-theme-accent-list')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('global-theme-custom-accent')),
      findsOneWidget,
    );
    expect(find.text('Use default theme'), findsNothing);
    expect(
      find.text(
        'Import a Telegram theme for chats. Applying its colors to the rest of the app is optional.',
      ),
      findsNothing,
    );

    final selectedPill = tester.getSize(
      find.byKey(const ValueKey('global-theme-brightness-light')),
    );
    expect(selectedPill.height, 36);
  });

  testWidgets('day and night selection previews only the theme page', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'appearanceMode': 'light'});
    final prefs = await SharedPreferences.getInstance();
    final controller = ThemeController(prefs);
    final service = TelegramCloudThemeService(
      query: (_) async => {
        '@type': 'installedCloudThemes',
        'themes': const <Object>[],
      },
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: WidgetsApp(
          color: const Color(0xFF0099FF),
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [AppLocalizations.delegate],
          onGenerateRoute: (_) => PageRouteBuilder<void>(
            pageBuilder: (_, _, _) => Theme(
              data: ThemeData(
                brightness: Brightness.light,
                extensions: [AppColors.light],
              ),
              child: GlobalThemeView(themeService: service),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('global-theme-brightness-dark')),
    );
    await tester.pumpAndSettle();

    expect(
      Theme.of(
        tester.element(
          find.byKey(const ValueKey('global-theme-brightness-picker')),
        ),
      ).brightness,
      Brightness.dark,
    );
    expect(controller.mode, AppearanceMode.light);
  });

  testWidgets('theme picker omits the custom addtheme URL control', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final service = TelegramCloudThemeService(
      query: (_) async => {
        '@type': 'installedCloudThemes',
        'themes': const <Object>[],
      },
    );

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ThemeController(prefs),
        child: WidgetsApp(
          color: const Color(0xFF0099FF),
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [AppLocalizations.delegate],
          onGenerateRoute: (_) => PageRouteBuilder<void>(
            pageBuilder: (_, _, _) => GlobalThemeView(themeService: service),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('global-theme-link-control')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('global-theme-save-action')),
      findsNothing,
    );
    expect(find.text('https://t.me/addtheme/'), findsNothing);
    expect(find.text('Customize'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('conflicting imported theme confirms before switching mode', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = ThemeController(prefs);
    final service = TelegramCloudThemeService(
      query: (request) async {
        if (request['@type'] == 'getInstalledCloudThemes') {
          return {
            '@type': 'installedCloudThemes',
            'themes': const [
              {'slug': 'MountainSolitude', 'title': 'Mountain Solitude'},
            ],
          };
        }
        return _previewFor('MountainSolitude');
      },
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: WidgetsApp(
          color: const Color(0xFF0099FF),
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [AppLocalizations.delegate],
          onGenerateRoute: (_) => PageRouteBuilder<void>(
            pageBuilder: (_, _, _) => Theme(
              data: ThemeData(
                brightness: Brightness.dark,
                extensions: [AppColors.dark],
              ),
              child: GlobalThemeView(themeService: service),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<AnimatedContainer>(
            find.byKey(const ValueKey('global-theme-brightness-dark')),
          )
          .decoration,
      isA<BoxDecoration>(),
    );
    await tester.tap(find.text('Mountain Solitude'));
    await tester.pumpAndSettle();

    expect(find.text('Switch to Light mode?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('app-confirm-cancel')));
    await tester.pumpAndSettle();

    expect(controller.lightCloudTheme, isNull);
    expect(controller.darkCloudTheme, isNull);

    await tester.tap(find.text('Mountain Solitude'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('app-confirm-accept')));
    await tester.pumpAndSettle();
    expect(find.text('Use this theme’s wallpaper too?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('app-confirm-cancel')));
    await tester.pumpAndSettle();

    expect(controller.lightCloudTheme?.slug, 'MountainSolitude');
    expect(controller.darkCloudTheme, isNull);
    expect(controller.mode, AppearanceMode.light);
  });
}

Widget _themeTestApp(Widget child) => MaterialApp(
  locale: const Locale('en'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [AppLocalizations.delegate],
  theme: ThemeData(extensions: [AppColors.light]),
  home: child,
);

class _ControlledThemeService extends TelegramCloudThemeService {
  _ControlledThemeService(this.result) : super(query: (_) async => const {});

  final Completer<List<TelegramCloudTheme>> result;

  @override
  Future<List<TelegramCloudTheme>> loadInstalled({
    Iterable<TelegramCloudTheme> fallback = const [],
  }) => result.future;
}

class _QueuedThemeService extends TelegramCloudThemeService {
  _QueuedThemeService(this.results) : super(query: (_) async => const {});

  final List<Completer<List<TelegramCloudTheme>>> results;
  int requestCount = 0;

  @override
  Future<List<TelegramCloudTheme>> loadInstalled({
    Iterable<TelegramCloudTheme> fallback = const [],
  }) {
    final index = requestCount++;
    return results[index].future;
  }
}

TelegramCloudTheme _theme(String slug, String title) => TelegramCloudTheme(
  slug: slug,
  rawTitle: title,
  baseTheme: 'builtInThemeDay',
  accentColorValue: 0x2481CC,
  outgoingColors: const [0xD8F3FF],
  palette: const {},
);

Map<String, dynamic> _previewFor(String slug) => {
  '@type': 'linkPreview',
  'title': 'Preview $slug',
  'type': {
    '@type': 'linkPreviewTypeTheme',
    'documents': const <Object>[],
    'settings': {
      '@type': 'themeSettings',
      'base_theme': {'@type': 'builtInThemeDay'},
      'accent_color': 0x2481CC,
      'background': {
        '@type': 'background',
        'id': '1',
        'type': {
          '@type': 'backgroundTypeFill',
          'fill': {
            '@type': 'backgroundFillGradient',
            'top_color': 0x18263B,
            'bottom_color': 0xF3B4BD,
            'rotation_angle': 0,
          },
        },
      },
      'outgoing_message_fill': {
        '@type': 'backgroundFillSolid',
        'color': 0xD8F3FF,
      },
    },
  },
};
