//
//  FoilLog.swift
//  Foil
//

import Foundation
import os.log

/// Debug-friendly logging: **`print`** lines show in Xcode’s bottom **Debug console** when you run a **Debug** build (⌘R).
/// Also uses `Logger` so you can filter **Console.app** by the app’s bundle identifier subsystem.
enum FoilLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "systems.trackit.Foil"

    private static let apiLogger = Logger(subsystem: subsystem, category: "API")
    private static let hotkeyLogger = Logger(subsystem: subsystem, category: "Hotkey")
    private static let uiLogger = Logger(subsystem: subsystem, category: "UI")
    private static let appLogger = Logger(subsystem: subsystem, category: "App")

    private static func debugPrint(_ message: String) {
        #if DEBUG
        print(message)
        #endif
    }

    static func app(_ message: String) {
        appLogger.info("\(message, privacy: .public)")
        debugPrint("[Foil][App] \(message)")
    }

    static func apiRequest(method: String, url: URL, bodyByteCount: Int? = nil) {
        var line = "[Foil][API] → \(method) \(url.absoluteString)"
        if let n = bodyByteCount { line += " (body: \(n) bytes)" }
        apiLogger.info("\(line, privacy: .public)")
        debugPrint(line)
    }

    static func apiResponse(method: String, url: String, status: Int, body: Data, logBodyOnSuccess: Bool = false) {
        let ok = (200 ... 299).contains(status)
        var line = "[Foil][API] ← \(method) HTTP \(status) \(url) (\(body.count) bytes)"
        if !ok || logBodyOnSuccess {
            line += "\n" + truncateForLog(body)
        }
        if ok {
            apiLogger.info("\(line, privacy: .public)")
        } else {
            apiLogger.error("\(line, privacy: .public)")
        }
        debugPrint(line)
    }

    static func apiError(_ message: String) {
        apiLogger.error("\(message, privacy: .public)")
        debugPrint("[Foil][API][error] \(message)")
    }

    static func hotkey(_ message: String) {
        hotkeyLogger.info("\(message, privacy: .public)")
        debugPrint("[Foil][Hotkey] \(message)")
    }

    static func ui(_ message: String) {
        uiLogger.info("\(message, privacy: .public)")
        debugPrint("[Foil][UI] \(message)")
    }

    private static func truncateForLog(_ data: Data, maxChars: Int = 1200) -> String {
        guard !data.isEmpty else { return "  (empty body)" }
        let s = String(data: data, encoding: .utf8) ?? "  (non-UTF8, \(data.count) bytes)"
        if s.count <= maxChars { return "  " + s }
        return "  " + String(s.prefix(maxChars)) + "…"
    }
}
