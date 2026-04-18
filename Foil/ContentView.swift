//
//  ContentView.swift
//  Foil
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var environment: FoilEnvironment
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Group {
            if environment.config.isConfigured {
                mainLanding
            } else {
                OnboardingView()
            }
        }
        .frame(minWidth: 480, minHeight: 420)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var mainLanding: some View {
        VStack(spacing: 24) {
            HStack(alignment: .center, spacing: 14) {
                Image("Logo")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                Text("Foil")
                    .font(.largeTitle.weight(.bold))
            }
            Text("Press \(environment.config.hotkey.displayString) to open quick capture in your last-used mode (work item or intake). With the panel open, the same shortcut switches between the two. Close the panel with Escape, Discard, or the close button.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 400)
            Text("You can close this window; Foil will keep running in the background.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)
            HStack(spacing: 12) {
                Button("Open quick capture") {
                    environment.quickPanel.show()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .buttonStyle(.borderedProminent)
                Button("Settings…") {
                    openSettings()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
        .environmentObject(FoilEnvironment())
}
