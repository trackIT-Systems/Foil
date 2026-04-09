//
//  AppDelegate.swift
//  Foil
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var environment: FoilEnvironment?

    func applicationWillFinishLaunching(_ notification: Notification) {
        PlaneConfigStore.registerAppPresenceDefaults()
        if !PlaneConfigStore.readAppPresenceFromDefaults().showInDock {
            applyActivationPolicyFromDefaults()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        FoilLog.app("applicationDidFinishLaunching")
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appPresencePreferencesChanged),
            name: .foilAppPresenceChanged,
            object: nil
        )
        DispatchQueue.main.async { [weak self] in
            self?.applyActivationPolicyFromDefaults()
        }
        environment?.installHotkeyFromConfig()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func appPresencePreferencesChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.applyActivationPolicyFromDefaults()
        }
    }

    func applyActivationPolicyFromDefaults() {
        assert(Thread.isMainThread)
        let showInDock = PlaneConfigStore.readAppPresenceFromDefaults().showInDock
        let target: NSApplication.ActivationPolicy = showInDock ? .regular : .accessory
        if NSApp.activationPolicy() == target {
            return
        }
        let ok = NSApp.setActivationPolicy(target)
        FoilLog.app("setActivationPolicy \(target == .regular ? "regular" : "accessory") → \(ok ? "ok" : "failed")")
        if showInDock {
            NSApp.activate(ignoringOtherApps: false)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard PlaneConfigStore.readAppPresenceFromDefaults().showInDock else { return true }
        if let environment, environment.config.isConfigured {
            environment.quickPanel.show()
            return false
        }
        if !flag {
            NSApp.activate(ignoringOtherApps: true)
            for window in sender.windows where window.styleMask.contains(.titled) && !(window is NSPanel) {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }
}
