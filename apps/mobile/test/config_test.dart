import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/config.dart';

void main() {
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
