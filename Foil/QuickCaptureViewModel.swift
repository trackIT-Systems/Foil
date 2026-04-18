//
//  QuickCaptureViewModel.swift
//  Foil
//

import Combine
import SwiftUI

@MainActor
final class QuickCaptureViewModel: ObservableObject {
    private unowned let environment: FoilEnvironment
    var onDismissPanel: (() -> Void)?

    @Published var projects: [PlaneProject] = []
    @Published var selectedProjectId: String?
    @Published var states: [PlaneState] = []
    @Published var cycles: [PlaneCycle] = []
    @Published var modules: [PlaneModule] = []
    @Published var labels: [PlaneLabel] = []
    @Published var workItemTypes: [PlaneWorkItemType] = []
    @Published var members: [PlaneMember] = []

    @Published var isLoadingProjects = false
    @Published var isLoadingProjectMeta = false
    @Published var isSubmitting = false
    @Published var errorMessage: String?
    @Published var partialSuccessMessage: String?
    @Published var partialIssueId: String?

    @Published var title = ""
    @Published var description = ""
    @Published var priority: String = "none"
    @Published var selectedStateId: String?
    @Published var selectedTypeId: String?
    @Published var selectedCycleId: String?
    @Published var selectedModuleIds: Set<String> = []
    @Published var selectedAssigneeIds: Set<String> = []
    @Published var selectedLabelIds: Set<String> = []
    @Published var selectedParentId: String?
    @Published var workItems: [PlaneWorkItemSummary] = []
    @Published var isLoadingWorkItems = false
    @Published var workItemsLoadError: String?
    @Published var startDate: Date?
    @Published var targetDate: Date?
    @Published var pointText = ""
    @Published var isDraft = false
    @Published var createMore = false

    /// Workspace projects from the last successful `listProjects` fetch (unfiltered).
    private var cachedProjectsRaw: [PlaneProject] = []

    init(environment: FoilEnvironment) {
        self.environment = environment
    }

    /// Clears cached project rows so the next `loadProjectsIfNeeded()` hits the API (e.g. after changing list endpoints).
    func invalidateProjectsCache() {
        cachedProjectsRaw = []
        projects = []
    }

    func resetForDisplay() {
        clearFormForModeSwitch()
    }

    /// Clears captured fields when the panel opens or when switching work item ↔ intake (mode is unchanged on open).
    func clearFormForModeSwitch() {
        errorMessage = nil
        partialSuccessMessage = nil
        partialIssueId = nil
        title = ""
        description = ""
        priority = "none"
        selectedStateId = nil
        selectedTypeId = nil
        selectedCycleId = nil
        selectedModuleIds = []
        selectedAssigneeIds = []
        selectedLabelIds = []
        selectedParentId = nil
        workItems = []
        workItemsLoadError = nil
        startDate = nil
        targetDate = nil
        pointText = ""
        isDraft = false
    }

    func loadProjectsIfNeeded() async {
        guard let client = environment.makeAPIClient() else {
            errorMessage = PlaneAPIError.notConfigured.localizedDescription
            return
        }
        if cachedProjectsRaw.isEmpty {
            isLoadingProjects = true
            errorMessage = nil
            defer { isLoadingProjects = false }
            do {
                cachedProjectsRaw = try await client.listProjects()
                FoilLog.ui("Fetched \(cachedProjectsRaw.count) workspace project(s)")
                await ensureIntakeFlagsFromDetailsIfNeeded(client: client)
            } catch {
                FoilLog.ui("loadProjects failed: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
                return
            }
        }
        applyProjectFilterForCurrentMode()
    }

    /// List responses may omit `intake_view`; detail `GET .../projects/{id}/` includes it (Plane API).
    func ensureIntakeFlagsFromDetailsIfNeeded() async {
        guard let client = environment.makeAPIClient() else { return }
        await ensureIntakeFlagsFromDetailsIfNeeded(client: client)
    }

    private func ensureIntakeFlagsFromDetailsIfNeeded(client: PlaneAPIClient) async {
        guard environment.config.quickCaptureMode == .intake else { return }
        let ambiguous = cachedProjectsRaw.filter { $0.intakeView == nil }
        guard !ambiguous.isEmpty else { return }
        FoilLog.ui("Merging intake_view from project details for \(ambiguous.count) project(s)")
        var detailById: [String: PlaneProject] = [:]
        await withTaskGroup(of: (String, PlaneProject?).self) { group in
            for p in ambiguous {
                group.addTask {
                    do {
                        let d = try await client.getProject(projectId: p.id)
                        return (p.id, d)
                    } catch {
                        FoilLog.ui("getProject(\(p.id)) failed: \(error.localizedDescription)")
                        return (p.id, nil)
                    }
                }
            }
            for await (id, detail) in group {
                if let detail { detailById[id] = detail }
            }
        }
        guard !detailById.isEmpty else { return }
        cachedProjectsRaw = cachedProjectsRaw.map { detailById[$0.id] ?? $0 }
    }

    /// Rebuilds `projects` for the current quick capture tab (member list vs intake-enabled list).
    func applyProjectFilterForCurrentMode() {
        guard !cachedProjectsRaw.isEmpty else {
            projects = []
            return
        }
        let mode = environment.config.quickCaptureMode
        let filtered: [PlaneProject]
        switch mode {
        case .workItem:
            filtered = cachedProjectsRaw.filter { $0.isMember != false }
        case .intake:
            filtered = cachedProjectsRaw.filter { $0.intakeView == true }
        }
        projects = filtered
        if selectedProjectId == nil || !filtered.contains(where: { $0.id == selectedProjectId }) {
            selectedProjectId = filtered.first?.id
        }
        FoilLog.ui("Project picker [\(mode)]: \(filtered.count) project(s)")
    }

    func onProjectChanged() async {
        guard let pid = selectedProjectId, let client = environment.makeAPIClient() else { return }
        selectedStateId = nil
        selectedTypeId = nil
        selectedCycleId = nil
        selectedModuleIds = []
        selectedAssigneeIds = []
        selectedLabelIds = []
        selectedParentId = nil
        workItems = []
        workItemsLoadError = nil
        await loadProjectMetadata(projectId: pid, client: client)
    }

    private func loadProjectMetadata(projectId: String, client: PlaneAPIClient) async {
        isLoadingProjectMeta = true
        errorMessage = nil
        defer { isLoadingProjectMeta = false }
        do {
            async let s = client.listStates(projectId: projectId)
            async let c = client.listCycles(projectId: projectId)
            async let m = client.listModules(projectId: projectId)
            async let l = client.listProjectLabelsBestEffort()
            async let t = client.listWorkItemTypes(projectId: projectId)
            async let mem = client.listProjectMembers(projectId: projectId)
            let (st, cy, mo, ty, me) = try await (s, c, m, t, mem)
            let la = await l
            states = st
            cycles = cy
            modules = mo
            let filteredLabels = la.filter { lab in
                guard let p = lab.project else { return true }
                return p == projectId
            }
            labels = filteredLabels.isEmpty ? la : filteredLabels
            workItemTypes = ty
            members = me
        } catch {
            FoilLog.ui("loadProjectMetadata failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            states = []
            cycles = []
            modules = []
            labels = []
            workItemTypes = []
            members = []
        }
    }

    /// Loads all work items for the parent picker (on-demand; can be slow on huge projects).
    func loadWorkItemsForParentPickerIfNeeded() async {
        guard let projectId = selectedProjectId, let client = environment.makeAPIClient() else { return }
        if isLoadingWorkItems { return }
        if !workItems.isEmpty, workItemsLoadError == nil { return }
        isLoadingWorkItems = true
        workItemsLoadError = nil
        defer { isLoadingWorkItems = false }
        do {
            workItems = try await client.listWorkItems(projectId: projectId)
        } catch {
            FoilLog.ui("listWorkItems failed: \(error.localizedDescription)")
            workItems = []
            workItemsLoadError = error.localizedDescription
        }
    }

    func submit() async {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "Title is required."
            return
        }
        guard let projectId = selectedProjectId, let client = environment.makeAPIClient() else {
            errorMessage = PlaneAPIError.notConfigured.localizedDescription
            return
        }
        isSubmitting = true
        errorMessage = nil
        partialSuccessMessage = nil
        partialIssueId = nil
        defer { isSubmitting = false }
        switch environment.config.quickCaptureMode {
        case .workItem:
            let point = Int(pointText.trimmingCharacters(in: .whitespacesAndNewlines))
            let input = WorkItemCreationInput(
                name: name,
                description: description,
                priority: priority == "none" ? nil : priority,
                stateId: selectedStateId,
                parentId: selectedParentId,
                assigneeIds: Array(selectedAssigneeIds),
                labelIds: Array(selectedLabelIds),
                typeId: selectedTypeId,
                cycleId: selectedCycleId,
                moduleIds: Array(selectedModuleIds),
                startDate: startDate,
                targetDate: targetDate,
                point: point,
                isDraft: isDraft
            )
            let service = WorkItemCreationService(client: client)
            FoilLog.ui("Submit work item… project=\(projectId) title=\(name.prefix(80))")
            do {
                let result = try await service.create(projectId: projectId, input: input)
                switch result {
                case .success:
                    FoilLog.ui("Work item created")
                    if createMore {
                        resetForDisplay()
                    } else {
                        onDismissPanel?()
                    }
                case let .createdButLinkFailed(id, msg):
                    FoilLog.ui("Work item created id=\(id) but link failed: \(msg)")
                    partialIssueId = id
                    partialSuccessMessage = "Work item was created, but cycle or module linking failed: \(msg)"
                }
            } catch {
                FoilLog.ui("Submit failed: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
            }
        case .intake:
            let intakeInput = IntakeCreationInput(
                name: name,
                description: description,
                priority: priority == "none" ? nil : priority,
                assigneeIds: Array(selectedAssigneeIds),
                labelIds: Array(selectedLabelIds),
                targetDate: targetDate
            )
            let intakeService = IntakeCreationService(client: client)
            FoilLog.ui("Submit intake… project=\(projectId) title=\(name.prefix(80))")
            do {
                try await intakeService.create(projectId: projectId, input: intakeInput)
                FoilLog.ui("Intake item created")
                if createMore {
                    resetForDisplay()
                } else {
                    onDismissPanel?()
                }
            } catch {
                FoilLog.ui("Intake submit failed: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
            }
        }
    }

    func cancel() {
        onDismissPanel?()
    }

    func dismissKeepingPartialInfo() {
        onDismissPanel?()
    }
}
