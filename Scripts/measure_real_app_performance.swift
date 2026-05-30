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
    case command(String)
    case timeout(String)
    case missingElement(String)

    var description: String {
        switch self {
        case .appleScript(let message):
            return "AppleScript error: \(message)"
        case .command(let message):
            return "Command error: \(message)"
        case .timeout(let message):
            return "Timeout: \(message)"
        case .missingElement(let message):
            return "Missing element: \(message)"
        }
    }
}

struct TraceBreakdown {
    let detect: Double
    let fetch: Double
    let history: Double
    let adapter: Double
    let viewModel: Double
    let ax: Double
    let saveStart: Double?
    let saveDuration: Double?
}

let args = CommandLine.arguments
let iterations = argumentValue("--iterations").flatMap(Int.init) ?? 5
let timeoutSeconds = argumentValue("--timeout").flatMap(Double.init) ?? 5.0
let enableTrace = args.contains("--trace")
let traceURL = URL(fileURLWithPath: "/tmp/kipple-perf-trace.jsonl")
let traceFlagURL = URL(fileURLWithPath: "/tmp/kipple-enable-perf-trace")

var copyToHistory = Measurement(name: "copy_to_history_visible")
var clickToClipboard = Measurement(name: "history_click_to_clipboard")
var openWindow = Measurement(name: "menubar_press_to_window")
var detectLatency = Measurement(name: "trace_copy_to_detected")
var fetchLatency = Measurement(name: "trace_detected_to_fetched")
var historyLatency = Measurement(name: "trace_fetched_to_history")
var adapterLatency = Measurement(name: "trace_history_to_adapter")
var viewModelLatency = Measurement(name: "trace_adapter_to_viewmodel")
var axLatency = Measurement(name: "trace_viewmodel_to_ax_visible")
var saveDelay = Measurement(name: "trace_copy_to_save_start")
var saveDuration = Measurement(name: "trace_save_duration")

do {
    if enableTrace {
        try setPerformanceTraceEnabled(true)
        clearTraceFile()
    }
    defer {
        if enableTrace {
            try? setPerformanceTraceEnabled(false)
        }
    }

    try ensureKippleRunning()
    try openKippleWindow()

    for index in 1...iterations {
        let stamp = Int(Date().timeIntervalSince1970 * 1_000)
        let first = "Kipple perf \(stamp)-\(index)-A"
        let second = "Kipple perf \(stamp)-\(index)-B"

        let copyStart = CFAbsoluteTimeGetCurrent()
        let copyStartUs = epochMicros()
        setClipboard(first)
        try waitUntil("history contains first copied item", timeout: timeoutSeconds) {
            try staticTextExists(first)
        }
        let visibleUs = epochMicros()
        let copyDuration = CFAbsoluteTimeGetCurrent() - copyStart
        copyToHistory.add(copyDuration)

        if enableTrace, let breakdown = try waitForTraceBreakdown(
            content: first,
            copyStartUs: copyStartUs,
            visibleUs: visibleUs
        ) {
            detectLatency.add(breakdown.detect)
            fetchLatency.add(breakdown.fetch)
            historyLatency.add(breakdown.history)
            adapterLatency.add(breakdown.adapter)
            viewModelLatency.add(breakdown.viewModel)
            axLatency.add(breakdown.ax)
            if let saveStart = breakdown.saveStart {
                saveDelay.add(saveStart)
            }
            if let saveTime = breakdown.saveDuration {
                saveDuration.add(saveTime)
            }
            printTraceRow(iteration: index, breakdown: breakdown)
        }

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

        printRow(
            iteration: index,
            copy: copyToHistory.values.last,
            click: clickToClipboard.values.last,
            open: openWindow.values.last
        )
    }

    print("")
    printSummary(copyToHistory)
    printSummary(clickToClipboard)
    printSummary(openWindow)
    if enableTrace {
        print("")
        printSummary(detectLatency)
        printSummary(fetchLatency)
        printSummary(historyLatency)
        printSummary(adapterLatency)
        printSummary(viewModelLatency)
        printSummary(axLatency)
        printSummary(saveDelay)
        printSummary(saveDuration)
    }
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

func setPerformanceTraceEnabled(_ enabled: Bool) throws {
    try runCommand(
        "/usr/bin/defaults",
        arguments: ["write", "com.nissy.Kipple", "enablePerformanceTrace", "-bool", enabled ? "true" : "false"]
    )
    if enabled {
        FileManager.default.createFile(atPath: traceFlagURL.path, contents: Data())
    } else {
        try? FileManager.default.removeItem(at: traceFlagURL)
    }
}

func clearTraceFile() {
    try? FileManager.default.removeItem(at: traceURL)
}

func runCommand(_ path: String, arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let message = String(data: data, encoding: .utf8) ?? "\(path) failed"
        throw MeasureError.command(message)
    }
}

func epochMicros() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1_000_000)
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
        set historyScrollArea to last scroll area of group 1 of window "Kipple"
        return exists static text "\(escaped)" of UI element 1 of historyScrollArea
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
        set historyScrollArea to last scroll area of group 1 of window "Kipple"
        set targetText to static text "\(escaped)" of UI element 1 of historyScrollArea
        set p to position of targetText
        set s to size of targetText
        set frameText to (item 1 of p as text) & "," & (item 2 of p as text)
        set frameText to frameText & "," & (item 1 of s as text) & "," & (item 2 of s as text)
        return frameText
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

func waitForTraceBreakdown(content: String, copyStartUs: Int64, visibleUs: Int64) throws -> TraceBreakdown? {
    _ = try waitForTraceEvent(content: content, name: "viewmodel_history_published", timeout: timeoutSeconds)
    _ = try? waitForTraceEvent(content: content, name: "history_save_finished", timeout: 2.0)

    let events = try traceEvents(for: content)
    guard let detected = eventTime("pasteboard_change_detected", in: events),
          let fetched = eventTime("clipboard_item_fetched", in: events),
          let history = eventTime("history_update_finished", in: events),
          let adapter = eventTime("adapter_history_will_publish", in: events),
          let viewModel = eventTime("viewmodel_history_published", in: events) else {
        return nil
    }

    let saveStarted = eventTime("history_save_started", in: events)
    let saveFinished = eventTime("history_save_finished", in: events)
    let saveStartSeconds = saveStarted.map { secondsBetween(copyStartUs, $0) }
    let saveDurationSeconds: Double?
    if let saveStarted, let saveFinished {
        saveDurationSeconds = secondsBetween(saveStarted, saveFinished)
    } else {
        saveDurationSeconds = nil
    }

    return TraceBreakdown(
        detect: secondsBetween(copyStartUs, detected),
        fetch: secondsBetween(detected, fetched),
        history: secondsBetween(fetched, history),
        adapter: secondsBetween(history, adapter),
        viewModel: secondsBetween(adapter, viewModel),
        ax: secondsBetween(viewModel, visibleUs),
        saveStart: saveStartSeconds,
        saveDuration: saveDurationSeconds
    )
}

func waitForTraceEvent(content: String, name: String, timeout: Double) throws -> Bool {
    let deadline = CFAbsoluteTimeGetCurrent() + timeout
    while CFAbsoluteTimeGetCurrent() < deadline {
        if try traceEvents(for: content).contains(where: { event in
            (event["event"] as? String) == name
        }) {
            return true
        }
        usleep(20_000)
    }
    return false
}

func traceEvents(for content: String) throws -> [[String: Any]] {
    guard let text = try? String(contentsOf: traceURL, encoding: .utf8) else {
        return []
    }

    return text.split(separator: "\n").compactMap { line in
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["content"] as? String == content else {
            return nil
        }
        return object
    }
}

func eventTime(_ name: String, in events: [[String: Any]]) -> Int64? {
    events.first { event in
        event["event"] as? String == name
    }.flatMap { event in
        if let value = event["time_us"] as? Int64 {
            return value
        }
        if let value = event["time_us"] as? NSNumber {
            return value.int64Value
        }
        return nil
    }
}

func secondsBetween(_ start: Int64, _ end: Int64) -> Double {
    Double(end - start) / 1_000_000
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
    print(String(
        format: "iteration=%d copy_to_history=%.1fms history_click=%.1fms open_window=%.1fms",
        iteration,
        copyMS,
        clickMS,
        openMS
    ))
}

func printTraceRow(iteration: Int, breakdown: TraceBreakdown) {
    let saveStart = breakdown.saveStart.map { String(format: "%.1fms", $0 * 1_000) } ?? "n/a"
    let saveDuration = breakdown.saveDuration.map { String(format: "%.1fms", $0 * 1_000) } ?? "n/a"
    let format = "trace iteration=%d detect=%.1fms fetch=%.1fms history=%.1fms adapter=%.1fms " +
        "viewmodel=%.1fms ax=%.1fms save_start=%@ save_duration=%@"
    print(String(
        format: format,
        iteration,
        breakdown.detect * 1_000,
        breakdown.fetch * 1_000,
        breakdown.history * 1_000,
        breakdown.adapter * 1_000,
        breakdown.viewModel * 1_000,
        breakdown.ax * 1_000,
        saveStart,
        saveDuration
    ))
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
