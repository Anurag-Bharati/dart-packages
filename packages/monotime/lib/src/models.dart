import 'package:flutter/foundation.dart';
import 'domain/marzullo_engine.dart';
export 'domain/marzullo_engine.dart' show ConfidenceLevel;


/// Configuration parameters for the [MonoTime] engine.
@immutable
final class MonoTimeConfig {
  /// Creates a [MonoTimeConfig] with sensible production defaults.
  const MonoTimeConfig({
    this.ntpServers = const [
      'pool.ntp.org',
      'time.google.com',
      'time.cloudflare.com',
    ],
    this.httpsSources = const [
      'https://www.google.com',
      'https://www.cloudflare.com',
      'https://time.cloudflare.com',
      'https://www.apple.com',
      'https://www.microsoft.com',
    ],
    this.additionalSources = const [],
    this.minQuorumRatio = 0.6,
    this.minimumQuorum = 2,
    this.minGroupCount = 2,
    this.maxLatency = const Duration(seconds: 4),
    this.refreshInterval = const Duration(minutes: 30),
    this.maxAllowedUncertaintyMs = 5000,
    this.persistState = true,
    this.earlyExit = true,
    this.oscillatorDriftFactor = 0.00005,
    this.backgroundSyncInterval,
  });

  /// NTP server hostnames queried via UDP (RFC 5905).
  final List<String> ntpServers;

  /// HTTPS endpoints from which the `Date` response header is parsed.
  ///
  /// These provide TLS-authenticated time without requiring Rust or
  /// the NTS-KE handshake.
  final List<String> httpsSources;

  /// Optional additional [TimeSource] instances to include in consensus.
  final List<Object> additionalSources; // typed as Object for abstraction

  /// Minimum fraction of responding sources required in the consensus.
  final double minQuorumRatio;

  /// Absolute minimum number of sources required regardless of ratio.
  final int minimumQuorum;

  /// Minimum distinct administrative groups required for medium/high confidence.
  final int minGroupCount;

  /// Per-source query timeout.
  final Duration maxLatency;

  /// How often the engine refreshes its trust anchor in the background.
  final Duration refreshInterval;

  /// Samples with uncertainty wider than this threshold are excluded.
  final int maxAllowedUncertaintyMs;

  /// Whether to persist the trust anchor to survive cold-starts.
  final bool persistState;

  /// Stop querying additional sources as soon as minimum quorum is reached.
  final bool earlyExit;

  /// Expected oscillator drift rate (default: 50 ppm).
  ///
  /// Used by [MonoTimeEstimate] to compute the estimated error growth rate
  /// over time since the last sync.
  final double oscillatorDriftFactor;

  /// If set, background sync is enabled at this interval after [initialize].
  final Duration? backgroundSyncInterval;

  /// Derives [MarzulloEngine] parameters from this config.
  MarzulloEngine toMarzulloEngine() => MarzulloEngine(
        minQuorumRatio: minQuorumRatio,
        maxAllowedUncertaintyMs: maxAllowedUncertaintyMs,
        minGroupCount: minGroupCount,
      );
}

/// A hardware-anchored trust anchor persisted between syncs.
///
/// All time projections are computed as:
/// ```
/// now = networkUtcMs + (currentUptimeMs - uptimeMs)
/// ```
/// This formula is immune to system-clock manipulation.
@immutable
final class TrustAnchor {
  /// Creates a [TrustAnchor].
  const TrustAnchor({
    required this.networkUtcMs,
    required this.uptimeMs,
    required this.wallMs,
    required this.uncertaintyMs,
    required this.confidence,
  });

  /// Verified UTC time in milliseconds since epoch at the moment of consensus.
  final int networkUtcMs;

  /// Platform monotonic uptime at the moment of consensus (ms since boot).
  final int uptimeMs;

  /// System wall-clock at the moment of consensus (ms since epoch).
  ///
  /// Used only for offline estimation fallback where the anchor is unavailable.
  final int wallMs;

  /// Uncertainty of the consensus estimate in milliseconds.
  final int uncertaintyMs;

  /// Confidence grade of this anchor.
  final ConfidenceLevel confidence;

  /// Constructs a [TrustAnchor] from a [ConsensusResult].
  factory TrustAnchor.fromConsensus(ConsensusResult result) => TrustAnchor(
        networkUtcMs: result.utc.millisecondsSinceEpoch,
        uptimeMs: result.uptimeMs,
        wallMs: DateTime.now().millisecondsSinceEpoch,
        uncertaintyMs: result.uncertaintyMs,
        confidence: result.confidence,
      );

  /// Serializes to a plain [Map] for storage.
  Map<String, dynamic> toJson() => {
        'networkUtcMs': networkUtcMs,
        'uptimeMs': uptimeMs,
        'wallMs': wallMs,
        'uncertaintyMs': uncertaintyMs,
        'confidence': confidence.index,
      };

  /// Deserializes from a plain [Map].
  factory TrustAnchor.fromJson(Map<String, dynamic> json) => TrustAnchor(
        networkUtcMs: json['networkUtcMs'] as int,
        uptimeMs: json['uptimeMs'] as int,
        wallMs: json['wallMs'] as int,
        uncertaintyMs: json['uncertaintyMs'] as int,
        confidence: ConfidenceLevel.values[json['confidence'] as int],
      );
}

/// Sync telemetry emitted after each synchronization cycle.
@immutable
final class SyncMetrics {
  /// Creates a [SyncMetrics].
  const SyncMetrics({
    required this.duration,
    required this.sourceCount,
    required this.participantCount,
    required this.groupCount,
    required this.confidence,
    required this.uncertaintyMs,
  });

  /// Wall-clock duration of the entire sync cycle.
  final Duration duration;

  /// Number of sources that responded.
  final int sourceCount;

  /// Number of sources that participated in the final consensus.
  final int participantCount;

  /// Number of distinct administrative groups in the consensus.
  final int groupCount;

  /// Confidence grade of the resulting anchor.
  final ConfidenceLevel confidence;

  /// Uncertainty of the resulting consensus in milliseconds.
  final int uncertaintyMs;

  @override
  String toString() =>
      'SyncMetrics(duration=${duration.inMilliseconds}ms, sources=$sourceCount, '
      'participants=$participantCount, groups=$groupCount, '
      'confidence=${confidence.name}, ±${uncertaintyMs}ms)';
}
