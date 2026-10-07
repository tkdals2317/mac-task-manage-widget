import SwiftUI
import TaskWidgetCore

extension Color {
    init(hex: String) {
        let c = HexColor.rgb(hex) ?? HexColor.rgb(TagColor.gray.hex)!
        self.init(.sRGB, red: c.r, green: c.g, blue: c.b)
    }

    /// 투명도 없는 sRGB hex. 변환 실패 시 nil.
    var hexString: String? {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return HexColor.hex(r: Double(c.redComponent), g: Double(c.greenComponent), b: Double(c.blueComponent))
    }
}

struct TagCapsule: View {
    let tag: Tag
    @Environment(\.fontScale) private var scale

    var body: some View {
        let gray = tag.colorHex.uppercased() == TagColor.gray.hex
        let base = Color(hex: tag.colorHex)
        Text(tag.name)
            .font(.system(size: 11 * scale))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .foregroundStyle(gray ? Color.primary.opacity(0.75) : base)
            .background(gray ? Color.primary.opacity(0.09) : base.opacity(0.2))
            .clipShape(Capsule())
    }
}

struct TagPopover: View {
    let todo: Todo
    @EnvironmentObject var state: AppState
    @Environment(\.fontScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(state.tagConfig.groups) { group in
                Text(group.selection == .single ? "\(group.name) · 하나만" : group.name)
                    .font(.system(size: 10.5 * scale, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                ForEach(group.tags) { tag in
                    Button { state.toggleTag(tag.id, on: todo) } label: {
                        HStack(spacing: 8) {
                            Circle().fill(Color(hex: tag.colorHex)).frame(width: 8, height: 8)
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
            }
            if state.tagConfig.allTags.isEmpty {
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
