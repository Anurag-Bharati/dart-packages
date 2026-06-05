import 'package:ntp/ntp.dart';
import '../domain/time_sample.dart';
import '../domain/time_interval.dart';
import '../domain/time_source.dart';

/// Fetches UTC time from an NTP server via UDP (RFC 5905).
///
/// Uses the [ntp] package for the actual UDP exchange. Wraps the returned
/// offset in a [TimeSample] with RTT-derived uncertainty.
final class NtpSource implements TimeSource {
  /// Creates an [NtpSource] for [hostname].
  NtpSource(this._hostname, {Duration timeout = const Duration(seconds: 5)})
      : _timeout = timeout;

  final String _hostname;
  final Duration _timeout;

  @override
  String get id => '${TimeSource.prefixNtp}$_hostname';

  @override
  String get groupId => _hostname;

  @override
  Future<TimeSample> getTime(int currentUptimeMs, Stopwatch syncStopwatch) async {
    final startElapsedMs = syncStopwatch.elapsedMilliseconds;
    final localBefore = DateTime.now();

    // getNtpOffset returns the signed offset (ms) to add to local time
    // to obtain NTP server time.
    final offsetMs = await NTP.getNtpOffset(
      localTime: localBefore,
      lookUpAddress: _hostname,
      timeout: _timeout,
    );

    final localAfter = DateTime.now();
    final rttMs =
        localAfter.millisecondsSinceEpoch - localBefore.millisecondsSinceEpoch;

    // The server's claimed time, corrected for half the round-trip latency.
    final serverUtcMs =
        localBefore.millisecondsSinceEpoch + offsetMs + (rttMs ~/ 2);

    // Project the server time back to the start of the sync cycle (when currentUptimeMs was recorded).
    final midpointElapsedMs = startElapsedMs + (rttMs ~/ 2);
    final correctedUtcMs = serverUtcMs - midpointElapsedMs;

    // Uncertainty = half RTT + 50 ms oscillator/quantisation buffer.
    final uncertaintyMs = (rttMs ~/ 2) + 50;

    return TimeSample(
      interval: TimeInterval(
        startMs: correctedUtcMs - uncertaintyMs,
        endMs: correctedUtcMs + uncertaintyMs,
      ),
      sourceId: id,
      groupId: groupId,
      group: TimeSourceGroup.ntp,
      uptimeMs: currentUptimeMs,
    );
  }
}
