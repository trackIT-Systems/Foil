//
//  PlaneConfig.swift
//  Foil
//

import Carbon.HIToolbox
import Combine
import Foundation

extension Notification.Name {
    static let foilAppPresenceChanged = Notification.Name("foil.appPresenceChanged")
}

struct HotkeyDefinition: Equatable, Codable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    static let `default` = HotkeyDefinition(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(optionKey))

    var displayString: String {
        Self.modifierDisplayPrefix(carbonModifiers: carbonModifiers) + keyCodeToString(keyCode)
    }

    /// Modifier symbols only, same order as in `displayString` (⌃ ⌥ ⇧ ⌘).
    static func modifierDisplayPrefix(carbonModifiers: UInt32) -> String {
        var parts: [String] = []
        if carbonModifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if carbonModifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if carbonModifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if carbonModifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        return parts.joined()
    }

    private func keyCodeToString(_ code: UInt32) -> String {
        switch Int(code) {
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Space: return "Space"
        case kVK_Delete: return "⌫"
        case kVK_Escape: return "⎋"
        case kVK_Command, kVK_RightCommand: return "⌘"
        case kVK_Shift, kVK_RightShift: return "⇧"
        case kVK_CapsLock: return "⇪"
        case kVK_Option, kVK_RightOption: return "⌥"
        case kVK_Control, kVK_RightControl: return "⌃"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Home: return "↖"
        case kVK_End: return "↘"
        case kVK_PageUp: return "⇞"
        case kVK_PageDown: return "⇟"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_DownArrow: return "↓"
        case kVK_UpArrow: return "↑"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_F13: return "F13"
        case kVK_F14: return "F14"
        case kVK_F15: return "F15"
        case kVK_F16: return "F16"
        case kVK_F17: return "F17"
        case kVK_F18: return "F18"
        case kVK_F19: return "F19"
        case kVK_F20: return "F20"
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Grave: return "`"
        case kVK_ISO_Section: return "§"
        case kVK_JIS_Yen: return "¥"
        case kVK_JIS_Underscore: return "_"
        case kVK_JIS_Eisu: return "英数"
        case kVK_JIS_Kana: return "かな"
        default: return "Key \(code)"
        }
    }
}

/// Which destination is selected in the quick capture panel (persisted).
enum QuickCaptureMode: String, Codable, CaseIterable, Identifiable {
    case workItem
    case intake

    var id: String { rawValue }
}

@MainActor
final class PlaneConfigStore: ObservableObject {
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let apiRoot = "plane.apiRoot"
        static let workspaceSlug = "plane.workspaceSlug"
        static let onboardingComplete = "plane.onboardingComplete"
        static let showInDock = "foil.showInDock"
        static let showInMenuBar = "foil.showInMenuBar"
        static let quickCaptureHotkey = "foil.quickCaptureHotkey"
        static let quickCaptureMode = "foil.quickCaptureMode"
        static let autoCheckForUpdates = "foil.autoCheckForUpdates"
    }

    /// Call early (e.g. `applicationWillFinishLaunching`) so reads use correct defaults before first `PlaneConfigStore` init.
    static func registerAppPresenceDefaults() {
        UserDefaults.standard.register(defaults: [
            Keys.showInDock: true,
            Keys.showInMenuBar: false,
            Keys.autoCheckForUpdates: true,
        ])
    }

    static func readAppPresenceFromDefaults() -> (showInDock: Bool, showInMenuBar: Bool) {
        (
            showInDock: UserDefaults.standard.bool(forKey: Keys.showInDock),
            showInMenuBar: UserDefaults.standard.bool(forKey: Keys.showInMenuBar),
        )
    }

    @Published var apiRootInput: String {
        didSet { defaults.set(apiRootInput, forKey: Keys.apiRoot) }
    }

    @Published var workspaceSlug: String {
        didSet { defaults.set(workspaceSlug, forKey: Keys.workspaceSlug) }
    }

    /// Global quick-capture shortcut (persisted).
    @Published var quickCaptureHotkey: HotkeyDefinition {
        didSet {
            guard oldValue != quickCaptureHotkey else { return }
            Self.persistHotkey(quickCaptureHotkey)
        }
    }

    /// Alias used by hotkey installation (`FoilEnvironment`).
    var hotkey: HotkeyDefinition { quickCaptureHotkey }

    /// Last-used quick capture tab (work item vs intake).
    @Published var quickCaptureMode: QuickCaptureMode {
        didSet {
            guard oldValue != quickCaptureMode else { return }
            defaults.set(quickCaptureMode.rawValue, forKey: Keys.quickCaptureMode)
        }
    }

    @Published var onboardingComplete: Bool {
        didSet { defaults.set(onboardingComplete, forKey: Keys.onboardingComplete) }
    }

    @Published var showInDock: Bool {
        didSet {
            guard oldValue != showInDock else { return }
            defaults.set(showInDock, forKey: Keys.showInDock)
            NotificationCenter.default.post(name: .foilAppPresenceChanged, object: nil)
        }
    }

    @Published var showInMenuBar: Bool {
        didSet {
            guard oldValue != showInMenuBar else { return }
            defaults.set(showInMenuBar, forKey: Keys.showInMenuBar)
            NotificationCenter.default.post(name: .foilAppPresenceChanged, object: nil)
        }
    }

    @Published var autoCheckForUpdates: Bool {
        didSet {
            guard oldValue != autoCheckForUpdates else { return }
            defaults.set(autoCheckForUpdates, forKey: Keys.autoCheckForUpdates)
        }
    }

    init() {
        Self.registerAppPresenceDefaults()
        let dockInit = defaults.bool(forKey: Keys.showInDock)
        let menuInit = defaults.bool(forKey: Keys.showInMenuBar)
        _showInDock = Published(initialValue: dockInit)
        _showInMenuBar = Published(initialValue: menuInit)
        apiRootInput = defaults.string(forKey: Keys.apiRoot) ?? "https://api.plane.so"
        workspaceSlug = defaults.string(forKey: Keys.workspaceSlug) ?? ""
        onboardingComplete = defaults.bool(forKey: Keys.onboardingComplete)
        let hotkeyInit = Self.loadHotkey() ?? .default
        _quickCaptureHotkey = Published(initialValue: hotkeyInit)
        _quickCaptureMode = Published(initialValue: Self.loadQuickCaptureMode())
        _autoCheckForUpdates = Published(initialValue: defaults.object(forKey: Keys.autoCheckForUpdates) as? Bool ?? true)
    }

    private static func loadQuickCaptureMode() -> QuickCaptureMode {
        guard let raw = UserDefaults.standard.string(forKey: Keys.quickCaptureMode),
              let mode = QuickCaptureMode(rawValue: raw)
        else { return .workItem }
        return mode
    }

    private static func loadHotkey() -> HotkeyDefinition? {
        guard let data = UserDefaults.standard.data(forKey: Keys.quickCaptureHotkey) else { return nil }
        return try? JSONDecoder().decode(HotkeyDefinition.self, from: data)
    }

    private static func persistHotkey(_ definition: HotkeyDefinition) {
        guard let data = try? JSONEncoder().encode(definition) else { return }
        UserDefaults.standard.set(data, forKey: Keys.quickCaptureHotkey)
    }

    /// Normalized API root whose path ends with `/api/v1`.
    func normalizedAPIRootURL() -> URL? {
        Self.normalizedAPIRootURL(for: apiRootInput)
    }

    /// Validates an API root string without mutating stored config (for settings drafts).
    static func normalizedAPIRootURL(for apiRootInput: String) -> URL? {
        var s = apiRootInput.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        guard var components = URLComponents(string: s) else { return nil }
        var path = components.path
        while path.hasSuffix("/"), path.count > 1 { path.removeLast() }
        if path.hasSuffix("/api/v1") {
            components.path = path
        } else if path.isEmpty || path == "/" {
            components.path = "/api/v1"
        } else {
            components.path = path + "/api/v1"
        }
        return components.url
    }

    var isConfigured: Bool {
        onboardingComplete && normalizedAPIRootURL() != nil && !workspaceSlug.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && KeychainStore.loadToken() != nil
    }

    func markConfiguredSavingToken(_ token: String) throws {
        try KeychainStore.saveToken(token)
        onboardingComplete = true
    }

    func updateToken(_ token: String) throws {
        try KeychainStore.saveToken(token)
    }

    func signOut() {
        KeychainStore.deleteToken()
        onboardingComplete = false
    }
}
