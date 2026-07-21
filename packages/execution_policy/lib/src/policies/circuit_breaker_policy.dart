import 'package:execution_policy/src/interface.dart';

/// The three states of the circuit.
enum CircuitState { closed, open, halfOpen }

/// Thrown by [CircuitBreakerPolicy] when the circuit rejects a call without
/// invoking the action — because it is open, or because a half-open trial is
/// already in flight.
///
/// [retryAfter] is the time remaining until the breaker will allow the next
/// half-open trial (`Duration.zero` when a concurrent probe is the reason).
class CircuitOpenException implements Exception {
  /// Time until the breaker will next admit a trial call.
  final Duration retryAfter;

  /// Creates a [CircuitOpenException].
  const CircuitOpenException(this.retryAfter);

  @override
  String toString() => 'CircuitOpenException(circuit is open; retry after '
      '${retryAfter.inMilliseconds}ms)';
}

/// A circuit breaker that opens after [failureThreshold] consecutive failures,
/// stays open for [resetTimeout], then admits exactly one trial (half-open).
///
/// State is held on the instance, so a breaker only accumulates failures if the
/// SAME instance is reused across calls — construct one long-lived breaker (or
/// [PolicyBuilder]) per protected endpoint, never one per call.
class CircuitBreakerPolicy<T> implements Policy<T> {
  @override
  int get order => 2;

  /// Number of consecutive failures before opening.
  final int failureThreshold;

  /// How long to stay open before admitting a half-open trial.
  final Duration resetTimeout;

  /// Notified on every state change (`from` → `to`). Never affects control flow.
  final void Function(CircuitState from, CircuitState to)? onStateChange;

  int _failureCount = 0;
  CircuitState _state = CircuitState.closed;
  DateTime? _openedAt;
  bool _probeInFlight = false;

  /// Creates a [CircuitBreakerPolicy]. [failureThreshold] must be ≥ 1.
  CircuitBreakerPolicy({
    this.failureThreshold = 3,
    this.resetTimeout = const Duration(seconds: 60),
    this.onStateChange,
  }) : assert(failureThreshold >= 1);

  /// The breaker's current state (read-only).
  CircuitState get state => _state;

  /// Consecutive failures recorded since the last success (read-only).
  int get failureCount => _failureCount;

  @override
  Future<T> execute(FutureFunction<T> action) async {
    _admit();
    try {
      final result = await action();
      _onSuccess();
      return result;
    } catch (_) {
      _onFailure();
      rethrow;
    }
  }

  /// Decides whether this call may proceed, transitioning open → half-open when
  /// the reset window has elapsed. Throws [CircuitOpenException] to reject.
  void _admit() {
    if (_state == CircuitState.open) {
      final remaining = _remainingOpen();
      if (remaining > Duration.zero) throw CircuitOpenException(remaining);
      _transition(CircuitState.halfOpen);
    }
    if (_state == CircuitState.halfOpen) {
      // Admit a single probe; reject concurrent callers while it is in flight.
      if (_probeInFlight) throw const CircuitOpenException(Duration.zero);
      _probeInFlight = true;
    }
  }

  Duration _remainingOpen() {
    final openedAt = _openedAt;
    if (openedAt == null) return Duration.zero;
    final remaining = resetTimeout - DateTime.now().difference(openedAt);
    return remaining > Duration.zero ? remaining : Duration.zero;
  }

  void _onSuccess() {
    _probeInFlight = false;
    _failureCount = 0;
    _transition(CircuitState.closed);
  }

  void _onFailure() {
    _probeInFlight = false;
    _failureCount++;
    if (_state == CircuitState.halfOpen || _failureCount >= failureThreshold) {
      _openedAt = DateTime.now();
      _transition(CircuitState.open);
    }
  }

  void _transition(CircuitState to) {
    if (_state == to) return;
    final from = _state;
    _state = to;
    try {
      onStateChange?.call(from, to);
    } catch (_) {}
  }
}
