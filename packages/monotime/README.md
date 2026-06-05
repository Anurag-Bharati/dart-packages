# monotime

**Tamper-resistant network time for Flutter.**

Anchors multi-source NTP + HTTPS consensus to the device's hardware monotonic clock.  
Immune to system-clock manipulation. No Rust, no native build complexity.

---

## How it works

| Layer | What it does |
|---|---|
| **NTP sources** | Queries multiple NTP servers concurrently via UDP (RFC 5905) |
| **HTTPS sources** | Parses `Date` headers from TLS-verified HTTPS endpoints |
| **Marzullo consensus** | Resolves a provably correct interval across all sources, enforcing source-diversity |
| **Monotonic anchoring** | Anchors the consensus UTC to the hardware uptime counter (`SystemClock.elapsedRealtime` / `ProcessInfo.systemUptime`) |
| **Tamper detection** | Listens for `ACTION_TIME_CHANGED` (Android) and `NSSystemClockDidChange` (iOS) |

The key formula:
```
now = anchoredNetworkUtcMs + (currentHardwareUptimeMs − anchorUptimeMs)
```
This makes `now` immune to the user changing the system clock. The uptime counter only advances forward and resets on reboot.

---

## Quick start

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MonoTime.initialize();
  runApp(const MyApp());
}
```

```dart
// Get tamper-resistant time (throws if engine not ready)
final now = MonoTime.now();

// Safe fallback — never throws, null only on cold start with no persisted anchor
final estimate = MonoTime.nowEstimated();
if (estimate != null) {
  print('${estimate.estimatedTime} (confidence: ${estimate.confidence.toStringAsFixed(2)})');
}

// Listen for tamper events
MonoTime.onIntegrityLost.listen((event) {
  switch (event.reason) {
    case TamperReason.systemClockJumped:
      // User changed the system clock — re-evaluate trust
      break;
    case TamperReason.deviceRebooted:
      // Uptime counter reset — anchor invalidated automatically
      break;
    case TamperReason.timezoneChanged:
      // UTC unaffected, but local-time representation changed
      break;
    default:
      break;
  }
});
```

---

## Configuration

```dart
await MonoTime.initialize(
  config: const MonoTimeConfig(
    ntpServers: ['time.cloudflare.com', 'time.google.com', 'pool.ntp.org'],
    httpsSources: [
      'https://www.cloudflare.com',
      'https://www.google.com',
      'https://www.apple.com',
    ],
    refreshInterval: Duration(hours: 6),
    minimumQuorum: 2,       // min sources in consensus
    minGroupCount: 2,        // min distinct hostnames
    persistState: true,      // survive cold starts via SharedPreferences
  ),
);
```

---

## Observability

```dart
// Register a SyncObserver for telemetry
MonoTime.registerObserver(MySyncObserver());

class MySyncObserver implements SyncObserver {
  @override
  void onSyncStarted() => print('Sync started');

  @override
  void onConsensusReached(ConsensusResult result) {
    print('Consensus: ${result.utc} ±${result.uncertaintyMs}ms '
          '(${result.confidence.name}, ${result.participantCount} sources)');
  }

  @override
  void onMetricsReported(SyncMetrics metrics) {
    print('Sync took ${metrics.duration.inMilliseconds}ms');
  }

  // ... other callbacks
}
```

---

## Testing

```dart
// Inject a fixed time for deterministic widget tests
MonoTime.setTestOverride(MonoTimeTestOverride(now: DateTime(2025, 1, 1, 0, 0, 0)));

expect(MonoTime.now(), DateTime.utc(2025, 1, 1));

MonoTime.setTestOverride(null); // restore
```

---

## Architecture

```
MonoTime              ← public static façade
└── MonoTimeImpl      ← lifecycle (bootstrap, warm-start, refresh, retry)
    ├── SyncEngine    ← concurrent multi-source orchestrator
    │   ├── NtpSource   (UDP, ntp package)
    │   └── HttpsSource (HTTPS Date header, http package)
    ├── MarzulloEngine  ← closed-interval consensus algorithm
    ├── IntegrityMonitor← clock tamper + reboot detection
    ├── SyncClock       ← sub-µs projection without platform calls
    └── AnchorStore     ← SharedPreferences persistence
```

---

## Platform support

| Platform | Uptime source | Tamper detection | Native Network Time (`getNetworkTimeMs`) |
|---|---|---|---|
| Android | `SystemClock.elapsedRealtime()` | `ACTION_TIME_CHANGED` + `ACTION_TIMEZONE_CHANGED` | Returns `null` (falls back to Dart multi-source consensus) |
| iOS | `ProcessInfo.systemUptime` | `NSSystemClockDidChange` + `NSSystemTimeZoneDidChange` | Always returns `null` (not supported by public APIs) |

---

## Roadmap: Google Play Services `TrustedTimeClient` Integration

To further enhance tamper-resistance on GMS-equipped Android devices, a future release can integrate Google's native [TrustedTimeClient](https://developers.google.com/android/reference/com/google/android/gms/time/TrustedTimeClient). 

### Fallback Architecture for Non-GMS Devices
Since many devices (e.g. Huawei, custom ROMs, or Chinese domestic market phones) do not ship with Google Play Services, the integration will follow a strict fallback architecture:

1. **GMS Availability Check**: The Android plugin will dynamically check if Google Play Services are available and up to date on the host device.
2. **Native TrustedTime Query**: If available, the native channel will call `TrustedTimeClient.getInstant()` to obtain Google's cryptographically-anchored network time.
3. **Consensus Fallback**: If GMS check fails or the Play Services API throws an error:
   - The plugin returns `null` for native network time.
   - The Dart engine gracefully falls back to the pure-Dart NTP (UDP) + HTTPS Date header consensus protocol.

This ensures high-precision native time where available, while keeping the app 100% functional and tamper-resistant on all devices globally.

---

## License

MIT
