//
//  AppUpdateController.swift
//  Foil
//

import AppKit
import Combine
import Foundation

/// Persisted outcome of the last **successful** GitHub check (survives restarts).
struct AppUpdateStoredOutcome: Codable, Equatable {
    var isUpdateAvailable: Bool
    /// Marketing-style version string when `isUpdateAvailable` is true (e.g. `2026.04.2`).
    var remoteVersionDisplay: String
    var htmlURLString: String
    var lastChecked: Date
}

private enum DefaultsKeys {
    static let snapshot = "foil.updateCheck.snapshot"
}

/// GitHub repository that hosts Foil releases (must match tags used in CI).
private enum FoilGitHubReleaseRepository {
    static let owner = "trackIT-Systems"
    static let repo = "Foil"
}

private let automaticCheckMinInterval: TimeInterval = 24 * 60 * 60

@MainActor
final class AppUpdateController: ObservableObject {
    private let config: PlaneConfigStore
    private let client: GitHubLatestReleaseClient
    private let defaults: UserDefaults

    /// True while a network check is in flight.
    @Published private(set) var isChecking = false

    /// Last successful check result, loaded from disk and updated after each success.
    @Published private(set) var storedOutcome: AppUpdateStoredOutcome?

    /// Set when a check fails; kept alongside `storedOutcome` so we can still show “update available” + Download.
    @Published private(set) var refreshFailureMessage: String?

    private var checkTask: Task<Void, Never>?
    /// Prevents duplicate automatic launch requests when both the main window and menu bar attach.
    private var didScheduleInitialAutomaticCheck = false

    init(config: PlaneConfigStore, client: GitHubLatestReleaseClient = GitHubLatestReleaseClient(), defaults: UserDefaults = .standard) {
        self.config = config
        self.client = client
        self.defaults = defaults
        storedOutcome = Self.loadSnapshot(from: defaults)
    }

    /// Auto check on launch: only when the user enabled auto-check and the last successful check is older than 24h (or missing).
    func scheduleAutomaticLaunchCheck() {
        guard config.autoCheckForUpdates else { return }
        guard !didScheduleInitialAutomaticCheck else { return }
        guard Self.needsAutomaticCheck(since: storedOutcome?.lastChecked) else { return }
        didScheduleInitialAutomaticCheck = true
        startCheck(kind: .automaticLaunch)
    }

    /// Optional long-session refresh: same 24h gate as launch when Settings opens.
    func scheduleStaleCheckWhenSettingsAppear() {
        guard config.autoCheckForUpdates else { return }
        guard Self.needsAutomaticCheck(since: storedOutcome?.lastChecked) else { return }
        startCheck(kind: .settingsStale)
    }

    /// User pressed **Check for updates** (Settings, when auto is off) or **Retry** after an error.
    func checkFromUserButton() {
        startCheck(kind: .manualButton)
    }

    /// App menu **Check for Updates…** — always runs immediately (plan).
    func checkFromAppMenu() {
        startCheck(kind: .menuCommand)
    }

    func openDownloadPageFromStoredOutcome() {
        guard let storedOutcome, storedOutcome.isUpdateAvailable else { return }
        guard let url = URL(string: storedOutcome.htmlURLString) else { return }
        NSWorkspace.shared.open(url)
    }

    private enum CheckKind {
        case automaticLaunch
        case settingsStale
        case manualButton
        case menuCommand
    }

    private static func needsAutomaticCheck(since last: Date?) -> Bool {
        guard let last else { return true }
        return Date().timeIntervalSince(last) >= automaticCheckMinInterval
    }

    private static func loadSnapshot(from defaults: UserDefaults) -> AppUpdateStoredOutcome? {
        guard let data = defaults.data(forKey: DefaultsKeys.snapshot) else { return nil }
        return try? JSONDecoder().decode(AppUpdateStoredOutcome.self, from: data)
    }

    private func saveSnapshot(_ outcome: AppUpdateStoredOutcome) {
        guard let data = try? JSONEncoder().encode(outcome) else { return }
        defaults.set(data, forKey: DefaultsKeys.snapshot)
    }

    private func startCheck(kind: CheckKind) {
        switch kind {
        case .manualButton, .menuCommand:
            checkTask?.cancel()
        case .automaticLaunch, .settingsStale:
            if isChecking { return }
        }
        checkTask = Task { [weak self] in
            await self?.runCheck(kind: kind)
        }
    }

    private func runCheck(kind: CheckKind) async {
        guard !Task.isCancelled else { return }
        isChecking = true
        refreshFailureMessage = nil

        let bundleVersion =
            (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let userAgent = "Foil/\(bundleVersion.isEmpty ? "0" : bundleVersion) (macOS)"

        do {
            let dto = try await client.fetchLatestRelease(
                owner: FoilGitHubReleaseRepository.owner,
                repo: FoilGitHubReleaseRepository.repo,
                userAgent: userAgent
            )
            guard !Task.isCancelled else { return }

            guard let remoteParsed = MarketingVersion.parseFromGitTag(dto.tagName) else {
                throw GitHubLatestReleaseError.decodingFailed
            }
            guard let localParsed = MarketingVersion(parsing: bundleVersion) else {
                throw GitHubLatestReleaseError.invalidResponse
            }

            let displayVersion = dto.tagName.trimmingCharacters(in: .whitespacesAndNewlines).drop(while: { $0 == "v" || $0 == "V" })
            let display = String(displayVersion)

            let now = Date()
            let outcome: AppUpdateStoredOutcome
            if remoteParsed > localParsed {
                outcome = AppUpdateStoredOutcome(
                    isUpdateAvailable: true,
                    remoteVersionDisplay: display,
                    htmlURLString: dto.htmlUrl,
                    lastChecked: now
                )
            } else {
                outcome = AppUpdateStoredOutcome(
                    isUpdateAvailable: false,
                    remoteVersionDisplay: display,
                    htmlURLString: dto.htmlUrl,
                    lastChecked: now
                )
            }
            storedOutcome = outcome
            saveSnapshot(outcome)
            refreshFailureMessage = nil
            FoilLog.app("update check OK — local=\(bundleVersion) remoteTag=\(dto.tagName) update=\(outcome.isUpdateAvailable) kind=\(String(describing: kind))")
        } catch let gh as GitHubLatestReleaseError {
            if Task.isCancelled { return }
            applyFailure(gh.localizedDescription)
            FoilLog.app("update check failed (GitHub error): \(gh.localizedDescription ?? "")")
        } catch {
            if Task.isCancelled { return }
            applyFailure(GitHubLatestReleaseError.invalidResponse.localizedDescription ?? "Unknown error")
            FoilLog.app("update check failed: \(error.localizedDescription)")
        }

        isChecking = false
    }

    /// On failure: keep prior `storedOutcome` so “update available” + Download still work; surface a short refresh warning.
    private func applyFailure(_ message: String) {
        if storedOutcome != nil {
            refreshFailureMessage = "Could not refresh: \(message)"
        } else {
            refreshFailureMessage = message
        }
    }
}
