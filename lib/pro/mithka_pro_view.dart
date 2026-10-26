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
  const MithkaProView({
    super.key,
    this.service,
    this.returnOnEntitlement = false,
  });

  final MithkaProService? service;
  final bool returnOnEntitlement;

  @override
  State<MithkaProView> createState() => _MithkaProViewState();
}

class _MithkaProViewState extends State<MithkaProView> {
  static final _termsUri = Uri.parse('https://mithka.ieb.app/terms');
  static final _privacyUri = Uri.parse('https://mithka.ieb.app/privacy');

  String _selectedProductId = mithkaProYearlyProductId;
  String? _errorKey;
  String? _statusKey;
  bool _restoring = false;
  bool _awaitingConfirmation = false;
  bool _completed = false;
  bool _operationInFlight = false;
  int _operation = 0;
  late final MithkaProService _observedService;

  MithkaProService _service(BuildContext context) =>
      widget.service ?? context.watch<MithkaProService>();

  @override
  void initState() {
    super.initState();
    final service = _observedService =
        widget.service ?? MithkaProService.shared;
    service.addListener(_serviceChanged);
    if (!service.initialized) unawaited(service.initialize());
  }

  bool get _routeCurrent =>
      mounted && ModalRoute.of(context)?.isCurrent != false;

  bool _acceptOperation(int token) =>
      _routeCurrent && !_completed && token == _operation;

  void _serviceChanged() {
    if (!mounted) return;
    setState(() {});
    _reconcilePending();
  }

  void _reconcilePending() {
    if (_awaitingConfirmation &&
        !_operationInFlight &&
        !_observedService.working &&
        _observedService.isPro) {
      _finishVerified(AppStringKeys.supporterPurchaseSuccess);
    }
  }

  void _finishVerified(String key) {
    if (!_routeCurrent ||
        _completed ||
        _operationInFlight ||
        !_observedService.isPro) {
      return;
    }
    _awaitingConfirmation = false;
    if (widget.returnOnEntitlement) {
      _completed = true;
      Navigator.of(context).pop(true);
    } else {
      setState(() => _statusKey = key);
    }
  }

  void _cancelOnce() {
    _awaitingConfirmation = false;
    if (!_routeCurrent || _completed) return;
    _completed = true;
    Navigator.of(context).pop();
  }

  int _beginOperation({required bool restoring}) {
    // A retry owns its own outcome. A prior pending purchase may complete
    // during it, but must not dismiss this route before cancellation/error
    // for the new attempt has been handled.
    final token = ++_operation;
    _operationInFlight = true;
    _awaitingConfirmation = false;
    setState(() {
      _errorKey = null;
      _statusKey = null;
      _restoring = restoring;
    });
    return token;
  }

  void _showPending(int token) {
    if (!_acceptOperation(token)) return;
    _operationInFlight = false;
    setState(() {
      _statusKey = AppStringKeys.supporterPurchasePending;
      _awaitingConfirmation = true;
    });
    // The verified event may have arrived before the transaction's final
    // working=false notification, while pending completion was suspended.
    _reconcilePending();
  }

  @override
  void dispose() {
    _operation++;
    _observedService.removeListener(_serviceChanged);
    super.dispose();
  }

  Future<void> _purchase(
    MithkaProService service, {
    bool manageOnly = false,
  }) async {
    final managing = manageOnly || service.isPro;
    if (_operationInFlight ||
        _completed ||
        service.working ||
        !(managing
            ? service.canManageSubscriptions
            : service.canMakePayments)) {
      return;
    }
    final token = _beginOperation(restoring: false);
    try {
      if (managing) {
        await service.manage(productId: _selectedProductId);
        if (_acceptOperation(token)) _operationInFlight = false;
      } else {
        await service.purchase(_selectedProductId);
        if (!_acceptOperation(token)) return;
        _operationInFlight = false;
        if (service.isPro) {
          _finishVerified(AppStringKeys.supporterPurchaseSuccess);
        } else {
          _showPending(token);
        }
      }
    } on PlatformException catch (error) {
      if (!_acceptOperation(token)) return;
      _operationInFlight = false;
      if (_isCancellation(error.code)) {
        _cancelOnce();
      } else if (error.code.toLowerCase().contains('pending')) {
        _showPending(token);
      } else {
        setState(() => _errorKey = AppStringKeys.mithkaProPurchaseFailed);
      }
    } catch (_) {
      if (_acceptOperation(token)) {
        _operationInFlight = false;
        setState(() => _errorKey = AppStringKeys.mithkaProPurchaseFailed);
      }
    }
  }

  Future<void> _restore(MithkaProService service) async {
    if (_operationInFlight ||
        _completed ||
        service.working ||
        !service.canRestore) {
      return;
    }
    final token = _beginOperation(restoring: true);
    try {
      await service.restore();
      if (!_acceptOperation(token)) return;
      _operationInFlight = false;
      if (service.isPro) {
        _finishVerified(AppStringKeys.supporterRestoreSuccess);
      } else {
        setState(
          () => _statusKey = service.isAppleStore
              ? AppStringKeys.mithkaProNothingToRestore
              : AppStringKeys.supporterNothingToRestoreGoogle,
        );
      }
    } on PlatformException catch (error) {
      if (!_acceptOperation(token)) return;
      _operationInFlight = false;
      if (_isCancellation(error.code)) {
        _cancelOnce();
      } else {
        setState(() => _errorKey = AppStringKeys.mithkaProRestoreFailed);
      }
    } catch (_) {
      if (_acceptOperation(token)) {
        _operationInFlight = false;
        setState(() => _errorKey = AppStringKeys.mithkaProRestoreFailed);
      }
    } finally {
      if (_acceptOperation(token)) setState(() => _restoring = false);
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
    return SettingsPageScaffold(
      title: AppStringKeys.mithkaProTitle,
      onBack: () => Navigator.of(context).pop(),
      child: SettingsListView(
        children: [
          _hero(service),
          _notice(AppStringKeys.supporterFunctionalAccess),
          const SizedBox(height: 14),
          SettingsPanel(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _benefit(
                  HeroAppIcons.image,
                  AppStringKeys.supporterIconsBenefit,
                  AppStringKeys.supporterIconsMobileBenefit,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (service.loading)
            _notice(AppStringKeys.supporterPlansLoading)
          else if (service.products.isEmpty) ...[
            _notice(AppStringKeys.supporterPlansUnavailable),
            _retryButton(service),
          ] else
            SettingsPanel(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  _productCard(
                    service,
                    id: mithkaProMonthlyProductId,
                    titleKey: AppStringKeys.mithkaProMonthly,
                    periodKey: AppStringKeys.mithkaProPerMonth,
                  ),
                  const InsetDivider(leadingInset: 16),
                  _productCard(
                    service,
                    id: mithkaProYearlyProductId,
                    titleKey: AppStringKeys.mithkaProYearly,
                    periodKey: AppStringKeys.mithkaProPerYear,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          _purchaseButton(service),
          const SizedBox(height: 6),
          _accountButton(service),
          if (!service.isPro && service.canManageSubscriptions)
            _accountButton(service, manage: true),
          if (_statusKey != null) _notice(_statusKey!),
          if (service.working)
            _notice(
              _restoring
                  ? AppStringKeys.supporterRestoring
                  : AppStringKeys.supporterPurchasing,
            ),
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
          _notice(AppStringKeys.supporterIconAccess),
          _notice(AppStringKeys.supporterCancellation),
          Text(
            AppStrings.t(
              service.isAppleStore
                  ? AppStringKeys.mithkaProBillingNotice
                  : AppStringKeys.supporterBillingNoticeGoogle,
            ),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, height: 1.35, color: c.textTertiary),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legalLink(
                AppStringKeys.mithkaProTerms,
                () =>
                    launchUrl(_termsUri, mode: LaunchMode.externalApplication),
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
    );
  }

  Widget _notice(String key) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      AppStrings.t(key),
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 13,
        height: 1.35,
        color: context.colors.textSecondary,
      ),
    ),
  );

  Widget _retryButton(MithkaProService service) => Semantics(
    button: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: service.loading || service.working
          ? null
          : () => unawaited(service.refresh()),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          AppStrings.t(AppStringKeys.supporterPlansRetry),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: AppTheme.brand,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  );

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
        : AppStrings.t(AppStringKeys.mithkaProSupportOnly);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.brand.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.card),
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
                  AppStrings.t(AppStringKeys.mithkaProSupportDevelopment),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
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
              borderRadius: BorderRadius.circular(AppRadius.control),
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
    required String periodKey,
    String? badgeKey,
  }) {
    final c = context.colors;
    final selected = _selectedProductId == id;
    final products = service.products.where((product) => product.id == id);
    final product = products.isEmpty ? null : products.first;
    final price = product?.displayPrice;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: service.working || price == null
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
                              borderRadius: BorderRadius.circular(
                                AppRadius.control,
                              ),
                            ),
                            child: Text(
                              AppStrings.t(badgeKey),
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.brand,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      price == null
                          ? AppStrings.t(
                              AppStringKeys.supporterPlansUnavailable,
                            )
                          : AppStrings.t(AppStringKeys.supporterPlanPrice, {
                              'value1': price,
                              'value2': AppStrings.t(periodKey),
                            }),
                      style: TextStyle(fontSize: 12, color: c.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ExcludeSemantics(
                child: ExcludeFocus(
                  child: IgnorePointer(
                    child: AppCheckbox(value: selected, onChanged: (_) {}),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _purchaseButton(MithkaProService service) {
    final enabled =
        !service.working &&
        (service.isPro
            ? service.canManageSubscriptions
            : service.canMakePayments &&
                  service.product(_selectedProductId) != null);
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
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: service.working
                ? AppActivityIndicator(size: 19, color: AppTheme.onBrand)
                : Text(
                    AppStrings.t(
                      service.isPro
                          ? AppStringKeys.mithkaProManagePlan
                          : service.canMakePayments
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

  Widget _accountButton(MithkaProService service, {bool manage = false}) {
    final c = context.colors;
    final enabled =
        !service.working &&
        (manage ? service.canManageSubscriptions : service.canRestore);
    return Semantics(
      button: true,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled
            ? () => unawaited(
                manage
                    ? _purchase(service, manageOnly: true)
                    : _restore(service),
              )
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            AppStrings.t(
              manage
                  ? AppStringKeys.mithkaProManagePlan
                  : AppStringKeys.mithkaProRestore,
            ),
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
