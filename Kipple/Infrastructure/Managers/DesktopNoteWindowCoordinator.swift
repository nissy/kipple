import AppKit
import Combine
import CoreGraphics

@MainActor
struct DesktopNoteDisplay: Identifiable {
    let id: String
    let screen: NSScreen

    init?(screen: NSScreen) {
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
        id = CFUUIDCreateString(nil, uuid) as String
        self.screen = screen
    }

    static var connected: [Self] {
        NSScreen.screens.compactMap(Self.init)
    }

    static func destination(preferredID: String, originatingScreen: NSScreen?, among screens: [NSScreen]) -> NSScreen? {
        let displays = screens.compactMap(Self.init)
        let fallbackID = originatingScreen.flatMap(Self.init)?.id
        let mainScreen = NSScreen.main
        return displays.first { $0.id == preferredID }?.screen
            ?? displays.first { $0.id == fallbackID }?.screen
            ?? screens.first { $0 == originatingScreen }
            ?? screens.first { $0 == mainScreen }
            ?? screens.first
    }
}

struct DesktopNotePlacement: Codable {
    private static let defaultsKey = "desktopNotePlacements"

    let frame: CGRect
    let color: DesktopNoteColor
    let usesManualSize: Bool

    static func load(from defaults: UserDefaults) -> [UUID: Self] {
        guard let data = defaults.data(forKey: defaultsKey) else { return [:] }
        return (try? JSONDecoder().decode([UUID: Self].self, from: data)) ?? [:]
    }

    static func save(_ placements: [UUID: Self], to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(placements) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}

@MainActor
final class DesktopNoteWindowCoordinator: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = DesktopNoteWindowCoordinator(defaults: .standard)

    @Published private var notes: [UUID: DesktopNotePanel] = [:]
    private var closingNotes: [UUID: Task<Void, Never>] = [:]
    private let adapter: ModernClipboardServiceAdapter
    private let defaults: UserDefaults?
    private let playRepeatedCopySound: () -> Void
    private var placements: [UUID: DesktopNotePlacement]
    private var isTerminating = false
    private var historyObservation: AnyCancellable?
    private var repeatedCopyObservation: AnyCancellable?

    init(
        adapter: ModernClipboardServiceAdapter = .shared,
        defaults: UserDefaults? = nil,
        playRepeatedCopySound: @escaping () -> Void = {
            if NSSound(named: NSSound.Name("Purr"))?.play() != true { NSSound.beep() }
        }
    ) {
        self.adapter = adapter
        self.defaults = defaults
        self.playRepeatedCopySound = playRepeatedCopySound
        placements = defaults.map { DesktopNotePlacement.load(from: $0) } ?? [:]
        super.init()
        historyObservation = adapter.$history.sink { [weak self] history in
            self?.updateOpenNotes(from: history)
        }
        repeatedCopyObservation = adapter.repeatedCopyDesktopNoteRequests.sink { [weak self] itemID in
            Task {
                guard let self, await self.post(itemID, on: nil) else { return }
                self.playRepeatedCopySound()
            }
        }
    }

    func isPosted(_ id: UUID) -> Bool {
        notes[id] != nil
    }

    func toggle(_ itemID: UUID, on screen: NSScreen?) async {
        if let note = notes[itemID] {
            if closingNotes[itemID] == nil { note.performClose(nil) }
            await closingNotes[itemID]?.value
            return
        }
        _ = await post(itemID, on: screen)
    }

    private func post(_ itemID: UUID, on screen: NSScreen?) async -> Bool {
        guard !isTerminating, notes[itemID] == nil, !NSScreen.screens.isEmpty,
              let item = await adapter.protectHistoryForDesktopNote(itemID) else { return false }
        guard !isTerminating, let destination = DesktopNoteDisplay.destination(
            preferredID: AppSettings.shared.desktopNoteDisplayID, originatingScreen: screen, among: NSScreen.screens
        ) else {
            await adapter.removeDesktopNoteProtection(itemID)
            return false
        }
        openNote(for: item, on: destination)
        return true
    }

    func restoreNotes() async {
        let ids = Set(placements.keys.filter { notes[$0] == nil })
        guard !isTerminating, !ids.isEmpty, let fallbackScreen = NSScreen.main ?? NSScreen.screens.first,
              let items = await adapter.desktopNoteItemsToRestore(ids), !isTerminating else { return }
        let missing = ids.subtracting(items.map(\.id))
        for id in missing where notes[id] == nil { placements.removeValue(forKey: id) }
        for item in items {
            guard notes[item.id] == nil, let placement = placements[item.id] else { continue }
            let screen = screen(for: placement.frame) ?? fallbackScreen
            openNote(for: item, on: screen, restoring: placement)
        }
        savePlacements()
    }

    func prepareForTermination() {
        isTerminating = true
        for (id, note) in notes where closingNotes[id] == nil { placements[id] = note.placement }
        savePlacements()
    }

    private func openNote(for item: ClipItem, on screen: NSScreen, restoring placement: DesktopNotePlacement? = nil) {
        let id = item.id
        let note = DesktopNotePanel(
            item: item,
            screenFrame: screen.visibleFrame,
            displayMode: AppSettings.shared.desktopNoteDefaultDisplayMode,
            onSave: { [adapter] text, allowsRemovingRichText in
                try await adapter.updateDetails(
                    itemID: id, title: nil, content: text, categoryChanges: [:],
                    allowsRemovingRichText: allowsRemovingRichText
                )
            },
            onChangeCategory: { [adapter] change in
                try await adapter.updateCategories(itemID: id, change: change)
            },
            copyLink: adapter.writeToClipboardOnly,
            copyItem: adapter.recopyFromHistory
        )
        note.delegate = self
        if let placement {
            note.restorePlacement(placement, in: screen.visibleFrame)
        } else {
            note.setFrameOrigin(initialOrigin(for: note.frame.size, in: screen.visibleFrame))
        }
        notes[id] = note
        note.onPlacementChange = { [weak self, weak note] in
            guard let self, let note, closingNotes[id] == nil else { return }
            placements[id] = note.placement
            savePlacements()
        }
        placements[id] = note.placement
        if placement == nil { savePlacements() }
        note.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        guard !isTerminating, let note = notification.object as? DesktopNotePanel,
              let id = notes.first(where: { $0.value === note })?.key,
              closingNotes[id] == nil else { return }
        placements.removeValue(forKey: id)
        savePlacements()
        closingNotes[id] = Task { [weak self, adapter] in
            await adapter.removeDesktopNoteProtection(id)
            self?.notes.removeValue(forKey: id)
            self?.closingNotes.removeValue(forKey: id)
        }
    }

    private func savePlacements() {
        if let defaults { DesktopNotePlacement.save(placements, to: defaults) }
    }

    private func screen(for frame: CGRect) -> NSScreen? {
        NSScreen.screens.filter { $0.visibleFrame.intersects(frame) }.max { first, second in
            let a = first.visibleFrame.intersection(frame)
            let b = second.visibleFrame.intersection(frame)
            return a.width * a.height < b.width * b.height
        }
    }

    private func updateOpenNotes(from history: [ClipItem]) {
        for item in history {
            notes[item.id]?.update(from: item)
        }
        if adapter.isHistoryLoaded, placements.keys.contains(where: { notes[$0] == nil }) {
            Task { [weak self] in await self?.restoreNotes() }
        }
    }

    private func initialOrigin(for size: NSSize, in frame: NSRect) -> NSPoint {
        let margin: CGFloat = 24
        let occupied = notes.values.map { NSPoint(x: $0.frame.minX, y: $0.frame.maxY) }
        let positions = (0..<8).map { index in
            let offset = margin * CGFloat(index + 1)
            return NSPoint(
                x: max(frame.minX, min(frame.minX + offset, frame.maxX - size.width)),
                y: max(frame.minY + size.height, frame.maxY - offset)
            )
        }
        let topLeft = positions.first { !occupied.contains($0) } ?? positions[0]
        return NSPoint(x: topLeft.x, y: topLeft.y - size.height)
    }
}
