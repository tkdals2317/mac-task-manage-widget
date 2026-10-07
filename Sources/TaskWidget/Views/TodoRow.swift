import SwiftUI
import TaskWidgetCore

struct TodoRow: View {
    let todo: Todo
    @EnvironmentObject var state: AppState
    @Environment(\.fontScale) private var scale
    @State private var hovering = false
    @State private var showDue = false
    @State private var showTags = false
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var titleFocused: Bool

    var body: some View {
        let badge = DueBadge.badge(due: todo.dueDate, today: Date())
        HStack(spacing: 8) {
            Button { state.toggle(todo) } label: {
                Image(systemName: todo.done ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13 * scale))
                    .foregroundStyle(todo.done ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            if editing {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5 * scale))
                    .focused($titleFocused)
                    .onSubmit { commitEdit() }
                    .onExitCommand { cancelEdit() }
                    .onChange(of: titleFocused) { _, focused in if !focused && editing { commitEdit() } }
            } else {
                Text(todo.title)
                    .font(.system(size: 12.5 * scale))
                    .strikethrough(todo.done)
                    .foregroundStyle(todo.done ? Color.secondary : Color.primary)
                    .lineLimit(1)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { beginEdit() }
                    .help("더블클릭하면 수정")
            }

            Spacer(minLength: 4)

            tagsArea.opacity(todo.done ? 0.5 : 1)

            Button { showDue = true } label: {
                if badge.style == .none {
                    Image(systemName: "calendar")
                        .font(.system(size: 11 * scale))
                        .foregroundStyle(.quaternary)
                } else {
                    Text(badge.text)
                        .font(.system(size: 10.5 * scale, weight: .medium))
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(badgeColor(badge.style).opacity(0.18))
                        .foregroundStyle(badgeColor(badge.style))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showDue) {
                DuePopover(due: todo.dueDate) { key in
                    state.setDue(todo, key)
                }
            }

            Button { state.delete(todo) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9 * scale, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            ForEach(state.tagConfig.groups) { group in
                Menu(group.name) {
                    ForEach(group.tags) { tag in
                        Toggle(tag.name, isOn: Binding(
                            get: { todo.tagIds.contains(tag.id) },
                            set: { _ in state.toggleTag(tag.id, on: todo) }
                        ))
                    }
                }
            }
        }
        Divider()
    }

    @ViewBuilder
    private var tagsArea: some View {
        let shown = TagSort.ordered(todo.tagIds, config: state.tagConfig)
        if shown.isEmpty && !hovering && !showTags {
            EmptyView()
        } else {
            Button { showTags = true } label: {
                HStack(spacing: 3) {
                    if shown.isEmpty {
                        Text("＋태그").font(.system(size: 11 * scale)).foregroundStyle(.tertiary)
                    } else {
                        ForEach(shown.prefix(2)) { TagCapsule(tag: $0) }
                        if shown.count > 2 {
                            Text("+\(shown.count - 2)").font(.system(size: 11 * scale)).foregroundStyle(.secondary)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showTags) { TagPopover(todo: todo).environmentObject(state) }
        }
    }

    private func beginEdit() {
        draft = todo.title
        editing = true
        DispatchQueue.main.async { titleFocused = true }
    }

    private func commitEdit() {
        guard editing else { return }
        editing = false
        state.rename(todo, draft)
    }

    private func cancelEdit() {
        editing = false
        draft = todo.title
    }

    private func badgeColor(_ style: DueStyle) -> Color {
        switch style {
        case .overdue: return .red
        case .today: return .orange
        default: return .secondary
        }
    }
}
