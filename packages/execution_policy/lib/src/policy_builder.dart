import 'dart:async';

import 'package:execution_policy/execution_policy.dart';

/// Builds and composes multiple [Policy] instances into a single execution
/// pipeline.
///
/// Policies are ordered by their `order` property (ascending), so the wrap order
/// is fixed regardless of the order you add them in:
///  1. FallbackPolicy (outermost)
///  2. CircuitBreakerPolicy
///  3. RetryPolicy
///  4. TimeoutPolicy (innermost)
///
/// Two consequences follow from this fixed order, and they are intentional:
///  - the timeout is applied **per attempt** (each retry gets a fresh deadline),
///    not to the whole execution; and
///  - the breaker sits **outside** retry, so one `execute` may record up to
///    `maxAttempts` failures against the breaker.
///
/// A builder may hold at most one policy of each type; adding a second throws.
/// Because [CircuitBreakerPolicy] and a [CancellationToken] carry state, reuse
/// the SAME builder across calls for a given endpoint rather than rebuilding it.
///
/// ## Usage
///
/// ```dart
/// final result = await PolicyBuilder<String>()
///   .retry(
///     RetryOptions.exponentialJitter.copyWith(maxAttempts: 4),
///     retryIf: (e) => e is HttpException,
///   )
///   .timeout(Duration(seconds: 2))
///   .circuitBreaker(failureThreshold: 3, resetTimeout: Duration(seconds: 10))
///   .fallback((error) async => 'default')
///   .execute(() async => fetchData());
/// ```
class PolicyBuilder<T> {
  final List<Policy<T>> _policies = [];

  /// Adds a [RetryPolicy] configured by [options].
  ///
  /// - [retryIf]: called on each caught error; return `true` to retry.
  /// - [shouldContinue]: cheap gate checked before each backoff; return `false`
  ///   (e.g. the caller went away) to stop retrying.
  /// - [cancelToken]: hard-aborts further attempts and interrupts a sleeping
  ///   backoff.
  /// - [onError]: awaited defensively after each failed attempt.
  /// - [onRetry]: synchronous observability hook before each backoff.
  PolicyBuilder<T> retry(
    RetryOptions options, {
    bool Function(Object error)? retryIf,
    bool Function()? shouldContinue,
    CancellationToken? cancelToken,
    FutureOr<void> Function(Object error, StackTrace? stack, int attempt)?
        onError,
    OnRetry? onRetry,
  }) {
    return _add(RetryPolicy<T>(
      options: options,
      retryIf: retryIf,
      shouldContinue: shouldContinue,
      cancelToken: cancelToken,
      onError: onError,
      onRetry: onRetry,
    ));
  }

  /// Adds a [TimeoutPolicy] that fails the action if it exceeds [duration].
  PolicyBuilder<T> timeout(Duration duration) {
    return _add(TimeoutPolicy<T>(duration));
  }

  /// Adds a [FallbackPolicy] that returns [fallbackFn]'s value if an inner
  /// policy throws a handled [Exception]. [shouldHandle] narrows which errors
  /// fall back (default: all exceptions; [Error]s always propagate).
  PolicyBuilder<T> fallback(
    FallbackFunction<T> fallbackFn, {
    bool Function(Object error)? shouldHandle,
  }) {
    return _add(
        FallbackPolicy<T>(fallback: fallbackFn, shouldHandle: shouldHandle));
  }

  /// Adds a [CircuitBreakerPolicy].
  /// - [failureThreshold]: consecutive failures before opening.
  /// - [resetTimeout]: how long to wait before a half-open trial.
  /// - [onStateChange]: notified on every state transition.
  PolicyBuilder<T> circuitBreaker({
    int failureThreshold = 3,
    Duration resetTimeout = const Duration(seconds: 60),
    void Function(CircuitState from, CircuitState to)? onStateChange,
  }) {
    return _add(CircuitBreakerPolicy<T>(
      failureThreshold: failureThreshold,
      resetTimeout: resetTimeout,
      onStateChange: onStateChange,
    ));
  }

  /// Executes the composed pipeline on [action].
  Future<T> execute(FutureFunction<T> action) {
    return _wrap(action, (policy, next) => () => policy.execute(next))();
  }

  /// Executes the pipeline with per-policy debug instrumentation into [logger].
  Future<T> debugExecute(
    FutureFunction<T> action,
    void Function(String message) logger,
  ) {
    return _wrap(
      action,
      (policy, next) => () => PolicyDebugger<T>(policy, logger).execute(next),
    )();
  }

  /// Clears all added policies, allowing reuse of the builder.
  PolicyBuilder<T> reset() {
    _policies.clear();
    return this;
  }

  /// Returns a new builder with the same policy instances.
  ///
  /// The policy list is copied but its entries are shared, so a stateful
  /// [CircuitBreakerPolicy] is shared between the original and the copy.
  PolicyBuilder<T> copy() {
    return PolicyBuilder<T>().._policies.addAll(_policies);
  }

  PolicyBuilder<T> _add(Policy<T> policy) {
    if (_policies.any((p) => p.runtimeType == policy.runtimeType)) {
      throw StateError(
          '${policy.runtimeType} already added to this PolicyBuilder');
    }
    _policies.add(policy);
    return this;
  }

  /// Folds the sorted policies (outermost first) around [action].
  FutureFunction<T> _wrap(
    FutureFunction<T> action,
    FutureFunction<T> Function(Policy<T> policy, FutureFunction<T> next) step,
  ) {
    final ordered = List<Policy<T>>.from(_policies)
      ..sort((a, b) => a.order.compareTo(b.order));
    var current = action;
    for (final policy in ordered.reversed) {
      final next = current;
      current = step(policy, next);
    }
    return current;
  }
}
