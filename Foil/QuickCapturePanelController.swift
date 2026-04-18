//
//  QuickCapturePanelController.swift
//  Foil
//

import AppKit
import SwiftUI

@MainActor
final class QuickCapturePanelController {
    private unowned let environment: FoilEnvironment
    private var panel: NSPanel?
    private var viewModel: QuickCaptureViewModel?

    init(environment: FoilEnvironment) {
        self.environment = environment
    }

    /// True when the quick capture panel exists and is on screen (global shortcut switches intake ↔ work item while open).
    var isVisible: Bool { panel?.isVisible == true }

    func show() {
        guard environment.config.isConfigured else {
            FoilLog.ui("Quick capture show skipped: not configured (finish onboarding or sign in)")
            return
        }
        FoilLog.ui("Quick capture panel show")
        NSApp.activate(ignoringOtherApps: true)

        if panel == nil {
            let vm = QuickCaptureViewModel(environment: environment)
            vm.onDismissPanel = { [weak self] in
                self?.hide()
            }
            let view = QuickCreateWorkItemView()
                .environmentObject(environment)
                .environmentObject(vm)
                .environmentObject(environment.config)
            let host = NSHostingController(rootView: view)
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 400),
                styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.title = Self.panelTitle(for: environment.config.quickCaptureMode)
            p.titlebarAppearsTransparent = true
            p.isFloatingPanel = true
            p.level = .floating
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.isMovableByWindowBackground = true
            host.view.frame = p.contentView!.bounds
            p.contentViewController = host
            p.center()
            p.isReleasedWhenClosed = false
            p.standardWindowButton(.zoomButton)?.isHidden = true
            p.standardWindowButton(.miniaturizeButton)?.isHidden = true
            panel = p
            viewModel = vm
        }

        viewModel?.invalidateProjectsCache()
        viewModel?.resetForDisplay()
        syncWindowTitleFromConfig()
        Task { await viewModel?.loadProjectsIfNeeded() }
        panel?.makeKeyAndOrderFront(nil)
    }

    /// Flips work item ↔ intake when the global shortcut fires while the panel is open.
    /// Side effects (clear form, project list, title) run deferred in `QuickCreateWorkItemView.onChange` to avoid publishing during view updates.
    func toggleQuickCaptureMode() {
        environment.config.quickCaptureMode = environment.config.quickCaptureMode == .workItem ? .intake : .workItem
    }

    func syncWindowTitleFromConfig() {
        panel?.title = Self.panelTitle(for: environment.config.quickCaptureMode)
    }

    private static func panelTitle(for mode: QuickCaptureMode) -> String {
        switch mode {
        case .workItem: return "Create work item"
        case .intake: return "Create intake work item"
        }
    }

    func hide() {
        FoilLog.ui("Quick capture panel hide")
        panel?.orderOut(nil)
    }
}
