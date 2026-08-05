import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/l10n/app_localizations.dart';

import 'support/l10n_fixtures.dart';

final fixtures = L10nFixtures.load();

void main() {
  test('diagnostic feedback copy exists in every supported locale', () {
    final tables = [
      fixtures.messages('en'),
      fixtures.messages('de'),
      fixtures.messages('es'),
      fixtures.messages('fr'),
      fixtures.messages('ja'),
      fixtures.messages('ko'),
      fixtures.messages('zhHans'),
      fixtures.messages('zhHant'),
    ];
    const keys = [
      AppStringKeys.aboutReportProblem,
      AppStringKeys.aboutReportProblemDetail,
      AppStringKeys.feedbackReportDescription,
      AppStringKeys.feedbackReportFailed,
      AppStringKeys.feedbackReportPlaceholder,
      AppStringKeys.feedbackReportPrivacy,
      AppStringKeys.feedbackReportSend,
      AppStringKeys.feedbackReportSending,
      AppStringKeys.feedbackReportSent,
      AppStringKeys.feedbackReportTitle,
    ];

    for (final table in tables) {
      for (final key in keys) {
        expect(table[key]?.trim(), isNotEmpty, reason: 'missing $key');
      }
      expect(table[AppStringKeys.feedbackReportSent], contains('{value1}'));
    }
  });
}
