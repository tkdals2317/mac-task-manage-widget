import Foundation

public struct StarredPage: Identifiable, Equatable, Codable {
    public let id: String
    public let title: String
    public let spaceKey: String
    public let url: URL
    public let updated: Date?

    public init(id: String, title: String, spaceKey: String, url: URL, updated: Date?) {
        self.id = id; self.title = title; self.spaceKey = spaceKey; self.url = url; self.updated = updated
    }
}

public enum ConfluenceError: Error, Equatable {
    case unauthorized
    case http(Int)
    case network(String)
    case decode

    public var userMessage: String {
        switch self {
        case .unauthorized: return "토큰 확인 필요 (401/403)"
        case .http(let c): return "HTTP \(c)"
        case .network(let m): return "네트워크: \(m)"
        case .decode: return "응답을 읽지 못함"
        }
    }
}

public enum ConfluenceClient {
    public static let cql = "favourite = currentUser() order by lastmodified desc"

    /// Jira 와 같은 Atlassian 계정(이메일+API 토큰)으로 내가 별표한 문서를 가져온다.
    public static func fetchStarred(baseURL: URL, email: String, token: String,
                                    session: URLSession = .shared) async throws -> [StarredPage] {
        var comps = URLComponents(url: baseURL.appendingPathComponent("wiki/rest/api/content/search"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "cql", value: cql),
            URLQueryItem(name: "limit", value: "50"),
            URLQueryItem(name: "expand", value: "space,version"),
        ]
        // URLComponents 는 '+' 를 인코딩하지 않아 서버가 공백으로 읽는다 (JiraClient 와 같은 이유).
        comps.percentEncodedQuery = comps.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        var req = URLRequest(url: comps.url!)
        req.timeoutInterval = 20
        req.setValue("Basic " + Data("\(email):\(token)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        let resp: URLResponse
        do { (data, resp) = try await session.data(for: req) }
        catch is CancellationError { throw CancellationError() }
        catch let e as URLError where e.code == .cancelled { throw e }
        catch { throw ConfluenceError.network(error.localizedDescription) }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200...299: return try decode(data, base: baseURL)
        case 401, 403: throw ConfluenceError.unauthorized
        default: throw ConfluenceError.http(code)
        }
    }

    struct Response: Decodable {
        struct Links: Decodable { let base: String?; let webui: String? }
        struct Space: Decodable { let key: String? }
        struct Version: Decodable { let when: String? }
        struct Result: Decodable {
            let id: String; let title: String
            let space: Space?; let version: Version?; let _links: Links?
        }
        let results: [Result]
        let _links: Links?
    }

    /// `_links.base`(응답 최상위, 보통 …/wiki) + 결과의 `_links.webui`. base 가 없으면 `{base}/wiki`.
    public static func decode(_ data: Data, base: URL) throws -> [StarredPage] {
        guard let r = try? JSONDecoder().decode(Response.self, from: data) else { throw ConfluenceError.decode }
        let root = r._links?.base ?? base.appendingPathComponent("wiki").absoluteString
        return r.results.compactMap { item in
            guard let webui = item._links?.webui, let url = URL(string: root + webui) else { return nil }
            return StarredPage(id: item.id, title: item.title, spaceKey: item.space?.key ?? "",
                               url: url, updated: item.version?.when.flatMap(parseDate))
        }
    }

    // 소수초 유무 둘 다 받는다.
    private static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
