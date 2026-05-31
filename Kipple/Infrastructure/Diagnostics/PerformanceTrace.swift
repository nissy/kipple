import Foundation

enum PerformanceTrace {
    private static let queue = DispatchQueue(label: "com.nissy.Kipple.performanceTrace")
    private static let flagURL = URL(fileURLWithPath: "/tmp/kipple-enable-perf-trace")
    static let fileURL = URL(fileURLWithPath: "/tmp/kipple-perf-trace.jsonl")
    private static let maxContentLength = 200

    static var isEnabled: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "enablePerformanceTrace") ||
            FileManager.default.fileExists(atPath: flagURL.path)
        #else
        false
        #endif
    }

    static func nowMicros() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1_000_000)
    }

    static func event(
        _ name: String,
        atMicros: Int64 = nowMicros(),
        content: String? = nil,
        revision: UInt64? = nil,
        count: Int? = nil,
        details: [String: String] = [:]
    ) {
        guard isEnabled else { return }

        var fields: [(String, String)] = [
            ("time_us", String(atMicros)),
            ("event", jsonString(name))
        ]

        if let content {
            fields.append(("content", jsonString(truncatedContent(content))))
        }
        if let revision {
            fields.append(("revision", String(revision)))
        }
        if let count {
            fields.append(("count", String(count)))
        }
        for key in details.keys.sorted() {
            if let value = details[key] {
                fields.append((key, jsonString(value)))
            }
        }

        let line = "{\(fields.map { "\"\($0.0)\":\($0.1)" }.joined(separator: ","))}\n"
        queue.async {
            append(line)
        }
    }

    private static func append(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        let path = fileURL.path

        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }

        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    private static func truncatedContent(_ content: String) -> String {
        guard content.count > maxContentLength else { return content }
        return String(content.prefix(maxContentLength)) + "…"
    }

    private static func jsonString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }
}
