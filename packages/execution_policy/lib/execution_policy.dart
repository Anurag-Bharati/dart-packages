/// execution_policy.dart
///
/// A resilient execution-policy framework for Dart applications.
///
/// This library provides:
///  • Core abstractions and interfaces for defining resilience policies
///  • Built-in policy implementations (retry, timeout, fallback, circuit-breaker)
///  • A fluent `PolicyBuilder` for composing multiple policies in the correct order
///  • A `PolicyDebugger` for instrumenting and tracing each policy’s execution
///
/// ## Getting Started
///
/// ```dart
/// import 'package:execution_policy/execution_policy.dart';
///
/// final result = await PolicyBuilder<String>()
///   // Retry up to 3 times with fixed 300ms delay
///   .retry(RetryOptions.fixed,
///     retryIf: (e) => e is HttpException,
///     onError: (e, stack, attempt) async {
///       print('Attempt $attempt failed: $e');
///     })
///   // Fail fast if action takes longer than 2s
///   .timeout(Duration(seconds: 2))
///   // If all else fails, return a default
///   .fallback(() async => 'default')
///   // Execute your asynchronous operation
///   .execute(() async => fetchData());
/// ```
///
/// For per-policy tracing of start/success/failure events:
/// ```dart
/// await PolicyBuilder<String>()
///   .retry(RetryOptions.exponentialJitter)
///   .timeout(Duration(seconds: 1))
///   .debugExecute(
///     () async => unreliableOperation(),
///     (msg) => print('[DEBUG] $msg'),
///   );
/// ```
library;

export 'src/interface.dart'; // Core Policy<T> interface and FutureFunction typedef
export 'src/policies/_wrapper.dart'; // Built-in policy implementations: RetryPolicy, TimeoutPolicy, FallbackPolicy, CircuitBreakerPolicy
export 'src/policy_builder.dart'; // Fluent PolicyBuilder for composing and executing policies
export 'src/policy_debugger.dart'; // PolicyDebugger for instrumenting and logging policy execution
