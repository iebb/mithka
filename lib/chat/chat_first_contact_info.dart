import '../tdlib/json_helpers.dart';

/// Telegram's safety metadata for a private chat started by another user.
///
/// TDLib exposes this only through
/// `chat.action_bar.account_info`, even when the user's phone number itself is
/// hidden. Keeping it as a typed value avoids leaking raw action-bar payloads
/// into the view layer.
class ChatFirstContactInfo {
  const ChatFirstContactInfo({
    required this.countryCode,
    required this.registrationMonth,
    required this.registrationYear,
    this.isContact = false,
    this.isOfficial = false,
  });

  final String countryCode;
  final int registrationMonth;
  final int registrationYear;
  final bool isContact;
  final bool isOfficial;

  bool get hasRegistrationDate =>
      registrationMonth >= 1 && registrationMonth <= 12 && registrationYear > 0;

  static ChatFirstContactInfo? fromActionBar(
    Map<String, dynamic>? actionBar, {
    Map<String, dynamic>? user,
  }) {
    final accountInfo = actionBar?.obj('account_info');
    if (accountInfo == null) return null;
    final verification = user?.obj('verification_status');
    return ChatFirstContactInfo(
      countryCode: (accountInfo.str('phone_number_country_code') ?? '')
          .trim()
          .toUpperCase(),
      registrationMonth: accountInfo.integer('registration_month') ?? 0,
      registrationYear: accountInfo.integer('registration_year') ?? 0,
      isContact: user?.boolean('is_contact') ?? false,
      isOfficial:
          (verification?.boolean('is_verified') ?? false) ||
          (user?.boolean('is_support') ?? false),
    );
  }

  ChatFirstContactInfo withUser(Map<String, dynamic> user) {
    final verification = user.obj('verification_status');
    return ChatFirstContactInfo(
      countryCode: countryCode,
      registrationMonth: registrationMonth,
      registrationYear: registrationYear,
      isContact: user.boolean('is_contact') ?? false,
      isOfficial:
          (verification?.boolean('is_verified') ?? false) ||
          (user.boolean('is_support') ?? false),
    );
  }
}
