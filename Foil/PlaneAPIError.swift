//
//  PlaneAPIError.swift
//  Foil
//

import Foundation

enum PlaneAPIError: LocalizedError {
    case invalidURL
    case notConfigured
    case httpStatus(Int, String?)
    case decoding(Error)
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The API URL is invalid."
        case .notConfigured:
            return "Plane is not configured yet."
        case let .httpStatus(code, body):
            if let body, !body.isEmpty {
                return "Server error (\(code)): \(body)"
            }
            return "Server error (\(code))."
        case let .decoding(err):
            return "Could not read response: \(err.localizedDescription)"
        case let .network(err):
            return err.localizedDescription
        }
    }
}
