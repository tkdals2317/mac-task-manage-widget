import SwiftUI
import TaskWidgetCore

struct TasksView: View {
    @EnvironmentObject var state: AppState
    @AppStorage(SettingsKey.todoSectionCollapsed) private var todoCollapsed = false
    @AppStorage(SettingsKey.jiraSectionCollapsed) private var jiraCollapsed = false
    @Environment(\.fontScale) private var scale
    @State private var newTitle = ""
    @State private var doneExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "내 할 일", count: state.openTodos.count, collapsed: $todoCollapsed)
                if !todoCollapsed { todoSection }

                SectionHeader(title: "Jira", count: 0, collapsed: $jiraCollapsed)
                if !jiraCollapsed {
                    Text("Jira (Task 15)").font(.system(size: 12 * scale)).foregroundStyle(.secondary).padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
    }

    private var todoSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("할 일 추가…", text: $newTitle)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12 * scale))
                .onSubmit {
                    state.addTodo(newTitle)
                    newTitle = ""
                }
                .padding(.vertical, 4)

            ForEach(state.openTodos) { todo in
                TodoRow(todo: todo)
            }

            if state.openTodos.isEmpty {
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
                    Button("비우기") { state.clearDone() }
                        .controlSize(.mini)
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
