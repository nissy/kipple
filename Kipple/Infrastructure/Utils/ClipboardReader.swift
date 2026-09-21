import AppKit
import Combine

/// All programmatic reads share one attempt per clipboard revision and access policy.
@MainActor
final class ClipboardReader: ObservableObject {
    struct Stamp: Equatable, Sendable {
        let changeCount: Int
        let accessRevision: UInt64
    }

    struct Snapshot: Sendable {
        let stamp: Stamp
        let text: String?
        let richText: ClipboardRichText?
    }

    static let shared = ClipboardReader()
    @Published private(set) var accessBehavior: NSPasteboard.AccessBehavior
    @Published private(set) var readFailed = false
    private let pasteboard: NSPasteboard
    private let readAccess: () -> NSPasteboard.AccessBehavior
    private let readText: () -> String?
    private var accessRevision: UInt64 = 0
    private var cached: Snapshot?
    private var failedAttempt: Stamp?

    init(
        pasteboard: NSPasteboard = .general,
        readAccess: (() -> NSPasteboard.AccessBehavior)? = nil,
        readText: (() -> String?)? = nil
    ) {
        self.pasteboard = pasteboard
        self.readAccess = readAccess ?? { pasteboard.accessBehavior }
        self.readText = readText ?? { pasteboard.string(forType: .string) }
        accessBehavior = self.readAccess()
    }

    var observation: Stamp {
        refreshAccess()
        return Stamp(changeCount: pasteboard.changeCount, accessRevision: accessRevision)
    }

    func refreshAccess() {
        let behavior = readAccess()
        guard behavior != accessBehavior else { return }
        accessBehavior = behavior
        invalidate()
        SystemDiagnostics.clipboard(policy: behavior, readFailed: false)
    }

    /// A retry is explicit user intent; polling never repeatedly asks for the same content.
    func read(retry: Bool = false) -> Snapshot? {
        if retry { invalidate() }
        let stamp = observation
        guard accessBehavior != .alwaysDeny else { return nil }
        if let cached, cached.stamp == stamp { return cached }
        guard failedAttempt != stamp else { return nil }

        let text = readText()
        let richText = text.flatMap { ClipboardRichText(pasteboard: pasteboard, text: $0) }
        let resultStamp = observation
        guard resultStamp.changeCount == stamp.changeCount, accessBehavior != .alwaysDeny else { return nil }
        let types = pasteboard.types
        if text == nil && (types?.contains(.string) == true || (types == nil && accessBehavior == .ask)) {
            failedAttempt = resultStamp
            readFailed = true
            SystemDiagnostics.clipboard(policy: accessBehavior, readFailed: true)
            return nil
        }
        let snapshot = Snapshot(stamp: resultStamp, text: text, richText: richText)
        cached = snapshot
        failedAttempt = nil
        readFailed = false
        return snapshot
    }

    private func invalidate() {
        accessRevision &+= 1
        cached = nil
        failedAttempt = nil
        readFailed = false
    }
}
