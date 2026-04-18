//
//  PlaneAPIClient.swift
//  Foil
//

import Foundation

final class PlaneAPIClient: @unchecked Sendable {
    private let apiRoot: URL
    private let workspaceSlug: String
    private let token: String
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(apiRoot: URL, workspaceSlug: String, token: String) {
        self.apiRoot = apiRoot
        self.workspaceSlug = workspaceSlug
        self.token = token
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        self.session = URLSession(configuration: config)
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = dec
        self.encoder = JSONEncoder()
    }

    private func url(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        // Build by string concatenation to preserve trailing slashes.
        // Using appendingPathComponent strips trailing slashes, which causes POST requests
        // to follow a 301 redirect as GET (returning a 200 list instead of creating a resource).
        let rootStr = apiRoot.absoluteString
        let base = rootStr.hasSuffix("/") ? String(rootStr.dropLast()) : rootStr
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        guard var components = URLComponents(string: base + normalizedPath) else {
            throw PlaneAPIError.invalidURL
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let out = components.url else { throw PlaneAPIError.invalidURL }
        return out
    }

    private func authorizedRequest(url: URL, method: String, body: Data? = nil) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(token, forHTTPHeaderField: "X-API-Key")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        return req
    }

    private func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let method = request.httpMethod ?? "GET"
        let urlStr = request.url?.absoluteString ?? "(no URL)"
        let urlForLog = request.url ?? URL(fileURLWithPath: "/")
        FoilLog.apiRequest(method: method, url: urlForLog, bodyByteCount: request.httpBody?.count)
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                FoilLog.apiError("No HTTPURLResponse for \(method) \(urlStr)")
                throw PlaneAPIError.httpStatus(-1, nil)
            }
            FoilLog.apiResponse(method: method, url: urlStr, status: http.statusCode, body: data)
            return (data, http)
        } catch let e as PlaneAPIError {
            throw e
        } catch {
            FoilLog.apiError("Network \(method) \(urlStr): \(error.localizedDescription)")
            throw PlaneAPIError.network(error)
        }
    }

    /// Uses `next_cursor` whenever present unless `next_page_results` is explicitly `false`.
    /// Some Plane / self-hosted builds omit `next_page_results`; requiring `true` skipped remaining pages.
    private func nextCursorAfterPage<T>(_ page: PlanePaginatedResponse<T>) -> String? {
        if page.nextPageResults == false { return nil }
        guard let c = page.nextCursor?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty else { return nil }
        return c
    }

    private func decodeListChunk<T: Decodable>(_ type: T.Type, data: Data) throws -> (items: [T], nextCursor: String?) {
        if let page = try? decoder.decode(PlanePaginatedResponse<T>.self, from: data) {
            let next = nextCursorAfterPage(page)
            return (page.results ?? [], next)
        }
        if let arr = try? decoder.decode([T].self, from: data) {
            return (arr, nil)
        }
        throw PlaneAPIError.decoding(NSError(domain: "Foil", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unexpected list JSON"]))
    }

    // MARK: - Paginated GET

    func fetchAllPages<T: Decodable>(_ path: String, perPage: Int = 100, additionalQueryItems: [URLQueryItem] = []) async throws -> [T] {
        var all: [T] = []
        var cursor: String?
        repeat {
            var items: [URLQueryItem] = [URLQueryItem(name: "per_page", value: String(perPage))]
            items.append(contentsOf: additionalQueryItems)
            if let c = cursor { items.append(URLQueryItem(name: "cursor", value: c)) }
            let u = try url(path: path, queryItems: items)
            let req = authorizedRequest(url: u, method: "GET")
            let (data, http) = try await data(for: req)
            guard (200 ... 299).contains(http.statusCode) else {
                throw PlaneAPIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
            }
            let (chunk, next) = try decodeListChunk(T.self, data: data)
            all.append(contentsOf: chunk)
            if let n = next, !n.isEmpty {
                cursor = n
            } else {
                cursor = nil
            }
        } while cursor != nil
        return all
    }

    // MARK: - Projects

    /// Documented list endpoint: `GET /api/v1/workspaces/{slug}/projects/` (see Plane API reference).
    /// The non-standard `.../projects/details/` path returns **404** on `api.plane.so` and must not be used.
    func listProjects() async throws -> [PlaneProject] {
        try await fetchAllPages("/workspaces/\(workspaceSlug)/projects/")
    }

    /// Single-project fetch (detail serializer may include flags omitted from the list response).
    func getProject(projectId: String) async throws -> PlaneProject {
        let u = try url(path: "/workspaces/\(workspaceSlug)/projects/\(projectId)/")
        let req = authorizedRequest(url: u, method: "GET")
        let (data, http) = try await data(for: req)
        guard (200 ... 299).contains(http.statusCode) else {
            throw PlaneAPIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
        }
        return try decoder.decode(PlaneProject.self, from: data)
    }

    /// Workspace labels; failures are downgraded to empty (some self-hosted builds 500 on this route; unrelated to projects list).
    func listProjectLabelsBestEffort() async -> [PlaneLabel] {
        do {
            return try await listProjectLabels()
        } catch {
            // Avoid implying this broke the work-item form: labels are optional; log at app level only.
            FoilLog.app("Labels list skipped: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Project-scoped lists

    func listStates(projectId: String) async throws -> [PlaneState] {
        try await fetchAllPages("/workspaces/\(workspaceSlug)/projects/\(projectId)/states/")
    }

    func listCycles(projectId: String) async throws -> [PlaneCycle] {
        try await fetchAllPages("/workspaces/\(workspaceSlug)/projects/\(projectId)/cycles/")
    }

    func listModules(projectId: String) async throws -> [PlaneModule] {
        try await fetchAllPages("/workspaces/\(workspaceSlug)/projects/\(projectId)/modules/")
    }

    func listWorkItemTypes(projectId: String) async throws -> [PlaneWorkItemType] {
        try await fetchAllPages("/workspaces/\(workspaceSlug)/projects/\(projectId)/work-item-types/")
    }

    func listWorkItems(projectId: String) async throws -> [PlaneWorkItemSummary] {
        try await fetchAllPages("/workspaces/\(workspaceSlug)/projects/\(projectId)/work-items/")
    }

    func listProjectLabels() async throws -> [PlaneLabel] {
        try await fetchAllPages("/workspaces/\(workspaceSlug)/project-labels/")
    }

    func listProjectMembers(projectId: String) async throws -> [PlaneMember] {
        let u = try url(path: "/workspaces/\(workspaceSlug)/projects/\(projectId)/project-members/")
        let req = authorizedRequest(url: u, method: "GET")
        let (data, http) = try await data(for: req)
        guard (200 ... 299).contains(http.statusCode) else {
            throw PlaneAPIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
        }
        return try decodeProjectMembers(data)
    }

    private func decodeProjectMembers(_ data: Data) throws -> [PlaneMember] {
        if let page = try? decoder.decode(PlanePaginatedResponse<PlaneMember>.self, from: data), let r = page.results {
            return r
        }
        if let arr = try? decoder.decode([PlaneMember].self, from: data) {
            return arr
        }
        // Nested array [[member]]
        if let outer = try? JSONSerialization.jsonObject(with: data) as? [[Any]] {
            var out: [PlaneMember] = []
            for inner in outer {
                for item in inner {
                    if let obj = item as? [String: Any],
                       let json = try? JSONSerialization.data(withJSONObject: obj),
                       let m = try? decoder.decode(PlaneMember.self, from: json)
                    {
                        out.append(m)
                    }
                }
            }
            if !out.isEmpty { return out }
        }
        throw PlaneAPIError.decoding(NSError(domain: "Foil", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unexpected project-members JSON"]))
    }

    // MARK: - Create + link

    func createWorkItem(projectId: String, body: PlaneCreateWorkItemRequest) async throws -> PlaneWorkItemCreated {
        let u = try url(path: "/workspaces/\(workspaceSlug)/projects/\(projectId)/work-items/")
        let encoded = try encoder.encode(body)
        let req = authorizedRequest(url: u, method: "POST", body: encoded)
        let (data, http) = try await data(for: req)
        guard http.statusCode == 201 || (200 ... 299).contains(http.statusCode) else {
            throw PlaneAPIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
        }
        return try Self.parseCreatedWorkItemPayload(data: data, jsonDecoder: decoder, projectId: projectId)
    }

    func createIntakeIssue(projectId: String, body: PlaneCreateIntakeIssueRequest) async throws -> PlaneWorkItemCreated {
        let u = try url(path: "/workspaces/\(workspaceSlug)/projects/\(projectId)/intake-issues/")
        let encoded = try encoder.encode(body)
        let req = authorizedRequest(url: u, method: "POST", body: encoded)
        let (data, http) = try await data(for: req)
        guard http.statusCode == 201 || (200 ... 299).contains(http.statusCode) else {
            throw PlaneAPIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
        }
        return try Self.parseCreatedWorkItemPayload(data: data, jsonDecoder: decoder, projectId: projectId)
    }

    /// Decodes only `id` + `name` so a mistyped `sequence_id` (string vs int) cannot break the whole response.
    private struct WorkItemIdOnly: Decodable {
        let id: String?
        let name: String?

        enum CodingKeys: String, CodingKey {
            case id
            case name
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decodeIfPresent(String.self, forKey: .name)
            if let s = try? c.decodeIfPresent(String.self, forKey: .id) {
                id = s
            } else if let i = try? c.decodeIfPresent(Int.self, forKey: .id) {
                id = String(i)
            } else {
                id = nil
            }
        }
    }

    /// Some Plane instances return **200** with a large JSON payload where `id` is nested or uses alternate keys.
    private static func parseCreatedWorkItemPayload(data: Data, jsonDecoder: JSONDecoder, projectId: String) throws -> PlaneWorkItemCreated {
        let projectIdLower = projectId.lowercased()

        func accept(_ id: String?) -> String? {
            guard let id, !id.isEmpty, id.lowercased() != projectIdLower else { return nil }
            return id
        }

        // 1) Minimal decode — avoids failing on unrelated field type drift (e.g. sequence_id as string).
        if let stub = try? jsonDecoder.decode(WorkItemIdOnly.self, from: data), let id = accept(stub.id) {
            FoilLog.app("createWorkItem: parsed work item id=\(id) (minimal decode)")
            return PlaneWorkItemCreated(id: id, name: stub.name, sequenceId: nil)
        }

        if let direct = try? jsonDecoder.decode(PlaneWorkItemCreated.self, from: data), let id = accept(direct.id) {
            FoilLog.app("createWorkItem: parsed work item id=\(id) (full decode)")
            return direct
        }

        struct IssueWrap: Decodable {
            let issue: WorkItemIdOnly?
        }
        if let wrap = try? jsonDecoder.decode(IssueWrap.self, from: data),
           let id = accept(wrap.issue?.id)
        {
            FoilLog.app("createWorkItem: parsed work item id=\(id) (wrapped issue)")
            return PlaneWorkItemCreated(id: id, name: wrap.issue?.name, sequenceId: nil)
        }

        if let extracted = extractWorkItemIdFromJSON(data, projectId: projectId) {
            FoilLog.app("createWorkItem: extracted work item id=\(extracted) (JSON walk — verify in Plane if missing)")
            return PlaneWorkItemCreated(id: extracted, name: nil, sequenceId: nil)
        }

        let preview = String(data: data, encoding: .utf8).map { String($0.prefix(900)) } ?? "(non-utf8, \(data.count) bytes)"
        FoilLog.apiError("createWorkItem: could not find work item id. Body preview: \(preview)")
        throw PlaneAPIError.decoding(NSError(domain: "Foil", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not parse created work item id from response"]))
    }

    /// Best-effort extraction for self-hosted / version drift. Prefer objects that look like the issue (e.g. have `name`).
    private static func extractWorkItemIdFromJSON(_ data: Data, projectId: String) -> String? {
        let projectIdLower = projectId.lowercased()
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return nil }

        func stringId(_ any: Any?) -> String? {
            guard let any else { return nil }
            if let s = any as? String {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                return t.isEmpty ? nil : t
            }
            if let n = any as? Int { return String(n) }
            if let n = any as? UInt64 { return String(n) }
            return nil
        }

        func idFromDict(_ dict: [String: Any]) -> String? {
            for key in ["id", "ID", "issue_id", "uuid", "pk", "entity_id", "uid"] {
                if let s = stringId(dict[key]), s.lowercased() != projectIdLower { return s }
            }
            return nil
        }

        /// Strong signal: work items almost always return a `name` next to `id` at the issue root.
        func idFromIssueLikeDict(_ dict: [String: Any]) -> String? {
            let hasName = (dict["name"] as? String)?.isEmpty == false
            if hasName, let s = idFromDict(dict) { return s }
            return nil
        }

        if let dict = root as? [String: Any] {
            if let s = idFromIssueLikeDict(dict) { return s }
            if let s = idFromDict(dict) { return s }
            for containerKey in ["issue", "work_item", "data", "work_item_detail", "issue_detail", "result", "detail"] {
                guard let inner = dict[containerKey] as? [String: Any] else { continue }
                if let s = idFromIssueLikeDict(inner) { return s }
                if let s = idFromDict(inner) { return s }
                // One more level under `data` (some APIs nest twice).
                if containerKey == "data" {
                    for sub in ["issue", "work_item", "issue_detail"] {
                        if let nested = inner[sub] as? [String: Any] {
                            if let s = idFromIssueLikeDict(nested) { return s }
                            if let s = idFromDict(nested) { return s }
                        }
                    }
                }
            }
            if let results = dict["results"] as? [[String: Any]], let first = results.first {
                if let s = idFromIssueLikeDict(first) { return s }
                if let s = idFromDict(first) { return s }
            }
        }

        if let arr = root as? [[String: Any]], let first = arr.first {
            if let s = idFromIssueLikeDict(first) { return s }
            if let s = idFromDict(first) { return s }
        }
        return nil
    }

    func addWorkItemsToCycle(projectId: String, cycleId: String, issueIds: [String]) async throws {
        let u = try url(path: "/workspaces/\(workspaceSlug)/projects/\(projectId)/cycles/\(cycleId)/cycle-issues/")
        let encoded = try encoder.encode(PlaneCycleIssuesBody(issues: issueIds))
        let req = authorizedRequest(url: u, method: "POST", body: encoded)
        let (data, http) = try await data(for: req)
        guard (200 ... 299).contains(http.statusCode) else {
            throw PlaneAPIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
        }
        _ = data
    }

    func addWorkItemsToModule(projectId: String, moduleId: String, issueIds: [String]) async throws {
        let u = try url(path: "/workspaces/\(workspaceSlug)/projects/\(projectId)/modules/\(moduleId)/module-issues/")
        let encoded = try encoder.encode(PlaneModuleIssuesBody(issues: issueIds))
        let req = authorizedRequest(url: u, method: "POST", body: encoded)
        let (data, http) = try await data(for: req)
        guard (200 ... 299).contains(http.statusCode) else {
            throw PlaneAPIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
        }
        _ = data
    }

    /// Lightweight validation (e.g. after onboarding).
    func pingProjects() async throws {
        _ = try await listProjects()
    }
}
