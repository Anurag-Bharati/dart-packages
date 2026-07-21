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
      expect(attempts, 1);
    });

    test('rejects maxAttempts < 1 at construction', () {
      // With asserts on (debug/test) RetryOptions' own assert fires first;
      // in release the RetryPolicy runtime guard throws ArgumentError. Either
      // way, maxAttempts < 1 is rejected rather than silently accepted.
      expect(
        () => RetryPolicy<int>(options: RetryOptions(maxAttempts: 0)),
        throwsA(anyOf(isA<ArgumentError>(), isA<AssertionError>())),
      );
    });

    test('a throwing retryIf does not mask the real error', () async {
      final policy = RetryPolicy<int>(
        options: RetryOptions(maxAttempts: 3, baseDelay: Duration.zero),
        retryIf: (_) => throw StateError('bad predicate'),
      );
      await expectLater(
        policy.execute(() async => throw Exception('real')),
        throwsA(isA<Exception>().having((e) => '$e', 'msg', contains('real'))),
      );
    });

    test('a throwing/rejecting onError never derails the loop', () async {
      var attempts = 0;
      final policy = RetryPolicy<int>(
        options: RetryOptions(maxAttempts: 3, baseDelay: Duration.zero),
        onError: (_, __, ___) async => throw StateError('logger down'),
      );
      await expectLater(
        policy.execute(() async {
          attempts++;
          throw Exception('real');
        }),
        throwsA(isA<Exception>().having((e) => '$e', 'msg', contains('real'))),
      );
      expect(attempts, 3, reason: 'all attempts still run');
    });

    test('shouldContinue=false stops retrying', () async {
      var attempts = 0;
      final policy = RetryPolicy<int>(
        options: RetryOptions(maxAttempts: 5, baseDelay: Duration.zero),
        shouldContinue: () => false,
      );
      await expectLater(
        policy.execute(() async {
          attempts++;
          throw Exception('fail');
        }),
        throwsA(isA<Exception>()),
      );
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
      await expectLater(
        policy.execute(() async {
          attempts++;
          throw Exception('fail');
        }),
        throwsA(isA<Exception>()),
      );
      expect(attempts, 2);
    });
  });

  group('RetryPolicy cancellation', () {
    test('cancelToken cancelled up-front stops after one attempt', () async {
      var attempts = 0;
      final token = CancellationToken()..cancel();
      final policy = RetryPolicy<int>(
        options: RetryOptions(maxAttempts: 5, baseDelay: Duration.zero),
        cancelToken: token,
      );
      await expectLater(
        policy.execute(() async {
          attempts++;
          throw Exception('fail');
        }),
        throwsA(isA<Exception>()),
      );
      expect(attempts, 1);
    });

    test('cancelling mid-backoff interrupts the sleep and stops', () async {
      var attempts = 0;
      final token = CancellationToken();
      final policy = RetryPolicy<int>(
        options: RetryOptions(
          maxAttempts: 5,
          baseDelay: Duration(seconds: 10), // would hang if not interrupted
        ),
        cancelToken: token,
      );
      final sw = Stopwatch()..start();
      final future = policy.execute(() async {
        attempts++;
        throw Exception('fail');
      });
      Timer(const Duration(milliseconds: 30), token.cancel);
      await expectLater(future, throwsA(isA<Exception>()));
      sw.stop();
      expect(attempts, 1);
      expect(sw.elapsed, lessThan(const Duration(seconds: 1)));
    });
  });

  group('RetryPolicy observability', () {
    test('onRetry fires once per backoff with attempt + delay', () async {
      final calls = <int>[];
      final policy = RetryPolicy<int>(
        options: RetryOptions(maxAttempts: 3, baseDelay: Duration.zero),
        onRetry: (error, attempt, delay) => calls.add(attempt),
      );
      await expectLater(
        policy.execute(() async => throw Exception('fail')),
        throwsA(isA<Exception>()),
      );
      // 3 attempts -> 2 backoffs (no backoff after the final failure).
      expect(calls, [1, 2]);
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

    test('a synchronous throw surfaces as a Future error, not sync', () {
      final policy = TimeoutPolicy<int>(Duration(milliseconds: 10));
      expect(
        policy.execute(() => throw StateError('sync boom')),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('FallbackPolicy', () {
    test('returns action result when no error', () async {
      final policy = FallbackPolicy<int>(fallback: (_) async => 99);
      final result = await policy.execute(() async => 55);
      expect(result, 55);
    });

    test('returns fallback when action throws an Exception', () async {
      Object? seen;
      final policy = FallbackPolicy<int>(fallback: (e) async {
        seen = e;
        return 99;
      });
      final result = await policy.execute(() async => throw Exception('oops'));
      expect(result, 99);
      expect(seen, isA<Exception>());
    });

    test('does NOT swallow Errors (programming bugs propagate)', () async {
      final policy = FallbackPolicy<int>(fallback: (_) async => 99);
      await expectLater(
        policy.execute(() async => throw TypeError()),
        throwsA(isA<TypeError>()),
      );
    });

    test('shouldHandle=false rethrows instead of falling back', () async {
      final policy = FallbackPolicy<int>(
        fallback: (_) async => 99,
        shouldHandle: (_) => false,
      );
      await expectLater(
        policy.execute(() async => throw Exception('x')),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('CircuitBreakerPolicy', () {
    test('resets on success when closed', () async {
      var calls = 0;
      final policy = CircuitBreakerPolicy<int>(
        failureThreshold: 2,
        resetTimeout: Duration(milliseconds: 20),
      );
      expect(await policy.execute(() async => ++calls), 1);
      expect(await policy.execute(() async => ++calls), 2);
      expect(policy.state, CircuitState.closed);
    });

    test('opens after threshold and rejects with CircuitOpenException',
        () async {
      final states = <CircuitState>[];
      final policy = CircuitBreakerPolicy<int>(
        failureThreshold: 2,
        resetTimeout: Duration(milliseconds: 20),
        onStateChange: (_, to) => states.add(to),
      );
      await expectLater(policy.execute(() async => throw Exception('f1')),
          throwsA(isA<Exception>()));
      await expectLater(policy.execute(() async => throw Exception('f2')),
          throwsA(isA<Exception>()));
      expect(policy.state, CircuitState.open);
      expect(policy.failureCount, 2);

      await expectLater(
        policy.execute(() async => 1),
        throwsA(isA<CircuitOpenException>().having(
            (e) => e.retryAfter, 'retryAfter', greaterThan(Duration.zero))),
      );
      expect(states, contains(CircuitState.open));
    });

    test('half-opens after resetTimeout and closes on success', () async {
      final policy = CircuitBreakerPolicy<int>(
        failureThreshold: 1,
        resetTimeout: Duration(milliseconds: 30),
      );
      await expectLater(policy.execute(() async => throw Exception()),
          throwsA(isA<Exception>()));
      await expectLater(policy.execute(() async => 123),
          throwsA(isA<CircuitOpenException>()));

      await Future.delayed(Duration(milliseconds: 40));

      expect(await policy.execute(() async => 7), 7);
      expect(policy.state, CircuitState.closed);
      expect(await policy.execute(() async => 8), 8);
    });

    test('half-open admits only ONE probe (no thundering herd)', () async {
      final policy = CircuitBreakerPolicy<int>(
        failureThreshold: 1,
        resetTimeout: Duration(milliseconds: 20),
      );
      await expectLater(policy.execute(() async => throw Exception()),
          throwsA(isA<Exception>()));
      await Future.delayed(Duration(milliseconds: 30));

      final probeStarted = Completer<void>();
      final releaseProbe = Completer<void>();
      final probe = policy.execute(() async {
        probeStarted.complete();
        await releaseProbe.future;
        return 1;
      });
      await probeStarted.future;

      await expectLater(
        policy.execute(() async => 2),
        throwsA(isA<CircuitOpenException>()),
      );

      releaseProbe.complete();
      expect(await probe, 1);
      expect(policy.state, CircuitState.closed);
    });
  });
}
