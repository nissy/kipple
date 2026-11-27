import AppKit
import Carbon

@MainActor
enum ComparisonClipboardCopy {
    enum Result: Sendable {
        case restored(text: String, stamp: ClipboardReader.Stamp, interrupted: Bool)
        case noSelection
        case unsupportedSelection
        case clipboardUnavailable
        case clipboardBackupUnavailable
        case interrupted
    }

    private static let copyTag: Int64 = 0x4B50_4443 // KPDC
    private static let pollInterval = Duration.milliseconds(10)
    private static let copyTimeout = Duration.milliseconds(750)

    static func capture(
        reader: ClipboardReader, stamp: ClipboardReader.Stamp, input: ClipboardReader.ComparisonInput, target: pid_t
    ) async -> Result {
        let interruption = ComparisonCopyInterruption(copyTag: copyTag)
        defer { interruption.stop() }
        return await capture(
            reader: reader, stamp: stamp, input: input,
            isCurrent: { NSWorkspace.shared.frontmostApplication?.processIdentifier == target },
            hasCompetingInteraction: { interruption.didInteract },
            sendCopy: { ClipboardCommand.send(CGKeyCode(kVK_ANSI_C), to: target, tag: copyTag) }
        )
    }

    static func capture(
        reader: ClipboardReader,
        stamp: ClipboardReader.Stamp,
        input: ClipboardReader.ComparisonInput,
        isCurrent: () -> Bool,
        hasCompetingInteraction: () -> Bool = { false },
        sendCopy: () -> Bool
    ) async -> Result {
        let pasteboard = reader.pasteboard
        guard reader.observation == stamp, isCurrent(), !hasCompetingInteraction(), !Task.isCancelled else {
            return .interrupted
        }
        guard !input.hasEmbeddedObjects else { return .unsupportedSelection }
        guard let backup = PasteboardSnapshot(pasteboard: pasteboard, changeCount: stamp.changeCount) else {
            return reader.observation == stamp ? .clipboardBackupUnavailable : .interrupted
        }
        guard reader.observation == stamp, isCurrent(), !hasCompetingInteraction(), !Task.isCancelled else {
            return .interrupted
        }
        guard sendCopy() else { return .noSelection }

        let deadline = ContinuousClock.now + copyTimeout
        var sourceChanged = false
        while ContinuousClock.now < deadline {
            guard !hasCompetingInteraction(), !Task.isCancelled else { return .interrupted }
            // A dispatched copy can still arrive after the user switches apps.
            sourceChanged = sourceChanged || !isCurrent()
            let incoming = reader.observation
            guard incoming.accessRevision == stamp.accessRevision,
                  incoming.changeCount <= stamp.changeCount + 1 else { return .interrupted }
            if incoming.changeCount != stamp.changeCount, pasteboard.types?.contains(.string) == true {
                guard let copy = reader.read(), copy.stamp == incoming, let text = copy.text,
                      input.matches(copy), !hasCompetingInteraction(), reader.observation == incoming
                else { return .interrupted }
                // Give a second clipboard writer an opportunity to publish its new revision.
                try? await Task.sleep(for: pollInterval)
                return restore(backup, replacing: incoming, text: text, reader: reader) {
                    !sourceChanged && isCurrent() && !hasCompetingInteraction()
                }
            }
            try? await Task.sleep(for: pollInterval)
        }
        return !sourceChanged && isCurrent() && reader.observation == stamp ? .noSelection : .interrupted
    }

    private static func restore(
        _ backup: PasteboardSnapshot,
        replacing copy: ClipboardReader.Stamp,
        text: String,
        reader: ClipboardReader,
        isCurrent: () -> Bool
    ) -> Result {
        guard reader.observation == copy else { return .interrupted }
        // A copy we already attributed still needs cleanup if the user switches focus or cancels.
        let interrupted = !isCurrent() || Task.isCancelled
        let revision = backup.write(to: reader.pasteboard) { reader.observation == copy }
        guard revision >= 0 else {
            return reader.observation == copy ? .clipboardUnavailable : .interrupted
        }
        return .restored(
            text: text, stamp: ClipboardReader.Stamp(changeCount: revision, accessRevision: copy.accessRevision),
            interrupted: interrupted
        )
    }
}

/// Observe only during a comparison. Regular copy commands still go to their destination normally.
@MainActor
private final class ComparisonCopyInterruption {
    private let copyTag: Int64
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private(set) var didInteract = false

    init(copyTag: Int64) {
        self.copyTag = copyTag
        let events: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] event in
            self?.observe(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            self?.observe(event)
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }

    private func observe(_ event: NSEvent) {
        guard event.cgEvent?.getIntegerValueField(.eventSourceUserData) != copyTag else { return }
        if event.type != .keyDown
            || (event.modifierFlags.contains(.command) && [kVK_ANSI_C, kVK_ANSI_X].contains(Int(event.keyCode))) {
            didInteract = true
        }
    }
}
