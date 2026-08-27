import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_row_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/app_icon_controller.dart';
import 'package:mithka/settings/appearance_view.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ThemeController> _controller(double fontScale) async {
  SharedPreferences.setMockInitialValues({'fontScale': fontScale});
  final prefs = await SharedPreferences.getInstance();
  return ThemeController(prefs);
}

void main() {
  test('the platform default renders the app at its designed sizes', () async {
    final controller = await _controller(1.0);
    addTearDown(controller.dispose);

    // A regression guard: anything other than 1.0 here means a fresh install
    // draws smaller or larger than the sizes the app is designed at.
    expect(controller.effectiveTextScale(const TextScaler.linear(1.0)), 1.0);
  });

  test('a system text size below the default never shrinks the app', () async {
    final controller = await _controller(1.0);
    addTearDown(controller.dispose);

    expect(controller.effectiveTextScale(const TextScaler.linear(0.85)), 1.0);
  });

  test('a larger system text size still carries into the app', () async {
    final controller = await _controller(1.5);
    addTearDown(controller.dispose);

    expect(controller.effectiveTextScale(const TextScaler.linear(1.0)), 1.5);
    expect(
      controller.effectiveTextScale(const TextScaler.linear(1.2)),
      closeTo(1.8, 0.0001),
    );
  });

  test('the composed scale stays inside the tested range', () async {
    final large = await _controller(ThemeController.maxFontScale);
    addTearDown(large.dispose);
    expect(
      large.effectiveTextScale(const TextScaler.linear(2.0)),
      ThemeController.maxFontScale,
    );

    final small = await _controller(ThemeController.minFontScale);
    addTearDown(small.dispose);
    expect(
      small.effectiveTextScale(const TextScaler.linear(1.0)),
      ThemeController.minFontScale,
    );
  });

  testWidgets('a chat list row grows with the text scale instead of clipping', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    addTearDown(theme.dispose);
    final chat = ChatSummary(
      id: 7,
      title: 'Mithka Users',
      lastMessage: 'A preview line that has to fit inside the row.',
      lastMessageId: 1,
      date: 0,
      unreadCount: 0,
      order: 1,
      isMuted: false,
    );

    Future<double> heightAt(double textScale) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: MaterialApp(
            locale: const Locale('en'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [AppLocalizations.delegate],
            theme: ThemeData(
              brightness: Brightness.light,
              extensions: [AppColors.light],
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child ?? const SizedBox.shrink(),
            ),
            home: Scaffold(body: ChatRowView(chat: chat)),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      return tester.getSize(find.byType(ChatRowView)).height;
    }

    final normal = await heightAt(1.0);
    final doubled = await heightAt(2.0);

    expect(normal, AppMetric.chatListRowHeight());
    expect(doubled, greaterThan(normal));
    // The avatar and the horizontal padding do not grow with the text, so the
    // row must stay well short of a plain doubling.
    expect(doubled, lessThan(normal * 2));
  });

  testWidgets('the font size page holds together at the largest scale', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({
      'fontScale': ThemeController.maxFontScale,
    });
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    addTearDown(theme.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeController>.value(value: theme),
          ChangeNotifierProvider(create: (_) => AppIconController(prefs)),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [AppLocalizations.delegate],
          theme: ThemeData(
            brightness: Brightness.light,
            platform: TargetPlatform.android,
            extensions: [AppColors.light],
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(
                theme.effectiveTextScale(MediaQuery.textScalerOf(context)),
              ),
            ),
            child: child ?? const SizedBox.shrink(),
          ),
          home: const AppearanceView(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Font'));
    await tester.pumpAndSettle();
    final fontSizeRow = find.text('Font Size').first;
    await tester.ensureVisible(fontSizeRow);
    await tester.tap(fontSizeRow);
    await tester.pumpAndSettle();

    // Both previews follow the setting now that it reaches every surface.
    expect(
      find.byKey(const ValueKey('font-size-chat-preview')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('font-size-chat-list-preview')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
