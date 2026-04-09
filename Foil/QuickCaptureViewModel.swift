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

    init(environment: FoilEnvironment) {
        self.environment = environment
    }

    func resetForDisplay() {
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
        if !projects.isEmpty { return }
        isLoadingProjects = true
        errorMessage = nil
        defer { isLoadingProjects = false }
        do {
            let raw = try await client.listProjects()
            projects = raw.filter { $0.isMember != false }
            FoilLog.ui("Loaded \(projects.count) project(s) in picker")
            if selectedProjectId == nil || projects.contains(where: { $0.id == selectedProjectId }) == false {
                selectedProjectId = projects.first?.id
            }
            // Metadata loads from `QuickCreateWorkItemView` via `.task(id: selectedProjectId)` so it runs
            // when the picker appears (and whenever the user switches projects).
        } catch {
            FoilLog.ui("loadProjects failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
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
    }

    func cancel() {
        onDismissPanel?()
    }

    func dismissKeepingPartialInfo() {
        onDismissPanel?()
    }
}
