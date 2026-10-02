import Foundation

public struct TodoStore {
    public let fileURL: URL

    public init(fileURL: URL = Paths.todosFile) {
        self.fileURL = fileURL
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// 파일 없으면 []. 파싱 실패면 todos.corrupt-<ts>.json 으로 옮기고 [].
    public func load() -> [Todo] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        if let todos = try? Self.decoder.decode([Todo].self, from: data) { return todos }
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = fileURL.deletingLastPathComponent().appendingPathComponent("todos.corrupt-\(stamp).json")
        try? FileManager.default.moveItem(at: fileURL, to: backup)
        return []
    }

    public func save(_ todos: [Todo]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try Self.encoder.encode(todos)
        try data.write(to: fileURL, options: .atomic)
    }
}
