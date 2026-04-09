//
//  OnboardingView.swift
//  Foil
//

import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var environment: FoilEnvironment
    @State private var token = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Connect to Plane")
                    .font(.largeTitle.weight(.bold))
                Text("Use your Plane API base URL, workspace slug, and a personal access token from Preferences → Personal access tokens.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Group {
                    labeled("API base URL") {
                        TextField("https://api.plane.so", text: $environment.config.apiRootInput)
                            .textFieldStyle(.roundedBorder)
                        Text("For self-hosted use the URL of your instance.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    labeled("Workspace slug") {
                        TextField("my-team", text: $environment.config.workspaceSlug)
                            .textFieldStyle(.roundedBorder)
                    }
                    labeled("Access token") {
                        SecureField("Paste token", text: $token)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.callout)
                }

                HStack {
                    Button("Save & continue") {
                        Task { await save() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaving || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .buttonStyle(.borderedProminent)
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    private func save() async {
        errorMessage = nil
        guard environment.config.normalizedAPIRootURL() != nil else {
            errorMessage = "Invalid API URL."
            return
        }
        let slug = environment.config.workspaceSlug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !slug.isEmpty else {
            errorMessage = "Workspace slug is required."
            return
        }
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else {
            errorMessage = "Token is required."
            return
        }
        isSaving = true
        defer { isSaving = false }
        FoilLog.app("Onboarding: validating connection (ping projects)…")
        do {
            try environment.config.markConfiguredSavingToken(t)
            guard let client = environment.makeAPIClient() else {
                FoilLog.app("Onboarding failed: makeAPIClient returned nil after save")
                errorMessage = "Configuration error."
                return
            }
            try await client.pingProjects()
            FoilLog.app("Onboarding: ping projects succeeded — hotkey refresh")
            environment.refreshHotkey()
        } catch {
            FoilLog.app("Onboarding failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            environment.config.signOut()
        }
    }
}
