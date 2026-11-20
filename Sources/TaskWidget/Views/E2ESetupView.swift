import SwiftUI
import TaskWidgetCore

extension E2ESetupItem.State {
    var icon: String {
        switch self {
        case .ok: return "checkmark.circle.fill"
        case .todo: return "exclamationmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        case .waiting: return "circle"
        }
    }

    var tint: Color {
        switch self {
        case .ok: return .green
        case .todo, .warn: return .orange
        case .info: return .secondary
        case .waiting: return Color.secondary.opacity(0.5)
        }
    }
}

/// 준비 점검 목록: 항목마다 상태, 막힌 항목에는 할 일과 그 단계를 푸는 버튼. E2E 탭·설정·설정 도우미가 같이 쓴다.
struct E2ESetupList: View {
    @ObservedObject var e2e: E2EModel
    let items: [E2ESetupItem]
    /// 환경을 여는 버튼이 열 환경
    var env: E2EEnv?
    /// 끝난 항목(✓)과 아직 알 수 없는 항목은 숨긴다 (E2E 탭)
    var pendingOnly = false
    /// 목록 아래에 '다시 확인' 버튼을 둔다 (머리글에 버튼이 없는 곳)
    var recheck = false
    @Environment(\.fontScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if e2e.report != nil {
                ForEach(pendingOnly ? items.filter(\.needsAttention) : items) { row($0) }
            } else {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Aside 준비 상태 확인 중…").font(.system(size: 11.5 * scale)).foregroundStyle(.secondary)
                }
            }
            if let error = e2e.setupError {
                Text(error).font(.system(size: 11 * scale)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            if recheck {
                HStack {
                    Spacer(minLength: 0)
                    E2ESetupRecheckButton(e2e: e2e)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ item: E2ESetupItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: item.state.icon).font(.system(size: 11 * scale)).foregroundStyle(item.state.tint)
            VStack(alignment: .leading, spacing: 3) {
                if item.needsAttention {
                    Text(item.title).font(.system(size: 11.5 * scale, weight: .semibold))
                    Text(item.detail).font(.system(size: 11.5 * scale))
                        .foregroundStyle(item.state == .info ? Color.secondary : Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(item.title).font(.system(size: 11.5 * scale, weight: .semibold))
                            .foregroundStyle(item.state == .waiting ? Color.secondary : Color.primary)
                        Text(item.detail).font(.system(size: 11 * scale)).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    }
                }
                ForEach(Array(item.steps.enumerated()), id: \.offset) { i, step in
                    Text("\(i + 1). \(step)").font(.system(size: 11 * scale)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !item.note.isEmpty {
                    Text(item.note).font(.system(size: 10.5 * scale))
                        .foregroundStyle(item.state == .todo ? Color.primary.opacity(0.75) : Color.secondary.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
                fixes(item)
            }
        }
    }

    /// 계정 바꾸기는 이메일이 길어 한 줄씩, 나머지는 옆으로 늘어놓는다.
    @ViewBuilder
    private func fixes(_ item: E2ESetupItem) -> some View {
        let switches = item.fixes.filter { if case .switchAccount = $0 { return true }; return false }
        let others = item.fixes.filter { !switches.contains($0) }
        if !others.isEmpty {
            HStack(spacing: 6) {
                ForEach(Array(others.enumerated()), id: \.offset) { i, fix in
                    fixButton(fix, style: i == 0 && item.state == .todo ? .solid : .soft)
                }
            }
            .padding(.top, 1)
        }
        ForEach(Array(switches.enumerated()), id: \.offset) { _, fix in fixButton(fix, style: .soft) }
    }

    private func fixButton(_ fix: E2ESetupFix, style: AccentChip.Style) -> some View {
        Button { e2e.perform(fix, env: env) } label: { AccentChip(icon: fix.icon, text: fix.label, style: style) }
            .buttonStyle(.plain)
    }
}

struct E2ESetupRecheckButton: View {
    @ObservedObject var e2e: E2EModel

    var body: some View {
        Button { Task { await e2e.checkAside() } } label: {
            AccentChip(icon: "arrow.clockwise", text: e2e.checkingAside ? "확인 중…" : "다시 확인", style: .plain)
        }
        .buttonStyle(.plain)
        .disabled(e2e.checkingAside)
    }
}

/// E2E 탭 위쪽의 준비 점검. 봐야 할 항목(막힘·주의·안내)이 있을 때만 보이고, 실행을 막는 항목이 있으면 접을 수 없다.
struct E2ESetupSection: View {
    @ObservedObject var e2e: E2EModel
    let env: E2EEnv
    @AppStorage private var url: String
    @AppStorage private var user: String
    @AppStorage(SettingsKey.e2eSetupCollapsed) private var collapsed = false

    init(e2e: E2EModel, env: E2EEnv) {
        self.e2e = e2e
        self.env = env
        _url = AppStorage(wrappedValue: "", SettingsKey.e2eURL(env))
        _user = AppStorage(wrappedValue: "", SettingsKey.e2eUser(env))
    }

    var body: some View {
        let items = e2e.setupItems(env: env, url: url, user: user)
        let pending = items.filter(\.needsAttention)
        let blocked = E2ESetup.blocker(items) != nil
        if !pending.isEmpty {
            SectionHeader(title: "준비", count: pending.count, collapsed: blocked ? .constant(false) : $collapsed) {
                E2ESetupRecheckButton(e2e: e2e)
            }
            if blocked || !collapsed {
                E2ESetupList(e2e: e2e, items: items, env: env, pendingOnly: true)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(blocked ? Color.orange.opacity(0.1) : Color.primary.opacity(0.05)))
            }
        }
    }
}
