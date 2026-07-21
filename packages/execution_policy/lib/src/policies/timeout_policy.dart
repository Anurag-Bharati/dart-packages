import 'package:execution_policy/src/interface.dart';

/// Fails the wrapped action with a [TimeoutException] if it does not complete
/// within [timeout].
///
/// Note: like `Future.timeout`, this races a timer against the action — it does
/// not abort the underlying work, which continues to run (its late result or
/// error is discarded). When composed via `PolicyBuilder`, the timeout is
/// applied per-attempt (innermost), so each retry gets a fresh deadline.
class TimeoutPolicy<T> implements Policy<T> {
  @override
  int get order => 4;

  /// The maximum time the action may run before failing.
  final Duration timeout;

  /// Creates a [TimeoutPolicy] bounding the action to [timeout].
  const TimeoutPolicy(this.timeout);

  @override
  Future<T> execute(FutureFunction<T> action) async {
    // `async` so a synchronous throw from `action()` surfaces as a Future error
    // rather than escaping `execute` synchronously.
    return action().timeout(timeout);
  }
}
