import Foundation

public struct SummaryInput: Equatable {
    public var dayKey: String
    public var worklogRaw: String?
    public var worklogProjects: Set<String>
    public var activity: [ActivityRecord]
    public var commits: [String: [String]]   // project -> "<hash> <subject>" lines
    public var jiraKeys: [String: [String]]  // project -> 정렬된 Jira 키
    /// 로그용 통계. 프롬프트에는 안 들어간다.
    public var worklogSectionCount: Int
    public var activityDropped: Int
    public var projects: [String]

    public init(dayKey: String, worklogRaw: String?, worklogProjects: Set<String>,
                activity: [ActivityRecord], commits: [String: [String]],
                worklogSectionCount: Int = 0, activityDropped: Int = 0, projects: [String] = [],
                jiraKeys: [String: [String]] = [:]) {
        self.dayKey = dayKey
        self.worklogRaw = worklogRaw
        self.worklogProjects = worklogProjects
        self.activity = activity
        self.commits = commits
        self.worklogSectionCount = worklogSectionCount
        self.activityDropped = activityDropped
        self.projects = projects
        self.jiraKeys = jiraKeys
    }
}

public enum SummaryPrompt {
    public static let promptCap = 400
    public static let stopCap = 1200
    public static let totalCap = 80_000

    /// 일지가 있는 프로젝트의 raw 는 버리고, 메시지별 캡 적용 후, 총량 초과분은 오래된 것부터 제거.
    public static func filterActivity(_ records: [ActivityRecord], coveredProjects: Set<String>) -> [ActivityRecord] {
        var kept: [ActivityRecord] = records
            .filter { !coveredProjects.contains($0.project) }
            .map { r in
                var r = r
                let cap = r.event == "prompt" ? promptCap : stopCap
                if r.text.count > cap { r.text = String(r.text.prefix(cap)) + "…" }
                return r
            }
        var total = kept.reduce(0) { $0 + $1.text.count }
        while total > totalCap, !kept.isEmpty {
            total -= kept.removeFirst().text.count
        }
        return kept
    }

    public static func isEmpty(_ i: SummaryInput) -> Bool {
        let worklogEmpty = i.worklogRaw?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        return worklogEmpty && i.activity.isEmpty && i.commits.values.allSatisfy { $0.isEmpty }
    }

    /// 알려진 프로젝트 접두사의 키만 (UTF-8, SHA-256 같은 건 무시). 중복 제거, 정렬.
    public static func jiraKeys(in texts: [String], prefixes: Set<String>) -> [String] {
        let alt = prefixes.map(NSRegularExpression.escapedPattern(for:)).sorted().joined(separator: "|")
        guard !prefixes.isEmpty, let re = try? NSRegularExpression(pattern: "\\b(?:\(alt))-\\d+\\b") else { return [] }
        var keys = Set<String>()
        for t in texts {
            for m in re.matches(in: t, range: NSRange(t.startIndex..., in: t)) {
                keys.insert((t as NSString).substring(with: m.range))
            }
        }
        return keys.sorted()
    }

    static func hhmm(_ d: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour!, c.minute!)
    }

    /// 기본 지시문. `{날짜}` 는 build 에서 그날 날짜로 바뀐다.
    public static let defaultInstructions = """
        {날짜} 개발자 업무 요약을 한국어 Markdown으로 쓰세요. 도구 사용 금지, 아래 데이터만 근거로.
        근거 우선순위: 1) 업무 일지 > 3) 커밋 > 2) 대화 기록.

        규칙:
        - 끝낸 일의 결과만 짧게. 한 줄 = 한 항목, 동사로 끝내는 개조식 ("~ 수정", "~ 추가").
        - 과정·시행착오·조사·잡담·질문 응답, 미완료·다음 할 일은 쓰지 않음.
        - 비슷한 항목은 하나로 합침. 프로젝트당 최대 5개.
        - 데이터에 Jira 키(예: NMRS-123)가 있으면 관련 항목 끝에 (NMRS-123) 처럼 붙임.
        - 머리말·맺음말 없이 아래 형식만 출력.

        # {날짜} 업무 요약
        ## {프로젝트명}
        - 한 일
        """

    /// instructions 가 nil/공백이면 defaultInstructions. 데이터 섹션은 항상 뒤에 붙는다.
    public static func build(_ i: SummaryInput, instructions: String? = nil, calendar: Calendar = .current) -> String {
        let custom = instructions?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var s = (custom.isEmpty ? defaultInstructions : custom).replacingOccurrences(of: "{날짜}", with: i.dayKey)

        let worklog = i.worklogRaw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        s += "\n\n=== 1) 업무 일지 ===\n" + (worklog.isEmpty ? "(없음)" : worklog)

        let groups = Dictionary(grouping: i.activity, by: { $0.project })
        if groups.isEmpty {
            s += "\n\n=== 2) 대화 기록 ===\n(없음)"
        }
        for project in groups.keys.sorted() {
            let recs = groups[project]!.sorted { $0.ts < $1.ts }
            s += "\n\n=== 2) 대화 기록: \(project) (\(recs[0].cwd)) ==="
            for r in recs {
                let role = r.event == "prompt" ? "user" : "assistant"
                s += "\n[\(hhmm(r.ts, calendar))] \(role): \(r.text)"
            }
        }

        let commits = i.commits.filter { !$0.value.isEmpty }
        if commits.isEmpty {
            s += "\n\n=== 3) 커밋 ===\n(없음)"
        }
        for project in commits.keys.sorted() {
            s += "\n\n=== 3) 커밋: \(project) ===\n" + commits[project]!.joined(separator: "\n")
        }
        let keys = i.jiraKeys.filter { !$0.value.isEmpty }
        if !keys.isEmpty {
            s += "\n\n=== 4) Jira 키 ===\n" + keys.keys.sorted().map { "\($0): " + keys[$0]!.joined(separator: ", ") }.joined(separator: "\n")
        }
        return s + "\n"
    }

    /// 주간 지시문. 고정(사용자 편집 불가). `{주}` 는 호출 쪽에서 치환.
    public static let weeklyInstructions = """
        {주} 개발자 주간 업무 요약을 한국어 Markdown으로 쓰세요. 도구 사용 금지, 아래 일간 요약만 근거로.
        - 여러 날에 걸친 같은 작업은 하나로 합쳐 결과만 씀. 날짜별로 나열하지 않음.
        - 한 줄 = 한 항목, 동사로 끝내는 개조식. 프로젝트당 최대 7개.
        - Jira 키가 있으면 항목 끝에 그대로 유지.
        - 과정·미완료·다음 할 일·머리말·맺음말 없음.

        # {주} 주간 업무 요약
        ## {프로젝트명}
        - 한 일
        """
}
