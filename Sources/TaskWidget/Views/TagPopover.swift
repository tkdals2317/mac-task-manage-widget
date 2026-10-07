import SwiftUI
import TaskWidgetCore

extension TagColor {
    var color: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .teal: return .teal
        case .blue: return .blue
        case .purple: return .purple
        case .gray: return .gray
        }
    }
}

struct TagCapsule: View {
    let tag: Tag
    @Environment(\.fontScale) private var scale

    var body: some View {
        let gray = tag.color == .gray
        Text(tag.name)
            .font(.system(size: 11 * scale))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .foregroundStyle(gray ? Color.primary.opacity(0.75) : tag.color.color)
            .background(gray ? Color.primary.opacity(0.09) : tag.color.color.opacity(0.2))
            .clipShape(Capsule())
    }
}

struct TagPopover: View {
    let todo: Todo
    @EnvironmentObject var state: AppState
    @Environment(\.fontScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(state.tags) { tag in
                Button { state.toggleTag(tag.id, on: todo) } label: {
                    HStack(spacing: 8) {
                        Circle().fill(tag.color.color).frame(width: 8, height: 8)
                        Text(tag.name).font(.system(size: 12 * scale))
                        Spacer(minLength: 12)
                        if todo.tagIds.contains(tag.id) {
                            Image(systemName: "checkmark").font(.system(size: 10 * scale, weight: .semibold))
                        }
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
            }
            if state.tags.isEmpty {
                Text("태그 없음").font(.system(size: 11 * scale)).foregroundStyle(.tertiary)
            }
            Divider().padding(.vertical, 2)
            Button("태그 관리…") { NotificationCenter.default.post(name: .openSettings, object: nil) }
                .buttonStyle(.plain)
                .font(.system(size: 11 * scale))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(minWidth: 150)
    }
}
