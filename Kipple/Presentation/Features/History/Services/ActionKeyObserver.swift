import AppKit
import Combine

@MainActor
final class ActionKeyObserver: ObservableObject {
    static let shared = ActionKeyObserver()

    @Published private(set) var modifiers: NSEvent.ModifierFlags
    private var monitor: Any?

    private init() {
        modifiers = NSEvent.modifierFlags
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.modifiers = event.modifierFlags
            return event
        }
    }

    func currentModifiers() -> NSEvent.ModifierFlags {
        modifiers
    }

#if DEBUG
    func simulateModifierChange(_ newValue: NSEvent.ModifierFlags) {
        modifiers = newValue
    }
#endif
}
