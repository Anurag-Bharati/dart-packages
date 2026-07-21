import 'package:execution_policy/execution_policy.dart';

Future<void> main() async {
  // Build ONE long-lived builder per endpoint so the circuit breaker (and any
  // cancel token) keep their state across calls.
  final token = CancellationToken();
  final builder = PolicyBuilder<String>()
      .retry(
        RetryOptions.exponentialJitter.copyWith(maxAttempts: 4),
        retryIf: (e) => e is Exception,
        cancelToken: token, // cancel() aborts further attempts + any backoff
        onRetry: (error, attempt, delay) =>
            print('Retry #$attempt in ${delay.inMilliseconds}ms after $error'),
        onError: (error, stack, attempt) async {
          // Awaited defensively — a throwing hook can't derail the retry loop.
          print('Attempt $attempt failed: $error');
        },
      )
      .timeout(const Duration(seconds: 2)) // per-attempt deadline
      .circuitBreaker(
        failureThreshold: 3,
        resetTimeout: const Duration(seconds: 10),
        onStateChange: (from, to) => print('Circuit $from -> $to'),
      )
      // Fallback catches only Exceptions; Errors (bugs) still propagate.
      .fallback((error) async => 'default (was: $error)');

  final result = await builder.execute(() async {
    print('Performing operation...');
    throw Exception('Simulated failure');
  });
  print('Result: $result');

  // Debug execution traces each policy's start/success/failure with timings.
  print('\n--- DEBUG EXECUTION ---');
  final logs = <String>[];
  final debugResult = await builder.copy().debugExecute(
        () async => throw Exception('Debug failure'),
        logs.add,
      );
  logs.forEach(print);
  print('Debug result: $debugResult');
}
