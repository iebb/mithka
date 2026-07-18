import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../theme/app_theme.dart';
import 'telegram_payment_service.dart';

class TelegramStorePurchaseProgressView extends StatefulWidget {
  const TelegramStorePurchaseProgressView({
    super.key,
    required this.title,
    required this.subtitle,
    required this.purchase,
  });

  final String title;
  final String subtitle;
  final Future<void> Function() purchase;

  @override
  State<TelegramStorePurchaseProgressView> createState() =>
      _TelegramStorePurchaseProgressViewState();
}

class _TelegramStorePurchaseProgressViewState
    extends State<TelegramStorePurchaseProgressView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotation;
  _StoreProgressState _state = _StoreProgressState.processing;
  String _message = 'Waiting for the App Store…';

  @override
  void initState() {
    super.initState();
    _rotation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
    _run();
  }

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    unawaited(_rotation.repeat());
    if (mounted) {
      setState(() {
        _state = _StoreProgressState.processing;
        _message = 'Waiting for the App Store…';
      });
    }
    try {
      await widget.purchase();
      if (!mounted) return;
      _rotation.stop();
      setState(() {
        _state = _StoreProgressState.complete;
        _message = 'Telegram accepted the verified App Store receipt.';
      });
    } catch (error) {
      if (!mounted) return;
      _rotation.stop();
      setState(() {
        _state = _StoreProgressState.failed;
        _message =
            '${_storeError(error)} If the store already completed the transaction, Retry only resends the same receipt and does not start another purchase.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = switch (_state) {
      _StoreProgressState.processing => c.linkBlue,
      _StoreProgressState.complete => const Color(0xFF28A36A),
      _StoreProgressState.failed => const Color(0xFFD94444),
    };
    final icon = switch (_state) {
      _StoreProgressState.processing => HeroAppIcons.arrowsRotate,
      _StoreProgressState.complete => HeroAppIcons.circleCheck,
      _StoreProgressState.failed => HeroAppIcons.triangleExclamation,
    };
    return PopScope(
      canPop: _state != _StoreProgressState.processing,
      child: Scaffold(
        backgroundColor: c.groupedBackground,
        body: Column(
          children: [
            NavHeader(
              title: widget.title,
              onBack: _state == _StoreProgressState.processing
                  ? null
                  : () => Navigator.of(
                      context,
                    ).pop(_state == _StoreProgressState.complete),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 380),
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
                    decoration: BoxDecoration(
                      color: c.card,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: c.divider),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x18000000),
                          blurRadius: 24,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 70,
                          height: 70,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(21),
                          ),
                          child: RotationTransition(
                            turns: _state == _StoreProgressState.processing
                                ? _rotation
                                : const AlwaysStoppedAnimation(0),
                            child: AppIcon(icon, size: 34, color: color),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          widget.subtitle,
                          textAlign: TextAlign.center,
                          style: AppTextStyle.title(
                            c.textPrimary,
                            weight: AppTextWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _message,
                          textAlign: TextAlign.center,
                          style: AppTextStyle.body(
                            c.textSecondary,
                          ).copyWith(height: 1.4),
                        ),
                        if (_state != _StoreProgressState.processing) ...[
                          const SizedBox(height: 22),
                          if (_state == _StoreProgressState.failed) ...[
                            _OwnedStoreAction(label: 'Retry', onTap: _run),
                            const SizedBox(height: 9),
                          ],
                          _OwnedStoreAction(
                            label: 'Done',
                            secondary: _state == _StoreProgressState.failed,
                            onTap: () => Navigator.of(
                              context,
                            ).pop(_state == _StoreProgressState.complete),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _StoreProgressState { processing, complete, failed }

class _OwnedStoreAction extends StatelessWidget {
  const _OwnedStoreAction({
    required this.label,
    required this.onTap,
    this.secondary = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool secondary;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 46,
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: secondary
              ? context.colors.groupedBackground
              : context.colors.linkBlue,
          borderRadius: BorderRadius.circular(13),
          border: secondary ? Border.all(color: context.colors.divider) : null,
        ),
        child: Text(
          label,
          style: AppTextStyle.body(
            secondary ? context.colors.textPrimary : context.colors.onAccent,
            weight: AppTextWeight.bold,
          ),
        ),
      ),
    ),
  );
}

String _storeError(Object error) {
  if (error is TelegramPaymentException) {
    return error.message ?? 'The App Store purchase could not be completed.';
  }
  return 'The App Store purchase could not be completed.';
}

class TelegramStoreProductPickerView extends StatelessWidget {
  const TelegramStoreProductPickerView({
    super.key,
    required this.title,
    required this.subtitle,
    required this.products,
    this.requestedStarCount = 0,
  });

  final String title;
  final String subtitle;
  final List<TelegramStoreProduct> products;
  final int requestedStarCount;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(title: title, onBack: () => Navigator.of(context).pop()),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 22, 16, 30),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: c.linkBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: c.linkBlue.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: c.linkBlue.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: AppIcon(
                          HeroAppIcons.star,
                          size: 23,
                          color: c.linkBlue,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          subtitle,
                          style: AppTextStyle.body(
                            c.textPrimary,
                          ).copyWith(height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  decoration: BoxDecoration(
                    color: c.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: c.divider),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (var index = 0; index < products.length; index++) ...[
                        _StoreProductRow(
                          product: products[index],
                          requestedStarCount: requestedStarCount,
                          onTap: () =>
                              Navigator.of(context).pop(products[index]),
                        ),
                        if (index != products.length - 1)
                          Padding(
                            padding: const EdgeInsets.only(left: 66),
                            child: SizedBox(
                              height: 0.5,
                              child: ColoredBox(color: c.divider),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
                if (products.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 28),
                    child: Column(
                      children: [
                        AppIcon(
                          HeroAppIcons.triangleExclamation,
                          size: 34,
                          color: c.textTertiary,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Telegram did not return an App Store product for this purchase.',
                          textAlign: TextAlign.center,
                          style: AppTextStyle.body(
                            c.textSecondary,
                          ).copyWith(height: 1.4),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StoreProductRow extends StatelessWidget {
  const _StoreProductRow({
    required this.product,
    required this.requestedStarCount,
    required this.onTap,
  });

  final TelegramStoreProduct product;
  final int requestedStarCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final meetsRequest =
        requestedStarCount <= 0 || product.starCount >= requestedStarCount;
    return Semantics(
      button: true,
      enabled: meetsRequest,
      label: '${product.label}, ${_formatStoreAmount(product)}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: meetsRequest ? onTap : null,
        child: Container(
          constraints: const BoxConstraints(minHeight: 70),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          color: meetsRequest
              ? c.card
              : c.groupedBackground.withValues(alpha: 0.55),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.linkBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: AppIcon(
                  HeroAppIcons.solidStar,
                  size: 21,
                  color: c.linkBlue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.label,
                      style: AppTextStyle.body(
                        meetsRequest ? c.textPrimary : c.textTertiary,
                        weight: AppTextWeight.semibold,
                      ),
                    ),
                    if (product.starCount > 0 && !meetsRequest)
                      Text(
                        'Below the requested $requestedStarCount Stars',
                        style: AppTextStyle.caption(c.textTertiary),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatStoreAmount(product),
                style: AppTextStyle.body(
                  meetsRequest ? c.linkBlue : c.textTertiary,
                  weight: AppTextWeight.bold,
                ),
              ),
              const SizedBox(width: 5),
              AppIcon(
                HeroAppIcons.chevronRight,
                size: 17,
                color: c.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatStoreAmount(TelegramStoreProduct product) {
  try {
    final formatter = NumberFormat.simpleCurrency(name: product.currency);
    var divisor = 1;
    for (var i = 0; i < formatter.maximumFractionDigits; i++) {
      divisor *= 10;
    }
    return formatter.format(product.amount / divisor);
  } catch (_) {
    return '${product.currency} ${product.amount}';
  }
}
