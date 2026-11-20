import Foundation

/// 검증 결과를 HTML 파일 하나로 내보낸다. 스크린샷을 파일 안에 넣어, 브라우저로 크게 보거나 이슈에 그대로 첨부할 수 있다.
public enum E2EReport {
    public struct Image {
        public let mime: String
        public let data: Data

        public init(mime: String, data: Data) {
            self.mime = mime
            self.data = data
        }
    }

    static let logTailLines = 40

    /// `ATM-E2E-<첫 이슈 키>[+N]-<환경>-<yyyyMMdd-HHmm>.html`. 이슈가 없으면 job id.
    public static func fileName(_ job: E2EJob, timeZone: TimeZone = .current) -> String {
        let keys = job.issueKeys.map(safe).filter { !$0.isEmpty }
        var name = keys.first ?? safe(job.id)
        if keys.count > 1 { name += "+\(keys.count - 1)" }
        return "ATM-E2E-\(name)-\(job.env.rawValue)-\(stamp(job.createdAt, "yyyyMMdd-HHmm", timeZone)).html"
    }

    /// result.json 과 스크린샷 이름은 Aside 가 쓴 값이라 모두 글자로만 넣는다 (링크는 ATM 이 만든 Jira 주소만).
    public static func html(job: E2EJob, result: E2EResultLoad, modelName: String, logTail: String = "",
                            timeZone: TimeZone = .current, image: (String) -> Image?) -> String {
        var b: [String] = []
        let keys = job.issueKeys.joined(separator: ", ")
        b.append("<!doctype html>")
        b.append("<html lang=\"ko\"><head><meta charset=\"utf-8\">")
        b.append("<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">")
        b.append("<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; img-src data:; style-src 'unsafe-inline'\">")
        b.append("<title>E2E 검증 결과 · \(esc(keys.isEmpty ? job.id : keys))</title>")
        b.append("<style>\(style)</style></head><body>")
        b.append("<h1>E2E 검증 결과</h1>")
        b.append(meta(job, modelName: modelName, timeZone: timeZone))

        if let error = job.error {
            let steps = job.status == .failed ? (E2EFailureKind.allCases.first { $0.message == error }?.steps ?? []) : []
            b.append(box("warn", title: "검증을 돌리지 못했어요", text: error, steps: steps))
        }
        switch result {
        case .ok(let r):
            if let block = r.loginBlocked {
                let account = job.username.isEmpty ? "테스트 계정" : "테스트 계정(\(job.username))"
                b.append(box("warn", title: "환경 로그인에서 막혔어요", text: block.reason, steps: block.steps(account: account)))
            }
            b.append(summary(r))
            for issue in r.issues { b.append(issueSection(issue, job: job, image: image)) }
        case .invalid(let m):
            b.append(box("warn", title: "result.json 을 읽지 못했어요", text: m, steps: []))
            b.append(log(logTail))
        case .missing:
            if job.error == nil { b.append("<p class=\"dim\">결과가 없어요</p>") }
            b.append(log(logTail))
        }
        b.append("<footer>ATM 자동 검증 결과는 참고용이에요. 가정과 스크린샷을 같이 확인해 주세요.</footer>")
        b.append("</body></html>")
        return b.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// job 폴더의 결과·스크린샷·run.log 로 보고서를 만들어 dir 에 쓴다. 같은 이름이 있으면 덮어쓴다.
    public static func export(_ job: E2EJob, store: E2EJobStore = E2EJobStore(), modelName: String, to dir: URL,
                              timeZone: TimeZone = .current) throws -> URL {
        let text = html(job: job, result: store.result(job.id), modelName: modelName,
                        logTail: store.logTail(job.id, lines: logTailLines), timeZone: timeZone) { name in
            guard let url = store.screenshotURL(job.id, name: name), let data = try? Data(contentsOf: url) else { return nil }
            return Image(mime: mime(url.pathExtension), data: data)
        }
        let url = dir.appendingPathComponent(fileName(job, timeZone: timeZone))
        try Data(text.utf8).write(to: url, options: .atomic)
        return url
    }

    // MARK: - 조각

    private static func meta(_ job: E2EJob, modelName: String, timeZone: TimeZone) -> String {
        var rows: [(String, String)] = []
        if !job.issues.isEmpty { rows.append(("이슈", job.issueKeys.joined(separator: ", "))) }
        rows.append(("환경", job.env.rawValue + (job.readOnly ? " · 조회만" : "")))
        rows.append(("주소", job.baseUrl))
        if !job.username.isEmpty { rows.append(("테스트 계정", job.username)) }
        rows.append(("모델", modelName))
        var time = stamp(job.createdAt, "yyyy-MM-dd HH:mm", timeZone)
        if let end = job.finishedAt { time += " ~ " + stamp(end, "HH:mm", timeZone) }
        rows.append(("실행", time))
        rows.append(("상태", job.status.label))
        if !job.notes.isEmpty { rows.append(("추가 요청사항", job.notes)) }
        let cells = rows.map { "<tr><th>\(esc($0.0))</th><td>\(esc($0.1))</td></tr>" }
        return "<table class=\"meta\">\(cells.joined())</table>"
    }

    private static func summary(_ r: E2EResult) -> String {
        let counts = r.counts
        let badges = E2EVerdict.displayOrder.compactMap { v in counts[v].map { badge(v, count: $0) } }
        guard !badges.isEmpty || !r.summary.isEmpty else { return "" }
        let text = r.summary.isEmpty ? "" : "<p>\(esc(r.summary))</p>"
        return "<section class=\"summary\"><div>\(badges.joined(separator: " "))</div>\(text)</section>"
    }

    private static func issueSection(_ issue: E2EIssueResult, job: E2EJob, image: (String) -> Image?) -> String {
        let ref = job.issues.first { $0.key == issue.key }
        let key = ref?.webURL.map { "<a href=\"\(esc($0.absoluteString))\">\(esc(issue.key))</a>" } ?? esc(issue.key)
        let title = issue.title.isEmpty ? (ref?.title ?? "") : issue.title
        var b: [String] = ["<section class=\"issue\">"]
        b.append("<h2>\(key) \(esc(title)) \(badge(issue.verdict))</h2>")
        if !issue.assumptions.isEmpty {
            b.append("<div class=\"box warn\"><strong>가정</strong>\(list(issue.assumptions, ordered: false))</div>")
        }
        for s in issue.scenarios { b.append(scenario(s, image: image)) }
        if !issue.notes.isEmpty { b.append("<p class=\"dim\">\(esc(issue.notes))</p>") }
        b.append("</section>")
        return b.joined(separator: "\n")
    }

    private static func scenario(_ s: E2EScenario, image: (String) -> Image?) -> String {
        var b: [String] = ["<div class=\"scenario\">"]
        b.append("<h3>\(esc(s.name)) \(badge(s.verdict))</h3>")
        if !s.steps.isEmpty { b.append(list(s.steps, ordered: true)) }
        var rows: [String] = []
        if !s.expected.isEmpty { rows.append("<tr><th>기대</th><td>\(esc(s.expected))</td></tr>") }
        if !s.actual.isEmpty { rows.append("<tr><th>실제</th><td>\(esc(s.actual))</td></tr>") }
        if !rows.isEmpty { b.append("<table class=\"meta\">\(rows.joined())</table>") }
        for name in s.screenshots {
            guard let img = image(name) else { continue }
            let caption = (name as NSString).lastPathComponent
            b.append("<figure><img alt=\"\(esc(caption))\" src=\"data:\(img.mime);base64,\(img.data.base64EncodedString())\">"
                     + "<figcaption>\(esc(caption))</figcaption></figure>")
        }
        b.append("</div>")
        return b.joined(separator: "\n")
    }

    private static func box(_ kind: String, title: String, text: String, steps: [String]) -> String {
        "<div class=\"box \(kind)\"><strong>\(esc(title))</strong><p>\(esc(text))</p>\(steps.isEmpty ? "" : list(steps, ordered: true))</div>"
    }

    private static func log(_ tail: String) -> String {
        tail.isEmpty ? "" : "<h3>run.log 마지막 부분</h3><pre>\(esc(tail))</pre>"
    }

    private static func list(_ items: [String], ordered: Bool) -> String {
        let tag = ordered ? "ol" : "ul"
        return "<\(tag)>\(items.map { "<li>\(esc($0))</li>" }.joined())</\(tag)>"
    }

    private static func badge(_ verdict: E2EVerdict?, count: Int? = nil) -> String {
        let text = [verdict?.rawValue ?? "?", count.map(String.init)].compactMap { $0 }.joined(separator: " ")
        return "<span class=\"badge \(verdict?.rawValue.lowercased() ?? "unknown")\">\(text)</span>"
    }

    // MARK: - 글자 처리

    static func esc(_ s: String) -> String {
        var out = ""
        for ch in s {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(ch)
            }
        }
        return out
    }

    /// 파일 이름에 써도 되는 글자(영문·숫자·-·_)만 남긴다.
    static func safe(_ s: String) -> String {
        String(s.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }.prefix(40))
    }

    public static func mime(_ ext: String) -> String {
        switch ext.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "webp": return "image/webp"
        case "gif": return "image/gif"
        default: return "image/png"
        }
    }

    static func stamp(_ date: Date, _ format: String, _ timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = format
        return f.string(from: date)
    }

    private static let style = """
    :root { color-scheme: light dark; --line: rgba(128,128,128,.3); --soft: rgba(128,128,128,.1); }
    body { font: 14px/1.55 -apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", "Malgun Gothic", sans-serif; max-width: 920px; margin: 0 auto; padding: 24px 20px 48px; }
    h1 { font-size: 20px; margin: 0 0 12px; }
    h2 { font-size: 16px; margin: 0 0 10px; }
    h3 { font-size: 14px; margin: 0 0 6px; }
    p, td, li, pre { white-space: pre-wrap; overflow-wrap: anywhere; }
    p { margin: 6px 0; }
    ol, ul { margin: 4px 0; padding-left: 22px; }
    table.meta { border-collapse: collapse; margin: 6px 0; }
    table.meta th { text-align: left; font-weight: 600; opacity: .65; padding: 2px 14px 2px 0; vertical-align: top; white-space: nowrap; }
    table.meta td { padding: 2px 0; }
    section { border: 1px solid var(--line); border-radius: 8px; padding: 14px 16px; margin: 14px 0; }
    .scenario { border-top: 1px solid var(--line); padding-top: 12px; margin-top: 12px; }
    .box { border-radius: 6px; padding: 10px 12px; margin: 10px 0; background: var(--soft); }
    .box.warn { background: rgba(255,149,0,.14); }
    .badge { display: inline-block; font-size: 11px; font-weight: 700; padding: 1px 6px; border-radius: 4px; vertical-align: middle; background: var(--soft); }
    .badge.pass { color: #1a7f37; background: rgba(26,127,55,.14); }
    .badge.fail { color: #d1242f; background: rgba(209,36,47,.14); }
    .badge.blocked { color: #b35900; background: rgba(255,149,0,.18); }
    .dim, footer, figcaption { opacity: .65; }
    figure { margin: 10px 0 0; }
    figure img { max-width: 100%; border: 1px solid var(--line); border-radius: 4px; }
    figcaption { font-size: 12px; }
    pre { font: 12px/1.45 ui-monospace, Menlo, monospace; background: var(--soft); border-radius: 6px; padding: 10px 12px; }
    footer { font-size: 12px; margin-top: 20px; }
    """
}
