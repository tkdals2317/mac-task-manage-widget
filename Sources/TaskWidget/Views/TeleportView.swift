import AppKit
import SwiftUI
import TaskWidgetCore

let teleportDownloadURL = URL(string: "https://goteleport.com/download/")!

struct TeleportView: View {
    @ObservedObject var tp: TeleportManager
    @Environment(\.fontScale) private var scale

    var body: some View {
        if tp.tshPath == nil {
            VStack(spacing: 8) {
                Text("tsh 가 설치되어 있지 않아요").font(.system(size: 13 * scale, weight: .semibold))
                Link("https://goteleport.com/download/", destination: teleportDownloadURL)
                    .font(.system(size: 12 * scale))
                Button("다시 찾기") { tp.locateTsh() }.controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !tp.isConfigured || tp.setupRequested {
            TeleportSetupView(tp: tp)
        } else {
            main
        }
    }

    private var main: some View {
        VStack(spacing: 0) {
            statusCard
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(groups, id: \.name) { g in
                        let on = g.tunnels.filter { tp.state($0) == .connected }.count
                        Text("\(g.name)  \(on)/\(g.tunnels.count) 연결")
                            .font(.system(size: 11 * scale, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 10).padding(.bottom, 4)
                        ForEach(g.tunnels) { TunnelRow(tp: tp, tunnel: $0) }
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                if let m = tp.message {
                    Text(m).foregroundStyle(.red).lineLimit(2).help(m)
                    Button("로그") { NSWorkspace.shared.open(TeleportManager.loginLogURL) }.controlSize(.mini)
                }
                Spacer()
                if let d = tp.lastLogin { Text("마지막 로그인 \(Self.hm.string(from: d))").foregroundStyle(.secondary) }
            }
            .font(.system(size: 10.5 * scale))
            .padding(.horizontal, 12).padding(.vertical, 5)
        }
    }

    private static let hm: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()

    private var groups: [(name: String, tunnels: [TeleportTunnel])] {
        var order: [String] = []
        var map: [String: [TeleportTunnel]] = [:]
        for t in tp.config.tunnels {
            if map[t.group] == nil { order.append(t.group) }
            map[t.group, default: []].append(t)
        }
        return order.map { ($0, map[$0]!) }
    }

    private var statusCard: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                if tp.loggedIn, let until = tp.validUntil {
                    Label("로그인됨", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        .font(.system(size: 12.5 * scale, weight: .semibold))
                    TimelineView(.periodic(from: .now, by: 30)) { _ in
                        Text(TeleportTsh.remainingText(until: until)).foregroundStyle(.green)
                    }
                    .font(.system(size: 11 * scale))
                } else {
                    Label(tp.validUntil == nil ? "로그인 필요" : "세션 만료", systemImage: "minus.circle")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12.5 * scale, weight: .semibold))
                }
            }
            Spacer()
            if let b = tp.busy {
                ProgressView().controlSize(.small)
                Text(b).font(.system(size: 11 * scale)).foregroundStyle(.secondary)
            } else {
                if !tp.loggedIn {
                    Button("다시 로그인") { Task { await tp.ensureLoggedIn(force: true) } }
                }
                Button("모두 연결") { Task { await tp.connectAll() } }
                Button("모두 끊기") { Task { await tp.disconnectAll() } }
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

private struct TunnelRow: View {
    @ObservedObject var tp: TeleportManager
    let tunnel: TeleportTunnel
    @Environment(\.fontScale) private var scale

    var body: some View {
        let st = tp.state(tunnel)
        HStack(spacing: 8) {
            Circle().fill(color(st)).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(tunnel.name).font(.system(size: 12.5 * scale, weight: .medium))
                Text("localhost:\(String(tunnel.port)) · \(label(st))")
                    .font(.system(size: 10.5 * scale)).foregroundStyle(.secondary)
                    .lineLimit(1).help(label(st))
            }
            Spacer()
            if case .failed = st { Button("로그") { NSWorkspace.shared.open(tp.logURL(for: tunnel)) }.controlSize(.mini) }
            Toggle("", isOn: Binding(
                get: { st == .connected || st == .connecting },
                set: { on in Task { if on { await tp.connect(tunnel) } else { tp.disconnect(tunnel) } } }
            ))
            .toggleStyle(PillSwitch()).labelsHidden()
            .disabled(st == .connecting)
        }
        .padding(.vertical, 3)
    }

    private func color(_ s: TunnelState) -> Color {
        switch s {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected: return .secondary.opacity(0.5)
        case .failed, .portInUse: return .red
        }
    }

    private func label(_ s: TunnelState) -> String {
        switch s {
        case .connected: return "연결됨"
        case .connecting: return "연결 중…"
        case .disconnected: return "끊김"
        case .failed(let m): return m
        case .portInUse: return "포트 사용 중 (다른 프로그램)"
        }
    }
}

/// 패널이 key 창이 아니면 기본 스위치가 회색(비활성)으로 그려진다. 상태가 늘 보이게 직접 그린다.
private struct PillSwitch: ToggleStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        Capsule()
            .fill(configuration.isOn ? Color.green : Color.secondary.opacity(0.3))
            .frame(width: 26, height: 15)
            .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                Circle().fill(.white).padding(2).shadow(radius: 0.5)
            }
            .opacity(enabled ? 1 : 0.6)
            .animation(.easeOut(duration: 0.15), value: configuration.isOn)
            .contentShape(Capsule())
            .onTapGesture { if enabled { configuration.isOn.toggle() } }
    }
}
