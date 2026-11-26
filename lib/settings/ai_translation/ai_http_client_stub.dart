import 'package:http/http.dart' as http;

bool isAiLoopbackHost(String host) {
  final normalized = host.toLowerCase();
  return normalized == 'localhost' ||
      normalized.endsWith('.localhost') ||
      normalized == '127.0.0.1' ||
      normalized == '::1';
}

http.Client createAiHttpClient() => http.Client();
