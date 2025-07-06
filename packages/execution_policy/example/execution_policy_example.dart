import 'package:execution_policy/execution_policy.dart';

Future<void> main() async {
  final builder = PolicyBuilder<String>()
      .retry(
        RetryOptions.exponentialJitter.copyWith(maxAttempts: 4),
        retryIf: (e) => e is Exception,
        onError: (e, stack, attempt) async {
          print('Attempt $attempt failed: $e');
        },
      )
      .timeout(Duration(seconds: 2))
      .circuitBreaker(failureThreshold: 3, resetTimeout: Duration(seconds: 10))
      .fallback(() async => 'default');

  // Default execution
  try {
    final result = await builder.execute(() async {
      print('Performing operation...');
      throw Exception('Simulated failure');
    });
    print('Result: $result');
  } catch (e) {
    print('Execution failed: $e');
  }

  // Debug execution
  print('\n--- DEBUG EXECUTION ---');
  final logs = <String>[];
  final debugResult = await builder.debugExecute(
    () async {
      print('Performing operation...');
      throw Exception('Debug failure');
    },
    logs.add,
  );
  print('Debug logs:');
  for (final log in logs) {
    print(log);
  }
  print('Debug result: $debugResult');
}
