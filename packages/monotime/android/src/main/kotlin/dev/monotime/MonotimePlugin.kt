package dev.monotime

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.SystemClock
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * MonotimePlugin
 *
 * Exposes three platform channels to Dart:
 *
 * **MethodChannel** `dev.monotime/monotonic`:
 *   - `getUptimeMs` → `Long`: `SystemClock.elapsedRealtime()`
 *     (includes deep-sleep, resets to 0 on reboot)
 *   - `getNetworkTimeMs` → `Long?`: Returns null (hidden in public Android SDK)
 *
 * **EventChannel** `dev.monotime/tamper`:
 *   Emits a `String` tag on clock-integrity events:
 *   - `"systemClockJumped"` on `ACTION_TIME_CHANGED`
 *   - `"timezoneChanged"` on `ACTION_TIMEZONE_CHANGED`
 *
 * **MethodChannel** `dev.monotime/background`:
 *   - `enableBackgroundSync(intervalHours: Int)` → Unit
 *     Schedules a WorkManager periodic task (implementation forthcoming).
 */
class MonotimePlugin : FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null
    private var clockReceiver: BroadcastReceiver? = null
    private lateinit var applicationContext: Context

    // ── FlutterPlugin ────────────────────────────────────────────────────────

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext

        methodChannel = MethodChannel(binding.binaryMessenger, "dev.monotime/monotonic")
        methodChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(binding.binaryMessenger, "dev.monotime/tamper")
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    // ── MethodCallHandler ────────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getUptimeMs" -> {
                // elapsedRealtime() = ms since boot, including deep-sleep.
                // Resets to 0 on every reboot — used for reboot detection.
                result.success(SystemClock.elapsedRealtime())
            }
            "getNetworkTimeMs" -> {
                // Return null since standard Android SDK does not expose currentNetworkTimeMillis publicly.
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // ── EventChannel.StreamHandler ───────────────────────────────────────────

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        eventSink = sink

        clockReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                when (intent.action) {
                    Intent.ACTION_TIME_CHANGED ->
                        sink?.success("systemClockJumped")
                    Intent.ACTION_TIMEZONE_CHANGED ->
                        sink?.success("timezoneChanged")
                }
            }
        }

        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_TIME_CHANGED)
            addAction(Intent.ACTION_TIMEZONE_CHANGED)
        }
        applicationContext.registerReceiver(clockReceiver, filter)
    }

    override fun onCancel(arguments: Any?) {
        clockReceiver?.let {
            try {
                applicationContext.unregisterReceiver(it)
            } catch (_: IllegalArgumentException) {
                // Receiver was never registered or already unregistered — safe to ignore.
            }
        }
        clockReceiver = null
        eventSink = null
    }
}
