import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/settings/google_translate_defaults.dart';
import 'package:mithka/settings/translation_api.dart';

void main() {
  test('Google Translate request matches the verified translateHtml shape', () {
    final body = buildGoogleTranslateRequestBody(
      'A quote: "hello"\nand a second line',
      'autodetect',
      'ja',
    );

    expect(body, [
      [
        ['A quote: "hello"\nand a second line'],
        'auto',
        'ja',
      ],
      'wt_lib',
    ]);
    expect(jsonDecode(jsonEncode(body)), body);
  });

  test('Google Translate parser reads the endpoint response array', () {
    expect(
      parseGoogleTranslateResponse([
        ['こんにちは。'],
        ['en'],
      ]),
      'こんにちは。',
    );
    expect(
      () => parseGoogleTranslateResponse(const <Object>[]),
      throwsA(isA<TranslationApiException>()),
    );
  });

  test('Google rotation pools mirror go_translate v1.0.6', () {
    expect(googleTranslateDefaultServiceUrls, hasLength(25));
    expect(googleTranslateDefaultServiceUrls.first, 'translate.google.com');
    expect(googleTranslateDefaultServiceUrls.last, 'translate.google.com.cu');
    expect(googleTranslateDefaultUserAgents, hasLength(52));
    expect(
      googleTranslateDefaultUserAgents.first,
      contains('Chrome/135.0.0.0'),
    );
    expect(googleTranslateDefaultUserAgents.last, startsWith('DoCoMo/2.0'));
  });

  test('public Google rotates user agents and a GTX fallback host', () async {
    final calls =
        <
          ({
            String method,
            Uri uri,
            Object? body,
            String contentType,
            Map<String, String> headers,
          })
        >[];
    final selections = [1, 2, 3];
    var selectionIndex = 0;
    final api = GoogleTranslationApi(
      randomIndex: (max) => selections[selectionIndex++] % max,
      request:
          ({
            required method,
            required uri,
            required body,
            required contentType,
            required headers,
          }) async {
            calls.add((
              method: method,
              uri: uri,
              body: body,
              contentType: contentType,
              headers: {...headers},
            ));
            if (calls.length == 1) {
              throw TranslationApiException('translateHtml unavailable');
            }
            return [
              [
                ['Bon', 'Good'],
                ['jour', ' morning'],
              ],
              null,
              'en',
            ];
          },
    );

    final translated = await api.translatePublic(
      text: 'Good morning',
      source: 'en',
      target: 'fr',
    );

    expect(translated, 'Bonjour');
    expect(calls, hasLength(2));
    expect(calls.first.method, 'POST');
    expect(calls.first.uri.host, 'translate-pa.googleapis.com');
    expect(calls.first.contentType, 'application/json+protobuf');
    expect(
      calls.first.headers['User-Agent'],
      googleTranslateDefaultUserAgents[1],
    );
    expect(calls.first.headers['X-Goog-API-Key'], isNotEmpty);
    expect(calls.last.method, 'GET');
    expect(calls.last.uri.host, googleTranslateDefaultServiceUrls[2]);
    expect(calls.last.uri.queryParameters['client'], 'gtx');
    expect(calls.last.uri.queryParameters['sl'], 'auto');
    expect(calls.last.uri.queryParameters['tl'], 'fr');
    expect(calls.last.uri.queryParameters['q'], 'Good morning');
    expect(
      calls.last.headers['User-Agent'],
      googleTranslateDefaultUserAgents[3],
    );
  });

  test('Google Cloud Basic keeps the API key out of the URL', () async {
    late ({
      String method,
      Uri uri,
      Object? body,
      String contentType,
      Map<String, String> headers,
    })
    call;
    final api = GoogleTranslationApi(
      randomIndex: (_) => 0,
      request:
          ({
            required method,
            required uri,
            required body,
            required contentType,
            required headers,
          }) async {
            call = (
              method: method,
              uri: uri,
              body: body,
              contentType: contentType,
              headers: {...headers},
            );
            return {
              'data': {
                'translations': [
                  {'translatedText': 'こんにちは'},
                ],
              },
            };
          },
    );

    final translated = await api.translateCloud(
      text: 'Hello',
      source: 'autodetect',
      target: 'ja',
      apiKey: 'test-api-key',
    );

    expect(translated, 'こんにちは');
    expect(call.method, 'POST');
    expect(
      call.uri.toString(),
      'https://translation.googleapis.com/language/translate/v2',
    );
    expect(call.uri.queryParameters, isEmpty);
    expect(call.contentType, 'application/json');
    expect(call.headers, {'X-Goog-Api-Key': 'test-api-key'});
    expect(call.body, {'q': 'Hello', 'target': 'ja', 'format': 'text'});
  });
}
