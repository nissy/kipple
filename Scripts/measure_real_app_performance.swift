#!/usr/bin/env swift

import AppKit
import ApplicationServices
import Foundation

struct Measurement {
    let name: String
    var values: [Double] = []

    mutating func add(_ seconds: Double) {
        values.append(seconds)
    }

    var averageMS: Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count) * 1_000
    }

    var minMS: Double {
        (values.min() ?? 0) * 1_000
    }

    var maxMS: Double {
        (values.max() ?? 0) * 1_000
    }
}

enum MeasureError: Error, CustomStringConvertible {
    case appleScript(String)
    case timeout(String)
    case missingElement(String)

    var description: String {
        switch self {
        case .appleScript(let message):
            return "AppleScript error: \(message)"
        case .timeout(let message):
            return "Timeout: \(message)"
        case .missingElement(let message):
            return "Missing element: \(message)"
        }
    }
}

let args = CommandLine.arguments
let iterations = argumentValue("--iterations").flatMap(Int.init) ?? 5
let timeoutSeconds = argumentValue("--timeout").flatMap(Double.init) ?? 5.0

var copyToHistory = Measurement(name: "copy_to_history_visible")
var clickToClipboard = Measurement(name: "history_click_to_clipboard")
var openWindow = Measurement(name: "menubar_press_to_window")

do {
    try ensureKippleRunning()
    try openKippleWindow()

    for index in 1...iterations {
        let stamp = Int(Date().timeIntervalSince1970 * 1_000)
        let first = "Kipple perf \(stamp)-\(index)-A"
        let second = "Kipple perf \(stamp)-\(index)-B"

        let copyStart = CFAbsoluteTimeGetCurrent()
        setClipboard(first)
        try waitUntil("history contains first copied item", timeout: timeoutSeconds) {
            try staticTextExists(first)
        }
        copyToHistory.add(CFAbsoluteTimeGetCurrent() - copyStart)

        setClipboard(second)
        try waitUntil("history contains second copied item", timeout: timeoutSeconds) {
            try staticTextExists(second)
        }

        let targetFrame = try frameForStaticText(first)
        let clickPoint = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
        let clickStart = CFAbsoluteTimeGetCurrent()
        postClick(at: clickPoint)
        try waitUntil("clipboard equals clicked history item", timeout: timeoutSeconds) {
            clipboardString() == first
        }
        clickToClipboard.add(CFAbsoluteTimeGetCurrent() - clickStart)

        waitForWindowHiddenAfterSelection()

        let openStart = CFAbsoluteTimeGetCurrent()
        try pressStatusItem()
        try waitUntil("Kipple window appears", timeout: timeoutSeconds) {
            try windowExists()
        }
        openWindow.add(CFAbsoluteTimeGetCurrent() - openStart)

        printRow(iteration: index, copy: copyToHistory.values.last, click: clickToClipboard.values.last, open: openWindow.values.last)
    }

    print("")
    printSummary(copyToHistory)
    printSummary(clickToClipboard)
    printSummary(openWindow)
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}

func argumentValue(_ name: String) -> String? {
    guard let index = args.firstIndex(of: name), args.indices.contains(index + 1) else {
        return nil
    }
    return args[index + 1]
}

func ensureKippleRunning() throws {
    let output = try runAppleScript("""
    tell application "System Events"
      return exists process "Kipple"
    end tell
    """)
    guard output.trimmingCharacters(in: .whitespacesAndNewlines) == "true" else {
        throw MeasureError.missingElement("Kipple process is not running. Run make build-dev first.")
    }
}

func openKippleWindow() throws {
    if try windowExists() {
        return
    }
    try pressStatusItem()
    try waitUntil("Kipple window appears", timeout: timeoutSeconds) {
        try windowExists()
    }
}

func pressStatusItem() throws {
    _ = try runAppleScript("""
    tell application "System Events"
      tell process "Kipple"
        perform action "AXPress" of menu bar item 1 of menu bar 2
      end tell
    end tell
    """)
}

func windowExists() throws -> Bool {
    let output = try runAppleScript("""
    tell application "System Events"
      tell process "Kipple"
        return exists window "Kipple"
      end tell
    end tell
    """)
    return output.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
}

func staticTextExists(_ text: String) throws -> Bool {
    let escaped = appleScriptString(text)
    let output = try runAppleScript("""
    tell application "System Events"
      tell process "Kipple"
        if not (exists window "Kipple") then return false
        return exists static text "\(escaped)" of UI element 1 of scroll area 2 of group 1 of window "Kipple"
      end tell
    end tell
    """)
    return output.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
}

func frameForStaticText(_ text: String) throws -> CGRect {
    let escaped = appleScriptString(text)
    let output = try runAppleScript("""
    tell application "System Events"
      tell process "Kipple"
        set targetText to static text "\(escaped)" of UI element 1 of scroll area 2 of group 1 of window "Kipple"
        set p to position of targetText
        set s to size of targetText
        return (item 1 of p as text) & "," & (item 2 of p as text) & "," & (item 1 of s as text) & "," & (item 2 of s as text)
      end tell
    end tell
    """)

    let parts = output
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .split(separator: ",")
        .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }

    guard parts.count == 4 else {
        throw MeasureError.missingElement("Could not read frame for \(text)")
    }
    return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
}

func setClipboard(_ value: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(value, forType: .string)
}

func clipboardString() -> String? {
    NSPasteboard.general.string(forType: .string)
}

func postClick(at point: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
    usleep(80_000)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
}

func waitForWindowHiddenAfterSelection() {
    let deadline = CFAbsoluteTimeGetCurrent() + 1.0
    while CFAbsoluteTimeGetCurrent() < deadline {
        if (try? windowExists()) == false {
            return
        }
        usleep(50_000)
    }
    postClick(at: CGPoint(x: 10, y: 10))
    let secondDeadline = CFAbsoluteTimeGetCurrent() + 1.0
    while CFAbsoluteTimeGetCurrent() < secondDeadline {
        if (try? windowExists()) == false {
            return
        }
        usleep(50_000)
    }
}

func waitUntil(_ label: String, timeout: Double, condition: () throws -> Bool) throws {
    let deadline = CFAbsoluteTimeGetCurrent() + timeout
    while CFAbsoluteTimeGetCurrent() < deadline {
        if try condition() {
            return
        }
        usleep(20_000)
    }
    throw MeasureError.timeout(label)
}

func runAppleScript(_ source: String) throws -> String {
    var errorInfo: NSDictionary?
    guard let script = NSAppleScript(source: source) else {
        throw MeasureError.appleScript("Could not create script")
    }
    let descriptor = script.executeAndReturnError(&errorInfo)
    if let errorInfo {
        throw MeasureError.appleScript(errorInfo.description)
    }
    return descriptor.stringValue ?? descriptor.description
}

func appleScriptString(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}

func printRow(iteration: Int, copy: Double?, click: Double?, open: Double?) {
    let copyMS = (copy ?? 0) * 1_000
    let clickMS = (click ?? 0) * 1_000
    let openMS = (open ?? 0) * 1_000
    print(String(format: "iteration=%d copy_to_history=%.1fms history_click=%.1fms open_window=%.1fms", iteration, copyMS, clickMS, openMS))
}

func printSummary(_ measurement: Measurement) {
    print(String(
        format: "%@ avg=%.1fms min=%.1fms max=%.1fms n=%d",
        measurement.name,
        measurement.averageMS,
        measurement.minMS,
        measurement.maxMS,
        measurement.values.count
    ))
}
