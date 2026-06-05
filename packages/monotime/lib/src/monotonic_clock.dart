import 'package:flutter/services.dart';

/// Contract for a hardware-pinned monotonic ticker.
///
/// Monotonic clocks only advance forward and are immune to system-clock
/// manipulation. They reset to zero on device reboot, which we exploit for
/// reboot detection.
abstract interface class MonotonicClock {
  /// Returns the platform monotonic uptime in milliseconds since last boot.
  ///
  /// - **Android**: `SystemClock.elapsedRealtime()` — includes deep-sleep time.
  /// - **iOS**: `ProcessInfo.processInfo.systemUptime * 1000`.
  Future<int> uptimeMs();

  /// Returns the native platform-provided network time in milliseconds since epoch, or `null`.
  ///
  /// - **Android**: Returns the OS network-synced time (or `null` if GMS is unavailable,
  ///   or if standard framework APIs do not expose a public network time source).
  /// - **iOS**: Always returns `null` (not supported by public iOS system APIs).
  Future<int?> networkTimeMs();
}

/// Production implementation backed by native OS kernel timers via
/// platform channel.
final class PlatformMonotonicClock implements MonotonicClock {
  static const _channel = MethodChannel('dev.monotime/monotonic');

  @override
  Future<int> uptimeMs() async {
    final result = await _channel.invokeMethod<int>('getUptimeMs');
    if (result == null) {
      throw StateError('Platform returned null for monotonic uptime.');
    }
    return result;
  }

  @override
  Future<int?> networkTimeMs() async {
    try {
      return await _channel.invokeMethod<int?>('getNetworkTimeMs');
    } catch (_) {
      return null;
    }
  }
}

/// A sub-microsecond in-process projection clock.
///
/// After each call to [update], uses a Dart [Stopwatch] to project the
/// current uptime without a platform channel round-trip. This allows
/// [MonoTime.now] to be fully synchronous.
///
/// **Sleep note**: Dart's [Stopwatch] is backed by `CLOCK_MONOTONIC` on
/// Linux/Android, which does *not* advance during CPU sleep, whereas
/// `SystemClock.elapsedRealtime()` uses `CLOCK_BOOTTIME` which *does*.
/// The gap is corrected on every [update] call (triggered after each
/// network sync and on app-foreground events).
final class SyncClock {
  final _sw = Stopwatch();
  int _lastUptimeMs = 0;
  int _lastAnchorNetworkUtcMs = 0;

  /// Updates the internal baseline from a fresh platform uptime reading
  /// and the corresponding network UTC.
  void update(int uptimeMs, int networkUtcMs) {
    _lastUptimeMs = uptimeMs;
    _lastAnchorNetworkUtcMs = networkUtcMs;
    _sw.reset();
    _sw.start();
  }

  /// Returns milliseconds elapsed since the last [update] call.
  ///
  /// Dart stopwatch is monotonic and does not regress.
  int elapsedSinceAnchorMs() => _sw.elapsedMilliseconds;

  /// Current estimated uptime without a platform call.
  int get currentUptimeMs => _lastUptimeMs + _sw.elapsedMilliseconds;

  /// Current best-estimate network UTC time in milliseconds since epoch.
  int get nowMs => _lastAnchorNetworkUtcMs + _sw.elapsedMilliseconds;

  /// Releases resources.
  void dispose() => _sw.stop();
}
