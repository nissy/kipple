//
//  PerfTracer.swift
//  Kipple
//
//  KIPPLE_PERF_TRACE=1 で起動した時のみ ~/Library/Logs/Kipple/perf.jsonl に区間ログを吐く。
//  Release ビルドにも残るが、環境変数なしでは何もしない（オーバーヘッドはほぼゼロ）。
//

import Foundation
import AppKit

enum PerfTracer {
    static let isEnabled: Bool = ProcessInfo.processInfo.environment["KIPPLE_PERF_TRACE"] == "1"

    private static let queue = DispatchQueue(label: "kipple.perf.tracer", qos: .utility)
    private static let bootTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()

    private static let logURL: URL? = {
        guard isEnabled else { return nil }
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Kipple", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("perf.jsonl")
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        FileManager.default.createFile(atPath: url.path, contents: nil)
        return url
    }()

    static func event(_ name: String, extra: [String: Any] = [:]) {
        guard isEnabled, let url = logURL else { return }
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - bootTime
        let frontBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil"
        var dict: [String: Any] = [
            "t": now,
            "elapsed": elapsed,
            "event": name,
            "front": frontBundle
        ]
        for (key, value) in extra {
            dict[key] = value
        }
        queue.async {
            guard let data = try? JSONSerialization.data(withJSONObject: dict, options: []),
                  var line = String(data: data, encoding: .utf8) else { return }
            line.append("\n")
            guard let bytes = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                try? handle.seekToEnd()
                try? handle.write(contentsOf: bytes)
            }
        }
    }
}
