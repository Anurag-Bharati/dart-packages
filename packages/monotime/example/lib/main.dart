import 'dart:async';
import 'package:flutter/material.dart';
import 'package:monotime/monotime.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize the time subsystem with custom parameters for quicker demo updates
  await MonoTime.initialize(
    config: const MonoTimeConfig(
      ntpServers: ['time.cloudflare.com', 'time.google.com', 'pool.ntp.org'],
      httpsSources: [
        'https://www.cloudflare.com',
        'https://www.google.com',
        'https://www.apple.com',
      ],
      refreshInterval: Duration(minutes: 5), // short interval for demonstration
      minimumQuorum: 2,
      minGroupCount: 2,
      persistState: true,
    ),
  );

  runApp(const MyApp());
}

/// The main application widget.
class MyApp extends StatelessWidget {
  /// Creates the [MyApp] instance.
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MonoTime Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0F0E17),
        cardTheme: CardThemeData(
          color: const Color(0xFF1F1E29),
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      home: const MonoTimeHomeScreen(),
    );
  }
}

/// The dashboard home screen displaying MonoTime details.
class MonoTimeHomeScreen extends StatefulWidget {
  /// Creates the [MonoTimeHomeScreen] instance.
  const MonoTimeHomeScreen({super.key});

  @override
  State<MonoTimeHomeScreen> createState() => _MonoTimeHomeScreenState();
}

class _MonoTimeHomeScreenState extends State<MonoTimeHomeScreen> implements SyncObserver {
  late final Timer _uiTimer;
  StreamSubscription<IntegrityEvent>? _tamperSubscription;
  final List<String> _logs = [];
  bool _isSyncing = false;

  // Cached DateTime representations for rendering
  DateTime _deviceTime = DateTime.now();
  DateTime? _anchoredTime;
  MonoTimeEstimate? _estimate;

  @override
  void initState() {
    super.initState();
    MonoTime.registerObserver(this);
    _log('Application initialized.');
    _log('Current trust status: ${MonoTime.isTrusted ? "TRUSTED" : "UNTRUSTED"}');

    // Subscribe to integrity/tamper events
    _tamperSubscription = MonoTime.onIntegrityLost.listen((event) {
      _log('⚠️ INTEGRITY EVENT: ${event.reason.name} at ${event.detectedAt.toLocal()}');
      setState(() {});
    });

    // High frequency UI ticking (approx 30fps) for smooth millisecond display
    _uiTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
      if (!mounted) return;
      setState(() {
        _deviceTime = DateTime.now();
        if (MonoTime.isTrusted) {
          try {
            _anchoredTime = MonoTime.now();
          } catch (_) {
            _anchoredTime = null;
          }
        } else {
          _anchoredTime = null;
        }
        _estimate = MonoTime.nowEstimated();
      });
    });
  }

  @override
  void dispose() {
    _uiTimer.cancel();
    _tamperSubscription?.cancel();
    MonoTime.unregisterObserver(this);
    super.dispose();
  }

  void _log(String message) {
    final timestamp = DateTime.now().toLocal().toString().split(' ')[1].substring(0, 12);
    setState(() {
      _logs.insert(0, '[$timestamp] $message');
      if (_logs.length > 100) {
        _logs.removeLast();
      }
    });
  }

  Future<void> _handleResync() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);
    _log('Forcing manual NTP/HTTPS clock synchronisation...');
    try {
      await MonoTime.forceResync();
      _log('Synchronisation request dispatched.');
    } catch (e) {
      _log('❌ Sync dispatch error: $e');
      setState(() => _isSyncing = false);
    }
  }

  // ── SyncObserver Implementation ────────────────────────────────────────────

  @override
  void onSyncStarted() {
    _log('🔄 Synchronisation cycle started.');
    setState(() => _isSyncing = true);
  }

  @override
  void onSampleReceived(TimeSample sample) {
    _log('📥 Sample received from ${sample.sourceId}: interval=${sample.interval.startMs}-${sample.interval.endMs}');
  }

  @override
  void onSourceFailed(String sourceId, Object error) {
    _log('⚠️ Source $sourceId failed: $error');
  }

  @override
  void onConsensusReached(ConsensusResult result) {
    _log('✅ Quorum consensus reached!');
    _log('↳ UTC: ${result.utc.toIso8601String()}');
    _log('↳ Uncertainty: ±${result.uncertaintyMs.toStringAsFixed(1)} ms');
    _log('↳ Participant count: ${result.participantCount}');
    _log('↳ Confidence level: ${result.confidence.name.toUpperCase()}');
  }

  @override
  void onMetricsReported(SyncMetrics metrics) {
    _log('📈 Sync metrics: duration=${metrics.duration.inMilliseconds}ms, sources=${metrics.sourceCount}, participants=${metrics.participantCount}');
    setState(() => _isSyncing = false);
  }

  @override
  void onSyncFailed(Object error) {
    _log('❌ Quorum sync failed: $error');
    setState(() => _isSyncing = false);
  }

  // ── Rendering Helpers ──────────────────────────────────────────────────────

  String _formatDateTime(DateTime dt) {
    final hr = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final sec = dt.second.toString().padLeft(2, '0');
    final ms = dt.millisecond.toString().padLeft(3, '0');
    return '$hr:$min:$sec.$ms';
  }

  Color _getConfidenceColor(ConfidenceLevel? level) {
    switch (level) {
      case ConfidenceLevel.high:
        return Colors.greenAccent;
      case ConfidenceLevel.medium:
        return Colors.amberAccent;
      case ConfidenceLevel.low:
        return Colors.orangeAccent;
      case ConfidenceLevel.none:
      case null:
        return Colors.redAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTrusted = MonoTime.isTrusted;
    final activeAnchor = MonoTime.anchor;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'MonoTime Time Integrity',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
        backgroundColor: const Color(0xFF0F0E17),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('About MonoTime'),
                  content: const Text(
                    'MonoTime provides a tamper-proof clock by combining NTP '
                    'and HTTPS queries via a Marzullo quorum consensus engine, '
                    'anchoring the resulting UTC time to the device\'s hardware monotonic '
                    'uptime oscillator. This prevents client clock manipulation.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Close'),
                    )
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Security Status Header
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isTrusted
                        ? [const Color(0x2000E676), const Color(0x0500E676)]
                        : [const Color(0x20FF1744), const Color(0x05FF1744)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isTrusted ? Colors.greenAccent.withValues(alpha: 0.4) : Colors.redAccent.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isTrusted ? Icons.verified_user : Icons.gpp_bad,
                      color: isTrusted ? Colors.greenAccent : Colors.redAccent,
                      size: 32,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isTrusted ? 'CLOCK SYSTEM SECURE' : 'CLOCK SYSTEM UNVERIFIED',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: isTrusted ? Colors.greenAccent : Colors.redAccent,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isTrusted
                                ? 'Hardware-anchored UTC consensus active.'
                                : 'Sync pending or clock state untrusted.',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Live Time Cards (Side-by-side or stacked depending on space)
              Row(
                children: [
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.security, size: 16, color: Colors.indigoAccent),
                                SizedBox(width: 8),
                                Text('MONOTIME UTC', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 11)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _anchoredTime != null ? _formatDateTime(_anchoredTime!.toUtc()) : 'No Active Sync',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: _anchoredTime != null ? Colors.cyanAccent : Colors.grey,
                                fontFamily: 'Courier',
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _anchoredTime != null ? 'Hardware-Anchored' : 'No anchor established',
                              style: const TextStyle(fontSize: 10, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.settings_cell, size: 16, color: Colors.orangeAccent),
                                SizedBox(width: 8),
                                Text('DEVICE SYSTEM TIME', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 11)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _formatDateTime(_deviceTime.toUtc()),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Colors.orangeAccent,
                                fontFamily: 'Courier',
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'User-modifiable local clock',
                              style: TextStyle(fontSize: 10, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Best-Effort Estimate Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.query_stats, size: 18, color: Colors.purpleAccent),
                              SizedBox(width: 8),
                              Text('BEST-EFFORT ESTIMATE', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 12)),
                            ],
                          ),
                          if (_estimate != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: _getConfidenceColor(_estimate!.confidenceLevel).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _getConfidenceColor(_estimate!.confidenceLevel),
                                ),
                              ),
                              child: Text(
                                _estimate!.confidenceLevel.name.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: _getConfidenceColor(_estimate!.confidenceLevel),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_estimate != null) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Estimated Time (UTC):', style: TextStyle(fontSize: 13, color: Colors.grey)),
                            Text(
                              _formatDateTime(_estimate!.estimatedTime.toUtc()),
                              style: const TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Max Uncertainty Error:', style: TextStyle(fontSize: 13, color: Colors.grey)),
                            Text(
                              '±${_estimate!.estimatedError.inMilliseconds} ms',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.purpleAccent),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Quorum Confidence Score:', style: TextStyle(fontSize: 13, color: Colors.grey)),
                            Text(
                              '${(_estimate!.confidence * 100).toStringAsFixed(1)}%',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _getConfidenceColor(_estimate!.confidenceLevel),
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        const Text(
                          'No estimate available yet. System is cold-starting.',
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Anchor metadata (NTP/HTTPS Details)
              if (activeAnchor != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('TRUST ANCHOR METADATA', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 11)),
                        const Divider(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Anchored at System Uptime:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            Text('${(activeAnchor.uptimeMs / 1000).toStringAsFixed(2)} seconds', style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Hardware-to-UTC Offset:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            Text('${(activeAnchor.networkUtcMs - activeAnchor.uptimeMs).toStringAsFixed(1)} ms', style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Sync Uncertainty Interval:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            Text('±${activeAnchor.uncertaintyMs.toStringAsFixed(1)} ms', style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 12),

              // Control Panel
              ElevatedButton.icon(
                onPressed: _isSyncing ? null : _handleResync,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: _isSyncing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.sync),
                label: Text(
                  _isSyncing ? 'VERIFYING TIME QUORUM...' : 'TRIGGER CONSENSUS SYNC',
                  style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.8),
                ),
              ),

              const SizedBox(height: 16),

              // Telemetry Log Console
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4.0),
                child: Text(
                  'TELEMETRY & DEVIATION LOGS',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 11),
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF07070B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: _logs.isEmpty
                        ? const Center(
                            child: Text(
                              'Logs console empty.',
                              style: TextStyle(color: Colors.grey, fontFamily: 'Courier', fontSize: 13),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: _logs.length,
                            itemBuilder: (context, index) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2.0),
                                child: Text(
                                  _logs[index],
                                  style: const TextStyle(
                                    color: Color(0xFFE0E0FF),
                                    fontFamily: 'Courier',
                                    fontSize: 12,
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
