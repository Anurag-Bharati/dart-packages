import 'package:flutter/foundation.dart';

/// Enumerates every class of violation that can compromise the temporal
/// baseline of the [MonoTime] engine.
enum TamperReason {
  /// A significant discrepancy was detected in the system wall clock.
  ///
  /// Typically caused by manual user manipulation or an OS-initiated clock jump.
  systemClockJumped,

  /// The device timezone was changed via OS settings.
  ///
  /// Does not affect internal UTC correctness, but may impact local-time
  /// representation and localised application logic.
  timezoneChanged,

  /// A hardware reboot was detected via monotonic uptime reset.
  ///
  /// Reboots invalidate the trust anchor (uptime counter resets to zero),
  /// requiring a fresh network synchronisation.
  deviceRebooted,

  /// A manual resynchronisation was requested via [MonoTime.forceResync].
  forceResync,
}

/// An integrity-violation event emitted by [MonoTime.onIntegrityLost].
@immutable
final class IntegrityEvent {
  /// Creates an [IntegrityEvent].
  const IntegrityEvent({required this.reason, required this.detectedAt});

  /// The specific cause of the integrity violation.
  final TamperReason reason;

  /// UTC timestamp at which the violation was detected.
  final DateTime detectedAt;

  @override
  String toString() =>
      'IntegrityEvent(reason=${reason.name}, at=${detectedAt.toIso8601String()})';
}
