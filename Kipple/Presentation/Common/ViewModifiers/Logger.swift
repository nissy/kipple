//
//  Logger.swift
//  Kipple
//
//  Created by Kipple on 2025/06/28.
//

import Foundation
import os.log

enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
}

class Logger {
    static let shared = Logger()
    private let subsystem = Bundle.main.bundleIdentifier ?? "com.Kipple"
    private let osLog: OSLog?
    private let isTestEnvironment: Bool
    private var _isDebugEnabledCache: Bool?
    
    private init() {
        isTestEnvironment = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        
        if isTestEnvironment {
            osLog = nil
        } else {
            osLog = OSLog(subsystem: subsystem, category: "Kipple")
        }
    }
    
    // デバッグログの有効/無効をUserDefaultsで制御（既定: false）
    private var isDebugEnabled: Bool {
        if let cached = _isDebugEnabledCache { return cached }
        let enabled = UserDefaults.standard.bool(forKey: "enableDebugLogs")
        _isDebugEnabledCache = enabled
        return enabled
    }

    // 設定変更時にキャッシュをクリア
    func refreshConfig() {
        _isDebugEnabledCache = nil
    }

    // 外部API（@autoclosure）
    func log(_ message: @autoclosure () -> String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        _log(message, level: level, file: file, function: function, line: line)
    }

    // 実装本体（クロージャ）: メッセージを必要時のみ評価
    private func _log(_ message: () -> String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        // デバッグログは無効なら即リターン
        if level == .debug && !isDebugEnabled {
            return
        }
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let built = message()
        let logMessage = "[\(level.rawValue)] \(fileName):\(line) \(function) - \(built)"
        
        if isTestEnvironment {
            // テスト実行時はNSLogを使用
            NSLog("%@", logMessage)
        } else {
            // 通常時はOSLogを使用
            guard let osLog = osLog else { return }
            switch level {
            case .debug:
                os_log(.debug, log: osLog, "%{private}@", logMessage)
            case .info:
                os_log(.info, log: osLog, "%{private}@", logMessage)
            case .warning:
                os_log(.default, log: osLog, "%{private}@", logMessage)
            case .error:
                os_log(.error, log: osLog, "%{private}@", logMessage)
            }
        }
    }
    
    func debug(_ message: @autoclosure () -> String, file: String = #file, function: String = #function, line: Int = #line) {
        _log(message, level: .debug, file: file, function: function, line: line)
    }
    
    func info(_ message: @autoclosure () -> String, file: String = #file, function: String = #function, line: Int = #line) {
        _log(message, level: .info, file: file, function: function, line: line)
    }
    
    func warning(_ message: @autoclosure () -> String, file: String = #file, function: String = #function, line: Int = #line) {
        _log(message, level: .warning, file: file, function: function, line: line)
    }
    
    func error(_ message: @autoclosure () -> String, file: String = #file, function: String = #function, line: Int = #line) {
        _log(message, level: .error, file: file, function: function, line: line)
    }
}
