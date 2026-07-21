import 'dart:async' show FutureOr, Future;
import 'dart:math' show Random, pow, min;

import 'package:execution_policy/src/cancellation_token.dart';
import 'package:execution_policy/src/interface.dart';

/// How delay grows (optionally with jitter).
enum RetryDelayType {
  fixed, // always baseDelay
  linear, // baseDelay × attempt
  exponential, // baseDelay × 2^(attempt-1)
  exponentialJitter // exponential + ±jitterFactor%
}

/// Configure the behaviour of the retry mechanism.
class RetryOptions {
  /// Must be ≥ 1.
  final int maxAttempts;

  /// Delay before 1st retry.
  final Duration baseDelay;

  /// Growth strategy.
  final RetryDelayType delayType;

  /// Fractional jitter to apply when [delayType] == exponentialJitter.
  /// E.g. 0.25 means ±25% randomization.
  final double jitterFactor;

  /// Absolute cap on any computed delay.
  final Duration maxDelay;

  const RetryOptions({
    this.maxAttempts = 3,
    this.baseDelay = const Duration(milliseconds: 300),
    this.delayType = RetryDelayType.fixed,
    this.jitterFactor = 0.25,
    this.maxDelay = const Duration(seconds: 30),
  })  : assert(maxAttempts >= 1),
        assert(jitterFactor >= 0 && jitterFactor <= 1);

  /// Shared RNG for jitter — instantiating `Random()` per call is wasteful.
  static final Random _random = Random();

  /// 3 attempts, 300 ms fixed delay.
  static const RetryOptions fixed = RetryOptions();

  /// 5 attempts, 200 ms base, linear backoff (1×, 2×, 3×…).
  static const RetryOptions linear = RetryOptions(
    maxAttempts: 5,
    baseDelay: Duration(milliseconds: 200),
    delayType: RetryDelayType.linear,
  );

  /// 5 attempts, 200 ms base, exponential backoff (1×, 2×, 4×…).
  static const RetryOptions exponential = RetryOptions(
    maxAttempts: 5,
    baseDelay: Duration(milliseconds: 200),
    delayType: RetryDelayType.exponential,
  );

  /// 7 attempts, 200 ms base, exponential backoff with ±25% jitter.
  static const RetryOptions exponentialJitter = RetryOptions(
    maxAttempts: 7,
    baseDelay: Duration(milliseconds: 200),
    delayType: RetryDelayType.exponentialJitter,
    jitterFactor: 0.25,
  );

  /// Copy this instance, overriding only the provided fields.
  RetryOptions copyWith({
    int? maxAttempts,
    Duration? baseDelay,
    RetryDelayType? delayType,
    double? jitterFactor,
    Duration? maxDelay,
  }) {
    return RetryOptions(
      maxAttempts: maxAttempts ?? this.maxAttempts,
      baseDelay: baseDelay ?? this.baseDelay,
      delayType: delayType ?? this.delayType,
      jitterFactor: jitterFactor ?? this.jitterFactor,
      maxDelay: maxDelay ?? this.maxDelay,
    );
  }

  /// Compute the actual delay for [attempt], never exceeding [maxDelay].
  ///
  /// The exponential curve is computed and capped in `double` space *before*
  /// jitter is applied, so a large [attempt] can never overflow into a negative
  /// (or zero) delay that bypasses [maxDelay].
  Duration delayFor(int attempt) {
    if (attempt <= 0) return Duration.zero;
    final capMs = maxDelay.inMilliseconds;
    var ms = min(_rawDelayMs(attempt), capMs.toDouble());
    if (delayType == RetryDelayType.exponentialJitter && jitterFactor > 0) {
      ms *= 1 + (_random.nextDouble() * 2 - 1) * jitterFactor;
    }
    final clamped = ms.isFinite ? ms.round().clamp(0, capMs) : capMs;
    return Duration(milliseconds: clamped);
  }

  /// The uncapped growth curve, in double space (finite or `infinity`).
  double _rawDelayMs(int attempt) {
    final baseMs = baseDelay.inMilliseconds.toDouble();
    switch (delayType) {
      case RetryDelayType.fixed:
        return baseMs;
      case RetryDelayType.linear:
        return baseMs * attempt;
      case RetryDelayType.exponential:
      case RetryDelayType.exponentialJitter:
        return baseMs * pow(2, attempt - 1).toDouble();
    }
  }
}

/// Called before each backoff, with the failing [error], the 1-based [attempt]
/// that just failed, and the [delay] about to elapse before the next attempt.
typedef OnRetry = void Function(Object error, int attempt, Duration delay);

/// Retries [action] according to [options].
///
/// - [retryIf] gates retrying on the caught error (default: retry everything).
/// - [shouldContinue] is a cheap gate checked before each backoff — return
///   `false` (e.g. a widget is no longer mounted) to stop retrying.
/// - [cancelToken] hard-aborts: it stops further attempts and interrupts a
///   backoff that is already sleeping.
/// - [onError] is a fire-and-forget hook awaited defensively; a throwing or
///   rejecting hook can never mask the real error or abort the retry loop.
/// - [onRetry] is a synchronous observability hook (metrics/logging).
class RetryPolicy<T> implements Policy<T> {
  @override
  int get order => 3;

  final RetryOptions options;
  final bool Function(Object error)? retryIf;
  final bool Function()? shouldContinue;
  final CancellationToken? cancelToken;
  final FutureOr<void> Function(Object error, StackTrace? stack, int attempt)?
      onError;
  final OnRetry? onRetry;

  RetryPolicy({
    this.options = const RetryOptions(),
    this.retryIf,
    this.shouldContinue,
    this.cancelToken,
    this.onError,
    this.onRetry,
  }) {
    // `assert` alone is stripped in release builds; fail loudly there too.
    if (options.maxAttempts < 1) {
      throw ArgumentError.value(
          options.maxAttempts, 'maxAttempts', 'must be >= 1');
    }
  }

  @override
  Future<T> execute(FutureFunction<T> action) async {
    for (var attempt = 1; attempt <= options.maxAttempts; attempt++) {
      try {
        return await action();
      } catch (error, stack) {
        await _reportError(error, stack, attempt);
        if (!_canRetry(error, attempt)) rethrow;
        final delay = options.delayFor(attempt);
        _reportRetry(error, attempt, delay);
        if (!await _wait(delay)) rethrow;
      }
    }
    throw StateError('RetryPolicy loop exited unexpectedly');
  }

  bool _canRetry(Object error, int attempt) {
    if (attempt >= options.maxAttempts) return false;
    if (cancelToken?.isCancelled ?? false) return false;
    if (!_gate(shouldContinue)) return false;
    return _gateError(retryIf, error);
  }

  /// Sleeps for [delay], returning `false` if cancelled before/during the sleep.
  Future<bool> _wait(Duration delay) async {
    final token = cancelToken;
    if (token == null) {
      await Future<void>.delayed(delay);
      return true;
    }
    if (token.isCancelled) return false;
    await Future.any([Future<void>.delayed(delay), token.whenCancelled]);
    return !token.isCancelled;
  }

  Future<void> _reportError(Object error, StackTrace stack, int attempt) async {
    final hook = onError;
    if (hook == null) return;
    try {
      await hook(error, stack, attempt);
    } catch (_) {
      // A telemetry hook must never affect control flow or replace the error.
    }
  }

  void _reportRetry(Object error, int attempt, Duration delay) {
    final hook = onRetry;
    if (hook == null) return;
    try {
      hook(error, attempt, delay);
    } catch (_) {}
  }

  bool _gate(bool Function()? gate) {
    if (gate == null) return true;
    try {
      return gate();
    } catch (_) {
      return false;
    }
  }

  bool _gateError(bool Function(Object)? gate, Object error) {
    if (gate == null) return true;
    try {
      return gate(error);
    } catch (_) {
      return false;
    }
  }
}
