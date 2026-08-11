import 'package:flutter/material.dart';

import '../components/app_icons.dart';
import '../components/toast.dart';
import '../l10n/app_localizations.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import 'telegram_link_details_view.dart';

typedef TelegramPremiumFeaturesQuery =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> request);

Future<void> openTelegramPremiumFeatures(
  BuildContext context, {
  String referrer = '',
  TelegramPremiumFeaturesQuery? query,
}) => _openTelegramPremiumFeatures(
  context,
  source: {'@type': 'premiumSourceLink', 'referrer': referrer},
  query: query,
);

Future<void> openTelegramPremiumBusinessFeature(
  BuildContext context, {
  required Map<String, dynamic> feature,
  TelegramPremiumFeaturesQuery? query,
}) => _openTelegramPremiumFeatures(
  context,
  source: {'@type': 'premiumSourceBusinessFeature', 'feature': feature},
  query: query,
);

Future<void> _openTelegramPremiumFeatures(
  BuildContext context, {
  required Map<String, dynamic> source,
  TelegramPremiumFeaturesQuery? query,
}) async {
  final nav = Navigator.of(context);
  try {
    await pushTelegramPremiumFeatures(nav, source: source, query: query);
  } catch (_) {
    if (context.mounted) {
      showToast(
        context,
        AppStrings.t(AppStringKeys.linkHandlerUnsupportedTelegramLink),
      );
    }
  }
}

/// Low-level Premium route used by link handling, where failures must continue
/// to the caller's normal unsupported-link fallback.
Future<void> pushTelegramPremiumFeatures(
  NavigatorState nav, {
  required Map<String, dynamic> source,
  TelegramPremiumFeaturesQuery? query,
}) async {
  final result = await (query ?? TdClient.shared.query)({
    '@type': 'getPremiumFeatures',
    'source': source,
  });
  if (!nav.mounted) return;
  final features = result.objects('features') ?? const <Map<String, dynamic>>[];
  final limits = result.objects('limits') ?? const <Map<String, dynamic>>[];
  await nav.push(
    MaterialPageRoute<void>(
      builder: (_) => TelegramLinkDetailsView(
        title: AppStrings.t(AppStringKeys.linkHandlerTelegramPremium),
        icon: HeroAppIcons.solidStar,
        subtitle: AppStrings.t(
          AppStringKeys.linkHandlerPremiumFeaturesSubtitle,
        ),
        details: [
          TelegramLinkDetail(
            AppStrings.t(AppStringKeys.linkHandlerDetailFeatures),
            '${features.length}',
          ),
          TelegramLinkDetail(
            AppStrings.t(AppStringKeys.linkHandlerDetailHigherLimits),
            '${limits.length}',
          ),
          if (result.obj('payment_link')?.type case final String paymentType)
            TelegramLinkDetail(
              AppStrings.t(AppStringKeys.linkHandlerDetailPurchaseOption),
              paymentType.replaceFirst('internalLinkType', ''),
            ),
        ],
      ),
    ),
  );
}
