//
//  IntakeCreationService.swift
//  Foil
//

import Foundation

struct IntakeCreationInput {
    var name: String
    var description: String
    var priority: String?
    var assigneeIds: [String]
    var labelIds: [String]
    var targetDate: Date?
}

struct IntakeCreationService {
    let client: PlaneAPIClient

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()

    func create(projectId: String, input: IntakeCreationInput) async throws {
        let strippedDesc = input.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = PlaneCreateIntakeIssueRequest(
            issue: PlaneIntakeIssuePayload(
                name: input.name.trimmingCharacters(in: .whitespacesAndNewlines),
                description: strippedDesc.isEmpty ? nil : strippedDesc,
                priority: input.priority,
                assignees: input.assigneeIds.isEmpty ? nil : input.assigneeIds,
                labels: input.labelIds.isEmpty ? nil : input.labelIds,
                targetDate: input.targetDate.map { Self.isoFormatter.string(from: $0) }
            )
        )
        let created = try await client.createIntakeIssue(projectId: projectId, body: body)
        guard let issueId = created.id, !issueId.isEmpty else {
            throw PlaneAPIError.decoding(NSError(domain: "Foil", code: 5, userInfo: [NSLocalizedDescriptionKey: "Missing issue id after intake create"]))
        }
    }
}
