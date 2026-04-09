//
//  ProjectNSPopUpPicker.swift
//  Foil
//

import AppKit
import SwiftUI

/// Uses AppKit `NSPopUpButton` so each project uses a plain `NSMenuItem` title string.
/// SwiftUI `Menu` / `.pickerStyle(.menu)` on macOS often drops composite row content and shows only the first glyph (emoji).
struct ProjectNSPopUpPicker: NSViewRepresentable {
    @Binding var selection: String?
    var projects: [PlaneProject]

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectionChanged(_:))
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.sync(
            button: button,
            selection: $selection,
            projects: projects
        )
    }

    final class Coordinator: NSObject {
        private var selectionBinding: Binding<String?>?
        private var projects: [PlaneProject] = []

        func sync(button: NSPopUpButton, selection: Binding<String?>, projects: [PlaneProject]) {
            selectionBinding = selection
            self.projects = projects

            let titles = projects.map(\.pickerMenuTitle)
            let needsRebuild = button.numberOfItems != projects.count
                || !zip(0 ..< projects.count, titles).allSatisfy { idx, title in
                    guard idx < button.numberOfItems else { return false }
                    return button.item(at: idx)?.title == title
                }

            if needsRebuild {
                let target = button.target
                let action = button.action
                button.target = nil
                button.action = nil
                button.removeAllItems()
                for t in titles {
                    button.addItem(withTitle: t)
                }
                button.target = target
                button.action = action
                button.sizeToFit()
                button.invalidateIntrinsicContentSize()
            }

            guard !projects.isEmpty else { return }

            let desiredIndex: Int = {
                if let sid = selection.wrappedValue, let i = projects.firstIndex(where: { $0.id == sid }) {
                    return i
                }
                return 0
            }()

            guard desiredIndex < button.numberOfItems else { return }
            if button.indexOfSelectedItem != desiredIndex {
                let target = button.target
                let action = button.action
                button.target = nil
                button.action = nil
                button.selectItem(at: desiredIndex)
                button.target = target
                button.action = action
            }
        }

        @objc func selectionChanged(_ sender: NSPopUpButton) {
            let idx = sender.indexOfSelectedItem
            guard idx >= 0, idx < projects.count, let binding = selectionBinding else { return }
            let newId = projects[idx].id
            if binding.wrappedValue != newId {
                binding.wrappedValue = newId
            }
        }
    }
}
