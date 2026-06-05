import '../domain/time_sample.dart';

/// Common contract for all time sources consumed by [SyncEngine].
abstract interface class TimeSource {
  /// Prefix used in [TimeSample.sourceId] for NTP sources.
  static const prefixNtp = 'ntp:';

  /// Prefix used in [TimeSample.sourceId] for HTTPS sources.
  static const prefixHttps = 'https:';

  /// Unique identifier for this source instance.
  String get id;

  /// Administrative group identifier (hostname or ASN) for Marzullo diversity.
  String get groupId;

  /// Queries the source and returns a [TimeSample].
  ///
  /// Throws on failure. The [SyncEngine] catches and blacklists failing sources.
  Future<TimeSample> getTime(int currentUptimeMs, Stopwatch syncStopwatch);
}
