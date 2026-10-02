import Foundation

public enum JiraError: Error, Equatable {
    case unauthorized
    case badQuery(String)
    case http(Int)
    case network(String)

    public var userMessage: String {
        switch self {
        case .unauthorized: return "토큰 확인 필요 (401/403)"
        case .badQuery(let m): return "JQL 오류: \(m)"
        case .http(let c): return "HTTP \(c)"
        case .network(let m): return "네트워크: \(m)"
        }
    }
}

public struct JiraClient {
    public let baseURL: URL
    public let email: String
    public let token: String
    let session: URLSession

    public init(baseURL: URL, email: String, token: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.email = email
        self.token = token
        self.session = session
    }

    public static let defaultJQL = "assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC"

    public static func effectiveJQL(custom: String) -> String {
        let t = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? defaultJQL : t
    }

    // MARK: - Network

    public struct Page: Equatable {
        public let issues: [JiraIssue]
        /// 서버에 더 있는데 100건에서 잘렸는지 (isLast == false)
        public let truncated: Bool
    }

    public func fetchMyOpenIssues(jql: String) async throws -> Page {
        var comps = URLComponents(url: baseURL.appendingPathComponent("rest/api/3/search/jql"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "jql", value: jql),
            URLQueryItem(name: "fields", value: "summary,status,priority,updated"),
            URLQueryItem(name: "maxResults", value: "100"),
        ]
        // URLComponents 는 '+' 를 인코딩하지 않아 서버가 공백으로 읽는다. JQL 의 "C++" 같은 값 보호.
        comps.percentEncodedQuery = comps.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        let data = try await get(comps.url!)
        return try Self.decodePage(data)
    }

    public func whoAmI() async throws -> String {
        struct Me: Decodable { let displayName: String }
        let data = try await get(baseURL.appendingPathComponent("rest/api/3/myself"))
        return try JSONDecoder().decode(Me.self, from: data).displayName
    }

    private func get(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        req.setValue("Basic " + Data("\(email):\(token)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await session.data(for: req)
        } catch {
            throw JiraError.network(error.localizedDescription)
        }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200...299: return data
        case 401, 403: throw JiraError.unauthorized
        case 400: throw JiraError.badQuery(Self.errorMessage(data))
        default: throw JiraError.http(code)
        }
    }

    static func errorMessage(_ data: Data) -> String {
        struct E: Decodable { let errorMessages: [String]? }
        return (try? JSONDecoder().decode(E.self, from: data))?.errorMessages?.first ?? "요청 오류"
    }

    // MARK: - Decoding

    struct SearchResponse: Decodable { let issues: [Issue]; let isLast: Bool? }
    struct Issue: Decodable { let key: String; let fields: Fields }
    struct Fields: Decodable {
        let summary: String
        let status: Status
        let priority: Priority?
        let updated: String
    }
    struct Status: Decodable { let name: String; let statusCategory: Category }
    struct Category: Decodable { let key: String }
    struct Priority: Decodable { let name: String }

    static let jiraDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        return f
    }()

    public static func decodePage(_ data: Data) throws -> Page {
        let r = try JSONDecoder().decode(SearchResponse.self, from: data)
        let issues = r.issues.map { i in
            JiraIssue(id: i.key,
                      summary: i.fields.summary,
                      status: i.fields.status.name,
                      statusCategory: i.fields.status.statusCategory.key,
                      priority: i.fields.priority?.name,
                      updated: jiraDate.date(from: i.fields.updated) ?? .distantPast)
        }
        return Page(issues: issues, truncated: r.isLast == false)
    }

    public static func decodeSearch(_ data: Data) throws -> [JiraIssue] {
        try decodePage(data).issues
    }

    // MARK: - Display order

    static func categoryRank(_ key: String) -> Int {
        switch key {
        case "indeterminate": return 0
        case "new": return 1
        default: return 2
        }
    }

    public static func sortedForDisplay(_ issues: [JiraIssue]) -> [JiraIssue] {
        issues.sorted { a, b in
            let ra = categoryRank(a.statusCategory), rb = categoryRank(b.statusCategory)
            if ra != rb { return ra < rb }
            if a.status != b.status { return a.status < b.status }
            return a.updated > b.updated
        }
    }

    public struct Group: Equatable {
        public let status: String
        public let issues: [JiraIssue]
    }

    public static func grouped(_ issues: [JiraIssue]) -> [Group] {
        var out: [Group] = []
        for i in sortedForDisplay(issues) {
            if let last = out.last, last.status == i.status {
                out[out.count - 1] = Group(status: last.status, issues: last.issues + [i])
            } else {
                out.append(Group(status: i.status, issues: [i]))
            }
        }
        return out
    }
}
