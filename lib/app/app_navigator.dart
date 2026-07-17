import 'package:flutter/widgets.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

Future<T?> pushAppChatRoute<T>(BuildContext context, Route<T> route) {
  final navigator =
      appNavigatorKey.currentState ??
      Navigator.of(context, rootNavigator: true);
  return navigator.push(route);
}

/// Replaces the current conversation route. If the caller is still on a
/// tab-local utility page (for example the create-group form), close that page
/// before opening the conversation in the app-level chat navigator.
Future<T?> replaceWithAppChatRoute<T, TO>(
  BuildContext context,
  Route<T> route, {
  TO? result,
}) {
  final sourceNavigator = Navigator.of(context);
  final rootNavigator =
      appNavigatorKey.currentState ??
      Navigator.of(context, rootNavigator: true);
  if (identical(sourceNavigator, rootNavigator)) {
    return sourceNavigator.pushReplacement<T, TO>(route, result: result);
  }
  if (sourceNavigator.canPop()) sourceNavigator.pop<TO>(result);
  return rootNavigator.push<T>(route);
}
