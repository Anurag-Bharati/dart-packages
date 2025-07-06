import 'dart:async';

import 'package:execution_policy/execution_policy.dart';
import 'package:test/test.dart';

void main() {
  group('RetryPolicy', () {
    test('returns value when action succeeds immediately', () async {
      final policy = RetryPolicy<int>(
        options: RetryOptions(maxAttempts: 2, baseDelay: Duration.zero),
      );
      final result = await policy.execute(() async => 42);
      expect(result, 42);
    });

    test('retries and returns when action eventually succeeds', () async {
      var callCount = 0;
      final policy = RetryPolicy<int>(
        options: RetryOptions(maxAttempts: 3, baseDelay: Duration.zero),
      );
      final result = await policy.execute(() async {
        callCount++;
        if (callCount < 3) throw Exception('fail');
        return 7;
      });
      expect(result, 7);
      expect(callCount, 3);
    });

    test('throws after maxAttempts', () {
      final policy = RetryPolicy<int>(
        options: RetryOptions(maxAttempts: 2, baseDelay: Duration.zero),
      );
      expect(
        () => policy.execute(() async => throw Exception('always fail')),
        throwsA(isA<Exception>()),
      );
    });

    test('onError is called for each failure', () async {
      var errors = <Object>[];
      final policy = RetryPolicy<int>(
        options: RetryOptions(maxAttempts: 3, baseDelay: Duration.zero),
        onError: (error, stack, _) async {
          errors.add(error);
        },
      );
      await expectLater(
        policy.execute(() async => throw Exception('err')),
        throwsA(isA<Exception>()),
      );
      // Should have been called once per attempt
      expect(errors.length, 3);
    });

    test('respects retryIf predicate', () async {
      var attempts = 0;
      final policy = RetryPolicy<int>(
        options: RetryOptions(maxAttempts: 3, baseDelay: Duration.zero),
        retryIf: (error) => false,
      );
      await expectLater(
        policy.execute(() async {
          attempts++;
          throw Exception('no-retry');
        }),
        throwsA(isA<Exception>()),
      );
      // retryIf returns false, so only one attempt
      expect(attempts, 1);
    });

    test('jitter/backoff does not throw', () async {
      var attempts = 0;
      final policy = RetryPolicy<int>(
        options: RetryOptions(
          maxAttempts: 2,
          baseDelay: Duration(milliseconds: 50),
          delayType: RetryDelayType.exponentialJitter,
          jitterFactor: 0.5,
          maxDelay: Duration(milliseconds: 100),
        ),
      );

      // compute the minimum possible back-off (50ms × (1 – 0.5) = 25ms)
      final minDelay = (policy.options.baseDelay.inMilliseconds *
              (1 - policy.options.jitterFactor))
          .round();

      final sw = Stopwatch()..start();
      await expectLater(
        policy.execute(() async {
          attempts++;
          throw Exception('fail');
        }),
        throwsA(isA<Exception>()),
      );
      sw.stop();

      // we expect at least the *minimum* jitter delay before the retry
      expect(
        sw.elapsedMilliseconds,
        greaterThanOrEqualTo(minDelay),
        reason:
            'elapsed ${sw.elapsedMilliseconds}ms should be ≥ minDelay ${minDelay}ms',
      );
      expect(attempts, 2);
    });
  });

  group('TimeoutPolicy', () {
    test('returns value if within timeout', () async {
      final policy = TimeoutPolicy<int>(Duration(milliseconds: 50));
      final result = await policy.execute(() async {
        await Future.delayed(Duration(milliseconds: 10));
        return 123;
      });
      expect(result, 123);
    });

    test('throws TimeoutException if exceeds timeout', () {
      final policy = TimeoutPolicy<int>(Duration(milliseconds: 10));
      expect(
        () => policy.execute(() async {
          await Future.delayed(Duration(milliseconds: 50));
          return 1;
        }),
        throwsA(isA<TimeoutException>()),
      );
    });
  });

  group('FallbackPolicy', () {
    test('returns action result when no error', () async {
      final policy = FallbackPolicy<int>(fallback: () async => 99);
      final result = await policy.execute(() async => 55);
      expect(result, 55);
    });

    test('returns fallback when action throws', () async {
      final policy = FallbackPolicy<int>(fallback: () async => 99);
      final result = await policy.execute(() async => throw Exception('oops'));
      expect(result, 99);
    });
  });

  group('CircuitBreakerPolicy', () {
    test('resets on success when closed', () async {
      var calls = 0;
      final policy = CircuitBreakerPolicy<int>(
        failureThreshold: 2,
        resetTimeout: Duration(milliseconds: 20),
      );

      // First call succeeds
      final r1 = await policy.execute(() async {
        calls++;
        return 10;
      });
      expect(r1, 10);
      expect(calls, 1);

      // Second call also succeeds
      final r2 = await policy.execute(() async {
        calls++;
        return 20;
      });
      expect(r2, 20);
      expect(calls, 2);
    });

    test('opens circuit after threshold failures', () async {
      final policy = CircuitBreakerPolicy<int>(
        failureThreshold: 2,
        resetTimeout: Duration(milliseconds: 20),
      );

      // Two consecutive failures
      await expectLater(
        policy.execute(() async => throw Exception('f1')),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        policy.execute(() async => throw Exception('f2')),
        throwsA(isA<Exception>()),
      );

      // Circuit now open: immediate reject as StateError('Circuit is open')
      await expectLater(
        policy.execute(() async => 1),
        throwsA(predicate((e) =>
            e is StateError && e.toString().contains('Circuit is open'))),
      );
    });

    test('half-opens after resetTimeout and closes on success', () async {
      final policy = CircuitBreakerPolicy<int>(
        failureThreshold: 1,
        resetTimeout: Duration(milliseconds: 30),
      );

      // 1st failure opens circuit
      await expectLater(
        policy.execute(() async => throw Exception()),
        throwsA(isA<Exception>()),
      );

      // Immediately still open
      await expectLater(
        policy.execute(() async => 123),
        throwsA(predicate((e) => e.toString().contains('Circuit is open'))),
      );

      // Wait for resetTimeout
      await Future.delayed(Duration(milliseconds: 40));

      // Now half-open: allow one trial
      final r = await policy.execute(() async => 7);
      expect(r, 7);

      // After success, circuit closed
      final r2 = await policy.execute(() async => 8);
      expect(r2, 8);
    });
  });
}
