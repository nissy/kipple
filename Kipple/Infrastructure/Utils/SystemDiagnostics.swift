import AppKit
import ApplicationServices
import Security
import os.log

/// Clipboard contents never enter this log. Only status codes and signing identifiers are public.
enum SystemDiagnostics {
    private static let log = OSLog(subsystem: "com.nissy.Kipple", category: "SystemStatus")
    @MainActor private static var previousPermissions: String?
    @MainActor private static var didLogIdentity = false

    @MainActor
    static func permissions(screenCapture: Bool, accessibility: Bool, clipboard: NSPasteboard.AccessBehavior) {
        let value = "screenCapture=\(screenCapture) accessibility=\(accessibility) clipboardPolicy=\(clipboard.rawValue)"
        guard value != previousPermissions else { return }
        previousPermissions = value
        os_log(.default, log: log, "%{public}@", value)
        identity()
    }

    static func failure(_ operation: StaticString, error: Error) {
        let error = error as NSError
        os_log(.error, log: log, "%{public}@ domain=%{public}@ code=%ld",
               String(describing: operation), error.domain, error.code)
    }

    static func clipboard(policy: NSPasteboard.AccessBehavior, readFailed: Bool) {
        os_log(.default, log: log, "clipboardPolicy=%ld readFailed=%{public}@",
               policy.rawValue, readFailed ? "true" : "false")
    }

    @MainActor
    static func identity() {
        guard !didLogIdentity else { return }
        didLogIdentity = true
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        if SecCodeCopySelf([], &code) == errSecSuccess, let code,
           SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode {
            _ = SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        }
        let team = (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String ?? "unavailable"
        os_log(.default, log: log, "bundle=%{public}@ team=%{public}@ pid=%d executable=%{private}@",
               Bundle.main.bundleIdentifier ?? "unknown", team, ProcessInfo.processInfo.processIdentifier,
               Bundle.main.executableURL?.path ?? "unknown")
    }
}
