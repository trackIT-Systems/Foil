//
//  FoilApp.swift
//  Foil
//

import AppKit
import SwiftUI

@main
struct FoilApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var environment = FoilEnvironment()

    private var showInMenuBarBinding: Binding<Bool> {
        Binding(
            get: { environment.config.showInMenuBar },
            set: { newValue in
                DispatchQueue.main.async {
                    environment.config.showInMenuBar = newValue
                }
            }
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(environment)
                .onAppear {
                    appDelegate.environment = environment
                    FoilLog.app("Main window appeared — installing global shortcut if configured")
                    environment.installHotkeyFromConfig()
                }
        }
        .defaultSize(width: 520, height: 440)

        MenuBarExtra(isInserted: showInMenuBarBinding) {
            FoilMenuBarExtraMenu()
                .environmentObject(environment)
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .accessibilityLabel("Foil")
        }

        Settings {
            SettingsView()
                .environmentObject(environment)
        }
    }
}

private struct FoilMenuBarExtraMenu: View {
    @EnvironmentObject private var environment: FoilEnvironment

    var body: some View {
        Button("Create new work item") {
            environment.quickPanel.show()
        }

        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
