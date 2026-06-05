import 'dart:async';
import 'package:flutter/services.dart';
import 'integrity_event.dart';
import 'monotonic_clock.dart';
import 'models.dart';

/// Detects and broadcasts clock-integrity violations.
///
/// Listens to two signals:
/// 1. **Platform tamper events** (via [EventChannel]): `ACTION_TIME_CHANGED`
///    on Android, `NSSystemClockDidChange` / `NSSystemTimeZoneDidChange` on iOS.
/// 2. **Proactive reboot detection**: on each [attach] call (after a fresh sync),
///    compares the new anchor's uptime against the previously known uptime to
///    detect whether the device rebooted between syncs.
final class IntegrityMonitor {
  /// Creates an [IntegrityMonitor].
  IntegrityMonitor({required MonotonicClock clock}) : _clock = clock;

  static const _eventChannel = EventChannel('dev.monotime/tamper');

  final MonotonicClock _clock;
  final _controller = StreamController<IntegrityEvent>.broadcast();
  StreamSubscription<Object?>? _platformSub;
  TrustAnchor? _currentAnchor;

  /// Stream of [IntegrityEvent]s. Broadcast — safe for multiple listeners.
  Stream<IntegrityEvent> get events => _controller.stream;

  /// Starts listening for platform tamper events.
  void start() {
    _platformSub?.cancel();
    _platformSub = _eventChannel.receiveBroadcastStream().listen(
      _onPlatformEvent,
      onError: (_) {}, // silently ignore channel errors
    );
  }

  /// Attaches a newly established [anchor] and performs reboot detection.
  ///
  /// Returns `true` if a reboot was detected (caller should invalidate state).
  bool attach(TrustAnchor anchor) {
    final prev = _currentAnchor;
    _currentAnchor = anchor;

    if (prev != null && anchor.uptimeMs < prev.uptimeMs) {
      // New anchor's uptime is lower than the previous anchor's uptime →
      // the monotonic counter reset → device rebooted.
      _emit(TamperReason.deviceRebooted);
      return true;
    }
    return false;
  }

  /// Checks whether a reboot occurred since [storedAnchor] was persisted.
  ///
  /// Called during warm-start to decide whether to restore the persisted anchor.
  Future<bool> checkRebootOnWarmStart(TrustAnchor storedAnchor) async {
    final currentUptime = await _clock.uptimeMs();
    if (currentUptime < storedAnchor.uptimeMs) {
      // Uptime is lower than when the anchor was stored → device rebooted.
      _emit(TamperReason.deviceRebooted);
      return true;
    }
    return false;
  }

  void _onPlatformEvent(Object? event) {
    if (event is! String) return;
    final reason = switch (event) {
      'systemClockJumped' => TamperReason.systemClockJumped,
      'timezoneChanged' => TamperReason.timezoneChanged,
      _ => null,
    };
    if (reason != null) _emit(reason);
  }

  void _emit(TamperReason reason) {
    if (_controller.isClosed) return;
    _controller.add(IntegrityEvent(
      reason: reason,
      detectedAt: DateTime.now().toUtc(),
    ));
  }

  /// Releases resources.
  void dispose() {
    _platformSub?.cancel();
    _controller.close();
  }
}
