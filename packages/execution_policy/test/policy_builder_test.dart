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
          .fallback((_) async => 99);
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

    test('fallback receives the triggering error', () async {
      Object? seen;
      final builder = PolicyBuilder<int>()
          .retry(RetryOptions(maxAttempts: 1, baseDelay: Duration.zero))
          .fallback((e) async {
        seen = e;
        return 0;
      });
      await builder.execute(() async => throw Exception('boom'));
      expect(seen, isA<Exception>());
    });
  });

  group('PolicyBuilder guards', () {
    test('rejects a second policy of the same type', () {
      final builder = PolicyBuilder<int>().fallback((_) async => 1);
      expect(
          () => builder.fallback((_) async => 2), throwsA(isA<StateError>()));
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
          .fallback((_) async => 'FB');

      final result = await builder.debugExecute(
        () async => throw Exception('x'),
        logs.add,
      );

      expect(result, 'FB');

      final startLogs = logs.where(
          (m) => m.contains('FallbackPolicy') && m.contains('→ Starting'));
      final successLogs = logs.where(
          (m) => m.contains('FallbackPolicy') && m.contains('✓ Succeeded'));

      expect(startLogs.length, 1, reason: 'FallbackPolicy should start once');
      expect(successLogs.length, 1,
          reason: 'FallbackPolicy should succeed once');
    });
  });

  group('PolicyBuilder.reset', () {
    test('clears previously added policies', () async {
      final builder = PolicyBuilder<int>()
          .retry(RetryOptions(maxAttempts: 2, baseDelay: Duration.zero))
          .timeout(Duration(milliseconds: 50));

      builder.reset();
      builder.fallback((_) async => 123);

      final result = await builder.execute(() async {
        throw Exception('fail');
      });

      expect(result, 123);
    });

    test('can reuse builder after reset with different configuration',
        () async {
      final builder = PolicyBuilder<int>()
          .retry(RetryOptions(maxAttempts: 2, baseDelay: Duration.zero));

      final firstResult = await builder.execute(() async => 1);
      expect(firstResult, 1);

      builder.reset().fallback((_) async => 9);
      final secondResult = await builder.execute(() async => throw Exception());

      expect(secondResult, 9);
    });
  });

  group('PolicyBuilder.copy', () {
    test('creates a new builder with identical policy configuration', () async {
      final original = PolicyBuilder<int>()
          .retry(RetryOptions(maxAttempts: 2, baseDelay: Duration.zero))
          .fallback((_) async => 88);

      final copied = original.copy();

      final result = await copied.execute(() async => throw Exception());
      expect(result, 88);
    });

    test('resetting a copy does not affect the original', () async {
      final original = PolicyBuilder<int>().fallback((_) async => 1);
      final copied = original.copy()
        ..reset()
        ..fallback((_) async => 2);

      expect(await original.execute(() async => throw Exception()), 1);
      expect(await copied.execute(() async => throw Exception()), 2);
    });

    test('a copy SHARES the stateful circuit breaker instance', () async {
      final original = PolicyBuilder<int>().circuitBreaker(
        failureThreshold: 1,
        resetTimeout: const Duration(seconds: 10),
      );
      final copied = original.copy();

      // Trip the breaker via the original...
      await expectLater(original.execute(() async => throw Exception()),
          throwsA(isA<Exception>()));
      // ...the copy sees the same open circuit.
      await expectLater(
          copied.execute(() async => 1), throwsA(isA<CircuitOpenException>()));
    });
  });
}
