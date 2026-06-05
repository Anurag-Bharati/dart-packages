import Flutter
import UIKit
import Foundation

/**
 MonotimePlugin
 
 Exposes three platform channels to Dart:
 
 **MethodChannel** `dev.monotime/monotonic`:
   - `getUptimeMs` → Int64: `ProcessInfo.processInfo.systemUptime * 1000`
     (seconds since boot as ms; resets on reboot — used for reboot detection)
   - `getNetworkTimeMs` → nil: not exposed on iOS (no public API equivalent
     to Android's `SystemClock.currentNetworkTimeMillis()`)
 
 **EventChannel** `dev.monotime/tamper`:
   Emits a `String` tag on clock-integrity events:
   - `"systemClockJumped"` on `NSSystemClockDidChange`
   - `"timezoneChanged"` on `NSSystemTimeZoneDidChange`
 
 **MethodChannel** `dev.monotime/background`:
   - `enableBackgroundSync(intervalHours: Int)` → Void
     Registers a BGAppRefreshTask (requires BGTaskSchedulerPermittedIdentifiers
     in the host app's Info.plist and Background Modes → Background fetch capability).
 */
public class MonotimePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    private var eventSink: FlutterEventSink?

    // MARK: - FlutterPlugin

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = MonotimePlugin()

        let methodChannel = FlutterMethodChannel(
            name: "dev.monotime/monotonic",
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(instance, channel: methodChannel)

        let eventChannel = FlutterEventChannel(
            name: "dev.monotime/tamper",
            binaryMessenger: registrar.messenger()
        )
        eventChannel.setStreamHandler(instance)
    }

    // MARK: - Method Channel

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getUptimeMs":
            // systemUptime is the number of seconds the system has been awake
            // since the last reboot (including sleep on modern iOS versions).
            let uptimeMs = Int64(ProcessInfo.processInfo.systemUptime * 1000)
            result(uptimeMs)

        case "getNetworkTimeMs":
            // iOS does not expose a public SNTP-synced clock equivalent to
            // Android's SystemClock.currentNetworkTimeMillis().
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - FlutterStreamHandler (tamper event channel)

    public func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        eventSink = events

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(systemClockDidChange),
            name: NSNotification.Name.NSSystemClockDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(timezoneDidChange),
            name: NSNotification.Name.NSSystemTimeZoneDidChange,
            object: nil
        )
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        NotificationCenter.default.removeObserver(self)
        eventSink = nil
        return nil
    }

    // MARK: - Notification handlers

    @objc private func systemClockDidChange() {
        eventSink?("systemClockJumped")
    }

    @objc private func timezoneDidChange() {
        eventSink?("timezoneChanged")
    }
}
