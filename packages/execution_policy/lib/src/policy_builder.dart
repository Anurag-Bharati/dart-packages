import 'dart:async';

import 'package:execution_policy/execution_policy.dart';

/// Builds and composes multiple [Policy] instances into a single execution pipeline.
///
/// A fluent builder for composing resilience and transient-fault-handling policies.
///
/// Policies are automatically ordered by their `order` property (ascending) so
/// you don’t need to worry about wrap order:
///  1. FallbackPolicy (outermost)
///  2. CircuitBreakerPolicy
///  3. RetryPolicy
///  4. TimeoutPolicy (innermost)
///
/// ## Usage
///
/// ```dart
/// final result = await PolicyBuilder<String>()
///   .retry(
///     RetryOptions.exponentialJitter.copyWith(maxAttempts: 4),
///     retryIf: (e) => e is HttpException,
///     onError: (e, stack, attempt) async {
///       log('Attempt $attempt failed: $e');
///     },
///   )
///   .timeout(Duration(seconds: 2))
///   .fallback(() async => 'default')
///   .execute(() async => fetchData());
/// ```
///
/// For per-policy tracing, use `debugExecute`:
/// ```dart
/// await PolicyBuilder<String>()
///   .retry(RetryOptions.fixed)
///   .timeout(Duration(seconds: 1))
///   .debugExecute(
///     () async => unreliableOperation(),
///     (msg) => print('[DEBUG] $msg'),
///   );
/// ```
class PolicyBuilder<T> {
  final List<Policy<T>> _policies = [];

  /// Adds a [RetryPolicy] configured by [options].
  ///
  /// - [retryIf]: called on each caught error (before retry). Return `true` to retry.
  /// - [onError]: called after each failed attempt, with the error, optional stack, and 1-based attempt count.
  PolicyBuilder<T> retry(
    RetryOptions options, {
    bool Function(Object error)? retryIf,
    FutureOr<void> Function(Object error, StackTrace? stack, int attempt)? onError,
  }) {
    _policies.add(RetryPolicy<T>(options: options, retryIf: retryIf, onError: onError));
    return this;
  }

  /// Adds a [TimeoutPolicy] that aborts the action if it exceeds [duration].
  PolicyBuilder<T> timeout(Duration duration) {
    _policies.add(TimeoutPolicy<T>(duration));
    return this;
  }

  /// Adds a [FallbackPolicy] that returns [fallbackFn] if an earlier policy rethrows.
  PolicyBuilder<T> fallback(FutureFunction<T> fallbackFn) {
    _policies.add(FallbackPolicy<T>(fallback: fallbackFn));
    return this;
  }

  /// Adds a [CircuitBreakerPolicy]:
  /// - `failureThreshold`: how many failures to open the circuit.
  /// - `resetTimeout`: how long to wait before allowing a half-open trial.
  PolicyBuilder<T> circuitBreaker({
    int failureThreshold = 3,
    Duration resetTimeout = const Duration(seconds: 60),
  }) {
    _policies.add(CircuitBreakerPolicy<T>(
      failureThreshold: failureThreshold,
      resetTimeout: resetTimeout,
    ));
    return this;
  }

  /// Executes the composed pipeline on [action].
  ///
  /// Policies are sorted by `order` and wrapped so that the outermost policy
  /// runs first and the innermost last.
  Future<T> execute(FutureFunction<T> action) async {
    final ordered = List<Policy<T>>.from(_policies)..sort((a, b) => a.order.compareTo(b.order));
    FutureFunction<T> current = action;
    for (final policy in ordered.reversed) {
      final prev = current;
      current = () => policy.execute(prev);
    }
    return current();
  }

  /// Executes the pipeline with debug instrumentation.
  ///
  /// Wraps each policy in a [PolicyDebugger], which logs “Starting”, “✓ Succeeded”
  /// and “✗ Failed” (with durations) to [logger].
  Future<T> debugExecute(
    FutureFunction<T> action,
    void Function(String message) logger,
  ) {
    final ordered = List<Policy<T>>.from(_policies)..sort((a, b) => a.order.compareTo(b.order));
    FutureFunction<T> current = action;
    for (final policy in ordered.reversed) {
      final prev = current;
      current = () => PolicyDebugger<T>(policy, logger).execute(prev);
    }
    return current();
  }

  /// Clears all added policies, allowing reuse of the builder.
  PolicyBuilder<T> reset() {
    _policies.clear();
    return this;
  }

  /// Returns a new PolicyBuilder with the same policies.
  PolicyBuilder<T> copy() {
    final newBuilder = PolicyBuilder<T>();
    newBuilder._policies.addAll(_policies);
    return newBuilder;
  }
}
