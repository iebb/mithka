import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'mithka_pro_service.dart';

class MithkaProView extends StatefulWidget {
  const MithkaProView({super.key, this.service});

  final MithkaProService? service;

  @override
  State<MithkaProView> createState() => _MithkaProViewState();
}

class _MithkaProViewState extends State<MithkaProView> {
  static final _termsUri = Uri.parse('https://mithka.ieb.app/terms');
  static final _privacyUri = Uri.parse('https://mithka.ieb.app/privacy');

  String _selectedProductId = mithkaProYearlyProductId;
  String? _errorKey;

  MithkaProService _service(BuildContext context) =>
      widget.service ?? context.watch<MithkaProService>();

  @override
  void initState() {
    super.initState();
    final service = widget.service ?? MithkaProService.shared;
    if (!service.initialized) unawaited(service.initialize());
  }

  Future<void> _purchase(MithkaProService service) async {
    if (service.working || !service.state.storeAvailable) return;
    setState(() => _errorKey = null);
    try {
      if (service.isPro) {
        await service.manage(productId: _selectedProductId);
      } else {
        await service.purchase(_selectedProductId);
      }
    } on PlatformException catch (error) {
      if (!_isCancellation(error.code) && mounted) {
        setState(() => _errorKey = AppStringKeys.mithkaProPurchaseFailed);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _errorKey = AppStringKeys.mithkaProPurchaseFailed);
      }
    }
  }

  Future<void> _restore(MithkaProService service) async {
    if (service.working || !service.state.storeAvailable) return;
    setState(() => _errorKey = null);
    try {
      await service.restore();
      if (mounted && !service.isPro) {
        setState(() => _errorKey = AppStringKeys.mithkaProNothingToRestore);
      }
    } on PlatformException catch (error) {
      if (!_isCancellation(error.code) && mounted) {
        setState(() => _errorKey = AppStringKeys.mithkaProRestoreFailed);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _errorKey = AppStringKeys.mithkaProRestoreFailed);
      }
    }
  }

  bool _isCancellation(String code) {
    final normalized = code.toLowerCase();
    return normalized.contains('cancel') || normalized == 'user_cancelled';
  }

  @override
  Widget build(BuildContext context) {
    final service = _service(context);
    final c = context.colors;
    return DefaultTextStyle(
      style: AppTextStyle.body(c.textPrimary),
      child: ColoredBox(
        color: c.groupedBackground,
        child: Column(
          children: [
            NavHeader(
              title: AppStringKeys.mithkaProTitle,
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 28),
                children: [
                  _hero(service),
                  const SizedBox(height: 14),
                  Container(
                    decoration: BoxDecoration(
                      color: c.card,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        _benefit(
                          HeroAppIcons.cloudArrowDown,
                          AppStringKeys.mithkaProUnlimitedCloudSessionSyncs,
                          AppStringKeys
                              .mithkaProUnlimitedCloudSessionSyncsDescription,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    decoration: BoxDecoration(
                      color: c.card,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        _productCard(
                          service,
                          id: mithkaProMonthlyProductId,
                          titleKey: AppStringKeys.mithkaProMonthly,
                          fallbackPrice: r'$0.69',
                          periodKey: AppStringKeys.mithkaProPerMonth,
                        ),
                        const InsetDivider(leadingInset: 16),
                        _productCard(
                          service,
                          id: mithkaProYearlyProductId,
                          titleKey: AppStringKeys.mithkaProYearly,
                          fallbackPrice: r'$4.99',
                          periodKey: AppStringKeys.mithkaProPerYear,
                          badgeKey: AppStringKeys.mithkaProBestValue,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _purchaseButton(service),
                  const SizedBox(height: 6),
                  _restoreButton(service),
                  if (_errorKey != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      AppStrings.t(_errorKey!),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.3,
                        color: AppTheme.tagRed,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    AppStrings.t(AppStringKeys.mithkaProBillingNotice),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: c.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _legalLink(
                        AppStringKeys.mithkaProTerms,
                        () => launchUrl(
                          _termsUri,
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          '·',
                          style: TextStyle(color: c.textTertiary, fontSize: 13),
                        ),
                      ),
                      _legalLink(
                        AppStringKeys.mithkaProPrivacy,
                        () => launchUrl(
                          _privacyUri,
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legalLink(String labelKey, Future<bool> Function() onTap) {
    return Semantics(
      link: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => unawaited(onTap()),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            AppStrings.t(labelKey),
            style: TextStyle(
              color: AppTheme.brand,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ),
    );
  }

  Widget _hero(MithkaProService service) {
    final expiration = service.state.expirationDate;
    final status = service.isPro
        ? expiration == null
              ? AppStrings.t(AppStringKeys.mithkaProActive)
              : AppStrings.t(AppStringKeys.mithkaProActiveUntil, {
                  'value1': DateFormat.yMMMd().format(expiration.toLocal()),
                })
        : service.isLimitExempt
        ? AppStrings.t(AppStringKeys.mithkaProLimitExempt)
        : AppStrings.t(AppStringKeys.mithkaProFreePlan);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.brand.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: AppIcon(
              HeroAppIcons.solidStar,
              size: 22,
              color: AppTheme.brand,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.t(AppStringKeys.mithkaProTitle),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  status,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.3,
                    color: context.colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _benefit(AppIconData icon, String titleKey, String descriptionKey) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.brand.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: AppIcon(icon, size: 17, color: AppTheme.brand),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.t(titleKey),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  AppStrings.t(descriptionKey),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: c.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _productCard(
    MithkaProService service, {
    required String id,
    required String titleKey,
    required String fallbackPrice,
    required String periodKey,
    String? badgeKey,
  }) {
    final c = context.colors;
    final selected = _selectedProductId == id;
    final products = service.products.where((product) => product.id == id);
    final product = products.isEmpty ? null : products.first;
    final price = product?.displayPrice.trim().isNotEmpty == true
        ? product!.displayPrice
        : fallbackPrice;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: service.working
            ? null
            : () => setState(() => _selectedProductId = id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          constraints: const BoxConstraints(minHeight: 66),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          color: selected
              ? AppTheme.brand.withValues(alpha: 0.07)
              : const Color(0x00000000),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            AppStrings.t(titleKey),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: selected ? AppTheme.brand : c.textPrimary,
                            ),
                          ),
                        ),
                        if (badgeKey != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.brand.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              AppStrings.t(badgeKey),
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.brand,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$price ${AppStrings.t(periodKey)}',
                      style: TextStyle(fontSize: 12, color: c.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              IgnorePointer(
                child: AppCheckbox(value: selected, onChanged: (_) {}),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _purchaseButton(MithkaProService service) {
    final enabled = service.state.storeAvailable && !service.working;
    return Semantics(
      button: true,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => unawaited(_purchase(service)) : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: enabled ? 1 : 0.45,
          child: Container(
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.brand,
              borderRadius: BorderRadius.circular(12),
            ),
            child: service.working
                ? AppActivityIndicator(size: 19, color: AppTheme.onBrand)
                : Text(
                    AppStrings.t(
                      service.isPro
                          ? AppStringKeys.mithkaProManagePlan
                          : service.state.storeAvailable
                          ? AppStringKeys.mithkaProContinue
                          : AppStringKeys.mithkaProStoreUnavailable,
                    ),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.onBrand,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _restoreButton(MithkaProService service) {
    final c = context.colors;
    final enabled = service.state.storeAvailable && !service.working;
    return Semantics(
      button: true,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => unawaited(_restore(service)) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            AppStrings.t(AppStringKeys.mithkaProRestore),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: enabled ? AppTheme.brand : c.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}
