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

/// `<root>/<jobId>/` 폴더 하나가 job 하나. Aside 는 이 폴더를 보지 않는다.
/// 실행할 때만 Aside 쪽 실행용 폴더에 요청을 복사하고(prepareWorkDir), 끝나면 결과만 골라 가져온다(importResults).
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

    /// job.json 의 키만 바꾼다. 모르는 키는 그대로 둔다.
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

    /// 실행이 끝난 job 을 마무리한다: 상태·오류·종료 시각을 쓴다.
    /// job.json 이 깨졌거나 없어졌으면 메모리의 job 으로 다시 쓴다.
    @discardableResult
    public func finish(_ job: E2EJob, status: E2EJobStatus, error: String?, sessionId: String?,
                       now: Date = Date()) throws -> E2EJob {
        var out = load(job.id) ?? job
        out.status = status
        out.finishedAt = now
        out.error = error
        out.sessionId = sessionId ?? out.sessionId
        var set: [String: Any] = ["status": status.rawValue, "finishedAt": E2EDate.string(now)]
        if let error { set["error"] = error }
        if let s = out.sessionId { set["sessionId"] = s }
        do {
            try patch(job.id, set: set, remove: error == nil ? ["error"] : [])
        } catch {
            try OwnerOnlyFile.write(Self.encoder.encode(out), to: jobFile(job.id))
        }
        try? FileManager.default.removeItem(at: pidFile(job.id))
        return out
    }

    // MARK: - 실행용 폴더 (Aside 쪽)

    static let requestName = "request.json"
    static let resultName = "result.json"
    static let jiraDirName = "jira"
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "webp", "gif"]
    static let maxResultBytes = 2 * 1024 * 1024
    static let maxImageBytes = 20 * 1024 * 1024

    /// Aside 가 읽을 요청(request.json)과 Jira 내용(jira/)을 실행용 폴더에 둔다. 남아 있던 폴더는 비우고 다시 만든다.
    public func prepareWorkDir(_ job: E2EJob, at work: URL) throws {
        let fm = FileManager.default
        try? fm.removeItem(at: work)
        try fm.createDirectory(at: work, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try OwnerOnlyFile.write(Self.encoder.encode(E2ERequest(job)), to: work.appendingPathComponent(Self.requestName))
        let jira = dir(job.id).appendingPathComponent(Self.jiraDirName, isDirectory: true)
        if fm.fileExists(atPath: jira.path) {
            try fm.copyItem(at: jira, to: work.appendingPathComponent(Self.jiraDirName, isDirectory: true))
        }
    }

    /// 실행용 폴더에서 result.json 과 스크린샷 이미지만 job 폴더로 가져오고 실행용 폴더를 지운다.
    /// 링크·폴더·이미지가 아닌 파일·너무 큰 파일은 가져오지 않고, 그 이름을 돌려준다 (run.log 에 남긴다).
    @discardableResult
    public func importResults(from work: URL, into id: String) -> [String] {
        let fm = FileManager.default
        defer { try? fm.removeItem(at: work) }
        var skipped: [String] = []
        for name in ((try? fm.contentsOfDirectory(atPath: work.path)) ?? []).sorted() {
            if name == Self.requestName || name == Self.jiraDirName { continue }
            let isResult = name == Self.resultName
            let src = work.appendingPathComponent(name)
            guard isResult || Self.isImageName(name),
                  Self.isPlainFile(src, maxBytes: isResult ? Self.maxResultBytes : Self.maxImageBytes),
                  let data = try? Data(contentsOf: src) else {
                skipped.append(name)
                continue
            }
            // 새로 써서 실행 권한 없는 0600 파일로 둔다.
            if (try? OwnerOnlyFile.write(data, to: dir(id).appendingPathComponent(name))) == nil { skipped.append(name) }
        }
        return skipped
    }

    /// ATM 이 실행 중에 죽어 남은 실행용 폴더를 지운다. createdBefore 이후에 만든 job(이번 실행)의 것은 둔다.
    @discardableResult
    public static func pruneWorkDirs(in roots: [URL], createdBefore: Date) -> [String] {
        let fm = FileManager.default
        var removed: [String] = []
        for root in roots {
            for id in ((try? fm.contentsOfDirectory(atPath: root.path)) ?? []).sorted() where E2EJobID.isValid(id) {
                guard let created = E2EJobID.date(id), created < createdBefore else { continue }
                if (try? fm.removeItem(at: root.appendingPathComponent(id))) != nil { removed.append(id) }
            }
        }
        return removed
    }

    /// 점으로 시작하지 않고 확장자가 이미지인 파일 이름.
    static func isImageName(_ name: String) -> Bool {
        !name.hasPrefix(".") && imageExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    /// 심볼릭 링크·폴더가 아닌 일반 파일이고 maxBytes 이하인지 (링크를 따라가지 않고 본다).
    static func isPlainFile(_ url: URL, maxBytes: Int) -> Bool {
        guard let a = try? FileManager.default.attributesOfItem(atPath: url.path),
              a[.type] as? FileAttributeType == .typeRegular,
              let size = a[.size] as? NSNumber else { return false }
        return size.intValue <= maxBytes
    }

    /// 앱 시작 시: 끝나지 못한 job 을 닫는다.
    /// 실행 중이던 job 은 failed, 대기 중이던 job 은 cancelled. 닫은 job 의 남은 aside pid 를 돌려준다(호출부가 정리).
    /// createdBefore 이후에 만든 job(이번 실행에서 벌써 요청한 것)은 건드리지 않는다.
    @discardableResult
    public func recoverOnLaunch(createdBefore: Date, now: Date = Date()) -> [E2ERecovered] {
        var closed: [E2ERecovered] = []
        for id in ids() {
            if let created = load(id)?.createdAt ?? E2EJobID.date(id), created >= createdBefore { continue }
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

    /// result.json 의 스크린샷 이름 → job 폴더 안의 이미지 파일. 경로가 붙어 와도 이름만 본다.
    /// 이미지 확장자의 일반 파일이 아니면(없음·링크·폴더·다른 종류) nil 이라 눌러도 열리지 않는다.
    public func screenshotURL(_ id: String, name: String) -> URL? {
        let n = (name as NSString).lastPathComponent
        guard Self.isImageName(n) else { return nil }
        let url = dir(id).appendingPathComponent(n)
        return Self.isPlainFile(url, maxBytes: Self.maxImageBytes) ? url : nil
    }
}
