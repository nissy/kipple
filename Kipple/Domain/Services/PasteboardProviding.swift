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
        // @MainActor により必ずメインスレッドで実行されるため、
        // 追加のスレッド分岐や同期呼び出しは不要。
        return NSPasteboard.general.changeCount
    }

    func string() -> String? {
        return NSPasteboard.general.string(forType: .string)
    }

    func setString(_ string: String) {
        NSPasteboard.general.setString(string, forType: .string)
    }

    func clearContents() {
        NSPasteboard.general.clearContents()
    }
}
