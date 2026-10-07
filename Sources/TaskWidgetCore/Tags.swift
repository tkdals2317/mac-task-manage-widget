import Foundation

public enum TagColor: String, Codable, CaseIterable { case red, orange, yellow, green, teal, blue, purple, gray }

public struct Tag: Codable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var color: TagColor

    public init(id: String = UUID().uuidString, name: String, color: TagColor) {
        self.id = id
        self.name = name
        self.color = color
    }
}

public enum TagDefaults {
    public static let all: [Tag] = [
        Tag(id: "urgent", name: "긴급", color: .red),
        Tag(id: "high", name: "높음", color: .orange),
        Tag(id: "normal", name: "보통", color: .gray),
        Tag(id: "low", name: "낮음", color: .blue),
    ]
}

public struct TagStore {
    public let fileURL: URL

    public init(fileURL: URL = Paths.dataDir.appendingPathComponent("tags.json")) {
        self.fileURL = fileURL
    }

    /// 파일 없으면 기본 태그. 파싱 실패면 tags.corrupt-<ts>.json 으로 옮기고 기본 태그.
    public func load() -> [Tag] {
        guard let data = try? Data(contentsOf: fileURL) else { return TagDefaults.all }
        if let tags = try? JSONDecoder().decode([Tag].self, from: data) { return tags }
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = fileURL.deletingLastPathComponent().appendingPathComponent("tags.corrupt-\(stamp).json")
        try? FileManager.default.moveItem(at: fileURL, to: backup)
        return TagDefaults.all
    }

    public func save(_ tags: [Tag]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try e.encode(tags).write(to: fileURL, options: .atomic)
    }
}

public enum TagSort {
    /// 할 일 태그 중 가장 앞 순서 index. 태그 없거나 모르는 id 만 있으면 Int.max.
    public static func rank(_ todo: Todo, tags: [Tag]) -> Int {
        todo.tagIds.compactMap { id in tags.firstIndex { $0.id == id } }.min() ?? Int.max
    }

    /// byTag: rank → 마감 오름차순(nil 뒤) → createdAt. 아니면 DueBadge.sorted 와 동일.
    public static func sorted(_ todos: [Todo], tags: [Tag], byTag: Bool) -> [Todo] {
        guard byTag else { return DueBadge.sorted(todos) }
        return todos.sorted { a, b in
            let (ra, rb) = (rank(a, tags: tags), rank(b, tags: tags))
            if ra != rb { return ra < rb }
            switch (a.dueDate, b.dueDate) {
            case (nil, nil): return a.createdAt < b.createdAt
            case (nil, _): return false
            case (_, nil): return true
            case let (x?, y?): return x == y ? a.createdAt < b.createdAt : x < y
            }
        }
    }

    /// 태그 순서대로 정렬한 태그들. 모르는 id 제외.
    public static func ordered(_ ids: [String], tags: [Tag]) -> [Tag] {
        tags.filter { ids.contains($0.id) }
    }
}
