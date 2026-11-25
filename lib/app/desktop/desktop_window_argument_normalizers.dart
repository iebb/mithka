//
//  desktop_window_argument_normalizers.dart
//
//  Shared sanitizers for the JSON arguments the main engine hands to a
//  desktop child window. Every window type bounds its strings the same way.
//

final RegExp _lineBreaks = RegExp(r'[\r\n]+');
final RegExp _localeTag = RegExp(r'^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$');
final RegExp _instanceId = RegExp(r'^[A-Za-z0-9_-]+$');

/// Flattens [source] onto one line, trims it and caps it at [maxLength];
/// a blank value falls back to [fallback].
String normalizeDesktopWindowTitle(
  String? source, {
  required String fallback,
  int maxLength = 256,
}) {
  final value = source?.replaceAll(_lineBreaks, ' ').trim() ?? '';
  if (value.isEmpty) return fallback;
  return value.length <= maxLength ? value : value.substring(0, maxLength);
}

/// A BCP 47-shaped language tag, or `en` when [source] is not one.
String normalizeDesktopWindowLocaleTag(String? source) {
  final value = source?.trim() ?? '';
  if (value.isEmpty || value.length > 32) return 'en';
  return _localeTag.hasMatch(value) ? value : 'en';
}

/// Whether [source] is a safe window instance id: 1–96 URL-safe characters.
bool isDesktopWindowInstanceId(String source) =>
    source.isNotEmpty && source.length <= 96 && _instanceId.hasMatch(source);
