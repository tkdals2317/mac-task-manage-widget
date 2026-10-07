import SwiftUI
import TaskWidgetCore

@MainActor
final class AppState: ObservableObject {
    @Published var todos: [Todo]
    @Published var jiraIssues: [JiraIssue] = []
    @Published var jiraError: String?
    @Published var jiraUpdatedAt: Date?
    @Published var jiraLoading = false
    @Published var jiraConfigured = false
    @Published var jiraTruncated = false
    @Published var summary: Summary?
    @Published var worklogRaw: String?
    @Published var summaryDay = Date()
    @Published var summaryGenerating = false
    @Published var summaryError: String?
    @Published var tagConfig: TagConfig
    let todoStore: TodoStore
    let tagStore = TagStore()

    /// runner 는 호출 시점의 설정(모델, 경로)을 읽는다.
    let summaryService = SummaryService(instructions: {
        let s = Settings.shared.summaryInstructions
        return s.isEmpty ? nil : s
    }) { prompt in
        let s = Settings.shared
        return try ClaudeRunner(configuredPath: s.claudePath, model: s.claudeModel).run(prompt: prompt)
    }

    init(todoStore: TodoStore = TodoStore()) {
        self.todoStore = todoStore
        self.todos = todoStore.load()
        self.tagConfig = tagStore.load()
        enforceSingleSelect()
    }

    // MARK: - Todos

    /// byTag 는 호출하는 뷰가 @AppStorage 로 읽어 넘긴다 (토글 시 다시 그려지도록).
    func openTodos(byTag: Bool) -> [Todo] {
        TagSort.sorted(todos.filter { !$0.done }, config: tagConfig, byTag: byTag)
    }

    var doneTodos: [Todo] {
        todos.filter(\.done).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    func addTodo(_ raw: String) {
        guard let title = Todo.normalizedTitle(raw) else { return }
        todos.append(Todo(title: title))
        persistTodos()
    }

    func toggle(_ todo: Todo) {
        update(todo.id) {
            $0.done.toggle()
            $0.completedAt = $0.done ? Date() : nil
        }
    }

    func setDue(_ todo: Todo, _ dayKey: String?) {
        update(todo.id) { $0.dueDate = dayKey }
    }

    /// 제목 수정. 공백만이면 무시.
    func rename(_ todo: Todo, _ raw: String) {
        guard let title = Todo.normalizedTitle(raw), title != todo.title else { return }
        update(todo.id) { $0.title = title }
    }

    func delete(_ todo: Todo) {
        todos.removeAll { $0.id == todo.id }
        persistTodos()
    }

    func clearDone() {
        todos.removeAll(where: \.done)
        persistTodos()
    }

    // MARK: - Tags

    func toggleTag(_ tagId: String, on todo: Todo) {
        let cfg = tagConfig
        update(todo.id) { $0.tagIds = cfg.toggled(tagId, in: $0.tagIds) }
    }

    @discardableResult
    func addTag(toGroup groupId: String, name: String, colorHex: String) -> Tag {
        let t = Tag(name: name, colorHex: colorHex)
        editGroup(groupId) { $0.tags.append(t) }
        return t
    }

    func updateTag(_ tag: Tag) {
        guard let gi = tagConfig.groups.firstIndex(where: { $0.tags.contains { $0.id == tag.id } }),
              let ti = tagConfig.groups[gi].tags.firstIndex(where: { $0.id == tag.id }) else { return }
        tagConfig.groups[gi].tags[ti] = tag
        persistTags()
    }

    func moveTags(in groupId: String, from: IndexSet, to: Int) {
        editGroup(groupId) { $0.tags.move(fromOffsets: from, toOffset: to) }
    }

    func deleteTag(_ id: String) {
        for gi in tagConfig.groups.indices { tagConfig.groups[gi].tags.removeAll { $0.id == id } }
        persistTags()
        stripUnknownTagIds()
    }

    @discardableResult
    func addGroup() -> TagGroup {
        let g = TagGroup(name: "새 그룹", selection: .multiple)
        tagConfig.groups.append(g)
        persistTags()
        return g
    }

    func renameGroup(_ id: String, _ name: String) {
        editGroup(id) { $0.name = name }
    }

    func moveGroup(_ id: String, by delta: Int) {
        guard let i = tagConfig.groups.firstIndex(where: { $0.id == id }) else { return }
        let j = i + delta
        guard tagConfig.groups.indices.contains(j) else { return }
        tagConfig.groups.swapAt(i, j)
        persistTags()
    }

    func deleteGroup(_ id: String) {
        tagConfig.groups.removeAll { $0.id == id }
        if tagConfig.sortGroupId == id { tagConfig.sortGroupId = tagConfig.groups.first?.id }
        persistTags()
        stripUnknownTagIds()
    }

    func setSelection(_ id: String, _ mode: TagSelection) {
        editGroup(id) { $0.selection = mode }
        if mode == .single { enforceSingleSelect() }
    }

    func setSortGroup(_ id: String) {
        tagConfig.sortGroupId = id
        persistTags()
    }

    func resetTags() {
        tagConfig = TagDefaults.config
        persistTags()
        stripUnknownTagIds()
    }

    private func editGroup(_ id: String, _ change: (inout TagGroup) -> Void) {
        guard let i = tagConfig.groups.firstIndex(where: { $0.id == id }) else { return }
        change(&tagConfig.groups[i])
        persistTags()
    }

    private func stripUnknownTagIds() {
        let known = Set(tagConfig.allTags.map(\.id))
        for i in todos.indices { todos[i].tagIds.removeAll { !known.contains($0) } }
        persistTodos()
    }

    /// 하나만 그룹에서 2개 이상 가진 할 일은 태그 순서상 첫 번째만 남긴다. 모르는 id 는 건드리지 않는다.
    private func enforceSingleSelect() {
        let known = Set(tagConfig.allTags.map(\.id))
        var changed = false
        for i in todos.indices {
            let ids = todos[i].tagIds
            let fixed = tagConfig.normalized(ids) + ids.filter { !known.contains($0) }
            if Set(fixed) != Set(ids) { todos[i].tagIds = fixed; changed = true }
        }
        if changed { persistTodos() }
    }

    private func persistTags() {
        do { try tagStore.save(tagConfig) } catch { NSLog("tags save failed: \(error)") }
    }

    private func update(_ id: UUID, _ change: (inout Todo) -> Void) {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        change(&todos[i])
        persistTodos()
    }

    private func persistTodos() {
        do { try todoStore.save(todos) } catch { NSLog("todos save failed: \(error)") }
    }

    // MARK: - Jira

    private var cachedToken: (account: String, token: String)?

    /// 키체인 접근은 ACL 프롬프트로 무기한 블록될 수 있어 메인 스레드 밖에서만 한다.
    func jiraToken(for account: String) async -> String? {
        if let c = cachedToken, c.account == account { return c.token }
        let t = await Task.detached { Keychain.get(account: account) }.value
        if let t { cachedToken = (account, t) }
        return t
    }

    func setJiraToken(_ token: String, account: String) async throws {
        try await Task.detached { try Keychain.set(token, account: account) }.value
        cachedToken = (account, token)
    }

    func refreshJira() async {
        let s = Settings.shared
        let token = s.jiraEmail.isEmpty ? nil : await jiraToken(for: s.jiraEmail)
        jiraConfigured = token != nil
        guard let token, let url = URL(string: s.jiraBaseURL) else { return }
        guard !jiraLoading else { return }
        jiraLoading = true
        defer { jiraLoading = false }
        let client = JiraClient(baseURL: url, email: s.jiraEmail, token: token)
        do {
            let page = try await client.fetchMyOpenIssues(jql: JiraClient.effectiveJQL(custom: s.jiraJQL))
            jiraIssues = JiraClient.sortedForDisplay(page.issues)
            jiraTruncated = page.truncated
            jiraUpdatedAt = Date()
            jiraError = nil
        } catch let e as JiraError {
            // JiraClient 는 취소(URLError.cancelled)도 .network 로 감싸 던지므로 태스크 취소 여부로 거른다
            if Task.isCancelled { return }
            if case .unauthorized = e { cachedToken = nil }
            jiraError = e.userMessage
        } catch {
            // 갱신 주기 변경/뷰 사라짐으로 .task 가 취소된 경우는 오류가 아님
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            jiraError = error.localizedDescription
        }
    }

    // MARK: - Summary

    func loadSummary(for day: Date) {
        summaryDay = day
        summary = summaryService.existing(for: day)
        worklogRaw = Worklog.raw(on: day)
    }

    /// 성공하면 true. 실패는 summaryError 에.
    @discardableResult
    func generateSummary(for day: Date, force: Bool) async -> Bool {
        guard !summaryGenerating else { return false }
        summaryGenerating = true
        summaryError = nil
        defer { summaryGenerating = false }
        let service = summaryService
        do {
            let s = try await Task.detached { try service.generate(for: day, force: force) }.value
            if Calendar.current.isDate(day, inSameDayAs: summaryDay) { summary = s }
            return true
        } catch let e as SummaryError {
            summaryError = e.userMessage
        } catch {
            summaryError = error.localizedDescription
        }
        return false
    }
}
