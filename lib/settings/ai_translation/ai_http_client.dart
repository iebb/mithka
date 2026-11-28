import 'package:http/http.dart' as http;

import 'ai_http_client_stub.dart'
    if (dart.library.io) 'ai_http_client_io.dart'
    as impl;

/// Creates an HTTP client for AI provider requests that connects directly to
/// loopback hosts (`127.0.0.1`, `localhost`, `::1`, `*.localhost`) without
/// routing them through system or environment HTTP proxies.
http.Client createAiHttpClient() => impl.createAiHttpClient();

bool isAiLoopbackHost(String host) => impl.isAiLoopbackHost(host);
