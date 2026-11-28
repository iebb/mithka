import 'package:http/http.dart' as http;

String findAiProxy(
  Uri uri, {
  bool bypassProxyForLocalNetworks = true,
  Map<String, String>? environment,
}) => 'DIRECT';

http.Client createAiHttpClient({
  bool bypassProxyForLocalNetworks = true,
  bool Function()? shouldBypassProxyForLocalNetworks,
}) => http.Client();
