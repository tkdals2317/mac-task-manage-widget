import SwiftUI
import TaskWidgetCore

struct TasksView: View {
    @EnvironmentObject var state: AppState
    @AppStorage(SettingsKey.todoSectionCollapsed) private var todoCollapsed = false
    @AppStorage(SettingsKey.jiraSectionCollapsed) private var jiraCollapsed = false
    @AppStorage(SettingsKey.jiraVersionFilter) private var versionFilter = ""
    @AppStorage(SettingsKey.sortTodosByTag) private var sortByTag = true
    @Environment(\.fontScale) private var scale
    @State private var newTitle = ""
    @State private var doneExpanded = false
    @FocusState private var addFocused: Bool
    @Environment(\.atmAccent) private var accent

    var body: some View {
        let open = state.openTodos(byTag: sortByTag)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "내 할 일", count: open.count, collapsed: $todoCollapsed)
                if !todoCollapsed { todoSection(open) }

                SectionHeader(title: "Jira", count: JiraVersions.filter(state.jiraIssues, VersionFilter(storage: versionFilter)).count, collapsed: $jiraCollapsed) {
                    JiraVersionMenu()
                    Button {
                        Task { await state.refreshJira() }
                    } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 10 * scale))
                    }
                    .buttonStyle(.plain)
                    .help("새로고침")
                }
                if !jiraCollapsed { JiraSection() }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .themedScrollbar()
        .onAppear(perform: consumeFocusRequest)
        .onChange(of: state.focusNewTodo) { _, _ in consumeFocusRequest() }
    }

    private func consumeFocusRequest() {
        guard state.focusNewTodo else { return }
        state.focusNewTodo = false
        todoCollapsed = false
        addFocused = true
    }

    private func todoSection(_ open: [Todo]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("할 일 추가…", text: $newTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 12 * scale))
                .focused($addFocused)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
                // 선택됐을 때만 테마 강조색 테두리 (시스템 파란 포커스 링 대신)
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(addFocused ? accent : Color.primary.opacity(0.12), lineWidth: addFocused ? 1.5 : 0.5))
                .onSubmit {
                    state.addTodo(newTitle)
                    newTitle = ""
                }
                .padding(.vertical, 4)

            ForEach(open) { todo in
                TodoRow(todo: todo)
            }

            if open.isEmpty {
                Text("할 일 없음").font(.system(size: 11.5 * scale)).foregroundStyle(.tertiary).padding(.vertical, 8)
            }

            if !state.doneTodos.isEmpty {
                HStack(spacing: 6) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { doneExpanded.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: doneExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 8 * scale, weight: .semibold))
                            Text("완료 \(state.doneTodos.count)").font(.system(size: 10.5 * scale))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    // 시스템 미니 버튼은 패널 테마와 따로 놀아서 다른 칩 버튼과 같은 모양으로
                    Button { state.clearDone() } label: { AccentChip(icon: "trash", text: "비우기", style: .plain) }
                        .buttonStyle(.plain)
                        .help("완료한 할 일을 모두 지워요")
                }
                .foregroundStyle(.secondary)
                .padding(.top, 8)
                .padding(.bottom, 2)

                if doneExpanded {
                    ForEach(state.doneTodos) { todo in
                        TodoRow(todo: todo)
                    }
                }
            }
        }
    }
}
