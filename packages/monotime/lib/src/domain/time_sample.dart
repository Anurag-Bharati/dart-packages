import 'package:flutter/foundation.dart';
import 'time_interval.dart';

/// Protocol group classifier for Marzullo diversity requirements.
enum TimeSourceGroup {
  /// NTP (UDP, RFC 5905).
  ntp,

  /// HTTPS Date-header source (TLS-authenticated, HTTP RFC 7231).
  https,

  /// Unknown / custom source.
  other,
}

/// A single time measurement from a remote authority.
///
/// Wraps the mathematical [interval] with source telemetry so [MarzulloEngine]
/// can enforce administrative-group diversity.
@immutable
final class TimeSample {
  /// Creates a [TimeSample].
  const TimeSample({
    required this.interval,
    required this.sourceId,
    required this.groupId,
    required this.group,
    required this.uptimeMs,
  });

  /// The closed-interval `[T - error, T + error]` in epoch ms.
  final TimeInterval interval;

  /// Unique identifier for the source (e.g. `'ntp:time.cloudflare.com'`).
  final String sourceId;

  /// Administrative group identifier (hostname or ASN) used for
  /// diversity checking.
  final String groupId;

  /// Protocol classification.
  final TimeSourceGroup group;

  /// Platform monotonic uptime at the moment this sample was captured (ms).
  ///
  /// Used to anchor network time to the hardware oscillator.
  final int uptimeMs;

  @override
  String toString() => 'TimeSample(src=$sourceId, mid=${interval.midpointMs}ms, '
      '±${interval.uncertaintyMs}ms, uptime=${uptimeMs}ms)';
}
