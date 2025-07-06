import 'dart:async' show FutureOr;
import 'dart:math' show Random, pow, min;

import 'package:execution_policy/src/interface.dart';

/// How delay grows (optionally with jitter).
enum RetryDelayType {
  fixed, // always baseDelay
  linear, // baseDelay × attempt
  exponential, // baseDelay × 2^(attempt-1)
  exponentialJitter // exponential + ±jitterFactor%
}

/// Configure the behaviour or the retry mechanism
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

  /// Compute the actual delay for [attempt], capped by [maxDelay].
  Duration delayFor(int attempt) {
    if (attempt <= 0) return Duration.zero;
    final baseMs = baseDelay.inMilliseconds;
    int raw;
    switch (delayType) {
      case RetryDelayType.fixed:
        raw = baseMs;
        break;
      case RetryDelayType.linear:
        raw = baseMs * attempt;
        break;
      case RetryDelayType.exponential:
      case RetryDelayType.exponentialJitter:
        raw = (baseMs * pow(2, attempt - 1)).toInt();
        break;
    }

    double ms = raw.toDouble();
    if (delayType == RetryDelayType.exponentialJitter && jitterFactor > 0) {
      final rnd = (Random().nextDouble() * 2 - 1) * jitterFactor;
      ms = ms * (1 + rnd);
    }
    final cappedMs = min(ms.round(), maxDelay.inMilliseconds);
    return Duration(milliseconds: cappedMs);
  }
}

/// Retries your action according to [options], calls [retryIf] and [onError] if provided.
class RetryPolicy<T> implements Policy<T> {
  @override
  int get order => 3;

  final RetryOptions options;
  final bool Function(Object error)? retryIf;
  final FutureOr<void> Function(Object error, StackTrace? stack, int attempt)?
      onError;

  RetryPolicy(
      {this.options = const RetryOptions(), this.retryIf, this.onError});

  @override
  Future<T> execute(FutureFunction<T> action) async {
    for (var attempt = 1; attempt <= options.maxAttempts; attempt++) {
      try {
        return await action();
      } catch (error, stack) {
        onError?.call(error, stack, attempt);
        final canRetry =
            attempt < options.maxAttempts && (retryIf?.call(error) ?? true);
        if (!canRetry) rethrow;
        await Future.delayed(options.delayFor(attempt));
      }
    }
    // unreachable
    throw StateError('RetryPolicy loop exited unexpectedly');
  }
}
