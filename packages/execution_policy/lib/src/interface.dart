/// A function that produces a `Future<T>`.
/// This represents the asynchronous operation that policies will wrap.
typedef FutureFunction<T> = Future<T> Function();

/// Core interface for resilience policies.
///
/// A [Policy] applies a particular behavior (retry, timeout, fallback,
/// circuit-breaker, etc.) around the execution of an asynchronous [action].
abstract class Policy<T> {
  /// The wrap order for this policy.
  /// Lower values execute (wrap) outermost; higher values execute innermost.
  int get order;

  /// Executes the given [action] under this policy.
  ///
  /// The [action] is an asynchronous function returning a `Future<T>`.
  /// Implementations should apply their policy-specific logic around
  /// invoking [action], for example:
  ///  - Retrying on transient errors
  ///  - Timing out after a maximum duration
  ///  - Providing a fallback value on failure
  ///  - Opening or closing a circuit breaker on errors/successes
  ///
  /// Returns a `Future<T>` that completes with:
  ///  - The successful result of [action], or
  ///  - A fallback or alternative value if defined by the policy, or
  ///  - An error if the policy deems the execution has irrecoverably failed.
  Future<T> execute(FutureFunction<T> action);
}
