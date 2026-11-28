import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'ai_http_client.dart';

String findAiProxy(
  Uri uri, {
  bool bypassProxyForLocalNetworks = true,
  Map<String, String>? environment,
}) {
  if (bypassProxyForLocalNetworks && isLocalNetworkHost(uri.host)) {
    return 'DIRECT';
  }
  return HttpClient.findProxyFromEnvironment(uri, environment: environment);
}

http.Client createAiHttpClient({
  bool bypassProxyForLocalNetworks = true,
  bool Function()? shouldBypassProxyForLocalNetworks,
}) {
  final ioHttpClient = HttpClient()
    ..findProxy = (uri) => findAiProxy(
      uri,
      bypassProxyForLocalNetworks:
          shouldBypassProxyForLocalNetworks?.call() ??
          bypassProxyForLocalNetworks,
    );
  return IOClient(ioHttpClient);
}
