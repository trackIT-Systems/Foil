//
//  GitHubLatestReleaseClient.swift
//  Foil
//

import Foundation

struct GitHubLatestReleaseDTO: Decodable {
    let name: String
    let htmlUrl: String
}

enum GitHubLatestReleaseError: LocalizedError, Equatable {
    case invalidRepositoryConfiguration
    case invalidResponse
    case httpStatus(code: Int, bodySnippet: String?)
    case decodingFailed
    case missingReleaseURL

    var errorDescription: String? {
        switch self {
        case .invalidRepositoryConfiguration:
            return "Update check is not configured for this build."
        case .invalidResponse:
            return "Could not read the update server response."
        case .httpStatus(let code, _):
            if code == 404 {
                return "No release was found (404)."
            }
            if code == 403 {
                return "Update check was denied (403). Try again later."
            }
            return "Update check failed (HTTP \(code))."
        case .decodingFailed:
            return "Could not parse the update response."
        case .missingReleaseURL:
            return "The release page URL was missing."
        }
    }
}

/// Fetches `GET /repos/{owner}/{repo}/releases/latest` from the GitHub REST API.
struct GitHubLatestReleaseClient: Sendable {
    private let session: URLSession

    init(session: URLSession = URLSession(configuration: .default)) {
        self.session = session
    }

    func fetchLatestRelease(owner: String, repo: String, userAgent: String) async throws -> GitHubLatestReleaseDTO {
        let o = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        let r = repo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !o.isEmpty, !r.isEmpty else {
            throw GitHubLatestReleaseError.invalidRepositoryConfiguration
        }
        let urlString = "https://api.github.com/repos/\(o)/\(r)/releases/latest"
        guard let url = URL(string: urlString) else {
            throw GitHubLatestReleaseError.invalidRepositoryConfiguration
        }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GitHubLatestReleaseError.invalidResponse
        }
        guard let http = response as? HTTPURLResponse else {
            throw GitHubLatestReleaseError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8).map { String($0.prefix(200)) }
            throw GitHubLatestReleaseError.httpStatus(code: http.statusCode, bodySnippet: snippet)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let dto = try? decoder.decode(GitHubLatestReleaseDTO.self, from: data) else {
            throw GitHubLatestReleaseError.decodingFailed
        }
        guard URL(string: dto.htmlUrl) != nil else {
            throw GitHubLatestReleaseError.missingReleaseURL
        }
        return dto
    }
}
