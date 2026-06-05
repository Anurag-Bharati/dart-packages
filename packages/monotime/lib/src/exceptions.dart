/// Exceptions thrown by the [MonoTime] engine.
library;

/// Thrown when [MonoTime.now] is called before the engine has established
/// a valid trust anchor.
///
/// Use [MonoTime.nowEstimated] for a safe fallback that never throws.
final class MonoTimeNotReadyException implements Exception {
  /// Creates a [MonoTimeNotReadyException].
  const MonoTimeNotReadyException();

  @override
  String toString() =>
      'MonoTimeNotReadyException: Call MonoTime.initialize() and wait for '
      'the first sync to complete before calling MonoTime.now. '
      'Use MonoTime.nowEstimated() for a safe non-throwing alternative.';
}

/// Thrown by [SyncEngine] when no valid quorum can be established across
/// all available time sources.
final class MonoTimeSyncException implements Exception {
  /// Creates a [MonoTimeSyncException].
  const MonoTimeSyncException(this.message);

  /// Human-readable description of the sync failure.
  final String message;

  @override
  String toString() => 'MonoTimeSyncException: $message';
}
