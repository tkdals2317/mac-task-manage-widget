import Foundation

/// E2E 검증에 넘길 이슈 본문 (REST API v2: 설명·댓글이 위키 마크업 문자열로 온다).
public struct JiraIssueDetail: Equatable {
    public struct Comment: Equatable {
        public var author: String
        public var created: String
        public var body: String
    }

    public struct Attachment: Equatable {
        public var id: String
        public var filename: String
        public var mimeType: String
        public var size: Int
        public var content: URL?

        public var isImage: Bool { mimeType.lowercased().hasPrefix("image/") }
    }

    public struct Related: Equatable {
        /// "relates to", "is blocked by", "하위 작업" 등
        public var relation: String
        public var key: String
        public var summary: String
        public var status: String
    }

    public struct RemoteLink: Equatable {
        public var title: String
        public var url: String
    }

    public var key: String
    public var summary: String
    public var type: String
    public var status: String
    public var priority: String
    public var assignee: String
    public var reporter: String
    public var labels: [String]
    public var components: [String]
    public var fixVersions: [String]
    public var description: String
    public var parent: Related?
    public var related: [Related]
    public var comments: [Comment]
    public var attachments: [Attachment]
    public var remoteLinks: [RemoteLink] = []

    // MARK: - Decoding

    private struct Named: Decodable { let name: String?; let displayName: String? }
    private struct Ref: Decodable {
        struct F: Decodable { let summary: String?; let status: Named? }
        let key: String
        let fields: F?
    }
    private struct LinkJSON: Decodable {
        struct LinkType: Decodable { let inward: String?; let outward: String? }
        let type: LinkType?
        let inwardIssue: Ref?
        let outwardIssue: Ref?
    }
    private struct CommentJSON: Decodable { let author: Named?; let body: String?; let created: String? }
    private struct AttachmentJSON: Decodable {
        let id: String?; let filename: String?; let mimeType: String?; let size: Int?; let content: String?
    }
    private struct Fields: Decodable {
        struct Comments: Decodable { let comments: [CommentJSON]? }
        let summary: String?
        let description: String?
        let status: Named?
        let issuetype: Named?
        let priority: Named?
        let assignee: Named?
        let reporter: Named?
        let labels: [String]?
        let components: [Named]?
        let fixVersions: [Named]?
        let parent: Ref?
        let subtasks: [Ref]?
        let issuelinks: [LinkJSON]?
        let comment: Comments?
        let attachment: [AttachmentJSON]?
    }
    private struct IssueJSON: Decodable { let key: String; let fields: Fields }

    public static func decode(_ data: Data) throws -> JiraIssueDetail {
        let i = try JSONDecoder().decode(IssueJSON.self, from: data)
        let f = i.fields
        func related(_ r: Ref, _ relation: String) -> Related {
            Related(relation: relation, key: r.key, summary: r.fields?.summary ?? "", status: r.fields?.status?.name ?? "")
        }
        var rel = (f.subtasks ?? []).map { related($0, "하위 작업") }
        for l in f.issuelinks ?? [] {
            if let o = l.outwardIssue { rel.append(related(o, l.type?.outward ?? "연결")) }
            if let n = l.inwardIssue { rel.append(related(n, l.type?.inward ?? "연결")) }
        }
        return JiraIssueDetail(
            key: i.key,
            summary: f.summary ?? "",
            type: f.issuetype?.name ?? "",
            status: f.status?.name ?? "",
            priority: f.priority?.name ?? "",
            assignee: f.assignee?.displayName ?? "",
            reporter: f.reporter?.displayName ?? "",
            labels: f.labels ?? [],
            components: (f.components ?? []).compactMap(\.name),
            fixVersions: (f.fixVersions ?? []).compactMap(\.name),
            description: f.description ?? "",
            parent: f.parent.map { related($0, "상위") },
            related: rel,
            comments: (f.comment?.comments ?? []).map {
                Comment(author: $0.author?.displayName ?? "", created: $0.created ?? "", body: $0.body ?? "")
            },
            attachments: (f.attachment ?? []).compactMap { a in
                guard let id = a.id else { return nil }
                return Attachment(id: id, filename: a.filename ?? id, mimeType: a.mimeType ?? "", size: a.size ?? 0,
                                  content: a.content.flatMap(URL.init(string:)))
            })
    }

    public static func decodeRemoteLinks(_ data: Data) -> [RemoteLink] {
        struct R: Decodable { struct O: Decodable { let url: String?; let title: String? }; let object: O? }
        return ((try? JSONDecoder().decode([R].self, from: data)) ?? []).compactMap { r in
            guard let url = r.object?.url, !url.isEmpty else { return nil }
            return RemoteLink(title: r.object?.title ?? url, url: url)
        }
    }
}

extension JiraClient {
    static let detailFields = "summary,description,status,issuetype,priority,assignee,reporter,labels,components,fixVersions,parent,subtasks,issuelinks,comment,attachment"

    /// 이슈 본문·댓글·연결·첨부 목록. 원격 링크(PR 등)는 실패해도 빈 목록으로.
    public func fetchIssueDetail(key: String) async throws -> JiraIssueDetail {
        var comps = URLComponents(url: baseURL.appendingPathComponent("rest/api/2/issue/\(key)"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "fields", value: Self.detailFields)]
        var d = try JiraIssueDetail.decode(try await get(comps.url!))
        if let data = try? await get(baseURL.appendingPathComponent("rest/api/2/issue/\(key)/remotelink")) {
            d.remoteLinks = JiraIssueDetail.decodeRemoteLinks(data)
        }
        return d
    }

    /// 첨부 내려받기. redirect=false 면 미디어 서버로 넘기지 않고 바로 내용을 준다 (인증 헤더가 다른 호스트로 가지 않게).
    public func downloadAttachment(_ a: JiraIssueDetail.Attachment) async throws -> Data {
        guard let url = a.content, var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw JiraError.message("첨부 주소 없음")
        }
        guard url.host == baseURL.host else { throw JiraError.message("다른 호스트의 첨부") }
        comps.queryItems = (comps.queryItems ?? []) + [URLQueryItem(name: "redirect", value: "false")]
        return try await get(comps.url!)
    }
}
