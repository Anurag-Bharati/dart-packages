import 'package:flutter_test/flutter_test.dart';
import 'package:monotime/src/sources/https_source.dart';

void main() {
  group('HttpsSource _parseHttpDate', () {
    test('parses IMF-fixdate format (e.g. Fri, 05 Jun 2026 13:05:00 GMT)', () {
      final result = HttpsSource.parseHttpDateForTesting('Fri, 05 Jun 2026 13:05:00 GMT');
      expect(result, DateTime.utc(2026, 6, 5, 13, 5, 0));
    });

    test('parses HTTP date string without weekday prefix', () {
      final result = HttpsSource.parseHttpDateForTesting('05 Jun 2026 13:05:00 GMT');
      expect(result, DateTime.utc(2026, 6, 5, 13, 5, 0));
    });

    test('parses RFC 850 format with 2-digit year expansion (e.g. Sunday, 06-Nov-94 08:49:37 GMT)', () {
      final result = HttpsSource.parseHttpDateForTesting('Sunday, 06-Nov-94 08:49:37 GMT');
      expect(result, DateTime.utc(1994, 11, 6, 8, 49, 37));
    });

    test('parses RFC 850 format with 2-digit year in 2000s (e.g. Friday, 05-Jun-26 13:05:00 GMT)', () {
      final result = HttpsSource.parseHttpDateForTesting('Friday, 05-Jun-26 13:05:00 GMT');
      expect(result, DateTime.utc(2026, 6, 5, 13, 5, 0));
    });

    test('parses asctime format (e.g. Sun Nov  6 08:49:37 1994)', () {
      final result = HttpsSource.parseHttpDateForTesting('Sun Nov  6 08:49:37 1994');
      expect(result, DateTime.utc(1994, 11, 6, 8, 49, 37));
    });

    test('throws FormatException for invalid HTTP date strings', () {
      expect(
        () => HttpsSource.parseHttpDateForTesting('Invalid Date String'),
        throwsFormatException,
      );
    });
  });
}
