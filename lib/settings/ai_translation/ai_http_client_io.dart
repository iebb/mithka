import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

bool isAiLoopbackHost(String host) {
  final normalized = host.toLowerCase();
  if (normalized == 'localhost' || normalized.endsWith('.localhost')) {
    return true;
  }
  return InternetAddress.tryParse(normalized)?.isLoopback ?? false;
}

http.Client createAiHttpClient() {
  final ioHttpClient = HttpClient()
    ..findProxy = (uri) {
      if (isAiLoopbackHost(uri.host)) return 'DIRECT';
      return HttpClient.findProxyFromEnvironment(uri);
    };
  return IOClient(ioHttpClient);
}
