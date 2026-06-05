# Changelog

All notable changes to this project will be documented in this file.

## [0.1.0] - 2026-06-05

### Added

- Initial release of `monotime`.
- Pure Dart NTP & HTTPS-authenticated Date header time sources.
- Marzullo consensus engine for multi-source time verification.
- Monotonic hardware clock anchoring on Android (`SystemClock.elapsedRealtime`) and iOS (`systemUptime`).
- Clock-tamper detection via `ACTION_TIME_CHANGED` and `NSSystemClockDidChange`.
- Offline time estimation fallback based on wall-clock progression with error-growth tracking.
- Test override mechanism to mock high-integrity time in unit/widget tests.
