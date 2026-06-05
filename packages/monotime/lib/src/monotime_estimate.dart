import 'package:flutter/foundation.dart';
import 'domain/marzullo_engine.dart';

/// A best-effort time estimate for scenarios where the device is offline
/// or has lost its primary trust anchor.
///
/// This is *not* tamper-proof — it projects forward from the last known
/// anchor using elapsed wall-clock time. Always check [confidence] before
/// using this in security-critical logic.
@immutable
final class MonoTimeEstimate {
  /// Creates a [MonoTimeEstimate].
  const MonoTimeEstimate({
    required this.estimatedTime,
    required this.confidence,
    required this.estimatedError,
    required this.confidenceLevel,
  });

  /// The extrapolated UTC time based on the last known trust anchor.
  final DateTime estimatedTime;

  /// Confidence score in `[0.0, 1.0]`. Decays linearly over [MonoTimeConfig.refreshInterval].
  ///
  /// - `1.0` — freshly anchored.
  /// - `0.5` — halfway through the refresh interval.
  /// - `0.0` — fully decayed; consider this time untrustworthy.
  final double confidence;

  /// Estimated error range at this point in time.
  ///
  /// Grows with elapsed time since the last sync at a rate of
  /// [MonoTimeConfig.oscillatorDriftFactor] × elapsed ms.
  final Duration estimatedError;

  /// Qualitative confidence grade.
  final ConfidenceLevel confidenceLevel;
}
