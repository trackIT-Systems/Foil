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

    /// True when the quick capture panel exists and is on screen (same shortcut toggles closed).
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
                .environmentObject(vm)
            let host = NSHostingController(rootView: view)
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 400),
                styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.title = "Create new work item"
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

        viewModel?.resetForDisplay()
        Task { await viewModel?.loadProjectsIfNeeded() }
        panel?.makeKeyAndOrderFront(nil)
    }

    func hide() {
        FoilLog.ui("Quick capture panel hide")
        panel?.orderOut(nil)
    }
}
