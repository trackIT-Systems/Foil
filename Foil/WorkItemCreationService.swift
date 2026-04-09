//
//  WorkItemCreationService.swift
//  Foil
//

import Foundation

struct WorkItemCreationInput {
    var name: String
    var description: String
    var priority: String?
    var stateId: String?
    var parentId: String?
    var assigneeIds: [String]
    var labelIds: [String]
    var typeId: String?
    var cycleId: String?
    var moduleIds: [String]
    var startDate: Date?
    var targetDate: Date?
    var point: Int?
    var isDraft: Bool
}

enum WorkItemCreationResult {
    case success
    case createdButLinkFailed(issueId: String, message: String)
}

struct WorkItemCreationService {
    let client: PlaneAPIClient

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()

    func create(projectId: String, input: WorkItemCreationInput) async throws -> WorkItemCreationResult {
        let stripped = input.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let html: String? = stripped.isEmpty ? nil : "<p>\(stripped.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\n", with: "<br/>"))</p>"

        let body = PlaneCreateWorkItemRequest(
            name: input.name.trimmingCharacters(in: .whitespacesAndNewlines),
            descriptionHtml: html,
            descriptionStripped: stripped.isEmpty ? nil : stripped,
            priority: input.priority,
            state: input.stateId,
            parent: input.parentId,
            assignees: input.assigneeIds.isEmpty ? nil : input.assigneeIds,
            labels: input.labelIds.isEmpty ? nil : input.labelIds,
            typeId: input.typeId,
            startDate: input.startDate.map { Self.isoFormatter.string(from: $0) },
            targetDate: input.targetDate.map { Self.isoFormatter.string(from: $0) },
            point: input.point,
            isDraft: input.isDraft ? true : nil
        )

        let created = try await client.createWorkItem(projectId: projectId, body: body)
        guard let issueId = created.id, !issueId.isEmpty else {
            throw PlaneAPIError.decoding(NSError(domain: "Foil", code: 4, userInfo: [NSLocalizedDescriptionKey: "Missing work item id after create"]))
        }

        var linkErrors: [String] = []
        if let cycleId = input.cycleId {
            do {
                try await client.addWorkItemsToCycle(projectId: projectId, cycleId: cycleId, issueIds: [issueId])
            } catch {
                linkErrors.append("Cycle: \(error.localizedDescription)")
            }
        }
        for moduleId in input.moduleIds {
            do {
                try await client.addWorkItemsToModule(projectId: projectId, moduleId: moduleId, issueIds: [issueId])
            } catch {
                linkErrors.append("Module \(moduleId): \(error.localizedDescription)")
            }
        }

        if linkErrors.isEmpty {
            return .success
        }
        return .createdButLinkFailed(issueId: issueId, message: linkErrors.joined(separator: " "))
    }
}
