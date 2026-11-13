import SwiftUI
import TaskWidgetCore

extension E2EVerdict {
    var color: Color {
        switch self {
        case .pass: return .green
        case .fail: return .red
        case .blocked: return .orange
        case .skipped: return .secondary
        }
    }
}

/// PASS / FAIL / BLOCKED / SKIPPED 작은 알약. count 를 주면 "FAIL 2".
struct E2EVerdictBadge: View {
    let verdict: E2EVerdict?
    var count: Int?
    @Environment(\.fontScale) private var scale

    var body: some View {
        let tint = verdict?.color ?? .secondary
        Text([verdict?.rawValue ?? "?", count.map(String.init)].compactMap { $0 }.joined(separator: " "))
            .font(.system(size: 9.5 * scale, weight: .bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(tint.opacity(0.16)))
            .fixedSize()
    }
}

/// 환경 표시 (DV / ST / ST2 / PR). PR 은 운영이라 주황.
struct E2EEnvTag: View {
    let env: E2EEnv
    @Environment(\.fontScale) private var scale

    var body: some View {
        Text(env.rawValue)
            .font(.system(size: 9.5 * scale, weight: .semibold))
            .foregroundStyle(env == .pr ? Color.orange : Color.primary.opacity(0.75))
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 3).fill((env == .pr ? Color.orange : Color.primary).opacity(0.1)))
    }
}

/// 이력·상세에서 job 상태 한 덩어리: 실행 중 · 대기 · 판정 수 · 실패/취소.
struct E2EJobStatusView: View {
    @ObservedObject var e2e: E2EModel
    let job: E2EJob
    @Environment(\.fontScale) private var scale

    var body: some View {
        if e2e.running == job.id {
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    Text("실행 중 · \(minutes(since: e2e.runningSince ?? job.createdAt, now: ctx.date))")
                }
            }
            .font(.system(size: 10.5 * scale))
            .foregroundStyle(.secondary)
        } else if let i = e2e.queued.firstIndex(of: job.id) {
            Text("대기 \(i + 1)번째").font(.system(size: 10.5 * scale)).foregroundStyle(.secondary)
        } else if job.status == .done, case .ok(let r) = e2e.results[job.id] {
            let counts = r.counts
            HStack(spacing: 3) {
                ForEach(E2EVerdict.displayOrder, id: \.self) { v in
                    if let n = counts[v] { E2EVerdictBadge(verdict: v, count: n) }
                }
            }
        } else {
            Text(job.status.label)
                .font(.system(size: 10.5 * scale, weight: .medium))
                .foregroundStyle(job.status == .failed ? Color.red : Color.secondary)
        }
    }

    private func minutes(since start: Date, now: Date) -> String {
        let m = Int(now.timeIntervalSince(start) / 60)
        return m < 1 ? "1분 미만" : "\(m)분"
    }
}
