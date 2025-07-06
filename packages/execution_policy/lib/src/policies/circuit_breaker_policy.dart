import 'package:execution_policy/src/interface.dart';

/// The three states of the circuit.
enum CircuitState { closed, open, halfOpen }

/// A simple circuit breaker that opens after [failureThreshold] failures,
/// stays open for [resetTimeout], then allows one trial (half-open).
class CircuitBreakerPolicy<T> implements Policy<T> {
  @override
  int get order => 2;

  /// Number of consecutive failures before opening.
  final int failureThreshold;

  /// How long to stay open before moving to half-open.
  final Duration resetTimeout;

  int _failureCount = 0;
  CircuitState _state = CircuitState.closed;
  DateTime? _lastFailureTime;

  CircuitBreakerPolicy({
    this.failureThreshold = 3,
    this.resetTimeout = const Duration(seconds: 60),
  });

  bool get _isOpen {
    if (_state != CircuitState.open) return false;
    // If enough time has passed, move to half-open
    if (_lastFailureTime != null && DateTime.now().difference(_lastFailureTime!) >= resetTimeout) {
      _state = CircuitState.halfOpen;
      return false;
    }
    return true;
  }

  @override
  Future<T> execute(FutureFunction<T> action) async {
    if (_isOpen) {
      throw StateError('Circuit is open');
    }
    try {
      final result = await action();
      // on success, reset
      _failureCount = 0;
      _state = CircuitState.closed;
      return result;
    } catch (e) {
      // on failure, record and possibly open
      _failureCount++;
      _lastFailureTime = DateTime.now();
      if (_failureCount >= failureThreshold) {
        _state = CircuitState.open;
      }
      rethrow;
    }
  }
}
