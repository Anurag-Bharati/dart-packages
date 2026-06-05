import '../domain/time_sample.dart';
import '../domain/marzullo_engine.dart';
import '../models.dart';

/// High-fidelity interface for monitoring the synchronization lifecycle.
///
/// Implement this to capture diagnostic metrics, build real-time progress UI,
/// or pipe telemetry to an analytics backend.
abstract interface class SyncObserver {
  /// Called when a sync cycle is initiated.
  void onSyncStarted();

  /// Called each time a source returns a valid [sample].
  void onSampleReceived(TimeSample sample);

  /// Called when a source fails to respond or returns unusable data.
  void onSourceFailed(String sourceId, Object error);

  /// Called when the [MarzulloEngine] resolves a [ConsensusResult].
  void onConsensusReached(ConsensusResult result);

  /// Called if the entire sync cycle fails (no quorum, all sources down).
  void onSyncFailed(Object error);

  /// Called after a successful sync with aggregate [metrics].
  void onMetricsReported(SyncMetrics metrics);
}
