import Foundation

/// 색 프리셋 팔레트. 태그 색은 hex 로 저장하고, 이건 빠른 선택용.
public enum TagColor: String, Codable, CaseIterable {
    case red, orange, yellow, green, teal, blue, purple, gray

    public var hex: String {
        switch self {
        case .red: return "#E24B4A"
        case .orange: return "#EF9F27"
        case .yellow: return "#E8C547"
        case .green: return "#22C55E"
        case .teal: return "#4FB3A3"
        case .blue: return "#7896C8"
        case .purple: return "#C77DFF"
        case .gray: return "#9A9A9A"
        }
    }
}

public enum HexColor {
    /// "#RRGGBB" ('#' 생략/소문자 허용) → 0...1 RGB. 형식이 틀리면 nil.
    public static func rgb(_ hex: String) -> (r: Double, g: Double, b: Double)? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }

    public static func hex(r: Double, g: Double, b: Double) -> String {
        func c(_ x: Double) -> Int { Int((min(max(x, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", c(r), c(g), c(b))
    }
}

public struct Tag: Codable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var colorHex: String

    public init(id: String = UUID().uuidString, name: String, colorHex: String) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }

    private enum CodingKeys: String, CodingKey { case id, name, colorHex, color }

    /// v1 파일(`color`: 프리셋 이름)도 읽는다.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        if let h = try c.decodeIfPresent(String.self, forKey: .colorHex) {
            colorHex = h
        } else {
            colorHex = try c.decode(TagColor.self, forKey: .color).hex
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(colorHex, forKey: .colorHex)
    }
}

public enum TagSelection: String, Codable { case single, multiple }

public struct TagGroup: Codable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var selection: TagSelection
    public var tags: [Tag]

    public init(id: String = UUID().uuidString, name: String, selection: TagSelection, tags: [Tag] = []) {
        self.id = id
        self.name = name
        self.selection = selection
        self.tags = tags
    }
}

public struct TagConfig: Codable, Equatable {
    public var groups: [TagGroup]
    public var sortGroupId: String?

    public init(groups: [TagGroup], sortGroupId: String?) {
        self.groups = groups
        self.sortGroupId = sortGroupId
    }

    /// 그룹 순서 → 그룹 안 태그 순서로 펼친 목록.
    public var allTags: [Tag] { groups.flatMap(\.tags) }

    public func group(of tagId: String) -> TagGroup? {
        groups.first { $0.tags.contains { $0.id == tagId } }
    }

    /// 정렬 기준 그룹. id 가 없는 그룹을 가리키면 첫 그룹, nil 이면 정렬 기준 없음.
    public var sortGroup: TagGroup? {
        guard let id = sortGroupId else { return nil }
        return groups.first { $0.id == id } ?? groups.first
    }

    /// 켜기: 하나만 그룹이면 같은 그룹의 다른 태그를 뺀다. 끄기: 그냥 뺀다. 모르는 태그는 무시.
    public func toggled(_ tagId: String, in ids: [String]) -> [String] {
        if ids.contains(tagId) { return ids.filter { $0 != tagId } }
        guard let g = group(of: tagId) else { return ids }
        var out = ids
        if g.selection == .single {
            let siblings = Set(g.tags.map(\.id))
            out.removeAll { siblings.contains($0) }
        }
        out.append(tagId)
        return out
    }

    /// 모르는 id 제거, 하나만 그룹은 태그 순서상 첫 번째만, 표시 순서로 반환.
    public func normalized(_ ids: [String]) -> [String] {
        groups.flatMap { g -> [String] in
            let mine = g.tags.map(\.id).filter(ids.contains)
            return g.selection == .single ? Array(mine.prefix(1)) : mine
        }
    }
}

public enum TagDefaults {
    public static let importanceGroupId = "importance"

    public static var config: TagConfig {
        TagConfig(groups: [TagGroup(id: importanceGroupId, name: "중요도", selection: .single, tags: [
            Tag(id: "urgent", name: "긴급", colorHex: TagColor.red.hex),
            Tag(id: "high", name: "높음", colorHex: TagColor.orange.hex),
            Tag(id: "normal", name: "보통", colorHex: TagColor.gray.hex),
            Tag(id: "low", name: "낮음", colorHex: TagColor.blue.hex),
        ])], sortGroupId: importanceGroupId)
    }
}

public struct TagStore {
    public let fileURL: URL

    public init(fileURL: URL = Paths.dataDir.appendingPathComponent("tags.json")) {
        self.fileURL = fileURL
    }

    private struct File: Codable {
        var version: Int
        var groups: [TagGroup]
        var sortGroupId: String?
    }

    /// 파일 없으면 기본값. v1(평평한 [Tag])은 '중요도'(하나만) 그룹으로 옮기고 v2 로 다시 쓴다.
    /// 파싱 실패면 tags.corrupt-<ts>.json 으로 옮기고 기본값.
    public func load() -> TagConfig {
        guard let data = try? Data(contentsOf: fileURL) else { return TagDefaults.config }
        let d = JSONDecoder()
        if let f = try? d.decode(File.self, from: data), f.version == 2 {
            return TagConfig(groups: f.groups, sortGroupId: f.sortGroupId)
        }
        if let tags = try? d.decode([Tag].self, from: data) {
            let id = TagDefaults.importanceGroupId
            let cfg = TagConfig(groups: [TagGroup(id: id, name: "중요도", selection: .single, tags: tags)], sortGroupId: id)
            try? save(cfg)
            return cfg
        }
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = fileURL.deletingLastPathComponent().appendingPathComponent("tags.corrupt-\(stamp).json")
        try? FileManager.default.moveItem(at: fileURL, to: backup)
        return TagDefaults.config
    }

    public func save(_ config: TagConfig) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        let f = File(version: 2, groups: config.groups, sortGroupId: config.sortGroupId)
        try e.encode(f).write(to: fileURL, options: .atomic)
    }
}

public enum TagSort {
    /// 정렬 기준 그룹 안에서 할 일 태그의 index. 없으면 Int.max.
    public static func rank(_ todo: Todo, config: TagConfig) -> Int {
        guard let g = config.sortGroup else { return Int.max }
        return todo.tagIds.compactMap { id in g.tags.firstIndex { $0.id == id } }.min() ?? Int.max
    }

    /// byTag: rank → 마감 오름차순(nil 뒤) → createdAt. 아니면 DueBadge.sorted 와 동일.
    public static func sorted(_ todos: [Todo], config: TagConfig, byTag: Bool) -> [Todo] {
        guard byTag else { return DueBadge.sorted(todos) }
        return todos.sorted { a, b in
            let (ra, rb) = (rank(a, config: config), rank(b, config: config))
            if ra != rb { return ra < rb }
            switch (a.dueDate, b.dueDate) {
            case (nil, nil): return a.createdAt < b.createdAt
            case (nil, _): return false
            case (_, nil): return true
            case let (x?, y?): return x == y ? a.createdAt < b.createdAt : x < y
            }
        }
    }

    /// (그룹 순서, 태그 순서)로 정렬한 태그들. 모르는 id 제외.
    public static func ordered(_ ids: [String], config: TagConfig) -> [Tag] {
        config.allTags.filter { ids.contains($0.id) }
    }
}
