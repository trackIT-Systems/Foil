//
//  FoilEnvironment.swift
//  Foil
//

import Combine
import SwiftUI

@MainActor
final class FoilEnvironment: ObservableObject {
    var config = PlaneConfigStore()
    let appUpdate: AppUpdateController
    private var cancellables = Set<AnyCancellable>()
    private let hotkey = HotkeyManager()
    private(set) lazy var quickPanel = QuickCapturePanelController(environment: self)

    init() {
        appUpdate = AppUpdateController(config: config)
        config.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        appUpdate.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
    }

    func makeAPIClient() -> PlaneAPIClient? {
        guard let root = config.normalizedAPIRootURL() else {
            FoilLog.app("makeAPIClient: invalid or missing API base URL")
            return nil
        }
        guard let token = KeychainStore.loadToken() else {
            FoilLog.app("makeAPIClient: no token in Keychain")
            return nil
        }
        let slug = config.workspaceSlug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !slug.isEmpty else {
            FoilLog.app("makeAPIClient: workspace slug empty")
            return nil
        }
        FoilLog.app("makeAPIClient OK — base \(root.absoluteString) workspace=\(slug)")
        return PlaneAPIClient(apiRoot: root, workspaceSlug: slug, token: token)
    }

    func installHotkeyFromConfig() {
        guard config.isConfigured else {
            FoilLog.hotkey("installHotkey skipped: not fully configured")
            return
        }
        FoilLog.hotkey("installHotkey registering: \(config.hotkey.displayString)")
        hotkey.register(definition: config.hotkey) { [weak self] in
            guard let self else { return }
            if self.quickPanel.isVisible {
                FoilLog.hotkey("Global shortcut fired → toggle quick capture mode")
                self.quickPanel.toggleQuickCaptureMode()
            } else {
                FoilLog.hotkey("Global shortcut fired → open quick capture")
                self.quickPanel.show()
            }
        }
    }

    func refreshHotkey() {
        hotkey.unregister()
        installHotkeyFromConfig()
    }
}
