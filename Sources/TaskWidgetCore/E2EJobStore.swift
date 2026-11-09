import Foundation

public enum E2EStoreError: Error, Equatable {
    case invalidId
    case corruptJob
}

/// 앱 시작 때 닫은 job. pid·sessionId 가 있으면 호출부가 남은 aside 프로세스·세션을 멈춘다.
public struct E2ERecovered: Equatable {
    public let id: String
    public let pid: Int32?
    public let sessionId: String?
}

public enum E2EResultLoad: Equatable {
    case missing
    case invalid(String)
    case ok(E2EResult)
}

/// `<root>/<jobId>/` 폴더 하나가 job 하나. job.json 은 ATM 과 Aside 가 같이 고치므로 키 단위로 바꾼다(patch).
public struct E2EJobStore {
    public let root: URL

    public init(root: URL = Paths.e2eJobsDir) {
        self.root = root
    }

    public func dir(_ id: String) -> URL { root.appendingPathComponent(id, isDirectory: true) }
    public func jobFile(_ id: String) -> URL { dir(id).appendingPathComponent("job.json") }
    public func resultFile(_ id: String) -> URL { dir(id).appendingPathComponent("result.json") }
    public func logFile(_ id: String) -> URL { dir(id).appendingPathComponent("run.log") }
    /// 실행 중인 aside pid. Aside 가 job.json 을 다시 쓰므로 따로 둔다 (앱이 죽은 뒤 남은 프로세스 정리용).
    func pidFile(_ id: String) -> URL { dir(id).appendingPathComponent("run.pid") }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    public func create(_ job: E2EJob) throws {
        guard E2EJobID.isValid(job.id) else { throw E2EStoreError.invalidId }
        try FileManager.default.createDirectory(at: dir(job.id), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try OwnerOnlyFile.write(Self.encoder.encode(job), to: jobFile(job.id))
    }

    public func load(_ id: String) -> E2EJob? {
        guard let data = try? Data(contentsOf: jobFile(id)) else { return nil }
        return try? JSONDecoder().decode(E2EJob.self, from: data)
    }

    func ids() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).filter(E2EJobID.isValid)
    }

    /// 최근 순. job.json 을 못 읽는 폴더는 뺀다.
    public func list() -> [E2EJob] {
        ids().compactMap(load).sorted { $0.createdAt > $1.createdAt }
    }

    public func result(_ id: String) -> E2EResultLoad {
        guard let data = try? Data(contentsOf: resultFile(id)) else { return .missing }
        do {
            return .ok(try E2EResult.decode(data))
        } catch {
            return .invalid(Self.describe(error))
        }
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case DecodingError.keyNotFound(let k, _): return "\(k.stringValue) 항목 없음"
        case DecodingError.typeMismatch(_, let c), DecodingError.valueNotFound(_, let c):
            return "\(c.codingPath.map(\.stringValue).joined(separator: ".")) 모양이 다름"
        case DecodingError.dataCorrupted: return "JSON 형식이 아님"
        default: return error.localizedDescription
        }
    }

    /// job.json 의 키만 바꾼다. Aside 가 덧붙인 키는 그대로 둔다.
    public func patch(_ id: String, set: [String: Any] = [:], remove: [String] = []) throws {
        let url = jobFile(id)
        let data = try Data(contentsOf: url)
        guard var obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw E2EStoreError.corruptJob }
        for (k, v) in set { obj[k] = v }
        for k in remove { obj.removeValue(forKey: k) }
        try OwnerOnlyFile.write(JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]), to: url)
    }

    public func writePid(_ pid: Int32, for id: String) {
        try? OwnerOnlyFile.write(Data(String(pid).utf8), to: pidFile(id))
    }

    /// 실행 직전에만 부른다. 끝나면 `finish` 또는 `scrubPassword` 가 지운다.
    public func setPassword(_ password: String, for id: String) throws {
        try patch(id, set: ["password": password])
    }

    /// 실행이 끝난 job 을 마무리한다: 상태·오류·종료 시각을 쓰고 비밀번호를 지운다.
    /// job.json 이 깨졌거나 없어졌으면 메모리의 job(비밀번호 없음)으로 다시 쓴다.
    @discardableResult
    public func finish(_ job: E2EJob, status: E2EJobStatus, error: String?, sessionId: String?,
                       secret: String? = nil, now: Date = Date()) throws -> E2EJob {
        var out = load(job.id) ?? job
        out.status = status
        out.finishedAt = now
        out.error = error
        out.sessionId = sessionId ?? out.sessionId
        var set: [String: Any] = ["status": status.rawValue, "finishedAt": E2EDate.string(now)]
        if let error { set["error"] = error }
        if let s = out.sessionId { set["sessionId"] = s }
        do {
            try patch(job.id, set: set, remove: ["password"] + (error == nil ? ["error"] : []))
        } catch {
            try OwnerOnlyFile.write(Self.encoder.encode(out), to: jobFile(job.id))
        }
        try? FileManager.default.removeItem(at: pidFile(job.id))
        if let secret { redact(secret, in: job.id) }
        return out
    }

    private static let passwordField = try! NSRegularExpression(pattern: "\"password\"\\s*:\\s*\"(?:[^\"\\\\]|\\\\.)*\"")

    /// job.json 에서 password 를 지운다. JSON 이 깨졌으면 password 항목을 글자 단위로 비운다.
    public func scrubPassword(_ id: String) {
        let url = jobFile(id)
        guard let data = try? Data(contentsOf: url) else { return }
        if let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            if obj["password"] != nil { try? patch(id, remove: ["password"]) }
            return
        }
        let text = String(decoding: data, as: UTF8.self)
        let range = NSRange(text.startIndex..., in: text)
        guard Self.passwordField.firstMatch(in: text, range: range) != nil else { return }
        let out = Self.passwordField.stringByReplacingMatches(in: text, range: range, withTemplate: "\"password\": \"\"")
        try? OwnerOnlyFile.write(Data(out.utf8), to: url)
    }

    static let mask = "****"

    /// job 폴더의 텍스트 파일(json·log)에 비밀번호가 글자 그대로 남아 있으면 가린다. JSON 이스케이프된 모양도 찾는다.
    public func redact(_ secret: String, in id: String) {
        guard !secret.isEmpty else { return }
        let forms = Self.secretForms(secret)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir(id).path)) ?? []
        for n in names where n.hasSuffix(".json") || n.hasSuffix(".log") || n.hasSuffix(".txt") {
            let url = dir(id).appendingPathComponent(n)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let out = Self.redact(text, forms: forms)
            if out != text { try? OwnerOnlyFile.write(Data(out.utf8), to: url) }
        }
    }

    static func secretForms(_ secret: String) -> [String] {
        var forms = [secret]
        if let d = try? JSONSerialization.data(withJSONObject: [secret]),
           let s = String(data: d, encoding: .utf8), s.count > 4 {
            let escaped = String(s.dropFirst(2).dropLast(2))
            if escaped != secret { forms.append(escaped) }
        }
        return forms
    }

    public static func redact(_ text: String, forms: [String]) -> String {
        forms.filter { !$0.isEmpty }.sorted { $0.count > $1.count }.reduce(text) { $0.replacingOccurrences(of: $1, with: mask) }
    }

    /// 앱 시작 시: 이전 실행이 남긴 비밀번호를 모두 지우고, 끝나지 못한 job 을 닫는다.
    /// 실행 중이던 job 은 failed, 대기 중이던 job 은 cancelled. 닫은 job 의 남은 aside pid 를 돌려준다(호출부가 정리).
    /// createdBefore 이후에 만든 job(이번 실행에서 벌써 요청한 것)은 건드리지 않는다.
    @discardableResult
    public func recoverOnLaunch(createdBefore: Date, now: Date = Date()) -> [E2ERecovered] {
        var closed: [E2ERecovered] = []
        for id in ids() {
            if let created = load(id)?.createdAt ?? E2EJobID.date(id), created >= createdBefore { continue }
            scrubPassword(id)
            let pid = (try? String(contentsOf: pidFile(id), encoding: .utf8)).flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            try? FileManager.default.removeItem(at: pidFile(id))
            guard let job = load(id), job.status.isActive else { continue }
            let interrupted = job.status == .running
            try? patch(id, set: [
                "status": (interrupted ? E2EJobStatus.failed : .cancelled).rawValue,
                "error": interrupted ? "ATM 이 종료되어 실행이 중단됐어요" : "ATM 이 종료되어 대기 중인 요청을 취소했어요",
                "finishedAt": E2EDate.string(now),
            ])
            // CLI 가 SIGTERM 없이 죽으면(파이프 끊김 등) Aside 세션은 계속 돈다. run.log 의 세션 id 로 멈추게 넘긴다.
            closed.append(E2ERecovered(id: id, pid: pid, sessionId: interrupted ? sessionId(id) : nil))
        }
        return closed
    }

    /// run.log 에 남은 `created new session: <id>`.
    func sessionId(_ id: String) -> String? {
        guard let text = try? String(contentsOf: logFile(id), encoding: .utf8) else { return nil }
        return text.split(separator: "\n").lazy.compactMap { AsideCLI.sessionId(in: String($0)) }.first
    }

    public func delete(_ id: String) throws {
        guard E2EJobID.isValid(id) else { throw E2EStoreError.invalidId }
        try FileManager.default.removeItem(at: dir(id))
    }

    /// 만든 지 days 일이 지난 job 폴더를 지운다 (실행 중인 것은 둔다). days 가 0 이하면 아무것도 안 한다.
    @discardableResult
    public func prune(olderThanDays days: Int, now: Date = Date()) -> Int {
        guard days > 0 else { return 0 }
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        var removed = 0
        for id in ids() {
            let job = load(id)
            if job?.status.isActive == true { continue }
            guard let created = job?.createdAt ?? E2EJobID.date(id), created < cutoff else { continue }
            if (try? delete(id)) != nil { removed += 1 }
        }
        return removed
    }

    /// result.json 의 스크린샷 이름 → job 폴더 안의 파일. 경로가 붙어 와도 이름만 보고, 없으면 nil.
    public func screenshotURL(_ id: String, name: String) -> URL? {
        let n = (name as NSString).lastPathComponent
        guard !n.isEmpty, n != "..", n != "." else { return nil }
        let url = dir(id).appendingPathComponent(n)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
