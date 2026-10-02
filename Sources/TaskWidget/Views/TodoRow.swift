import SwiftUI
import TaskWidgetCore

struct TodoRow: View {
    let todo: Todo
    @EnvironmentObject var state: AppState
    @Environment(\.fontScale) private var scale
    @State private var hovering = false
    @State private var showDue = false

    var body: some View {
        let badge = DueBadge.badge(due: todo.dueDate, today: Date())
        HStack(spacing: 8) {
            Button { state.toggle(todo) } label: {
                Image(systemName: todo.done ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13 * scale))
                    .foregroundStyle(todo.done ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            Text(todo.title)
                .font(.system(size: 12.5 * scale))
                .strikethrough(todo.done)
                .foregroundStyle(todo.done ? Color.secondary : Color.primary)
                .lineLimit(1)

            Spacer(minLength: 4)

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
        Divider()
    }

    private func badgeColor(_ style: DueStyle) -> Color {
        switch style {
        case .overdue: return .red
        case .today: return .orange
        default: return .secondary
        }
    }
}
