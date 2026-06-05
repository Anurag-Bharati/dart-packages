import 'package:flutter/foundation.dart';
import 'time_interval.dart';
import 'time_sample.dart';

/// Confidence grade assigned by [MarzulloEngine] to a consensus result.
enum ConfidenceLevel {
  /// No quorum established, or state has been explicitly invalidated.
  none,

  /// Minimal quorum: few sources, low diversity.
  low,

  /// Stable quorum with adequate cross-protocol diversity.
  medium,

  /// High-integrity quorum: broad diversity, very low variance.
  high,
}

/// The fully resolved output of a [MarzulloEngine] consensus cycle.
@immutable
final class ConsensusResult {
  /// Creates a [ConsensusResult].
  const ConsensusResult({
    required this.utc,
    required this.uncertaintyMs,
    required this.uptimeMs,
    required this.participantCount,
    required this.groupCount,
    required this.participants,
    this.confidence = ConfidenceLevel.low,
    this.interval,
  });

  /// The consensus UTC time (midpoint of the agreed interval).
  final DateTime utc;

  /// Half-width of the consensus interval in milliseconds.
  final int uncertaintyMs;

  /// Platform monotonic uptime at the moment consensus was resolved (ms).
  ///
  /// Used with [utc] to form the [TrustAnchor].
  final int uptimeMs;

  /// Number of unique time sources that contributed to this consensus.
  final int participantCount;

  /// Number of distinct administrative groups represented.
  final int groupCount;

  /// The set of samples whose interval contains the consensus midpoint.
  final Set<TimeSample> participants;

  /// Qualitative confidence grade.
  final ConfidenceLevel confidence;

  /// The raw intersection interval produced by Marzullo's algorithm.
  final TimeInterval? interval;

  @override
  String toString() =>
      'ConsensusResult(utc=${utc.toIso8601String()}, ±${uncertaintyMs}ms, '
      'participants=$participantCount, groups=$groupCount, '
      'confidence=${confidence.name})';
}

/// A high-integrity implementation of Marzullo's intersection algorithm.
///
/// Each [TimeSample] is treated as a closed interval `[T-ε, T+ε]`.
/// The algorithm finds the intersection that is covered by the most intervals,
/// then verifies it meets quorum and diversity requirements.
///
/// Key properties:
/// - **Group-aware diversity**: requires samples from [minGroupCount] distinct
///   administrative groups to prevent correlated failures.
/// - **Graduated trust**: assigns [ConfidenceLevel] based on depth + diversity.
/// - **Hard uncertainty cap**: discards samples wider than [maxAllowedUncertaintyMs].
final class MarzulloEngine {
  /// Creates a [MarzulloEngine].
  const MarzulloEngine({
    this.minQuorumRatio = 0.6,
    this.maxAllowedUncertaintyMs = 5000,
    this.minGroupCount = 2,
  });

  /// Minimum fraction of responding sources that must participate in the consensus.
  final double minQuorumRatio;

  /// Hard-cap: samples with uncertainty > this are discarded before consensus.
  final int maxAllowedUncertaintyMs;

  /// Minimum number of distinct administrative groups required for high/medium confidence.
  final int minGroupCount;

  /// Runs consensus resolution on [samples].
  ///
  /// Returns `null` if no valid quorum can be established.
  ConsensusResult? resolve(List<TimeSample> samples) {
    if (samples.isEmpty) return null;

    // 1. Discard samples that exceed the hard uncertainty cap.
    final valid = samples
        .where((s) => s.interval.uncertaintyMs <= maxAllowedUncertaintyMs)
        .toList();

    if (valid.isEmpty) return null;

    // 2. Build the endpoint list for Marzullo's sweep-line algorithm.
    //    Each interval contributes two events: +1 at start, -1 at end.
    final events = <(int ms, int delta, TimeSample sample)>[];
    for (final s in valid) {
      events.add((s.interval.startMs, 1, s));
      events.add((s.interval.endMs, -1, s));
    }
    // Sort ascending; for ties, put +1 before -1 so closed intervals
    // at a single point are counted.
    events.sort((a, b) {
      final cmp = a.$1.compareTo(b.$1);
      if (cmp != 0) return cmp;
      return b.$2.compareTo(a.$2); // +1 before -1
    });

    // 3. Sweep to find the maximum-overlap region.
    int maxDepth = 0;
    int currentDepth = 0;
    int? overlapStartMs;
    int? overlapEndMs;

    for (int i = 0; i < events.length; i++) {
      final (ms, delta, _) = events[i];
      currentDepth += delta;
      if (currentDepth > maxDepth) {
        maxDepth = currentDepth;
        overlapStartMs = ms;
        // Find where this depth falls back: scan ahead
        overlapEndMs = null;
        for (int j = i + 1; j < events.length; j++) {
          if (events[j].$2 == -1) {
            overlapEndMs = events[j].$1;
            break;
          }
        }
        overlapEndMs ??= ms;
      }
    }

    if (overlapStartMs == null || overlapEndMs == null) return null;

    final consensusInterval = TimeInterval(
      startMs: overlapStartMs,
      endMs: overlapEndMs,
    );
    final midpointMs = consensusInterval.midpointMs;

    // 4. Collect participants: samples whose interval contains the midpoint.
    final participants = valid
        .where((s) =>
            s.interval.startMs <= midpointMs && s.interval.endMs >= midpointMs)
        .toSet();

    final groupsRepresented =
        participants.map((s) => s.groupId).toSet().length;

    // 5. Quorum check.
    final quorumThreshold = (valid.length * minQuorumRatio).ceil();
    if (participants.length < quorumThreshold) return null;

    // 6. Grade confidence.
    final confidence = _gradeConfidence(
      participantCount: participants.length,
      groupCount: groupsRepresented,
      uncertaintyMs: consensusInterval.uncertaintyMs,
    );

    // 7. Use the uptime from the sample closest to the consensus midpoint.
    final anchor = participants.reduce((a, b) {
      final da = (a.interval.midpointMs - midpointMs).abs();
      final db = (b.interval.midpointMs - midpointMs).abs();
      return da <= db ? a : b;
    });

    return ConsensusResult(
      utc: DateTime.fromMillisecondsSinceEpoch(midpointMs, isUtc: true),
      uncertaintyMs: consensusInterval.uncertaintyMs,
      uptimeMs: anchor.uptimeMs,
      participantCount: participants.length,
      groupCount: groupsRepresented,
      participants: participants,
      confidence: confidence,
      interval: consensusInterval,
    );
  }

  ConfidenceLevel _gradeConfidence({
    required int participantCount,
    required int groupCount,
    required int uncertaintyMs,
  }) {
    if (participantCount >= 4 && groupCount >= minGroupCount && uncertaintyMs < 500) {
      return ConfidenceLevel.high;
    }
    if (participantCount >= 2 && groupCount >= minGroupCount) {
      return ConfidenceLevel.medium;
    }
    if (participantCount >= 1) {
      return ConfidenceLevel.low;
    }
    return ConfidenceLevel.none;
  }
}
