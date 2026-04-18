//
//  SettingsView.swift
//  Foil
//

import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var environment: FoilEnvironment
    @Environment(\.appearsActive) private var appearsActive
    @State private var draftShowInDock = true
    @State private var draftShowInMenuBar = false
    @State private var draftApiRoot = ""
    @State private var draftWorkspace = ""
    @State private var draftToken = ""
    @State private var draftHotkey = HotkeyDefinition.default
    @State private var isRecordingHotkey = false
    @State private var recordingLiveText = ""
    @State private var launchAtLogin = false
    @State private var launchAtLoginError: String?
    @State private var saveError: String?

    private var hasKeychainToken: Bool {
        KeychainStore.loadToken() != nil
    }

    private var tokenPrompt: Text {
        if hasKeychainToken && draftToken.isEmpty {
            Text(verbatim: "••••••••••••")
        } else {
            Text("Paste API access token")
        }
    }

    /// True when drafts differ from persisted config (including a non-empty token field).
    private var autoCheckForUpdatesBinding: Binding<Bool> {
        Binding(
            get: { environment.config.autoCheckForUpdates },
            set: { environment.config.autoCheckForUpdates = $0 }
        )
    }

    private var hasUnsavedChanges: Bool {
        let c = environment.config
        if draftShowInDock != c.showInDock { return true }
        if draftShowInMenuBar != c.showInMenuBar { return true }
        if draftHotkey != c.quickCaptureHotkey { return true }
        let root = draftApiRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        if root != c.apiRootInput.trimmingCharacters(in: .whitespacesAndNewlines) { return true }
        let slug = draftWorkspace.trimmingCharacters(in: .whitespacesAndNewlines)
        if slug != c.workspaceSlug.trimmingCharacters(in: .whitespacesAndNewlines) { return true }
        if !draftToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return false
    }

    var body: some View {
        Form {
            Section("App presence") {
                Toggle("Show in Dock", isOn: $draftShowInDock)
                    .toggleStyle(.checkbox)
                    .onChange(of: draftShowInDock) { _, _ in clearSaveFeedback() }
                Toggle("Show menu bar item", isOn: $draftShowInMenuBar)
                    .toggleStyle(.checkbox)
                    .onChange(of: draftShowInMenuBar) { _, _ in clearSaveFeedback() }
                Toggle("Open at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { applyLaunchAtLogin($0) }
                ))
                .toggleStyle(.checkbox)
                if SMAppService.mainApp.status == .requiresApproval {
                    Text("Finish approval in System Settings → General → Login Items.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                LabeledContent("Quick capture shortcut") {
                    Button {
                        recordingLiveText = ""
                        isRecordingHotkey = true
                        clearSaveFeedback()
                    } label: {
                        Text(isRecordingHotkey ? "Listening…" : draftHotkey.displayString)
                            .monospaced()
                            .frame(minWidth: 72, alignment: .center)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRecordingHotkey)
                }
                if isRecordingHotkey {
                    ZStack(alignment: .leading) {
                        TextField("", text: $recordingLiveText, prompt: Text("Press a new shortcut. Press Esc to cancel."))
                            .textFieldStyle(.roundedBorder)
                            .font(.body.monospaced())
                            .allowsHitTesting(false)
                        HotkeyRecorderKeyView(
                            isActive: isRecordingHotkey,
                            onPreview: { recordingLiveText = $0 },
                            onCapture: { definition in
                                draftHotkey = definition
                                isRecordingHotkey = false
                                clearSaveFeedback()
                            },
                            onCancel: {
                                isRecordingHotkey = false
                            }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(height: 22)
                    .frame(maxWidth: .infinity)
                }
            }

            Section("Plane connection") {
                TextField("API base URL", text: $draftApiRoot)
                    .onChange(of: draftApiRoot) { _, _ in clearSaveFeedback() }
                TextField("Workspace slug", text: $draftWorkspace)
                    .onChange(of: draftWorkspace) { _, _ in clearSaveFeedback() }
                SecureField("API token", text: $draftToken, prompt: tokenPrompt)
                    .textContentType(.password)
                    .onChange(of: draftToken) { _, _ in clearSaveFeedback() }
            }

            Section("Updates") {
                Toggle("Automatically check for updates", isOn: autoCheckForUpdatesBinding)
                    .toggleStyle(.checkbox)
                    .onChange(of: environment.config.autoCheckForUpdates) { _, enabled in
                        if enabled {
                            environment.appUpdate.scheduleStaleCheckWhenSettingsAppear()
                        }
                    }
                updatesStatusBlock
                if let outcome = environment.appUpdate.storedOutcome, outcome.isUpdateAvailable {
                    Button("Download on GitHub") {
                        environment.appUpdate.openDownloadPageFromStoredOutcome()
                    }
                }
                if !environment.config.autoCheckForUpdates {
                    Button("Check for updates") {
                        environment.appUpdate.checkFromUserButton()
                    }
                    .disabled(environment.appUpdate.isChecking)
                }
                if let refresh = environment.appUpdate.refreshFailureMessage {
                    Text(refresh)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if environment.config.autoCheckForUpdates {
                        Button("Retry") {
                            environment.appUpdate.checkFromUserButton()
                        }
                        .disabled(environment.appUpdate.isChecking)
                    }
                }
            }

            Section {
                HStack {
                    Button("Sign out", role: .destructive) {
                        environment.config.signOut()
                        environment.refreshHotkey()
                        loadDraftsFromConfig()
                        clearSaveFeedback()
                    }
                    Spacer()
                    Button("Save & Close") {
                        if save() {
                            closeSettingsWindow()
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                }
                if hasUnsavedChanges {
                    Text("You have unsaved changes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let saveError {
                    Text(saveError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 600)
        .onAppear {
            loadDraftsFromConfig()
            syncLaunchAtLoginFromSystem()
            environment.appUpdate.scheduleStaleCheckWhenSettingsAppear()
        }
        .onChange(of: appearsActive) { _, active in
            guard active else { return }
            syncLaunchAtLoginFromSystem()
        }
        .onChange(of: isRecordingHotkey) { _, recording in
            if !recording {
                recordingLiveText = ""
            }
        }
    }

    @ViewBuilder
    private var updatesStatusBlock: some View {
        let u = environment.appUpdate
        if u.isChecking {
            Text("Checking for updates…")
                .foregroundStyle(.secondary)
        } else if let outcome = u.storedOutcome {
            if outcome.isUpdateAvailable {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("A newer version is available:")
                        Text(outcome.remoteVersionDisplay)
                            .fontWeight(.semibold)
                    }
                    Text("Last checked: \(Self.shortDateTime.string(from: outcome.lastChecked))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("You’re on the latest version.")
                    Text("Last checked: \(Self.shortDateTime.string(from: outcome.lastChecked))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Text("Update status will appear after a check.")
                .foregroundStyle(.secondary)
        }
    }

    private static let shortDateTime: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private func clearSaveFeedback() {
        saveError = nil
    }

    private func syncLaunchAtLoginFromSystem() {
        launchAtLogin = loginItemToggleShouldBeOn
    }

    private var loginItemToggleShouldBeOn: Bool {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            return true
        case .notRegistered, .notFound:
            return false
        @unknown default:
            return false
        }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = nil
        let serviceDomain = SMAppServiceErrorDomain
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            let ns = error as NSError
            if enabled, ns.domain == serviceDomain, ns.code == kSMErrorAlreadyRegistered {
                // Already registered; treat as success.
            } else if !enabled, ns.domain == serviceDomain, ns.code == kSMErrorJobNotFound {
                // Already removed; treat as success.
            } else {
                launchAtLoginError = launchAtLoginFailureMessage(error)
            }
        }
        syncLaunchAtLoginFromSystem()
    }

    private func launchAtLoginFailureMessage(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == SMAppServiceErrorDomain, ns.code == kSMErrorLaunchDeniedByUser {
            return "Login was denied. Approve Foil under System Settings → General → Login Items."
        }
        return ns.localizedDescription
    }

    private func loadDraftsFromConfig() {
        draftShowInDock = environment.config.showInDock
        draftShowInMenuBar = environment.config.showInMenuBar
        draftHotkey = environment.config.quickCaptureHotkey
        draftApiRoot = environment.config.apiRootInput
        draftWorkspace = environment.config.workspaceSlug
        draftToken = ""
    }

    private func closeSettingsWindow() {
        DispatchQueue.main.async {
            NSApp.keyWindow?.performClose(nil)
        }
    }

    @discardableResult
    private func save() -> Bool {
        saveError = nil

        let root = draftApiRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        let slug = draftWorkspace.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokenTrim = draftToken.trimmingCharacters(in: .whitespacesAndNewlines)

        guard PlaneConfigStore.normalizedAPIRootURL(for: root) != nil else {
            saveError = "Invalid API URL."
            return false
        }
        guard !slug.isEmpty else {
            saveError = "Workspace slug is required."
            return false
        }
        if KeychainStore.loadToken() == nil && tokenTrim.isEmpty {
            saveError = "API token is required."
            return false
        }

        environment.config.apiRootInput = root
        environment.config.workspaceSlug = slug

        if !tokenTrim.isEmpty {
            do {
                try environment.config.updateToken(tokenTrim)
                draftToken = ""
            } catch {
                saveError = "Could not save token."
                return false
            }
        }

        environment.config.showInDock = draftShowInDock
        environment.config.showInMenuBar = draftShowInMenuBar
        environment.config.quickCaptureHotkey = draftHotkey

        environment.refreshHotkey()
        return true
    }
}
