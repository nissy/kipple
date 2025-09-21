import Foundation
import AppKit

@MainActor
protocol PasteboardProviding {
    func currentChangeCount() -> Int
    func string() -> String?
    func setString(_ string: String)
    func clearContents()
}

@MainActor
final class SystemPasteboard: PasteboardProviding {
    static let shared = SystemPasteboard()

    private init() {}

    func currentChangeCount() -> Int {
        if Thread.isMainThread {
            return NSPasteboard.general.changeCount
        }
        var result = 0
        DispatchQueue.main.sync {
            result = NSPasteboard.general.changeCount
        }
        return result
    }

    func string() -> String? {
        if Thread.isMainThread {
            return NSPasteboard.general.string(forType: .string)
        }
        var value: String?
        DispatchQueue.main.sync {
            value = NSPasteboard.general.string(forType: .string)
        }
        return value
    }

    func setString(_ string: String) {
        let writeBlock = { () -> Bool in
            NSPasteboard.general.setString(string, forType: .string)
        }
        if Thread.isMainThread {
            _ = writeBlock()
        } else {
            _ = DispatchQueue.main.sync(execute: writeBlock)
        }
    }

    func clearContents() {
        let clearBlock = { () -> Int in
            NSPasteboard.general.clearContents()
        }
        if Thread.isMainThread {
            _ = clearBlock()
        } else {
            _ = DispatchQueue.main.sync(execute: clearBlock)
        }
    }
}
