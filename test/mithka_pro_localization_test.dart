import 'package:flutter_test/flutter_test.dart';

import 'support/l10n_fixtures.dart';

final fixtures = L10nFixtures.load();

void main() {
  test('all supported locale maps own the Pro and backup consent copy', () {
    const keys = {
      'accountBackupLoginAndroid',
      'accountBackupLoginDescription',
      'accountBackupLoginICloud',
      'accountBackupNoticeAndroid',
      'accountBackupNoticeICloud',
      'accountBackupUnavailable',
      'mithkaProActive',
      'mithkaProActiveUntil',
      'mithkaProBestValue',
      'mithkaProBillingNotice',
      'mithkaProContinue',
      'mithkaProManagePlan',
      'mithkaProMonthly',
      'mithkaProNothingToRestore',
      'mithkaProPerMonth',
      'mithkaProPerYear',
      'mithkaProPurchaseFailed',
      'mithkaProPrivacy',
      'mithkaProRestore',
      'mithkaProRestoreFailed',
      'mithkaProStoreUnavailable',
      'mithkaProSupportDevelopment',
      'mithkaProSupportDevelopmentDescription',
      'mithkaProSupportOnly',
      'mithkaProTerms',
      'mithkaProTitle',
      'mithkaProYearly',
      'supporterFunctionalAccess',
      'supporterIcons',
      'supporterIconsBenefit',
      'supporterIconsMobileBenefit',
      'supporterIconsCaption',
      'supporterIconAccess',
      'supporterIconLockedHint',
      'supporterIconAccessibility',
      'supporterIconRequired',
      'supporterIconSelected',
      'supporterIconAvailable',
      'supporterPlansLoading',
      'supporterPlansUnavailable',
      'supporterPlansRetry',
      'supporterPurchasePending',
      'supporterPurchaseSuccess',
      'supporterRestoring',
      'supporterRestoreSuccess',
      'supporterBillingNoticeGoogle',
      'supporterNothingToRestoreGoogle',
      'appIconPilot',
      'appIconHeadphones',
      'appIconWinter',
      'appIconAstronaut',
      'appIconCrown',
      'appIconParty',
      'appIconSleepy',
      'appIconHeart',
      'appIconCoffee',
      'appIconDetective',
      'appIconGamer',
      'appIconFishing',
    };
    final locales = <String, Map<String, String>>{
      'en': fixtures.messages('en'),
      'zhHans': fixtures.messages('zhHans'),
      'zhHant': fixtures.messages('zhHant'),
      'ja': fixtures.messages('ja'),
      'ko': fixtures.messages('ko'),
      'fr': fixtures.messages('fr'),
      'es': fixtures.messages('es'),
      'de': fixtures.messages('de'),
    };

    for (final entry in locales.entries) {
      expect(
        entry.value.keys,
        containsAll(keys),
        reason: '${entry.key} must not fall back to raw English',
      );
      for (final oldKey in {
        'mithkaProBackupLimitReached',
        'mithkaProFreePlan',
        'mithkaProLimitExempt',
        'mithkaProUnlimitedAccounts',
        'mithkaProUnlimitedCloudSessionSyncs',
        'mithkaProUnlimitedCloudSessionSyncsDescription',
      }) {
        expect(
          entry.value.keys,
          isNot(contains(oldKey)),
          reason: '${entry.key} must not advertise a Pro feature gate',
        );
      }
      if (entry.key != 'en') {
        expect(
          entry.value['mithkaProSupportDevelopmentDescription'],
          isNot(
            fixtures.messages('en')['mithkaProSupportDevelopmentDescription'],
          ),
          reason: '${entry.key} needs native support copy',
        );
      }
    }

    expect(
      fixtures.messages('en')['supporterFunctionalAccess'],
      'Supporter adds cosmetic extras. All other features are the same.',
    );
    for (final locale in ['zhHans', 'zhHant']) {
      expect(
        fixtures.messages(locale)['supporterFunctionalAccess'],
        isNot(fixtures.messages('en')['supporterFunctionalAccess']),
      );
    }

    expect(
      fixtures.messages('en')['mithkaProSupportDevelopmentDescription'],
      'Help support Mithka and unlock 12 extra penguin icons.',
    );
    expect(
      fixtures.messages('en')['mithkaProSupportOnly'],
      'Help support Mithka and unlock 12 extra penguin icons.',
    );
  });
}
