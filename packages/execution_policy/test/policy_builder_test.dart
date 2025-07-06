import 'package:execution_policy/execution_policy.dart';
import 'package:test/test.dart';

void main() {
  group('PolicyBuilder.execute', () {
    test('returns value on immediate success', () async {
      final builder = PolicyBuilder<int>()
          .retry(RetryOptions(maxAttempts: 2, baseDelay: Duration.zero))
          .timeout(Duration(milliseconds: 50));
      final result = await builder.execute(() async => 7);
      expect(result, 7);
    });

    test('retries and returns when action eventually succeeds', () async {
      var count = 0;
      final builder = PolicyBuilder<int>()
          .retry(RetryOptions(maxAttempts: 3, baseDelay: Duration.zero));
      final result = await builder.execute(() async {
        count++;
        if (count < 3) throw Exception('fail');
        return 42;
      });
      expect(result, 42);
      expect(count, 3);
    });

    test('returns fallback when all retries fail', () async {
      final builder = PolicyBuilder<int>()
          .retry(RetryOptions(maxAttempts: 2, baseDelay: Duration.zero))
          .fallback(() async => 99);
      final result = await builder.execute(() async {
        throw Exception('always fail');
      });
      expect(result, 99);
    });

    test('throws when no fallback and all fail', () async {
      final builder = PolicyBuilder<int>()
          .retry(RetryOptions(maxAttempts: 2, baseDelay: Duration.zero));
      await expectLater(
        builder.execute(() async => throw Exception('fail')),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('PolicyBuilder.debugExecute', () {
    test('logs correct sequence for retry + timeout', () async {
      final logs = <String>[];
      var count = 0;
      final builder = PolicyBuilder<int>()
          .retry(RetryOptions(maxAttempts: 2, baseDelay: Duration.zero))
          .timeout(Duration(milliseconds: 10));

      final result = await builder.debugExecute(() async {
        count++;
        if (count < 2) throw Exception('err');
        return 8;
      }, logs.add);

      expect(result, 8);
      expect(logs.length, greaterThanOrEqualTo(2));
    });

    test('logs fallback start and success among all policies', () async {
      final logs = <String>[];
      final builder = PolicyBuilder<String>()
          .retry(RetryOptions(maxAttempts: 2, baseDelay: Duration.zero))
          .timeout(Duration(milliseconds: 10))
          .fallback(() async => 'FB');

      final result = await builder.debugExecute(
        () async => throw Exception('x'),
        logs.add,
      );

      expect(result, 'FB');

      // We expect exactly one "Starting" and one "✓ Succeeded" entry for FallbackPolicy:
      final startLogs = logs.where(
          (m) => m.contains('FallbackPolicy') && m.contains('→ Starting'));
      final successLogs = logs.where(
          (m) => m.contains('FallbackPolicy') && m.contains('✓ Succeeded'));

      expect(startLogs.length, 1, reason: 'FallbackPolicy should start once');
      expect(successLogs.length, 1,
          reason: 'FallbackPolicy should succeed once');
    });
  });
}
