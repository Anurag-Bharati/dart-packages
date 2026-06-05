/// MonoTime — Tamper-resistant network time for Flutter.
///
/// Provides cryptographically-aware, hardware-anchored UTC timestamps that
/// remain accurate even when the system clock is manipulated by the user.
///
/// ## Core Concepts
///
/// * **Monotonic Anchoring**: Network-verified time is anchored to the device's
///   hardware oscillator (monotonic uptime). This creates a virtual clock that
///   cannot be rolled back or forward by the user changing system settings.
/// * **Marzullo Consensus**: Multi-source quorum resolution filters out noisy
///   or compromised time authorities.
/// * **No Rust / No NTS-KE**: Sources are NTP (UDP) + HTTPS Date headers
///   (TLS-authenticated). Sufficient for mobile fraud prevention with zero
///   native build complexity.
///
/// ## Usage
///
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await MonoTime.initialize();
///   runApp(MyApp());
/// }
///
/// // Anywhere in the app:
/// final now = MonoTime.now();            // throws if not ready
/// final est = MonoTime.nowEstimated();   // safe fallback, never throws
/// ```
library;

export 'src/exceptions.dart';
export 'src/integrity_event.dart';
export 'src/models.dart' show MonoTimeConfig, TrustAnchor, ConfidenceLevel, SyncMetrics;
export 'src/monotime_estimate.dart';
export 'src/infra/sync_observer.dart';
export 'src/domain/time_sample.dart' show TimeSample, TimeSourceGroup;
export 'src/domain/marzullo_engine.dart' show ConsensusResult;
export 'src/domain/time_interval.dart' show TimeInterval;

import 'src/infra/sync_observer.dart';
import 'src/integrity_event.dart';
import 'src/models.dart';
import 'src/monotime_estimate.dart';
import 'src/monotime_impl.dart';

/// The primary gateway for high-integrity time synchronisation and retrieval.
///
/// [MonoTime] implements a self-healing state machine. It handles initial
/// synchronisation, background maintenance, and proactive drift detection.
///
/// For most use cases, [now] is the preferred retrieval method. For
/// non-critical paths where a cold-start estimate is acceptable, use
/// [nowEstimated].
abstract final class MonoTime {
  MonoTime._();

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Bootstraps the time integrity subsystem.
  ///
  /// Must be called once at app launch, before [runApp]. It:
  /// 1. Restores the last known trust anchor from storage.
  /// 2. Launches the initial network synchronization cycle.
  /// 3. Starts integrity monitoring for clock tamper events.
  ///
  /// ```dart
  /// void main() async {
  ///   WidgetsFlutterBinding.ensureInitialized();
  ///   await MonoTime.initialize(); // Essential first step
  ///   runApp(MyApp());
  /// }
  /// ```
  static Future<void> initialize({MonoTimeConfig? config}) async {
    if (_override != null) return;
    await MonoTimeImpl.init(config ?? const MonoTimeConfig());
  }

  // ── Time retrieval ────────────────────────────────────────────────────────

  /// Returns the current hardware-anchored UTC time. Synchronous — no I/O.
  ///
  /// This is an arithmetic projection based on the active [TrustAnchor] and
  /// typically completes in under 50 µs.
  ///
  /// Throws [MonoTimeNotReadyException] if no anchor is established yet.
  /// Use [nowEstimated] for a safe non-throwing alternative.
  static DateTime now() {
    final ov = _override;
    if (ov != null) return ov.now;
    return MonoTimeImpl.instance.now();
  }

  /// Returns the current time as Unix milliseconds.
  static int nowUnixMs() => now().millisecondsSinceEpoch;

  /// Returns the current time as an ISO 8601 string.
  static String nowIso() => now().toIso8601String();

  /// Returns a best-effort [MonoTimeEstimate] that never throws.
  ///
  /// Falls back to wall-clock projection from the last known anchor.
  /// Returns `null` only on a cold start with no persisted anchor state.
  static MonoTimeEstimate? nowEstimated() {
    final ov = _override;
    if (ov != null) {
      return MonoTimeEstimate(
        estimatedTime: ov.now,
        confidence: 1.0,
        estimatedError: Duration.zero,
        confidenceLevel: ConfidenceLevel.high,
      );
    }
    return MonoTimeImpl.instance.nowEstimated();
  }

  // ── Status ────────────────────────────────────────────────────────────────

  /// Whether the engine holds a valid, network-verified trust anchor.
  static bool get isTrusted => MonoTimeImpl.instance.isTrusted;

  /// The currently active [TrustAnchor], or `null` before the first sync.
  static TrustAnchor? get anchor => MonoTimeImpl.instance.anchor;

  // ── Actions ───────────────────────────────────────────────────────────────

  /// Forces an immediate network synchronization cycle.
  ///
  /// Invalidates the current anchor and re-establishes quorum from scratch.
  /// Use before high-value operations (e.g. financial transactions) where
  /// a fresh, cryptographically-recent anchor is required.
  static Future<void> forceResync() => MonoTimeImpl.instance.forceResync();

  /// Enables background sync at [interval] using OS-native task schedulers.
  ///
  /// - **Android**: Uses WorkManager / BGTaskScheduler.
  /// - **iOS**: Uses BGAppRefreshTask.
  /// - **Desktop**: Uses a Dart [Timer].
  static Future<void> enableBackgroundSync(Duration interval) =>
      MonoTimeImpl.instance.enableBackgroundSync(interval);

  // ── Observability ─────────────────────────────────────────────────────────

  /// Stream of [IntegrityEvent]s emitted when a tamper violation is detected.
  ///
  /// Subscribe to react to [TamperReason.systemClockJumped],
  /// [TamperReason.deviceRebooted], or [TamperReason.timezoneChanged].
  static Stream<IntegrityEvent> get onIntegrityLost =>
      MonoTimeImpl.instance.onIntegrityLost;

  /// Registers a [SyncObserver] for detailed synchronisation telemetry.
  static void registerObserver(SyncObserver observer) =>
      MonoTimeImpl.instance.registerObserver(observer);

  /// Unregisters a [SyncObserver].
  static void unregisterObserver(SyncObserver observer) =>
      MonoTimeImpl.instance.unregisterObserver(observer);

  // ── Testing ───────────────────────────────────────────────────────────────

  /// Injects a deterministic time override for testing.
  ///
  /// When set, [now] and [nowEstimated] return [override.now] instead of
  /// the live engine result. Call with `null` to restore normal behaviour.
  ///
  /// ```dart
  /// MonoTime.setTestOverride(MonoTimeTestOverride(now: DateTime(2025)));
  /// expect(MonoTime.now(), DateTime(2025).toUtc());
  /// MonoTime.setTestOverride(null);
  /// ```
  static void setTestOverride(MonoTimeTestOverride? override) {
    _override = override;
  }

  static MonoTimeTestOverride? _override;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Releases all resources held by the engine.
  ///
  /// Call in [State.dispose] of your root widget, or when the engine is
  /// no longer needed.
  static void dispose() {
    MonoTimeImpl.instance.dispose();
  }
}

/// A deterministic time override for widget and unit tests.
final class MonoTimeTestOverride {
  /// Creates a [MonoTimeTestOverride].
  const MonoTimeTestOverride({required this.now});

  /// The fixed UTC time to return from [MonoTime.now].
  final DateTime now;
}
