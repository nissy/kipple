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
    
    private init() {
        isTestEnvironment = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        
        if isTestEnvironment {
            osLog = nil
        } else {
            osLog = OSLog(subsystem: subsystem, category: "Kipple")
        }
    }
    
    func log(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let logMessage = "[\(level.rawValue)] \(fileName):\(line) \(function) - \(message)"
        
        if isTestEnvironment {
            // テスト実行時はコンソール出力のみ
            print(logMessage)
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
    
    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .debug, file: file, function: function, line: line)
    }
    
    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, file: file, function: function, line: line)
    }
    
    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .warning, file: file, function: function, line: line)
    }
    
    func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .error, file: file, function: function, line: line)
    }
}
