import 'package:flutter/foundation.dart';

/// A closed mathematical interval `[startMs, endMs]` in UNIX epoch milliseconds.
///
/// Used as the core primitive by [MarzulloEngine] for consensus resolution.
/// Both bounds are inclusive.
@immutable
final class TimeInterval {
  /// Creates a [TimeInterval]. Asserts that [startMs] <= [endMs].
  const TimeInterval({required this.startMs, required this.endMs})
      : assert(startMs <= endMs, 'Interval start must be <= end');

  /// Start of the interval, inclusive (ms since epoch, UTC).
  final int startMs;

  /// End of the interval, inclusive (ms since epoch, UTC).
  final int endMs;

  /// Midpoint of the interval in milliseconds since epoch.
  int get midpointMs => (startMs + endMs) ~/ 2;

  /// Half-width of the interval in milliseconds (the uncertainty radius).
  int get uncertaintyMs => (endMs - startMs) ~/ 2;

  /// Whether this interval overlaps [other] (closed-interval semantics).
  bool overlaps(TimeInterval other) =>
      startMs <= other.endMs && endMs >= other.startMs;

  /// Intersection of this interval with [other].
  /// Returns `null` if they do not overlap.
  TimeInterval? intersection(TimeInterval other) {
    final lo = startMs > other.startMs ? startMs : other.startMs;
    final hi = endMs < other.endMs ? endMs : other.endMs;
    if (lo > hi) return null;
    return TimeInterval(startMs: lo, endMs: hi);
  }

  @override
  String toString() => '[${DateTime.fromMillisecondsSinceEpoch(startMs, isUtc: true).toIso8601String()}'
      ', ${DateTime.fromMillisecondsSinceEpoch(endMs, isUtc: true).toIso8601String()}]'
      ' (±${uncertaintyMs}ms)';
}
