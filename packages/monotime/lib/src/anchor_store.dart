import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

/// Lightweight persistence layer for [TrustAnchor] using [SharedPreferences].
///
/// Uses [SharedPreferences] for zero extra dependencies. The anchor is not a
/// secret — it is a timestamp and uptime value. Security comes from the
/// monotonic anchoring, not from encrypting the stored value.
final class AnchorStore {
  static const _keyAnchor = 'monotime_anchor_v1';
  static const _keyLastTrustedUtcMs = 'monotime_last_trusted_utc_ms';
  static const _keyLastAnchorWallMs = 'monotime_last_anchor_wall_ms';

  /// Saves [anchor] to persistent storage.
  Future<void> save(TrustAnchor anchor) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString(_keyAnchor, jsonEncode(anchor.toJson())),
      prefs.setInt(_keyLastTrustedUtcMs, anchor.networkUtcMs),
      prefs.setInt(_keyLastAnchorWallMs, anchor.wallMs),
    ]);
  }

  /// Loads the persisted [TrustAnchor], or `null` if none exists or is corrupt.
  Future<TrustAnchor?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyAnchor);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return TrustAnchor.fromJson(json);
    } catch (_) {
      await prefs.remove(_keyAnchor);
      return null;
    }
  }

  /// Loads the last known UTC + wall-clock pair for offline estimation.
  ///
  /// Returns `null` if no data has been persisted.
  Future<({int utcMs, int wallMs})?> loadLastKnown() async {
    final prefs = await SharedPreferences.getInstance();
    final utcMs = prefs.getInt(_keyLastTrustedUtcMs);
    final wallMs = prefs.getInt(_keyLastAnchorWallMs);
    if (utcMs == null || wallMs == null) return null;
    return (utcMs: utcMs, wallMs: wallMs);
  }

  /// Clears all persisted anchor data.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove(_keyAnchor),
      prefs.remove(_keyLastTrustedUtcMs),
      prefs.remove(_keyLastAnchorWallMs),
    ]);
  }
}
