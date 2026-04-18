//
//  MarketingVersion.swift
//  Foil
//

import Foundation

/// Parses `YYYY.MM.patch`-style strings (from `CFBundleShortVersionString` or GitHub `tag_name` without `v`) for ordering.
struct MarketingVersion: Comparable, Equatable {
    private let segments: [Int]

    init?(parsing string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var parts: [Int] = []
        for piece in trimmed.split(separator: ".", omittingEmptySubsequences: false) {
            guard let n = Int(piece), n >= 0 else { return nil }
            parts.append(n)
        }
        guard !parts.isEmpty else { return nil }
        self.segments = parts
    }

    /// Strips a single leading `v` or `V`, then parses dotted numeric segments.
    static func parseFromGitTag(_ name: String) -> MarketingVersion? {
        var s = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.first == "v" || s.first == "V" { s.removeFirst() }
        return MarketingVersion(parsing: s)
    }

    static func == (lhs: MarketingVersion, rhs: MarketingVersion) -> Bool {
        lhs.segments == rhs.segments
    }

    static func < (lhs: MarketingVersion, rhs: MarketingVersion) -> Bool {
        let maxCount = max(lhs.segments.count, rhs.segments.count)
        for i in 0..<maxCount {
            let a = i < lhs.segments.count ? lhs.segments[i] : 0
            let b = i < rhs.segments.count ? rhs.segments[i] : 0
            if a != b { return a < b }
        }
        return false
    }
}
