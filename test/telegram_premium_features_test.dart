import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/telegram_link_details_view.dart';
import 'package:mithka/chat/telegram_premium_features.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('folder-tag upsell sends the exact Business feature source', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    addTearDown(theme.dispose);
    final requests = <Map<String, dynamic>>[];

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [AppLocalizations.delegate],
          theme: ThemeData(extensions: [AppColors.light]),
          home: Builder(
            builder: (context) => GestureDetector(
              key: const ValueKey('open-folder-tag-premium'),
              behavior: HitTestBehavior.opaque,
              onTap: () => unawaited(
                openTelegramPremiumBusinessFeature(
                  context,
                  feature: const {'@type': 'businessFeatureChatFolderTags'},
                  query: (request) async {
                    requests.add(request);
                    return {
                      '@type': 'premiumFeatures',
                      'features': <Object>[],
                      'limits': <Object>[],
                    };
                  },
                ),
              ),
              child: const SizedBox(width: 100, height: 50),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('open-folder-tag-premium')));
    await tester.pumpAndSettle();

    expect(requests, [
      {
        '@type': 'getPremiumFeatures',
        'source': {
          '@type': 'premiumSourceBusinessFeature',
          'feature': {'@type': 'businessFeatureChatFolderTags'},
        },
      },
    ]);
    expect(find.byType(TelegramLinkDetailsView), findsOneWidget);
    expect(
      find.text(AppStrings.t(AppStringKeys.linkHandlerTelegramPremium)),
      findsWidgets,
    );
  });

  testWidgets('low-level Premium route preserves query failures', (
    tester,
  ) async {
    late NavigatorState navigator;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            navigator = Navigator.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    await expectLater(
      pushTelegramPremiumFeatures(
        navigator,
        source: const {'@type': 'premiumSourceLink', 'referrer': 'test'},
        query: (_) async => throw StateError('query failed'),
      ),
      throwsStateError,
    );
    expect(find.byType(TelegramLinkDetailsView), findsNothing);
  });
}
