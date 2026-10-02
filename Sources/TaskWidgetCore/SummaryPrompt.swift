import Foundation

public struct SummaryInput: Equatable {
    public var dayKey: String
    public var worklogRaw: String?
    public var worklogProjects: Set<String>
    public var activity: [ActivityRecord]
    public var commits: [String: [String]]   // project -> "<hash> <subject>" lines
    /// 로그용 통계. 프롬프트에는 안 들어간다.
    public var worklogSectionCount: Int
    public var activityDropped: Int
    public var projects: [String]

    public init(dayKey: String, worklogRaw: String?, worklogProjects: Set<String>,
                activity: [ActivityRecord], commits: [String: [String]],
                worklogSectionCount: Int = 0, activityDropped: Int = 0, projects: [String] = []) {
        self.dayKey = dayKey
        self.worklogRaw = worklogRaw
        self.worklogProjects = worklogProjects
        self.activity = activity
        self.commits = commits
        self.worklogSectionCount = worklogSectionCount
        self.activityDropped = activityDropped
        self.projects = projects
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

    static func hhmm(_ d: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour!, c.minute!)
    }

    public static func build(_ i: SummaryInput, calendar: Calendar = .current) -> String {
        var s = """
        당신은 개발자의 하루 업무 일지를 작성합니다. 날짜: \(i.dayKey)

        입력은 세 종류입니다.
        1) 개발자가 세션 중 직접 기록한 업무 일지 — 가장 신뢰도 높음. 이 내용을 우선합니다.
        2) 일지가 없는 프로젝트의 Claude Code 대화 기록(raw) — 보완용.
        3) git 커밋 — 사실 확인용.

        도구를 사용하지 말고, 아래 데이터만 근거로 한국어 Markdown을 출력하세요. 데이터에 없는 일은 쓰지 않습니다. 다른 설명 없이 Markdown만 출력합니다.

        형식:
        # \(i.dayKey) 업무 요약
        ## {프로젝트명}
        - 한 일 (성과/결과 위주, 3~7개, 각 1~2문장)
        (프로젝트마다 반복)
        ## 미완료 / 내일
        - 일지나 대화에서 드러난 미완료 작업, 다음 단계
        """

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
        return s + "\n"
    }
}
