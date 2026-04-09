//
//  QuickCreateWorkItemView.swift
//  Foil
//

import AppKit
import SwiftUI

struct QuickCreateWorkItemView: View {
    @EnvironmentObject private var viewModel: QuickCaptureViewModel
    @State private var showAssigneePopover = false
    @State private var showLabelPopover = false
    @State private var showModulePopover = false
    @State private var showParentPopover = false
    @State private var parentFilter = ""

    var body: some View {
        VStack(spacing: 0) {
            mainContent
            propertyBar
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onExitCommand { viewModel.cancel() }
    }

    // MARK: - Main content

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let err = viewModel.errorMessage {
                errorBanner(err)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }
            if let partial = viewModel.partialSuccessMessage {
                partialBanner(partial)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }

            projectRow
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 12)

            Divider().opacity(0.12)

            // Title field
            TextField("Title", text: $viewModel.title)
                .font(.system(size: 16))
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .onSubmit { Task { await viewModel.submit() } }

            // Description field — TextField with vertical axis keeps placeholder perfectly aligned
            TextField("Click to add description", text: $viewModel.description, axis: .vertical)
                .font(.system(size: 13))
                .textFieldStyle(.plain)
                .lineLimit(3...)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 10)
                .onKeyPress { press in
                    guard press.key == .return else { return .ignored }
                    if press.modifiers.contains(.shift) {
                        return .ignored
                    }
                    let titleOK = !viewModel.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    guard titleOK, !viewModel.isSubmitting else { return .ignored }
                    Task { await viewModel.submit() }
                    return .handled
                }
        }
    }

    // MARK: - Project row

    private var projectRow: some View {
        HStack(alignment: .center, spacing: 8) {
            if viewModel.isLoadingProjects {
                Text("Loading projects…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                ProgressView().controlSize(.mini)
            } else if viewModel.projects.isEmpty {
                Text("No projects in this workspace")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                ProjectNSPopUpPicker(
                    selection: $viewModel.selectedProjectId,
                    projects: viewModel.projects
                )
                .fixedSize(horizontal: true, vertical: true)
                if viewModel.isLoadingProjectMeta {
                    ProgressView().controlSize(.mini)
                }
            }
        }
        .task(id: viewModel.selectedProjectId) {
            guard !viewModel.isLoadingProjects,
                  let pid = viewModel.selectedProjectId,
                  viewModel.projects.contains(where: { $0.id == pid })
            else { return }
            await viewModel.onProjectChanged()
        }
    }

    // MARK: - Property chip bar
    // Order matches Plane UI: Status | Priority | Assignees | Labels | Start | Due | Cycles | Modules | Parent

    private var propertyBar: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.12)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    stateChip
                    priorityChip
                    assigneeChip
                    labelChip
                    DateChip(icon: "calendar.badge.clock", placeholder: "Start date", date: $viewModel.startDate)
                    DateChip(icon: "calendar", placeholder: "Due date", date: $viewModel.targetDate)
                    if !viewModel.cycles.isEmpty { cycleChip }
                    if !viewModel.modules.isEmpty { moduleChip }
                    parentChip
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
            }
        }
    }

    // MARK: - Individual chips

    private var stateChip: some View {
        Menu {
            Button { viewModel.selectedStateId = nil } label: {
                Label("None", systemImage: "circle")
            }
            if !viewModel.states.isEmpty {
                Divider()
                ForEach(viewModel.states) { s in
                    Button { viewModel.selectedStateId = s.id } label: {
                        Label(s.name ?? s.id, systemImage: stateSystemImage(s.group))
                    }
                }
            }
        } label: {
            chipLabel(
                systemImage: stateSystemImage(selectedState?.group),
                imageColor: stateColor(selectedState?.group),
                text: selectedState?.name ?? "Status"
            )
        }
        .menuIndicator(.hidden)
        .menuStyle(.borderlessButton)
        .fixedSize()
        .chipStyle()
    }

    private var priorityChip: some View {
        Menu {
            ForEach(["none", "urgent", "high", "medium", "low"], id: \.self) { p in
                Button { viewModel.priority = p } label: {
                    Label(p.capitalized, systemImage: prioritySystemImage(p))
                }
            }
        } label: {
            chipLabel(
                systemImage: prioritySystemImage(viewModel.priority),
                imageColor: priorityColor(viewModel.priority),
                text: viewModel.priority == "none" ? "Priority" : viewModel.priority.capitalized
            )
        }
        .menuIndicator(.hidden)
        .menuStyle(.borderlessButton)
        .fixedSize()
        .chipStyle()
    }

    private var parentChip: some View {
        Button {
            showParentPopover.toggle()
        } label: {
            textChipLabel(
                text: selectedParentLine ?? "Parent",
                accent: viewModel.selectedParentId != nil ? Color.accentColor : nil
            )
        }
        .buttonStyle(.plain)
        .chipStyle()
        // Popover content is hosted in a separate window on macOS; it does not reliably
        // inherit `@EnvironmentObject` from an NSHostingController-backed panel.
        .popover(isPresented: $showParentPopover, arrowEdge: .bottom) {
            parentPickerPopover
                .environmentObject(viewModel)
        }
        .onChange(of: showParentPopover) { _, isOn in
            if !isOn { parentFilter = "" }
        }
    }

    private var assigneeChip: some View {
        Button { showAssigneePopover.toggle() } label: {
            chipLabel(
                systemImage: "person",
                imageColor: viewModel.selectedAssigneeIds.isEmpty ? .secondary : Color.accentColor,
                text: selectedAssigneesText ?? "Assignees"
            )
        }
        .buttonStyle(.plain)
        .chipStyle()
        .popover(isPresented: $showAssigneePopover, arrowEdge: .bottom) {
            multiSelectPopover(
                title: "Assignees",
                items: viewModel.members.map { (id: $0.id, name: $0.resolvedName) },
                selected: $viewModel.selectedAssigneeIds
            )
        }
    }

    private var labelChip: some View {
        Button { showLabelPopover.toggle() } label: {
            chipLabel(
                systemImage: "tag",
                imageColor: viewModel.selectedLabelIds.isEmpty ? .secondary : Color.accentColor,
                text: selectedLabelsText ?? "Labels"
            )
        }
        .buttonStyle(.plain)
        .chipStyle()
        .popover(isPresented: $showLabelPopover, arrowEdge: .bottom) {
            multiSelectPopover(
                title: "Labels",
                items: viewModel.labels.map { (id: $0.id, name: $0.name ?? $0.id) },
                selected: $viewModel.selectedLabelIds
            )
        }
    }

    private var cycleChip: some View {
        Menu {
            Button { viewModel.selectedCycleId = nil } label: { Label("None", systemImage: "circle") }
            Divider()
            ForEach(viewModel.cycles) { c in
                Button { viewModel.selectedCycleId = c.id } label: { Text(c.name ?? c.id) }
            }
        } label: {
            chipLabel(
                systemImage: "arrow.2.circlepath",
                imageColor: viewModel.selectedCycleId == nil ? .secondary : Color.accentColor,
                text: selectedCycleName ?? "Cycle"
            )
        }
        .menuIndicator(.hidden)
        .menuStyle(.borderlessButton)
        .fixedSize()
        .chipStyle()
    }

    // Modules are multi-select (Plane supports adding a work item to multiple modules)
    private var moduleChip: some View {
        Button { showModulePopover.toggle() } label: {
            chipLabel(
                systemImage: "square.3.layers.3d",
                imageColor: viewModel.selectedModuleIds.isEmpty ? .secondary : Color.accentColor,
                text: selectedModulesText ?? "Modules"
            )
        }
        .buttonStyle(.plain)
        .chipStyle()
        .popover(isPresented: $showModulePopover, arrowEdge: .bottom) {
            multiSelectPopover(
                title: "Modules",
                items: viewModel.modules.map { (id: $0.id, name: $0.name ?? $0.id) },
                selected: $viewModel.selectedModuleIds
            )
        }
    }

    // MARK: - Footer
    // Layout: [Spacer] [Create more toggle] [Discard] [Save]

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer()

            Toggle(isOn: $viewModel.createMore) {
                Text("Create more")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            Button("Discard") { viewModel.cancel() }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.system(size: 13))

            Button {
                Task { await viewModel.submit() }
            } label: {
                if viewModel.isSubmitting {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Saving…")
                    }
                } else {
                    Text("Save")
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(viewModel.isSubmitting || viewModel.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 1)
        }
    }

    // MARK: - Reusable chip label

    @ViewBuilder
    private func chipLabel(systemImage: String, imageColor: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 11))
                .foregroundStyle(imageColor)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }

    // MARK: - Multi-select popover

    @ViewBuilder
    private func multiSelectPopover(
        title: String,
        items: [(id: String, name: String)],
        selected: Binding<Set<String>>
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)
            Divider()
            if items.isEmpty {
                Text("None available")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(items, id: \.id) { item in
                            Toggle(isOn: Binding(
                                get: { selected.wrappedValue.contains(item.id) },
                                set: { on in
                                    if on { selected.wrappedValue.insert(item.id) }
                                    else { selected.wrappedValue.remove(item.id) }
                                }
                            )) {
                                Text(item.name).font(.system(size: 12))
                            }
                            .toggleStyle(.checkbox)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 220)
            }
        }
        .frame(minWidth: 180)
    }

    // MARK: - Banners

    private func errorBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func partialBanner(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                if let id = viewModel.partialIssueId {
                    Button("Copy issue ID") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(id, forType: .string)
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
                Button("Close") { viewModel.dismissKeepingPartialInfo() }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Computed helpers

    private var selectedState: PlaneState? {
        viewModel.states.first(where: { $0.id == viewModel.selectedStateId })
    }

    private var selectedAssigneesText: String? {
        let names = viewModel.members
            .filter { viewModel.selectedAssigneeIds.contains($0.id) }
            .map(\.resolvedName)
        guard !names.isEmpty else { return nil }
        return names.count == 1 ? names[0] : "\(names[0]) +\(names.count - 1)"
    }

    private var selectedLabelsText: String? {
        let names = viewModel.labels
            .filter { viewModel.selectedLabelIds.contains($0.id) }
            .compactMap(\.name)
        guard !names.isEmpty else { return nil }
        return names.count == 1 ? names[0] : "\(names[0]) +\(names.count - 1)"
    }

    private var selectedCycleName: String? {
        viewModel.cycles.first(where: { $0.id == viewModel.selectedCycleId })?.name
    }

    private var selectedModulesText: String? {
        let names = viewModel.modules
            .filter { viewModel.selectedModuleIds.contains($0.id) }
            .compactMap(\.name)
        guard !names.isEmpty else { return nil }
        return names.count == 1 ? names[0] : "\(names[0]) +\(names.count - 1)"
    }

    private var selectedParentLine: String? {
        guard let pid = viewModel.selectedParentId else { return nil }
        if let w = viewModel.workItems.first(where: { $0.id == pid }) {
            return w.displayLine
        }
        return "Work item \(pid.prefix(8))…"
    }

    // MARK: - State / priority helpers

    private func stateSystemImage(_ group: String?) -> String {
        switch group?.lowercased() {
        case "started":   return "circle.dotted"
        case "completed": return "checkmark.circle.fill"
        case "cancelled": return "xmark.circle.fill"
        default:          return "circle"
        }
    }

    private func stateColor(_ group: String?) -> Color {
        switch group?.lowercased() {
        case "started":   return .orange
        case "completed": return .green
        case "cancelled": return .secondary
        default:          return .secondary
        }
    }

    private func prioritySystemImage(_ priority: String) -> String {
        switch priority {
        case "urgent": return "exclamationmark.circle.fill"
        case "high":   return "arrow.up.circle.fill"
        case "medium": return "minus.circle.fill"
        case "low":    return "arrow.down.circle.fill"
        default:       return "circle"
        }
    }

    private func priorityColor(_ priority: String) -> Color {
        switch priority {
        case "urgent": return .red
        case "high":   return .orange
        case "medium": return .yellow
        case "low":    return .blue
        default:       return .secondary
        }
    }

    /// Parent chip (text-only; status/priority use `chipLabel` + SF Symbols above).
    @ViewBuilder
    private func textChipLabel(text: String, accent: Color?) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(accent ?? .secondary)
            .lineLimit(1)
    }

    private var parentPickerPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Parent work item")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)
            Divider()
            TextField("Filter by title", text: $parentFilter)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            if viewModel.isLoadingWorkItems {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Loading work items…")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
            } else if let err = viewModel.workItemsLoadError {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        Button("None") {
                            viewModel.selectedParentId = nil
                            showParentPopover = false
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        ForEach(filteredParentCandidates) { item in
                            Button {
                                viewModel.selectedParentId = item.id
                                showParentPopover = false
                            } label: {
                                Text(item.displayLine)
                                    .font(.system(size: 12))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(minHeight: 280, maxHeight: 420)
            }
        }
        .frame(minWidth: 260)
        .onAppear {
            Task { await viewModel.loadWorkItemsForParentPickerIfNeeded() }
        }
    }

    private var filteredParentCandidates: [PlaneWorkItemSummary] {
        let qRaw = parentFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let q = qRaw.lowercased()
        let qDigits = qRaw.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard !q.isEmpty else { return viewModel.workItems }
        return viewModel.workItems.filter { item in
            if let name = item.name?.lowercased(), name.contains(q) { return true }
            if let sid = item.sequenceId {
                if String(sid).contains(qDigits) { return true }
                if q.hasPrefix("#"), String(sid).contains(String(q.dropFirst())) { return true }
            }
            return item.id.lowercased().contains(q)
        }
    }
}

// MARK: - Chip style modifier

private extension View {
    func chipStyle() -> some View {
        self
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
    }
}

// MARK: - Date chip using native compact DatePicker

private struct DateChip: View {
    let icon: String
    let placeholder: String
    @Binding var date: Date?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(date == nil ? Color.secondary : Color.accentColor)

            if date != nil {
                // Compact DatePicker opens its own native calendar popover — no custom popover needed
                DatePicker(
                    "",
                    selection: Binding(
                        get: { date ?? Date() },
                        set: { date = $0 }
                    ),
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .labelsHidden()
                .fixedSize()

                Button { date = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 2)
            } else {
                Button(placeholder) { date = Date() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .fixedSize()
    }
}
