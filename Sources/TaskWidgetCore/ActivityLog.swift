import Foundation

public enum ActivityLog {
    public static let promptCap = 2000
    public static let stopCap = 4000

    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = .current
        return f
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, enc in
            var c = enc.singleValueContainer()
            try c.encode(iso.string(from: date))
        }
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Claude Code 훅 stdin JSON → 레코드. 대상 이벤트가 아니거나 텍스트가 없으면 nil.
    public static func record(fromHookInput data: Data, excludingCwdPrefix: String, now: Date = Date()) -> ActivityRecord? {
        guard let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: Any],
              let event = dict["hook_event_name"] as? String else { return nil }
        let cwd = dict["cwd"] as? String ?? ""
        if !excludingCwdPrefix.isEmpty, cwd.hasPrefix(excludingCwdPrefix) { return nil }

        let kind: String
        let raw: String
        let cap: Int
        switch event {
        case "UserPromptSubmit":
            kind = "prompt"; raw = dict["prompt"] as? String ?? ""; cap = promptCap
        case "Stop":
            kind = "stop"; raw = dict["last_assistant_message"] as? String ?? ""; cap = stopCap
        default:
            return nil
        }
        let text = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(cap))
        guard !text.isEmpty else { return nil }
        return ActivityRecord(ts: now, event: kind, session: dict["session_id"] as? String ?? "", cwd: cwd, text: text)
    }

    /// O_APPEND 로 한 줄 append. 동시에 여러 세션이 써도 줄이 섞이지 않는다.
    public static func append(_ record: ActivityRecord, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var line = try encoder.encode(record)
        line.append(0x0A)
        let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        try line.withUnsafeBytes { buf in
            var off = 0
            while off < buf.count {
                let n = write(fd, buf.baseAddress! + off, buf.count - off)
                guard n > 0 else { throw POSIXError(.EIO) }
                off += n
            }
        }
    }

    /// 그날(로컬 달력) 레코드만, ts 오름차순. 깨진 줄은 건너뜀.
    public static func records(on day: Date, from url: URL, calendar: Calendar = .current) -> [ActivityRecord] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        // ponytail: 파일 전체 로드. 수십 MB 넘으면 뒤에서부터 읽는 스트리밍으로 교체.
        return text.split(separator: "\n")
            .compactMap { try? decoder.decode(ActivityRecord.self, from: Data($0.utf8)) }
            .filter { calendar.isDate($0.ts, inSameDayAs: day) }
            .sorted { $0.ts < $1.ts }
    }

    /// `TaskWidget --hook` 진입점. 어떤 입력에도 throw/crash 하지 않는다.
    public static func handleHook(input: Data, dataDir: URL = Paths.dataDir, now: Date = Date()) {
        guard let rec = record(fromHookInput: input, excludingCwdPrefix: dataDir.path, now: now) else { return }
        do {
            try append(rec, to: dataDir.appendingPathComponent("activity.jsonl"))
        } catch {
            let log = dataDir.appendingPathComponent("logs/hook.log")
            try? FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
            let msg = "\(iso.string(from: now)) append failed: \(error)\n"
            if let h = try? FileHandle(forWritingTo: log) {
                try? h.seekToEnd()
                try? h.write(contentsOf: Data(msg.utf8))
                try? h.close()
            } else {
                try? msg.write(to: log, atomically: true, encoding: .utf8)
            }
        }
    }
}
