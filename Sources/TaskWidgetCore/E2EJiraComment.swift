import Foundation

/// 검증 결과를 Jira 이슈 댓글(ADF 문서)로 만든다.
/// Aside 가 쓴 글자는 모두 텍스트 노드로만 넣어 멘션·링크·마크업으로 살아나지 않는다.
public enum E2EJiraComment {
    static let maxText = 1500
    static let maxScenarios = 30

    /// 이 이슈 결과에 달린 스크린샷 이름 (경로는 떼고, 중복 없이, 적힌 순서대로).
    public static func screenshots(_ issue: E2EIssueResult) -> [String] {
        var seen = Set<String>()
        return issue.scenarios.flatMap(\.screenshots).map { ($0 as NSString).lastPathComponent }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Jira 에 올릴 첨부 이름. 다른 실행의 같은 이름 스크린샷과 섞이지 않게 환경·실행 시각을 붙인다.
    public static func attachmentName(_ job: E2EJob, screenshot: String, timeZone: TimeZone = .current) -> String {
        let base = (screenshot as NSString).lastPathComponent
        let ext = E2EReport.safe((base as NSString).pathExtension.lowercased())
        let stem = E2EReport.safe((base as NSString).deletingPathExtension)
        let name = "E2E-\(job.env.rawValue)-\(E2EReport.stamp(job.createdAt, "yyyyMMdd-HHmm", timeZone))-\(stem.isEmpty ? "shot" : stem)"
        return ext.isEmpty ? name : "\(name).\(ext)"
    }

    /// attached: 스크린샷 이름 → Jira 에 올린 첨부 이름 (올린 것만).
    public static func document(job: E2EJob, issue: E2EIssueResult, modelName: String, attached: [String: String] = [:],
                                timeZone: TimeZone = .current) -> [String: Any] {
        var content: [[String: Any]] = []
        content.append(node("heading", attrs: ["level": 3],
                            [text("E2E 자동 검증 · "), text(issue.verdict?.rawValue ?? "판정 없음", strong: true)]))
        var meta = "환경 \(job.env.rawValue)"
        if job.readOnly { meta += " (조회만)" }
        if !job.baseUrl.isEmpty { meta += " · \(job.baseUrl)" }
        meta += " · 모델 \(modelName) · \(E2EReport.stamp(job.createdAt, "yyyy-MM-dd HH:mm", timeZone))"
        content.append(paragraph(inline(meta)))
        if !job.notes.isEmpty { content.append(paragraph([text("추가 요청사항: ", strong: true)] + inline(job.notes))) }

        if !issue.assumptions.isEmpty {
            content.append(paragraph([text("가정", strong: true)]))
            content.append(list("bulletList", issue.assumptions))
        }
        for s in issue.scenarios.prefix(maxScenarios) {
            content.append(paragraph([text(s.verdict?.rawValue ?? "?", strong: true), text(" " + (s.name.isEmpty ? "시나리오" : clip(s.name)))]))
            if !s.steps.isEmpty { content.append(list("orderedList", s.steps)) }
            var lines: [[[String: Any]]] = []
            if !s.expected.isEmpty { lines.append([text("기대: ", strong: true)] + inline(s.expected)) }
            if !s.actual.isEmpty { lines.append([text("실제: ", strong: true)] + inline(s.actual)) }
            let shots = s.screenshots.compactMap { attached[($0 as NSString).lastPathComponent] }
            if !shots.isEmpty { lines.append([text("스크린샷(첨부): ", strong: true), text(shots.joined(separator: ", "))]) }
            if !lines.isEmpty { content.append(paragraph(broken(lines))) }
        }
        if issue.scenarios.count > maxScenarios {
            content.append(paragraph([text("… 시나리오 \(issue.scenarios.count - maxScenarios)개는 줄였어요")]))
        }
        if !issue.notes.isEmpty { content.append(paragraph(inline(issue.notes))) }
        content.append(paragraph([text("ATM 이 Aside 로 돌린 자동 검증 결과예요. 참고용이니 가정과 스크린샷을 같이 확인해 주세요.")]))
        return ["type": "doc", "version": 1, "content": content]
    }

    // MARK: - ADF 노드

    private static let hardBreak: [String: Any] = ["type": "hardBreak"]

    private static func node(_ type: String, attrs: [String: Any]? = nil, _ content: [[String: Any]]) -> [String: Any] {
        var n: [String: Any] = ["type": type, "content": content]
        if let attrs { n["attrs"] = attrs }
        return n
    }

    private static func paragraph(_ content: [[String: Any]]) -> [String: Any] { node("paragraph", content) }

    private static func list(_ type: String, _ items: [String]) -> [String: Any] {
        node(type, items.map { node("listItem", [paragraph(inline($0))]) })
    }

    /// ADF 는 빈 텍스트 노드를 받지 않아 빈 글자는 공백 하나로 넣는다.
    private static func text(_ s: String, strong: Bool = false) -> [String: Any] {
        var n: [String: Any] = ["type": "text", "text": s.isEmpty ? " " : s]
        if strong { n["marks"] = [["type": "strong"]] }
        return n
    }

    /// 줄바꿈은 hardBreak 로, 빈 줄은 건너뛴다. 너무 긴 글은 줄인다.
    private static func inline(_ s: String) -> [[String: Any]] {
        let lines = clip(s).components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { return [text(" ")] }
        return broken(lines.map { [text($0)] })
    }

    /// 줄마다의 노드를 hardBreak 로 이어 한 문단의 내용으로 만든다.
    private static func broken(_ lines: [[[String: Any]]]) -> [[String: Any]] {
        var out: [[String: Any]] = []
        for (i, line) in lines.enumerated() {
            if i > 0 { out.append(hardBreak) }
            out.append(contentsOf: line)
        }
        return out
    }

    static func clip(_ s: String) -> String {
        s.count > maxText ? String(s.prefix(maxText)) + "…" : s
    }
}
