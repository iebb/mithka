import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../components/app_confirm_dialog.dart';
import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../theme/app_theme.dart';
import 'telegram_payment_service.dart';

Future<TelegramInvoiceOutcome> openTelegramInvoiceCheckout(
  BuildContext context, {
  required Map<String, dynamic> inputInvoice,
}) async {
  final service = TelegramPaymentService();
  try {
    final form = await service.paymentForm(inputInvoice);
    if (!context.mounted) {
      return const TelegramInvoiceOutcome(TelegramInvoiceStatus.cancelled);
    }
    return await Navigator.of(context).push<TelegramInvoiceOutcome>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => TelegramInvoiceCheckoutView(
              inputInvoice: inputInvoice,
              paymentForm: form,
              service: service,
            ),
          ),
        ) ??
        const TelegramInvoiceOutcome(TelegramInvoiceStatus.cancelled);
  } catch (error) {
    return TelegramInvoiceOutcome(
      TelegramInvoiceStatus.failed,
      message: _safePaymentError(error),
    );
  }
}

Future<TelegramInvoiceOutcome> openTelegramInvoiceSlug(
  BuildContext context,
  String slug,
) async {
  final trimmed = slug.trim();
  if (trimmed.isEmpty) {
    return const TelegramInvoiceOutcome(
      TelegramInvoiceStatus.failed,
      message: 'The invoice link is empty.',
    );
  }
  var name = trimmed;
  if (trimmed.startsWith('tg:') || trimmed.startsWith('http')) {
    try {
      final type = await TdClient.shared.query({
        '@type': 'getInternalLinkType',
        'link': trimmed,
      });
      if (type.type != 'internalLinkTypeInvoice') {
        return const TelegramInvoiceOutcome(
          TelegramInvoiceStatus.failed,
          message: 'The link is not a Telegram invoice.',
        );
      }
      name = type.str('invoice_name') ?? '';
    } catch (error) {
      return TelegramInvoiceOutcome(
        TelegramInvoiceStatus.failed,
        message: _safePaymentError(error),
      );
    }
  }
  if (name.startsWith(r'$')) name = name.substring(1);
  if (!context.mounted) {
    return const TelegramInvoiceOutcome(TelegramInvoiceStatus.cancelled);
  }
  return openTelegramInvoiceCheckout(
    context,
    inputInvoice: {'@type': 'inputInvoiceName', 'name': name},
  );
}

class TelegramInvoiceCheckoutView extends StatefulWidget {
  const TelegramInvoiceCheckoutView({
    super.key,
    required this.inputInvoice,
    required this.paymentForm,
    required this.service,
  });

  final Map<String, dynamic> inputInvoice;
  final Map<String, dynamic> paymentForm;
  final TelegramPaymentService service;

  @override
  State<TelegramInvoiceCheckoutView> createState() =>
      _TelegramInvoiceCheckoutViewState();
}

class _TelegramInvoiceCheckoutViewState
    extends State<TelegramInvoiceCheckoutView> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _country = TextEditingController();
  final _state = TextEditingController();
  final _city = TextEditingController();
  final _street1 = TextEditingController();
  final _street2 = TextEditingController();
  final _postalCode = TextEditingController();
  final _tip = TextEditingController();

  bool _savingOrder = true;
  bool _termsAccepted = false;
  bool _recurringTermsAccepted = false;
  bool _busy = false;
  bool _allowSaveCredentials = false;
  String _error = '';
  String _orderInfoId = '';
  List<Map<String, dynamic>> _shippingOptions = const [];
  String _shippingOptionId = '';
  String _paymentMethod = '';

  Map<String, dynamic>? get _formType => widget.paymentForm.obj('type');
  Map<String, dynamic>? get _invoice => _formType?.obj('invoice');
  bool get _isStarPayment =>
      _formType?.type == 'paymentFormTypeStars' ||
      _formType?.type == 'paymentFormTypeStarSubscription';

  @override
  void initState() {
    super.initState();
    final saved = _formType?.obj('saved_order_info');
    _name.text = saved?.str('name') ?? '';
    _phone.text = saved?.str('phone_number') ?? '';
    _email.text = saved?.str('email_address') ?? '';
    final address = saved?.obj('shipping_address');
    _country.text = address?.str('country_code') ?? '';
    _state.text = address?.str('state') ?? '';
    _city.text = address?.str('city') ?? '';
    _street1.text = address?.str('street_line1') ?? '';
    _street2.text = address?.str('street_line2') ?? '';
    _postalCode.text = address?.str('postal_code') ?? '';
    final savedCredentials =
        _formType?.objects('saved_credentials') ?? const [];
    if (savedCredentials.isNotEmpty) {
      _paymentMethod = 'saved:${savedCredentials.first.str('id') ?? ''}';
    } else if (_formType?.obj('payment_provider')?.type ==
        'paymentProviderOther') {
      _paymentMethod =
          'web:${_formType?.obj('payment_provider')?.str('url') ?? ''}';
    } else if (_formType?.obj('payment_provider')?.type ==
        'paymentProviderStripe') {
      _paymentMethod = 'stripe';
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _phone,
      _email,
      _country,
      _state,
      _city,
      _street1,
      _street2,
      _postalCode,
      _tip,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final product = widget.paymentForm.obj('product_info');
    final invoice = _invoice;
    final currency = invoice?.str('currency') ?? '';
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: c.groupedBackground,
        body: Column(
          children: [
            NavHeader(
              title: 'Checkout',
              onBack: _busy ? null : () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
                children: [
                  _ProductCard(
                    title: product?.str('title') ?? 'Telegram invoice',
                    description: product?.obj('description')?.str('text') ?? '',
                    total: _displayTotal(),
                    isTest: invoice?.boolean('is_test') ?? false,
                  ),
                  if (!_isStarPayment && _needsOrderInfo) ...[
                    const SizedBox(height: 16),
                    _sectionTitle('Order information'),
                    _CheckoutCard(children: _orderFields()),
                    const SizedBox(height: 8),
                    _ToggleRow(
                      label: 'Save order information',
                      value: _savingOrder,
                      onTap: () => setState(() => _savingOrder = !_savingOrder),
                    ),
                  ],
                  if (_shippingOptions.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _sectionTitle('Shipping'),
                    _CheckoutCard(
                      children: [
                        for (final option in _shippingOptions)
                          _ChoiceRow(
                            title: option.str('title') ?? 'Shipping',
                            subtitle: _formatMinor(
                              currency,
                              _partsTotal(option.objects('price_parts')),
                            ),
                            selected:
                                _shippingOptionId == (option.str('id') ?? ''),
                            onTap: () => setState(
                              () => _shippingOptionId = option.str('id') ?? '',
                            ),
                          ),
                      ],
                    ),
                  ],
                  if (!_isStarPayment &&
                      (invoice?.int64('max_tip_amount') ?? 0) > 0) ...[
                    const SizedBox(height: 16),
                    _sectionTitle('Tip'),
                    _CheckoutCard(children: [_tipField(currency)]),
                    if ((invoice?.int64Array('suggested_tip_amounts') ??
                            const [])
                        .isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final amount in invoice!.int64Array(
                              'suggested_tip_amounts',
                            )!)
                              _SuggestionChip(
                                label: _formatMinor(currency, amount),
                                onTap: () => setState(
                                  () => _tip.text = _minorAsInput(
                                    currency,
                                    amount,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                  if (!_isStarPayment) ...[
                    const SizedBox(height: 16),
                    _sectionTitle('Payment method'),
                    _paymentMethods(),
                    if (_formType?.boolean('can_save_credentials') ?? false)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: _ToggleRow(
                          label: 'Save this payment method',
                          value: _allowSaveCredentials,
                          onTap: (_formType?.boolean('need_password') ?? false)
                              ? null
                              : () => setState(
                                  () => _allowSaveCredentials =
                                      !_allowSaveCredentials,
                                ),
                          note: (_formType?.boolean('need_password') ?? false)
                              ? 'Set a two-step verification password before saving payment methods.'
                              : null,
                        ),
                      ),
                  ],
                  if ((invoice?.str('terms_of_service_url') ?? '').isNotEmpty)
                    _termsRow(
                      label: 'I accept the payment terms',
                      url: invoice!.str('terms_of_service_url')!,
                      value: _termsAccepted,
                      onTap: () =>
                          setState(() => _termsAccepted = !_termsAccepted),
                    ),
                  if ((invoice?.str('recurring_payment_terms_of_service_url') ??
                          '')
                      .isNotEmpty)
                    _termsRow(
                      label: 'I accept recurring payment terms',
                      url: invoice!.str(
                        'recurring_payment_terms_of_service_url',
                      )!,
                      value: _recurringTermsAccepted,
                      onTap: () => setState(
                        () =>
                            _recurringTermsAccepted = !_recurringTermsAccepted,
                      ),
                    ),
                  if (_error.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _StatusCard(message: _error, error: true),
                  ],
                  const SizedBox(height: 18),
                  _PrimaryPaymentAction(
                    label: _busy ? 'Processing…' : 'Pay ${_displayTotal()}',
                    busy: _busy,
                    onTap: _busy ? null : _pay,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Payment details are sent directly to the selected provider. Telegram receives only the resulting credential token.',
                    textAlign: TextAlign.center,
                    style: AppTextStyle.caption(
                      c.textTertiary,
                    ).copyWith(height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _needsOrderInfo {
    final invoice = _invoice;
    return invoice?.boolean('need_name') == true ||
        invoice?.boolean('need_phone_number') == true ||
        invoice?.boolean('need_email_address') == true ||
        invoice?.boolean('need_shipping_address') == true ||
        invoice?.boolean('is_flexible') == true;
  }

  List<Widget> _orderFields() {
    final invoice = _invoice;
    return [
      if (invoice?.boolean('need_name') ?? false)
        _PaymentField(controller: _name, label: 'Name'),
      if (invoice?.boolean('need_phone_number') ?? false)
        _PaymentField(
          controller: _phone,
          label: 'Phone number',
          keyboardType: TextInputType.phone,
        ),
      if (invoice?.boolean('need_email_address') ?? false)
        _PaymentField(
          controller: _email,
          label: 'Email',
          keyboardType: TextInputType.emailAddress,
        ),
      if (invoice?.boolean('need_shipping_address') ?? false) ...[
        _PaymentField(
          controller: _country,
          label: 'Country code',
          capitalization: TextCapitalization.characters,
        ),
        _PaymentField(controller: _state, label: 'State or region'),
        _PaymentField(controller: _city, label: 'City'),
        _PaymentField(controller: _street1, label: 'Street address'),
        _PaymentField(controller: _street2, label: 'Address line 2'),
        _PaymentField(controller: _postalCode, label: 'Postal code'),
      ],
    ];
  }

  Widget _tipField(String currency) => _PaymentField(
    controller: _tip,
    label: 'Tip ($currency)',
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
  );

  Widget _paymentMethods() {
    final saved = _formType?.objects('saved_credentials') ?? const [];
    final provider = _formType?.obj('payment_provider');
    final additional =
        _formType?.objects('additional_payment_options') ?? const [];
    final children = <Widget>[
      for (final item in saved)
        _ChoiceRow(
          title: item.str('title') ?? 'Saved payment method',
          subtitle: 'Saved by Telegram',
          selected: _paymentMethod == 'saved:${item.str('id') ?? ''}',
          onTap: () =>
              setState(() => _paymentMethod = 'saved:${item.str('id') ?? ''}'),
        ),
      if (provider?.type == 'paymentProviderStripe')
        _ChoiceRow(
          title: 'Credit or debit card',
          subtitle: 'Tokenized securely by Stripe',
          selected: _paymentMethod == 'stripe',
          onTap: () => setState(() => _paymentMethod = 'stripe'),
        ),
      if (provider?.type == 'paymentProviderOther')
        _ChoiceRow(
          title: 'Payment provider',
          subtitle: Uri.tryParse(provider?.str('url') ?? '')?.host ?? '',
          selected: _paymentMethod == 'web:${provider?.str('url') ?? ''}',
          onTap: () => setState(
            () => _paymentMethod = 'web:${provider?.str('url') ?? ''}',
          ),
        ),
      if (provider?.type == 'paymentProviderSmartGlocal')
        const _UnavailablePaymentRow(
          title: 'Smart Glocal',
          note:
              'This provider requires its native tokenization SDK, which is not bundled in this build.',
        ),
      for (final option in additional)
        _ChoiceRow(
          title: option.str('title') ?? 'Additional payment method',
          subtitle: Uri.tryParse(option.str('url') ?? '')?.host ?? '',
          selected: _paymentMethod == 'web:${option.str('url') ?? ''}',
          onTap: () =>
              setState(() => _paymentMethod = 'web:${option.str('url') ?? ''}'),
        ),
    ];
    return _CheckoutCard(children: children);
  }

  Widget _termsRow({
    required String label,
    required String url,
    required bool value,
    required VoidCallback onTap,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: _ToggleRow(
      label: label,
      value: value,
      onTap: onTap,
      linkLabel: 'Read terms',
      onLinkTap: () =>
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
    ),
  );

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
    child: Text(
      text.toUpperCase(),
      style: AppTextStyle.caption(
        context.colors.textSecondary,
        weight: AppTextWeight.semibold,
      ).copyWith(letterSpacing: 0.5),
    ),
  );

  Future<void> _pay() async {
    final invoice = _invoice;
    if ((invoice?.str('terms_of_service_url') ?? '').isNotEmpty &&
        !_termsAccepted) {
      setState(() => _error = 'Accept the payment terms to continue.');
      return;
    }
    if ((invoice?.str('recurring_payment_terms_of_service_url') ?? '')
            .isNotEmpty &&
        !_recurringTermsAccepted) {
      setState(
        () => _error = 'Accept the recurring payment terms to continue.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      if (!_isStarPayment && _needsOrderInfo && _orderInfoId.isEmpty) {
        final validated = await widget.service.validateOrder(
          inputInvoice: widget.inputInvoice,
          orderInfo: _buildOrderInfo(),
          allowSave: _savingOrder,
        );
        _orderInfoId = validated.str('order_info_id') ?? '';
        _shippingOptions = validated.objects('shipping_options') ?? const [];
        if (_shippingOptions.isNotEmpty && _shippingOptionId.isEmpty) {
          _shippingOptionId = _shippingOptions.first.str('id') ?? '';
        }
        if (invoice?.boolean('is_flexible') == true &&
            _shippingOptionId.isEmpty) {
          throw const TelegramPaymentException(
            'shipping_unavailable',
            'The seller did not return an available shipping option.',
          );
        }
      }
      final tipAmount = _parseMinor(invoice?.str('currency') ?? '', _tip.text);
      final maxTip = invoice?.int64('max_tip_amount') ?? 0;
      if (tipAmount < 0 || tipAmount > maxTip) {
        throw TelegramPaymentException(
          'tip_invalid',
          'The tip must be between 0 and ${_formatMinor(invoice?.str('currency') ?? '', maxTip)}.',
        );
      }
      final credentials = _isStarPayment ? null : await _resolveCredentials();
      if (!_isStarPayment && credentials == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      if (!mounted) return;
      final accepted = await showAppConfirmDialog(
        context,
        title: 'Confirm payment',
        message: 'Pay ${_displayTotal(tipAmount: tipAmount)}?',
        confirmText: 'Pay',
      );
      if (!accepted) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final result = await widget.service.sendPayment(
        inputInvoice: widget.inputInvoice,
        paymentFormId: widget.paymentForm.int64('id') ?? 0,
        orderInfoId: _orderInfoId,
        shippingOptionId: _shippingOptionId,
        credentials: credentials,
        tipAmount: tipAmount,
      );
      if (!mounted) return;
      if (result.boolean('success') == true) {
        Navigator.of(
          context,
        ).pop(const TelegramInvoiceOutcome(TelegramInvoiceStatus.paid));
        return;
      }
      final verificationUrl = result.str('verification_url') ?? '';
      if (verificationUrl.isNotEmpty) {
        final uri = Uri.tryParse(verificationUrl);
        if (uri == null || uri.scheme != 'https') {
          throw const TelegramPaymentException(
            'verification_url_invalid',
            'The provider returned an unsafe verification URL.',
          );
        }
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => TelegramPaymentWebView(
              title: 'Verify payment',
              url: verificationUrl,
            ),
          ),
        );
        if (!mounted) return;
        Navigator.of(
          context,
        ).pop(const TelegramInvoiceOutcome(TelegramInvoiceStatus.pending));
        return;
      }
      throw const TelegramPaymentException(
        'payment_not_completed',
        'The payment was not completed.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _safePaymentError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, dynamic> _buildOrderInfo() => {
    '@type': 'orderInfo',
    'name': _name.text.trim(),
    'phone_number': _phone.text.trim(),
    'email_address': _email.text.trim(),
    'shipping_address': _invoice?.boolean('need_shipping_address') == true
        ? {
            '@type': 'address',
            'country_code': _country.text.trim().toUpperCase(),
            'state': _state.text.trim(),
            'city': _city.text.trim(),
            'street_line1': _street1.text.trim(),
            'street_line2': _street2.text.trim(),
            'postal_code': _postalCode.text.trim(),
          }
        : null,
  };

  Future<Map<String, dynamic>?> _resolveCredentials() async {
    if (_paymentMethod.startsWith('saved:')) {
      if (!await widget.service.hasTemporaryPassword()) {
        if (!mounted) return null;
        final password = await showPaymentPasswordDialog(context);
        if (password == null || password.isEmpty) return null;
        await widget.service.createTemporaryPassword(password);
      }
      return TelegramPaymentService.savedCredentials(
        _paymentMethod.substring('saved:'.length),
      );
    }
    if (_paymentMethod == 'stripe') {
      final provider = _formType?.obj('payment_provider');
      if (!mounted || provider == null) return null;
      final token = await Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) =>
              StripeCardEntryView(provider: provider, service: widget.service),
        ),
      );
      return token == null
          ? null
          : TelegramPaymentService.newCredentials(
              token,
              allowSave: _allowSaveCredentials,
            );
    }
    if (_paymentMethod.startsWith('web:')) {
      final url = _paymentMethod.substring('web:'.length);
      if (!mounted) return null;
      final submitted = await Navigator.of(context).push<PaymentFormSubmission>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => TelegramPaymentWebView(
            title: 'Payment details',
            url: url,
            capturePaymentSubmission: true,
          ),
        ),
      );
      return submitted == null
          ? null
          : TelegramPaymentService.newCredentials(
              submitted.credentials,
              allowSave: _allowSaveCredentials,
            );
    }
    throw const TelegramPaymentException(
      'payment_provider_unavailable',
      'No supported payment method is available for this invoice.',
    );
  }

  String _displayTotal({int tipAmount = 0}) {
    final type = _formType;
    if (type?.type == 'paymentFormTypeStars') {
      return '⭐ ${type?.int64('star_count') ?? 0}';
    }
    if (type?.type == 'paymentFormTypeStarSubscription') {
      return '⭐ ${type?.obj('pricing')?.int64('star_count') ?? 0}';
    }
    final currency = _invoice?.str('currency') ?? '';
    final base = _partsTotal(_invoice?.objects('price_parts'));
    final shipping = _shippingOptions
        .where((item) => item.str('id') == _shippingOptionId)
        .fold<int>(
          0,
          (sum, item) => sum + _partsTotal(item.objects('price_parts')),
        );
    return _formatMinor(currency, base + shipping + tipAmount);
  }
}

class PaymentFormSubmission {
  const PaymentFormSubmission({required this.credentials, this.title = ''});

  final Map<String, dynamic> credentials;
  final String title;
}

@visibleForTesting
PaymentFormSubmission? decodePaymentFormSubmit(String raw) {
  try {
    final outer = jsonDecode(raw);
    if (outer is! Map) return null;
    final event = Map<String, dynamic>.from(outer);
    if (event['eventType'] != 'payment_form_submit') return null;
    Object? data = event['eventData'];
    if (data is String) data = jsonDecode(data);
    if (data is! Map) return null;
    final payload = Map<String, dynamic>.from(data);
    Object? credentials = payload['credentials'];
    if (credentials is String) credentials = jsonDecode(credentials);
    if (credentials is! Map) return null;
    return PaymentFormSubmission(
      credentials: Map<String, dynamic>.from(credentials),
      title: payload['title'] as String? ?? '',
    );
  } catch (_) {
    return null;
  }
}

class TelegramPaymentWebView extends StatefulWidget {
  const TelegramPaymentWebView({
    super.key,
    required this.title,
    required this.url,
    this.capturePaymentSubmission = false,
  });

  final String title;
  final String url;
  final bool capturePaymentSubmission;

  @override
  State<TelegramPaymentWebView> createState() => _TelegramPaymentWebViewState();
}

class _TelegramPaymentWebViewState extends State<TelegramPaymentWebView> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final uri = Uri.tryParse(widget.url);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) async {
            if (widget.capturePaymentSubmission) {
              await _controller.runJavaScript(_paymentBridgeJavaScript);
            }
            if (mounted) setState(() => _loading = false);
          },
          onNavigationRequest: (request) {
            final next = Uri.tryParse(request.url);
            if (next == null ||
                (next.scheme != 'https' && next.scheme != 'about')) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..addJavaScriptChannel(
        'MithkaPayment',
        onMessageReceived: (message) {
          final submission = decodePaymentFormSubmit(message.message);
          if (submission != null && mounted) {
            Navigator.of(context).pop(submission);
          }
        },
      );
    if (uri != null && uri.scheme == 'https') {
      unawaited(_controller.loadRequest(uri));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: [
          NavHeader(
            title: widget.title,
            onBack: () => Navigator.of(context).pop(),
            trailing: _loading ? const _PaymentSpinner(size: 18) : null,
          ),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}

const _paymentBridgeJavaScript = r'''
(function() {
  var target = window.TelegramWebviewProxy || {};
  target.postEvent = function(eventType, eventData) {
    MithkaPayment.postMessage(JSON.stringify({
      eventType: eventType,
      eventData: eventData
    }));
  };
  window.TelegramWebviewProxy = target;
})();
''';

class StripeCardEntryView extends StatefulWidget {
  const StripeCardEntryView({
    super.key,
    required this.provider,
    required this.service,
  });

  final Map<String, dynamic> provider;
  final TelegramPaymentService service;

  @override
  State<StripeCardEntryView> createState() => _StripeCardEntryViewState();
}

class _StripeCardEntryViewState extends State<StripeCardEntryView> {
  final _number = TextEditingController();
  final _expiration = TextEditingController();
  final _cvc = TextEditingController();
  final _name = TextEditingController();
  final _country = TextEditingController();
  final _postal = TextEditingController();
  bool _busy = false;
  String _error = '';

  @override
  void dispose() {
    for (final controller in [
      _number,
      _expiration,
      _cvc,
      _name,
      _country,
      _postal,
    ]) {
      controller.clear();
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: 'Card details',
            onBack: _busy ? null : () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const _StatusCard(
                  message:
                      'Your card number and security code are sent directly to Stripe and are never sent to Telegram.',
                  error: false,
                ),
                const SizedBox(height: 14),
                _CheckoutCard(
                  children: [
                    _PaymentField(
                      controller: _number,
                      label: 'Card number',
                      keyboardType: TextInputType.number,
                      autofillHints: const [AutofillHints.creditCardNumber],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _PaymentField(
                            controller: _expiration,
                            label: 'MM/YY',
                            keyboardType: TextInputType.number,
                            autofillHints: const [
                              AutofillHints.creditCardExpirationDate,
                            ],
                          ),
                        ),
                        Expanded(
                          child: _PaymentField(
                            controller: _cvc,
                            label: 'Security code',
                            keyboardType: TextInputType.number,
                            obscureText: true,
                            autofillHints: const [
                              AutofillHints.creditCardSecurityCode,
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (widget.provider.boolean('need_cardholder_name') ??
                        false)
                      _PaymentField(
                        controller: _name,
                        label: 'Cardholder name',
                        autofillHints: const [AutofillHints.creditCardName],
                      ),
                    if (widget.provider.boolean('need_country') ?? false)
                      _PaymentField(
                        controller: _country,
                        label: 'Billing country code',
                        capitalization: TextCapitalization.characters,
                      ),
                    if (widget.provider.boolean('need_postal_code') ?? false)
                      _PaymentField(
                        controller: _postal,
                        label: 'Billing postal code',
                        autofillHints: const [AutofillHints.postalCode],
                      ),
                  ],
                ),
                if (_error.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _StatusCard(message: _error, error: true),
                ],
                const SizedBox(height: 18),
                _PrimaryPaymentAction(
                  label: _busy ? 'Tokenizing…' : 'Continue',
                  busy: _busy,
                  onTap: _busy ? null : _tokenize,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _tokenize() async {
    final expiration = RegExp(
      r'^\s*(\d{1,2})\s*/\s*(\d{2,4})\s*$',
    ).firstMatch(_expiration.text);
    final number = _number.text.replaceAll(RegExp(r'\D'), '');
    if (number.length < 12 || expiration == null || _cvc.text.length < 3) {
      setState(() => _error = 'Enter valid card details.');
      return;
    }
    var year = int.parse(expiration.group(2)!);
    if (year < 100) year += 2000;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final token = await widget.service.tokenizeStripeCard(
        publishableKey: widget.provider.str('publishable_key') ?? '',
        number: number,
        expirationMonth: int.parse(expiration.group(1)!),
        expirationYear: year,
        cvc: _cvc.text,
        cardholderName: _name.text,
        country: _country.text,
        postalCode: _postal.text,
      );
      if (mounted) Navigator.of(context).pop(token);
    } catch (error) {
      if (mounted) setState(() => _error = _safePaymentError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

Future<String?> showPaymentPasswordDialog(BuildContext context) async {
  final controller = TextEditingController();
  final result = await showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cancel',
    barrierColor: const Color(0x99000000),
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (dialogContext, _, _) => _PaymentPasswordDialog(
      controller: controller,
      onSubmit: () => Navigator.of(dialogContext).pop(controller.text),
    ),
    transitionBuilder: (_, animation, _, child) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
        child: child,
      ),
    ),
  );
  controller.clear();
  controller.dispose();
  return result;
}

class _PaymentPasswordDialog extends StatelessWidget {
  const _PaymentPasswordDialog({
    required this.controller,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SafeArea(
      child: Center(
        child: Container(
          width: 340,
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                color: Color(0x30000000),
                blurRadius: 28,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Two-step verification',
                style: AppTextStyle.title(
                  c.textPrimary,
                  weight: AppTextWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter your Telegram password to use the saved payment method.',
                style: AppTextStyle.body(
                  c.textSecondary,
                ).copyWith(height: 1.35),
              ),
              const SizedBox(height: 14),
              _PaymentField(
                controller: controller,
                label: 'Password',
                obscureText: true,
                autofocus: true,
                onSubmitted: (_) => onSubmit(),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _DialogAction(
                    label: 'Cancel',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  _DialogAction(
                    label: 'Continue',
                    fill: c.linkBlue,
                    foreground: c.onAccent,
                    onTap: onSubmit,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.title,
    required this.description,
    required this.total,
    required this.isTest,
  });

  final String title;
  final String description;
  final String total;
  final bool isTest;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.linkBlue.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(15),
            ),
            child: AppIcon(HeroAppIcons.clipboard, size: 26, color: c.linkBlue),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyle.title(
                    c.textPrimary,
                    weight: AppTextWeight.bold,
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.caption(c.textSecondary),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      total,
                      style: AppTextStyle.body(
                        c.linkBlue,
                        weight: AppTextWeight.bold,
                      ),
                    ),
                    if (isTest) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: c.textTertiary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          'TEST',
                          style: AppTextStyle.caption(
                            c.textSecondary,
                            weight: AppTextWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckoutCard extends StatelessWidget {
  const _CheckoutCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: context.colors.card,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: context.colors.divider),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(children: children),
  );
}

class _PaymentField extends StatelessWidget {
  const _PaymentField({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.obscureText = false,
    this.capitalization = TextCapitalization.none,
    this.autofillHints,
    this.autofocus = false,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final bool obscureText;
  final TextCapitalization capitalization;
  final Iterable<String>? autofillHints;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      constraints: const BoxConstraints(minHeight: 54),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        textCapitalization: capitalization,
        autofillHints: autofillHints,
        autofocus: autofocus,
        onSubmitted: onSubmitted,
        style: AppTextStyle.body(c.textPrimary),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: AppTextStyle.caption(c.textSecondary),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
        ),
      ),
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 58),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.divider, width: 0.5)),
        ),
        child: Row(
          children: [
            AppIcon(
              selected ? HeroAppIcons.circleCheck : HeroAppIcons.circle,
              size: 22,
              color: selected ? c.linkBlue : c.textTertiary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyle.body(c.textPrimary)),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: AppTextStyle.caption(c.textSecondary),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnavailablePaymentRow extends StatelessWidget {
  const _UnavailablePaymentRow({required this.title, required this.note});

  final String title;
  final String note;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIcon(
            HeroAppIcons.triangleExclamation,
            size: 21,
            color: c.textTertiary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyle.body(c.textPrimary)),
                const SizedBox(height: 2),
                Text(
                  note,
                  style: AppTextStyle.caption(
                    c.textSecondary,
                  ).copyWith(height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onTap,
    this.note,
    this.linkLabel,
    this.onLinkTap,
  });

  final String label;
  final bool value;
  final VoidCallback? onTap;
  final String? note;
  final String? linkLabel;
  final VoidCallback? onLinkTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.divider),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppIcon(
              value ? HeroAppIcons.circleCheck : HeroAppIcons.circle,
              size: 21,
              color: onTap == null
                  ? c.textTertiary
                  : value
                  ? c.linkBlue
                  : c.textSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTextStyle.body(c.textPrimary)),
                  if (note != null)
                    Text(
                      note!,
                      style: AppTextStyle.caption(
                        c.textSecondary,
                      ).copyWith(height: 1.3),
                    ),
                  if (linkLabel != null)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onLinkTap,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 2),
                        child: Text(
                          linkLabel!,
                          style: AppTextStyle.caption(
                            c.linkBlue,
                            weight: AppTextWeight.semibold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.colors.divider),
      ),
      child: Text(
        label,
        style: AppTextStyle.caption(
          context.colors.linkBlue,
          weight: AppTextWeight.semibold,
        ),
      ),
    ),
  );
}

class _PrimaryPaymentAction extends StatelessWidget {
  const _PrimaryPaymentAction({
    required this.label,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onTap != null,
    label: label,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: onTap == null
              ? context.colors.textTertiary.withValues(alpha: 0.45)
              : context.colors.linkBlue,
          borderRadius: BorderRadius.circular(14),
          boxShadow: onTap == null
              ? null
              : [
                  BoxShadow(
                    color: context.colors.linkBlue.withValues(alpha: 0.24),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: busy
            ? const _PaymentSpinner(size: 20, onAccent: true)
            : Text(
                label,
                style: AppTextStyle.body(
                  context.colors.onAccent,
                  weight: AppTextWeight.bold,
                ),
              ),
      ),
    ),
  );
}

class _PaymentSpinner extends StatefulWidget {
  const _PaymentSpinner({required this.size, this.onAccent = false});

  final double size;
  final bool onAccent;

  @override
  State<_PaymentSpinner> createState() => _PaymentSpinnerState();
}

class _PaymentSpinnerState extends State<_PaymentSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
    turns: _controller,
    child: AppIcon(
      HeroAppIcons.arrowsRotate,
      size: widget.size,
      color: widget.onAccent
          ? context.colors.onAccent
          : context.colors.linkBlue,
    ),
  );
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.message, required this.error});

  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = error ? const Color(0xFFD94444) : c.linkBlue;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIcon(
            error
                ? HeroAppIcons.triangleExclamation
                : HeroAppIcons.shieldHalved,
            size: 20,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTextStyle.caption(c.textPrimary).copyWith(height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _DialogAction extends StatelessWidget {
  const _DialogAction({
    required this.label,
    required this.onTap,
    this.fill,
    this.foreground,
  });

  final String label;
  final VoidCallback onTap;
  final Color? fill;
  final Color? foreground;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minWidth: 82, minHeight: 42),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: fill ?? context.colors.groupedBackground,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Text(
        label,
        style: AppTextStyle.body(
          foreground ?? context.colors.textPrimary,
          weight: AppTextWeight.semibold,
        ),
      ),
    ),
  );
}

int _partsTotal(List<Map<String, dynamic>>? parts) =>
    (parts ?? const <Map<String, dynamic>>[]).fold<int>(
      0,
      (sum, part) => sum + (part.int64('amount') ?? 0),
    );

int _fractionDigits(String currency) {
  if (currency == 'XTR') return 0;
  try {
    return NumberFormat.simpleCurrency(name: currency).maximumFractionDigits;
  } catch (_) {
    return 2;
  }
}

String _formatMinor(String currency, int amount) {
  if (currency == 'XTR') return '⭐ $amount';
  final digits = _fractionDigits(currency);
  final major = amount / _pow10(digits);
  try {
    return NumberFormat.simpleCurrency(name: currency).format(major);
  } catch (_) {
    return '$currency ${major.toStringAsFixed(digits)}';
  }
}

String _minorAsInput(String currency, int amount) {
  final digits = _fractionDigits(currency);
  return (amount / _pow10(digits)).toStringAsFixed(digits);
}

int _parseMinor(String currency, String input) {
  if (input.trim().isEmpty) return 0;
  final value = double.tryParse(input.trim());
  if (value == null || !value.isFinite) return -1;
  return (value * _pow10(_fractionDigits(currency))).round();
}

int _pow10(int value) {
  var result = 1;
  for (var i = 0; i < value; i++) {
    result *= 10;
  }
  return result;
}

String _safePaymentError(Object error) {
  if (error is TelegramPaymentException) {
    return error.message ?? 'The payment could not be completed.';
  }
  if (error is TdError) return error.message;
  if (error is PlatformException) {
    return error.message ?? 'The platform payment failed.';
  }
  return 'The payment could not be completed.';
}
