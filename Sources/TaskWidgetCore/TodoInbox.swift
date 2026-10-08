import Foundation

/// `TaskWidget --add-todo` 가 남기는 inbox 파일. 앱이 todos.json 의 유일한 쓰기 주체라서
/// CLI 는 여기에만 쓰고, 앱이 읽어 할 일로 옮긴다.
public struct InboxItem: Codable, Equatable {
    public var title: String
    public var due: String?
    public var tags: [String]
    public var memo: String?
    public var createdAt: Date

    public init(title: String, due: String? = nil, tags: [String] = [], memo: String? = nil, createdAt: Date = Date()) {
        self.title = title
        self.due = due
        self.tags = tags
        self.memo = memo
        self.createdAt = createdAt
    }
}

public enum TodoInbox {
    public static var dir: URL { Paths.dataDir.appendingPathComponent("inbox", isDirectory: true) }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// "yyyy-MM-dd" 형식이고 실제로 있는 날짜인지.
    static func validDue(_ s: String) -> Bool {
        let shape = s.count == 10 && s.enumerated().allSatisfy { i, c in (i == 4 || i == 7) ? c == "-" : (c.isASCII && c.isNumber) }
        return shape && DayKey.date(from: s) != nil
    }

    /// 태그 이름(대소문자 무시, 앞뒤 공백 제거) → id. 하나만 그룹은 앞의 것만 남긴다.
    public static func resolve(_ names: [String], in config: TagConfig) -> (ids: [String], unknown: [String]) {
        var ids: [String] = [], unknown: [String] = []
        for raw in names {
            let n = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if n.isEmpty { continue }
            if let t = config.allTags.first(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) {
                if !ids.contains(t.id) { ids.append(t.id) }
            } else {
                unknown.append(n)
            }
        }
        return (config.normalized(ids), unknown)
    }

    /// CLI 본체. (stdout 한 줄, 종료 코드). `args` 는 `--add-todo` 뒤의 인자들.
    public static func runCLI(args: [String], inboxDir: URL = dir, config: TagConfig = TagStore().load(),
                              now: Date = Date()) -> (output: String, code: Int32) {
        func fail(_ msg: String) -> (String, Int32) { (json(["ok": false, "error": msg]), 2) }
        var title = "", due: String?, memo: String?
        var tags: [String] = []
        var i = 0
        while i < args.count {
            let a = args[i]
            guard ["--title", "--due", "--tag", "--memo"].contains(a) else { i += 1; continue }
            guard i + 1 < args.count else { return fail("\(a) 값이 없습니다") }
            let v = args[i + 1]
            switch a {
            case "--title": title = v
            case "--due": due = v
            case "--tag": tags.append(v)
            default: memo = v
            }
            i += 2
        }
        guard let t = Todo.normalizedTitle(title) else { return fail("제목이 비어 있습니다") }
        if let d = due, !validDue(d) { return fail("마감일 형식이 잘못되었습니다 (YYYY-MM-DD): \(d)") }
        let m = memo.flatMap(Todo.normalizedTitle)
        let (_, unknown) = resolve(tags, in: config)
        let trimmed = tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let known = trimmed.filter { !unknown.contains($0) }

        let id = UUID()
        let item = InboxItem(title: t, due: due, tags: known, memo: m, createdAt: now)
        do {
            try FileManager.default.createDirectory(at: inboxDir, withIntermediateDirectories: true)
            try encoder.encode(item).write(to: inboxDir.appendingPathComponent("\(id.uuidString).json"), options: .atomic)
        } catch {
            return fail("inbox 에 쓰지 못했습니다: \(error.localizedDescription)")
        }
        let dueValue: Any = due ?? NSNull()
        return (json(["ok": true, "id": id.uuidString, "title": t, "due": dueValue,
                      "tags": known, "unknownTags": unknown]), 0)
    }

    private static func json(_ obj: [String: Any]) -> String {
        let d = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .withoutEscapingSlashes])
        return d.flatMap { String(data: $0, encoding: .utf8) } ?? "{\"ok\":false}"
    }

    /// inbox 의 *.json 을 읽어 할 일로 바꾼다. 할 일 id = 파일 이름(UUID) 이라 같은 파일을 다시 읽어도 중복되지 않는다.
    /// `apply` 가 (저장까지) 성공해야 파일을 지운다. 못 읽는 파일은 `bad/` 로 옮긴다.
    @discardableResult
    public static func importPending(inboxDir: URL = dir, config: TagConfig, apply: ([Todo]) throws -> Void) -> Int {
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(at: inboxDir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        var todos: [Todo] = [], good: [URL] = []
        for f in files {
            guard let data = try? Data(contentsOf: f), let item = try? decoder.decode(InboxItem.self, from: data),
                  let title = Todo.normalizedTitle(item.title), item.due.map(validDue) ?? true else {
                let bad = inboxDir.appendingPathComponent("bad", isDirectory: true)
                try? fm.createDirectory(at: bad, withIntermediateDirectories: true)
                try? fm.moveItem(at: f, to: bad.appendingPathComponent(f.lastPathComponent))
                continue
            }
            let id = UUID(uuidString: f.deletingPathExtension().lastPathComponent) ?? UUID()
            // TODO(memo): Todo 에 memo 필드가 생기면 item.memo 를 여기서 넘긴다. 지금은 버린다.
            todos.append(Todo(id: id, title: title, createdAt: item.createdAt, dueDate: item.due,
                              tagIds: resolve(item.tags, in: config).ids))
            good.append(f)
        }
        guard !todos.isEmpty, (try? apply(todos)) != nil else { return 0 }
        good.forEach { try? fm.removeItem(at: $0) }
        return todos.count
    }
}
