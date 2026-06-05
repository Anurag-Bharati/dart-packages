import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'domain/marzullo_engine.dart';
import 'domain/time_sample.dart';
import 'domain/time_source.dart';
import 'exceptions.dart';
import 'infra/sync_observer.dart';
import 'models.dart';
import 'monotonic_clock.dart';
import 'sources/https_source.dart';
import 'sources/ntp_source.dart';

/// Orchestrates multi-source time synchronisation and Marzullo consensus.
///
/// Responsibilities:
/// 1. Constructs [TimeSource] instances from [MonoTimeConfig].
/// 2. Queries all healthy sources in parallel.
/// 3. Feeds results to [MarzulloEngine] for consensus resolution.
/// 4. Returns a validated [TrustAnchor] or throws [MonoTimeSyncException].
final class SyncEngine {
  /// Creates a [SyncEngine].
  SyncEngine({
    required MonoTimeConfig config,
    required MonotonicClock clock,
    SyncObserver? observer,
  })  : _config = config,
        _clock = clock,
        _observer = observer,
        _engine = config.toMarzulloEngine();

  final MonoTimeConfig _config;
  final MonotonicClock _clock;
  final SyncObserver? _observer;
  final MarzulloEngine _engine;

  /// Lazily built source list. Rebuilt on first access only.
  late final List<TimeSource> _sources = [
    for (final host in _config.ntpServers) NtpSource(host, timeout: _config.maxLatency),
    for (final url in _config.httpsSources) HttpsSource(url, timeout: _config.maxLatency),
  ];

  /// Per-source consecutive failure counts for exponential backoff.
  final _sourceFailures = <String, int>{};

  /// Timestamps until which a source is in cooldown.
  final _blacklistUntil = <String, DateTime>{};

  int _syncAttempts = 0;

  /// Executes a full synchronization cycle.
  ///
  /// Queries all non-blacklisted sources concurrently, feeds samples to
  /// [MarzulloEngine], and returns a [TrustAnchor] on success.
  ///
  /// Throws [MonoTimeSyncException] if no quorum can be established.
  Future<TrustAnchor> sync() async {
    _observer?.onSyncStarted();
    _syncAttempts++;
    final sw = Stopwatch()..start();

    // Get current platform uptime so we can anchor samples.
    final uptimeMs = await _clock.uptimeMs();

    final now = DateTime.now();
    final healthySources = _sources.where((s) {
      final until = _blacklistUntil[s.id];
      return until == null || now.isAfter(until);
    }).toList();

    if (kDebugMode) {
      debugPrint('[monotime] Sync cycle #$_syncAttempts started.');
      debugPrint('[monotime] Healthy sources to query: ${healthySources.map((s) => s.id).join(', ')}');
    }

    if (healthySources.isEmpty) {
      throw const MonoTimeSyncException(
        'All time sources are currently in exponential backoff cooldown.',
      );
    }

    final samples = <TimeSample>[];
    var earlyExitReached = false;

    // Query sources concurrently but process results as they arrive.
    final futures = healthySources.map((source) async {
      if (earlyExitReached) return null;
      try {
        if (kDebugMode) {
          debugPrint('[monotime] Querying time from source: ${source.id}');
        }
        final sample = await source.getTime(uptimeMs, sw);
        _sourceFailures.remove(source.id);
        _observer?.onSampleReceived(sample);
        samples.add(sample);
        if (kDebugMode) {
          debugPrint('[monotime] Source ${source.id} succeeded: $sample');
        }

        // Early exit: try consensus as soon as we have enough samples.
        if (_config.earlyExit) {
          final provisional = _engine.resolve(samples);
          if (provisional != null) {
            earlyExitReached = true;
          }
        }
        return sample;
      } catch (e) {
        _observer?.onSourceFailed(source.id, e);
        _recordFailure(source.id);
        if (kDebugMode) {
          debugPrint('[monotime] Source ${source.id} failed: $e');
        }
        return null;
      }
    });

    await Future.wait(futures);

    final consensus = _engine.resolve(samples);

    if (consensus == null) {
      final error = MonoTimeSyncException(
        'Marzullo consensus failed. Responding sources: ${samples.length}, '
        'required quorum: ${(_config.minQuorumRatio * healthySources.length).ceil()}.',
      );
      _observer?.onSyncFailed(error);
      if (kDebugMode) {
        debugPrint('[monotime] Sync failed: $error');
      }
      throw error;
    }

    _observer?.onConsensusReached(consensus);
    sw.stop();

    if (kDebugMode) {
      debugPrint('[monotime] Consensus successfully resolved: $consensus');
    }

    final anchor = TrustAnchor.fromConsensus(consensus);

    _observer?.onMetricsReported(SyncMetrics(
      duration: sw.elapsed,
      sourceCount: samples.length,
      participantCount: consensus.participantCount,
      groupCount: consensus.groupCount,
      confidence: consensus.confidence,
      uncertaintyMs: consensus.uncertaintyMs,
    ));

    return anchor;
  }

  /// Computes the next retry delay using exponential backoff with jitter.
  Duration getNextRetryDelay() {
    const base = Duration(seconds: 15);
    const cap = Duration(minutes: 10);
    final exponent = min(_syncAttempts, 6);
    final delay = base * pow(2, exponent).toInt();
    final jitter = Duration(milliseconds: Random().nextInt(5000));
    return delay > cap ? cap + jitter : delay + jitter;
  }

  void _recordFailure(String sourceId) {
    final failures = (_sourceFailures[sourceId] ?? 0) + 1;
    _sourceFailures[sourceId] = failures;
    // Exponential backoff: 30s, 1m, 2m, 4m … up to 30m
    final backoff = const Duration(seconds: 30) * pow(2, min(failures - 1, 5)).toInt();
    _blacklistUntil[sourceId] = DateTime.now().add(backoff);
  }

  /// Releases resources owned by this engine.
  void dispose() {}
}
