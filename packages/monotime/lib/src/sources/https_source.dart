import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../domain/time_sample.dart';
import '../domain/time_interval.dart';
import '../domain/time_source.dart';

/// Fetches UTC time from an HTTPS endpoint's `Date` response header.
///
/// The `Date` header is mandated by RFC 7231 and carried over a TLS-verified
/// connection — providing server authentication without the NTS-KE handshake.
/// Uncertainty is higher than NTP (~200–1000 ms) due to HTTPS overhead.
final class HttpsSource implements TimeSource {
  /// Creates an [HttpsSource] for [url].
  HttpsSource(this._url, {http.Client? client, Duration timeout = const Duration(seconds: 4)})
      : _client = client ?? http.Client(),
        _timeout = timeout;

  final String _url;
  final http.Client _client;
  final Duration _timeout;

  @override
  String get id => '${TimeSource.prefixHttps}$_url';

  @override
  String get groupId {
    try {
      return Uri.parse(_url).host;
    } catch (_) {
      return _url;
    }
  }

  @override
  Future<TimeSample> getTime(int currentUptimeMs, Stopwatch syncStopwatch) async {
    final startElapsedMs = syncStopwatch.elapsedMilliseconds;
    final uri = Uri.parse(_url);
    final sw = Stopwatch()..start();

    // Prefer HEAD (no body); fall back to GET if the server rejects HEAD,
    // omits the Date header on HEAD responses, or throws/times out.
    http.Response response;
    try {
      response = await _client.head(uri).timeout(_timeout);
      if (response.statusCode == 405 || response.headers['date'] == null) {
        throw Exception('HEAD rejected or missing Date header');
      }
    } catch (_) {
      sw.reset();
      sw.start();
      response = await _client.get(uri).timeout(_timeout);
    }
    sw.stop();
    final rttMs = sw.elapsedMilliseconds;

    final dateHeader = response.headers['date'];
    if (dateHeader == null) {
      throw Exception('Server at $_url did not return a Date header.');
    }

    // Parse the RFC 7231 date string (e.g. "Thu, 05 Jun 2025 12:00:00 GMT").
    final serverUtc = _parseHttpDate(dateHeader);
    final serverUtcMs = serverUtc.millisecondsSinceEpoch;

    // Project the server time back to the start of the sync cycle (when currentUptimeMs was recorded).
    // The server's clock is assumed to be read at the midpoint of the request round trip.
    final midpointElapsedMs = startElapsedMs + (rttMs ~/ 2);
    final serverUtcAtMidpointMs = serverUtcMs + (rttMs ~/ 2);
    final correctedUtcMs = serverUtcAtMidpointMs - midpointElapsedMs;

    // HTTPS uncertainty: half RTT + 500 ms quantisation buffer (Date header
    // has 1-second granularity, so we use 500 ms as the half-second offset).
    final uncertaintyMs = (rttMs ~/ 2) + 500;

    return TimeSample(
      interval: TimeInterval(
        startMs: correctedUtcMs - uncertaintyMs,
        endMs: correctedUtcMs + uncertaintyMs,
      ),
      sourceId: id,
      groupId: groupId,
      group: TimeSourceGroup.https,
      uptimeMs: currentUptimeMs,
    );
  }

  /// Parses an RFC 7231 / RFC 1123 / RFC 850 / asctime HTTP date string to a UTC [DateTime].
  ///
  /// Supported formats:
  /// - IMF-fixdate: `Sun, 06 Nov 1994 08:49:37 GMT`
  /// - RFC 850: `Sunday, 06-Nov-94 08:49:37 GMT`
  /// - asctime: `Sun Nov  6 08:49:37 1994`
  static DateTime _parseHttpDate(String value) {
    const months = {
      'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4,
      'May': 5, 'Jun': 6, 'Jul': 7, 'Aug': 8,
      'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
    };

    const weekdays = {
      'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
    };

    final clean = value.trim();
    final parts = clean.split(RegExp(r'\s+'));
    if (parts.isEmpty) {
      throw FormatException('Invalid HTTP Date format: $value');
    }

    var startIndex = 0;
    final firstPart = parts[0];
    final cleanFirstPart = firstPart.endsWith(',')
        ? firstPart.substring(0, firstPart.length - 1)
        : firstPart;
    if (weekdays.contains(cleanFirstPart)) {
      startIndex = 1;
    }

    final dateParts = parts.sublist(startIndex);

    try {
      if (dateParts.isEmpty) {
        throw const FormatException('Empty date payload after weekday');
      }

      if (dateParts[0].contains('-')) {
        // RFC 850 format: "06-Nov-94 08:49:37 GMT"
        final dateSubParts = dateParts[0].split('-');
        if (dateSubParts.length < 3 || dateParts.length < 2) {
          throw const FormatException('Invalid RFC 850 format');
        }
        final day = int.parse(dateSubParts[0]);
        final monthStr = dateSubParts[1];
        final month = months[monthStr] ?? (throw FormatException('Unknown month: $monthStr'));
        var year = int.parse(dateSubParts[2]);
        
        // Two-digit year expansion:
        if (year >= 70 && year <= 99) {
          year += 1900;
        } else if (year >= 0 && year < 70) {
          year += 2000;
        }

        final timeParts = dateParts[1].split(':');
        if (timeParts.length < 3) throw FormatException('Invalid time format: ${dateParts[1]}');
        final hour = int.parse(timeParts[0]);
        final minute = int.parse(timeParts[1]);
        final second = int.parse(timeParts[2]);

        return DateTime.utc(year, month, day, hour, minute, second);
      } else if (months.containsKey(dateParts[0])) {
        // asctime format: "Nov  6 08:49:37 1994"
        if (dateParts.length < 4) {
          throw const FormatException('Invalid asctime format');
        }
        final month = months[dateParts[0]]!;
        final day = int.parse(dateParts[1]);
        final timeParts = dateParts[2].split(':');
        if (timeParts.length < 3) throw FormatException('Invalid time format: ${dateParts[2]}');
        final hour = int.parse(timeParts[0]);
        final minute = int.parse(timeParts[1]);
        final second = int.parse(timeParts[2]);
        final year = int.parse(dateParts[3]);

        return DateTime.utc(year, month, day, hour, minute, second);
      } else {
        // IMF-fixdate format: "06 Nov 1994 08:49:37 GMT"
        if (dateParts.length < 4) {
          throw const FormatException('Invalid IMF-fixdate format');
        }
        final day = int.parse(dateParts[0]);
        final monthStr = dateParts[1];
        final month = months[monthStr] ?? (throw FormatException('Unknown month: $monthStr'));
        final year = int.parse(dateParts[2]);
        final timeParts = dateParts[3].split(':');
        if (timeParts.length < 3) throw FormatException('Invalid time format: ${dateParts[3]}');
        final hour = int.parse(timeParts[0]);
        final minute = int.parse(timeParts[1]);
        final second = int.parse(timeParts[2]);

        return DateTime.utc(year, month, day, hour, minute, second);
      }
    } catch (e) {
      throw FormatException('Error parsing HTTP Date "$value": $e');
    }
  }

  /// Parses an HTTP date string (visible for testing).
  @visibleForTesting
  static DateTime parseHttpDateForTesting(String value) => _parseHttpDate(value);
}
