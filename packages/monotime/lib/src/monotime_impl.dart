import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'anchor_store.dart';
import 'domain/marzullo_engine.dart';
import 'domain/time_sample.dart';
import 'exceptions.dart';
import 'infra/sync_observer.dart';
import 'integrity_event.dart';
import 'integrity_monitor.dart';
import 'models.dart';
import 'monotime_estimate.dart';
import 'monotonic_clock.dart';
import 'sync_engine.dart';


/// Internal implementation engine for [MonoTime].
///
/// Manages the full lifecycle: bootstrap, warm-start restore, background
/// refresh, tamper monitoring, and resource cleanup.
final class MonoTimeImpl {
  MonoTimeImpl._({
    required MonoTimeConfig config,
    required AnchorStore store,
    required MonotonicClock clock,
  })  : _config = config,
        _store = store,
        _syncClock = SyncClock(),
        _monitor = IntegrityMonitor(clock: clock) {
    _syncEngine = SyncEngine(
      config: config,
      clock: clock,
      observer: _ProxySyncObserver(() => _observers),
    );
  }

  static MonoTimeImpl? _instance;

  /// The active singleton instance.
  static MonoTimeImpl get instance {
    assert(_instance != null, 'Call MonoTime.initialize() first.');
    return _instance!;
  }

  /// Initialises a new instance, disposing any previous one.
  static Future<MonoTimeImpl> init(MonoTimeConfig config) async {
    _instance?.dispose();
    final impl = MonoTimeImpl._(
      config: config,
      store: AnchorStore(),
      clock: PlatformMonotonicClock(),
    );
    await impl._bootstrap();
    _instance = impl;
    _bgChannel.setMethodCallHandler(impl._handleBackgroundMethodCall);
    return impl;
  }

  static const _bgChannel = MethodChannel('dev.monotime/background');

  final MonoTimeConfig _config;
  final AnchorStore _store;
  late final SyncEngine _syncEngine;
  final IntegrityMonitor _monitor;
  final SyncClock _syncClock;
  final Set<SyncObserver> _observers = {};

  TrustAnchor? _anchor;
  bool _trusted = false;
  Timer? _refreshTimer;
  Timer? _retryTimer;
  Timer? _desktopBgTimer;
  StreamSubscription<IntegrityEvent>? _integritySub;
  Completer<void>? _syncInProgress;

  // Offline estimation fallback — used when no anchor is active.
  int? _offlineLastUtcMs;
  int? _offlineLastWallMs;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Stream of [IntegrityEvent]s emitted on clock tamper or reboot.
  Stream<IntegrityEvent> get onIntegrityLost => _monitor.events;

  /// Whether the engine holds a valid, network-verified trust anchor.
  bool get isTrusted => _trusted;

  /// The current [TrustAnchor], or `null` before first sync.
  TrustAnchor? get anchor => _anchor;

  /// Registers a [SyncObserver] for telemetry callbacks.
  void registerObserver(SyncObserver observer) => _observers.add(observer);

  /// Unregisters a [SyncObserver].
  void unregisterObserver(SyncObserver observer) => _observers.remove(observer);

  /// Returns the current hardware-anchored UTC time. Synchronous — no I/O.
  ///
  /// Throws [MonoTimeNotReadyException] if no anchor is established.
  /// Use [nowEstimated] for a safe non-throwing alternative.
  DateTime now() {
    if (!_trusted || _anchor == null) {
      throw const MonoTimeNotReadyException();
    }
    return DateTime.fromMillisecondsSinceEpoch(
      _anchor!.networkUtcMs + _syncClock.elapsedSinceAnchorMs(),
      isUtc: true,
    );
  }

  /// Returns the current time as Unix milliseconds.
  int nowUnixMs() => now().millisecondsSinceEpoch;

  /// Returns the current time as an ISO 8601 string.
  String nowIso() => now().toIso8601String();

  /// Returns a best-effort [MonoTimeEstimate], falling back to wall-clock
  /// projection if no live anchor exists. Returns `null` on cold start with
  /// no persisted state.
  MonoTimeEstimate? nowEstimated() {
    int? baseUtcMs;
    int? baseWallMs;

    if (_anchor != null) {
      baseUtcMs = _anchor!.networkUtcMs;
      baseWallMs = _anchor!.wallMs;
    } else if (_offlineLastUtcMs != null && _offlineLastWallMs != null) {
      baseUtcMs = _offlineLastUtcMs;
      baseWallMs = _offlineLastWallMs;
    } else {
      return null;
    }

    final now = DateTime.now();
    final wallElapsed = Duration(
      milliseconds: now.millisecondsSinceEpoch - baseWallMs!,
    );

    // Confidence decays linearly over refreshInterval (72h fallback window).
    final totalMinutes =
        _config.refreshInterval.inMinutes > 0 ? _config.refreshInterval.inMinutes : 4320;
    final confidence =
        (1.0 - wallElapsed.inMinutes.abs() / totalMinutes).clamp(0.0, 1.0);

    // Error grows at the configured oscillator drift rate.
    final errorMs = (wallElapsed.inMilliseconds.abs() * _config.oscillatorDriftFactor)
        .round();

    return MonoTimeEstimate(
      estimatedTime: DateTime.fromMillisecondsSinceEpoch(
        baseUtcMs! + wallElapsed.inMilliseconds,
        isUtc: true,
      ),
      confidence: confidence,
      estimatedError: Duration(milliseconds: errorMs),
      confidenceLevel: _anchor?.confidence ?? ConfidenceLevel.none,
    );
  }

  /// Forces an immediate network sync cycle, invalidating the current anchor.
  Future<void> forceResync() async {
    _trusted = false;
    await _performSync();
  }

  /// Enables periodic background sync at [interval].
  ///
  /// On Android/iOS this delegates to the native background task scheduler.
  /// On desktop, a Dart timer is used.
  Future<void> enableBackgroundSync(Duration interval) async {
    if (kIsWeb) return;
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      if (kDebugMode && interval.inHours < 1) {
        debugPrint('[monotime] Background sync interval below 1h.');
      }
      await _invokeBackgroundSync(interval);
    } else {
      _desktopBgTimer?.cancel();
      _desktopBgTimer = Timer.periodic(interval, (_) => _performSync());
    }
  }

  // ── Private ───────────────────────────────────────────────────────────────

  Future<void> _bootstrap() async {
    _monitor.start();
    _listenForIntegrityEvents();

    // Load offline estimation fallback.
    if (_config.persistState) {
      final lastKnown = await _store.loadLastKnown();
      if (lastKnown != null) {
        _offlineLastUtcMs = lastKnown.utcMs;
        _offlineLastWallMs = lastKnown.wallMs;
      }
    }

    // Warm-start: restore persisted anchor if the device hasn't rebooted.
    final persisted = _config.persistState ? await _store.load() : null;
    if (persisted != null) {
      final rebooted = await _monitor.checkRebootOnWarmStart(persisted);
      if (!rebooted) {
        _applyAnchor(persisted);
        _trusted = true;
        _scheduleRefresh();
        if (_config.backgroundSyncInterval != null) {
          await enableBackgroundSync(_config.backgroundSyncInterval!);
        }
        return; // Skip initial sync — anchor is still valid.
      }
    }

    await _performSync();
    if (_config.backgroundSyncInterval != null) {
      await enableBackgroundSync(_config.backgroundSyncInterval!);
    }
  }

  void _listenForIntegrityEvents() {
    _integritySub?.cancel();
    _integritySub = _monitor.events.listen((event) {
      if (event.reason == TamperReason.systemClockJumped ||
          event.reason == TamperReason.deviceRebooted) {
        _trusted = false;
        // Trigger an immediate recovery sync.
        unawaited(_performSync());
      }
    });
  }

  Future<void> _performSync() async {
    // Deduplicate concurrent sync requests.
    if (_syncInProgress != null) return _syncInProgress!.future;
    final completer = Completer<void>();
    _syncInProgress = completer;
    _retryTimer?.cancel();

    try {
      final anchor = await _syncEngine.sync();
      _applyAnchor(anchor);
      if (_config.persistState) await _store.save(anchor);
      _trusted = true;
      _offlineLastUtcMs = anchor.networkUtcMs;
      _offlineLastWallMs = anchor.wallMs;
      _scheduleRefresh();
    } catch (e) {
      if (kDebugMode) debugPrint('[monotime] Sync failed: $e');
      _trusted = false;
      _scheduleRetry();
    } finally {
      _syncInProgress = null;
      completer.complete();
    }
  }

  void _applyAnchor(TrustAnchor anchor) {
    _anchor = anchor;
    _syncClock.update(anchor.uptimeMs, anchor.networkUtcMs);
    _monitor.attach(anchor);
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(_config.refreshInterval, _performSync);
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    final delay = _syncEngine.getNextRetryDelay();
    if (delay > Duration.zero) {
      _retryTimer = Timer(delay, _performSync);
    }
  }

  Future<void> _invokeBackgroundSync(Duration interval) async {
    try {
      await _bgChannel.invokeMethod<void>('enableBackgroundSync', {
        'intervalHours': interval.inHours.clamp(1, 168),
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[monotime] Native background sync setup failed: $e');
    }
  }

  Future<void> _handleBackgroundMethodCall(MethodCall call) async {
    if (call.method == 'onBackgroundSync') await _performSync();
  }

  /// Releases all resources.
  void dispose() {
    _refreshTimer?.cancel();
    _retryTimer?.cancel();
    _desktopBgTimer?.cancel();
    _integritySub?.cancel();
    _syncEngine.dispose();
    _monitor.dispose();
    _syncClock.dispose();
  }
}

// ── Internal proxy for multi-observer fanout ──────────────────────────────────

class _ProxySyncObserver implements SyncObserver {
  _ProxySyncObserver(this._getObservers);
  final Set<SyncObserver> Function() _getObservers;

  @override
  void onSyncStarted() {
    for (final o in _getObservers()) {
      o.onSyncStarted();
    }
  }

  @override
  void onSampleReceived(TimeSample sample) {
    for (final o in _getObservers()) {
      o.onSampleReceived(sample);
    }
  }

  @override
  void onSourceFailed(String sourceId, Object error) {
    for (final o in _getObservers()) {
      o.onSourceFailed(sourceId, error);
    }
  }

  @override
  void onConsensusReached(ConsensusResult result) {
    for (final o in _getObservers()) {
      o.onConsensusReached(result);
    }
  }

  @override
  void onSyncFailed(Object error) {
    for (final o in _getObservers()) {
      o.onSyncFailed(error);
    }
  }

  @override
  void onMetricsReported(SyncMetrics metrics) {
    for (final o in _getObservers()) {
      o.onMetricsReported(metrics);
    }
  }
}
