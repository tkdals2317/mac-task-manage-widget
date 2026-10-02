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
    let todoStore: TodoStore

    init(todoStore: TodoStore = TodoStore()) {
        self.todoStore = todoStore
        self.todos = todoStore.load()
    }

    // MARK: - Todos

    var openTodos: [Todo] { DueBadge.sorted(todos.filter { !$0.done }) }

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

    func delete(_ todo: Todo) {
        todos.removeAll { $0.id == todo.id }
        persistTodos()
    }

    func clearDone() {
        todos.removeAll(where: \.done)
        persistTodos()
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

    func refreshJira() async {
        let s = Settings.shared
        let token = s.jiraEmail.isEmpty ? nil : Keychain.get(account: s.jiraEmail)
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
            jiraError = e.userMessage
        } catch {
            // 갱신 주기 변경/뷰 사라짐으로 .task 가 취소된 경우는 오류가 아님
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            jiraError = error.localizedDescription
        }
    }
}
