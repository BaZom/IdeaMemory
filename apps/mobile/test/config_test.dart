import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/config.dart';

void main() {
  group('AppConfig', appConfigTests);

  test('accepts absolute http and https URLs', () {
    expect(
      parseApiBaseUrl('http://localhost:8000'),
      Uri.parse('http://localhost:8000'),
    );
    expect(
      parseApiBaseUrl(' https://api.example/v1 '),
      Uri.parse('https://api.example/v1'),
    );
    expect(
      parseApiBaseUrl('http://192.168.1.20:8000'),
      Uri.parse('http://192.168.1.20:8000'),
    );
  });

  for (final raw in [
    '',
    '   ',
    'localhost:8000',
    '/api',
    'ftp://localhost:8000',
    'http://',
    'http://localhost:8000?x=1',
    'http://localhost:8000#frag',
    'http://user:pass@localhost:8000',
  ]) {
    test('rejects "$raw"', () {
      expect(() => parseApiBaseUrl(raw), throwsFormatException);
    });
  }
}

String _jwtWithRole(String role) {
  String part(Map<String, Object> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.${part({'role': role})}.c2ln';
}

void appConfigTests() {
  test('parses a complete public configuration', () {
    final config = AppConfig.parse(
      apiBaseUrl: 'http://localhost:8000',
      supabaseUrl: 'http://127.0.0.1:54321',
      supabasePublishableKey: ' sb_publishable_abc ',
    );

    expect(config.supabaseUrl, Uri.parse('http://127.0.0.1:54321'));
    expect(config.supabasePublishableKey, 'sb_publishable_abc');
  });

  test('accepts a legacy anon key', () {
    final key = _jwtWithRole('anon');
    expect(parsePublishableKey(key), key);
  });

  for (final key in [
    '',
    'sb_secret_abc',
    _jwtWithRole('service_role'),
    _jwtWithRole('authenticated'),
  ]) {
    test(
      'refuses publishable key "${key.length > 20 ? '${key.substring(0, 20)}…' : key}"',
      () {
        expect(() => parsePublishableKey(key), throwsFormatException);
      },
    );
  }

  test('requires SUPABASE_URL', () {
    expect(
      () => AppConfig.parse(
        apiBaseUrl: 'http://localhost:8000',
        supabaseUrl: '',
        supabasePublishableKey: 'sb_publishable_abc',
      ),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('SUPABASE_URL'),
        ),
      ),
    );
  });
}
