//
//  PlaneAPIModels.swift
//  Foil
//

import Foundation

// MARK: - Pagination

struct PlanePaginatedResponse<T: Decodable>: Decodable {
    var results: [T]?
    var nextCursor: String?
    var nextPageResults: Bool?
}

// MARK: - Projects

/// Matches Plane web `TLogoProps` (`packages/types/src/common.ts`): `in_use` + `emoji` / `icon`.
struct PlaneLogoProps: Decodable, Hashable {
    let inUse: String?
    let emoji: PlaneLogoPropsEmoji?
    let icon: PlaneLogoPropsIcon?
}

struct PlaneLogoPropsEmoji: Decodable, Hashable {
    let value: String?
    let url: String?
}

struct PlaneLogoPropsIcon: Decodable, Hashable {
    let name: String?
    let color: String?
    let backgroundColor: String?
}

struct PlaneProject: Identifiable, Hashable {
    let id: String
    let name: String?
    let identifier: String?
    /// Legacy field; newer Plane instances store the glyph in `logo_props.emoji.value`.
    let emoji: String?
    /// Newer Plane UI (frimousse / logo picker) stores emoji or Lucide-style icon here.
    let logoProps: PlaneLogoProps?
    /// When present (Plane API), `false` means the current user is not a project member.
    let isMember: Bool?

    /// Human-readable name for UI (avoids raw UUIDs; some instances omit `name` in list payloads).
    var displayName: String {
        let n = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !n.isEmpty { return n }
        let idn = identifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !idn.isEmpty { return idn }
        return "Untitled project"
    }

    /// Plain string for `NSMenuItem` / `NSPopUpButton`. SwiftUI menus on macOS often drop multi-view rows and show only the emoji; AppKit titles are reliable.
    var pickerMenuTitle: String {
        let base = displayName
        if let ch = displayEmojiCharacter, !ch.isEmpty {
            return "\(ch)\u{00a0}\(base)"
        }
        if displayIconSystemName != nil {
            return "· \(base)"
        }
        return base
    }

    /// Text glyph for the project row when the API uses emoji (not icon mode).
    var displayEmojiCharacter: String? {
        if logoProps?.inUse == "icon" {
            return nil
        }
        if let v = logoProps?.emoji?.value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
            return PlaneProjectEmoji.displayString(from: v)
        }
        return PlaneProjectEmoji.displayString(from: emoji)
    }

    /// SF Symbol name when `logo_props.in_use == "icon"` (Lucide-style `icon.name` from Plane web).
    var displayIconSystemName: String? {
        guard logoProps?.inUse == "icon" else { return nil }
        guard let raw = logoProps?.icon?.name?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return PlaneProjectIcon.sfSymbol(forPlaneIconName: raw)
    }
}

extension PlaneProject: Decodable {
    enum CodingKeys: String, CodingKey {
        case id, name, identifier, emoji, logoProps, iconProp, isMember
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        identifier = try c.decodeIfPresent(String.self, forKey: .identifier)
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji)
        // Plane DB has both `logo_props` (current) and legacy `icon_prop`; list payloads may only include one.
        let fromLogo = try? c.decode(PlaneLogoProps.self, forKey: .logoProps)
        let fromIcon = try? c.decode(PlaneLogoProps.self, forKey: .iconProp)
        logoProps = Self.preferredLogoProps(fromLogo, fromIcon)
        isMember = try c.decodeIfPresent(Bool.self, forKey: .isMember)
    }

    /// Picks the richer of two logo blobs (same JSON shape in practice).
    private static func preferredLogoProps(_ a: PlaneLogoProps?, _ b: PlaneLogoProps?) -> PlaneLogoProps? {
        func score(_ p: PlaneLogoProps?) -> Int {
            guard let p else { return 0 }
            var s = 0
            if p.inUse != nil { s += 1 }
            if p.emoji?.value?.isEmpty == false { s += 2 }
            if p.icon?.name?.isEmpty == false { s += 2 }
            return s
        }
        return score(a) >= score(b) ? (a ?? b) : (b ?? a)
    }
}

enum PlaneProjectEmoji {
    /// Turns Plane `emoji` / `logo_props.emoji.value` into a display string.
    /// Plane often stores compound emoji as hyphen-separated **decimal** code points, e.g. `128736-65039` (U+1F4E0 + U+FE0F).
    static func displayString(from apiValue: String?) -> String? {
        let raw = apiValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return nil }

        if raw.contains("-") {
            let segments = raw.split(separator: "-", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if segments.count >= 2 {
                if let s = string(fromDecimalCodeSegments: segments) { return s }
                if let s = string(fromHexCodeSegments: segments) { return s }
            }
        }

        if let code = UInt32(raw), (1 ... 0x10FFFF).contains(code), let scalar = UnicodeScalar(code) {
            return String(Character(scalar))
        }
        if raw.count <= 8, let code = UInt32(raw, radix: 16), (1 ... 0x10FFFF).contains(code), let scalar = UnicodeScalar(code) {
            return String(Character(scalar))
        }
        return raw
    }

    private static func string(fromDecimalCodeSegments segments: [String]) -> String? {
        var scalars = [UnicodeScalar]()
        scalars.reserveCapacity(segments.count)
        for seg in segments {
            guard let code = UInt32(seg), (1 ... 0x10FFFF).contains(code), let u = UnicodeScalar(code) else {
                return nil
            }
            scalars.append(u)
        }
        return String(String.UnicodeScalarView(scalars))
    }

    private static func string(fromHexCodeSegments segments: [String]) -> String? {
        var scalars = [UnicodeScalar]()
        scalars.reserveCapacity(segments.count)
        for seg in segments {
            guard let code = UInt32(seg, radix: 16), (1 ... 0x10FFFF).contains(code), let u = UnicodeScalar(code) else {
                return nil
            }
            scalars.append(u)
        }
        return String(String.UnicodeScalarView(scalars))
    }
}

enum PlaneProjectIcon {
    /// Maps Plane/Lucide icon `name` values to SF Symbols (best effort).
    static func sfSymbol(forPlaneIconName name: String) -> String {
        let key = name.lowercased().replacingOccurrences(of: "-", with: "_")
        return map[key] ?? "cube.fill"
    }

    private static let map: [String: String] = [
        "rocket": "paperplane.fill",
        "layout_grid": "square.grid.2x2.fill",
        "folder": "folder.fill",
        "folder_open": "folder.fill",
        "briefcase": "briefcase.fill",
        "star": "star.fill",
        "heart": "heart.fill",
        "home": "house.fill",
        "settings": "gearshape.fill",
        "calendar": "calendar",
        "flag": "flag.fill",
        "zap": "bolt.fill",
        "target": "target",
        "layers": "square.stack.3d.up.fill",
        "box": "cube.box.fill",
        "package": "shippingbox.fill",
        "users": "person.3.fill",
        "user": "person.fill",
        "bell": "bell.fill",
        "mail": "envelope.fill",
        "coffee": "cup.and.saucer.fill",
        "music": "music.note",
        "camera": "camera.fill",
        "image": "photo.fill",
        "smile": "face.smiling",
        "sun": "sun.max.fill",
        "moon": "moon.fill",
        "cloud": "cloud.fill",
        "anchor": "anchor",
        "globe": "globe",
        "map": "map.fill",
        "compass": "location.north.circle.fill",
        "activity": "chart.line.uptrend.xyaxis",
        "trending_up": "chart.line.uptrend.xyaxis",
        "bar_chart": "chart.bar.fill",
        "pie_chart": "chart.pie.fill",
        "dollar_sign": "dollarsign.circle.fill",
        "shopping_cart": "cart.fill",
        "truck": "truck.box.fill",
        "wrench": "wrench.and.screwdriver.fill",
        "shield": "shield.fill",
        "lock": "lock.fill",
        "key": "key.fill",
        "book": "book.fill",
        "graduation_cap": "graduationcap.fill",
        "lightbulb": "lightbulb.fill",
        "feather": "leaf.fill",
        "hammer": "hammer.fill",
        "palette": "paintpalette.fill",
        "code": "chevron.left.forwardslash.chevron.right",
        "terminal": "terminal.fill",
        "cpu": "cpu.fill",
        "database": "cylinder.split.1x2",
        "server": "server.rack",
        "wifi": "wifi",
        "bluetooth": "dot.radiowaves.left.and.right",
        "battery": "battery.100",
        "watch": "applewatch",
        "smartphone": "iphone",
        "laptop": "laptopcomputer",
        "monitor": "display",
        "printer": "printer.fill",
        "paperclip": "paperclip",
        "link": "link",
        "bookmark": "bookmark.fill",
        "tag": "tag.fill",
        "inbox": "tray.fill",
        "send": "paperplane.fill",
        "archive": "archivebox.fill",
        "trash": "trash.fill",
        "edit": "pencil",
        "plus": "plus.circle.fill",
        "check": "checkmark.circle.fill",
        "x": "xmark.circle.fill",
        "alert_circle": "exclamationmark.circle.fill",
        "info": "info.circle.fill",
        "help_circle": "questionmark.circle.fill",
    ]
}

// MARK: - States

struct PlaneState: Decodable, Identifiable, Hashable {
    let id: String
    let name: String?
    let group: String?
    let color: String?
}

// MARK: - Members (project-members shape varies; keep tolerant)

struct PlaneMember: Decodable, Identifiable, Hashable {
    let id: String
    let displayName: String?
    let firstName: String?
    let lastName: String?
    let email: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case firstName = "first_name"
        case lastName = "last_name"
        case email
    }

    var resolvedName: String {
        if let d = displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty { return d }
        let fn = firstName ?? ""
        let ln = lastName ?? ""
        let joined = "\(fn) \(ln)".trimmingCharacters(in: .whitespacesAndNewlines)
        if !joined.isEmpty { return joined }
        return email ?? id
    }
}

// MARK: - Labels

struct PlaneLabel: Decodable, Identifiable, Hashable {
    let id: String
    let name: String?
    let project: String?
}

// MARK: - Work item types

struct PlaneWorkItemType: Decodable, Identifiable, Hashable {
    let id: String
    let name: String?
    let project: String?
}

// MARK: - Cycles / modules

struct PlaneCycle: Decodable, Identifiable, Hashable {
    let id: String
    let name: String?
}

struct PlaneModule: Decodable, Identifiable, Hashable {
    let id: String
    let name: String?
}

// MARK: - Work items (list / picker)

struct PlaneWorkItemSummary: Identifiable, Hashable {
    let id: String
    let name: String?
    let sequenceId: Int?

    var displayLine: String {
        let title = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let sid = sequenceId {
            if title.isEmpty { return "#\(sid)" }
            return "#\(sid) \(title)"
        }
        if !title.isEmpty { return title }
        return id
    }
}

extension PlaneWorkItemSummary: Decodable {
    enum CodingKeys: String, CodingKey {
        case id, name
        case sequenceId = "sequence_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        if let s = try? c.decode(String.self, forKey: .id) {
            id = s
        } else if let i = try? c.decode(Int.self, forKey: .id) {
            id = String(i)
        } else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "Missing work item id")
        }
        if let i = try? c.decode(Int.self, forKey: .sequenceId) {
            sequenceId = i
        } else if let s = try? c.decode(String.self, forKey: .sequenceId), let i = Int(s) {
            sequenceId = i
        } else {
            sequenceId = nil
        }
    }
}

// MARK: - Create work item

struct PlaneCreateWorkItemRequest: Encodable {
    var name: String
    var descriptionHtml: String?
    var descriptionStripped: String?
    var priority: String?
    var state: String?
    var parent: String?
    var assignees: [String]?
    var labels: [String]?
    var typeId: String?
    var startDate: String?
    var targetDate: String?
    var point: Int?
    var isDraft: Bool?

    enum CodingKeys: String, CodingKey {
        case name
        case descriptionHtml = "description_html"
        case descriptionStripped = "description_stripped"
        case priority
        case state
        case parent
        case assignees
        case labels
        case typeId = "type_id"
        case startDate = "start_date"
        case targetDate = "target_date"
        case point
        case isDraft = "is_draft"
    }
}

struct PlaneWorkItemCreated: Decodable {
    let id: String?
    let name: String?
    let sequenceId: Int?

    init(id: String?, name: String?, sequenceId: Int?) {
        self.id = id
        self.name = name
        self.sequenceId = sequenceId
    }
}

struct PlaneCycleIssuesBody: Encodable {
    let issues: [String]
}

struct PlaneModuleIssuesBody: Encodable {
    let issues: [String]
}
