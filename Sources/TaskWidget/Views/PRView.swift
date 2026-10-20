import AppKit
import SwiftUI
import TaskWidgetCore

/// PR 탭: 나한테 온 리뷰 요청 + 내가 올린 PR 의 승인 상태. 구조는 TasksView 와 같다 (SectionHeader + 행).
struct PRView: View {
    @ObservedObject var pr: PRModel
    @EnvironmentObject var state: AppState
    @Environment(\.fontScale) private var scale
    @Environment(\.atmAccent) private var accent
    @AppStorage(SettingsKey.prFilter) private var filter = "all"
    @AppStorage(SettingsKey.prReviewCollapsed) private var reviewCollapsed = false
    @AppStorage(SettingsKey.prMineCollapsed) private var mineCollapsed = false
    @AppStorage(SettingsKey.prGitHubEnabled) private var ghOn = false
    @AppStorage(SettingsKey.prBitbucketEnabled) private var bbOn = false
    @AppStorage(SettingsKey.prStaleDays) private var staleDays = 2
    @State private var expanded: String?

    private var effectiveFilter: String {
        (filter == "github" && ghOn) || (filter == "bitbucket" && bbOn) ? filter : "all"
    }

    private func visible(_ list: [PullRequest]) -> [PullRequest] {
        effectiveFilter == "all" ? list : list.filter { $0.provider.rawValue == effectiveFilter }
    }

    var body: some View {
        let now = Date()
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !ghOn && !bbOn {
                    connectCard
                } else {
                    topRow
                    ForEach(errors, id: \.self) { errorLine($0) }
                    if ghOn, pr.githubStatus == .ghMissing || pr.githubStatus == .loggedOut {
                        notConnected("GitHub")
                    }
                    if bbOn, pr.bitbucketStatus == .notConfigured { notConnected("Bitbucket") }

                    let rr = visible(pr.reviewRequests), mine = visible(pr.mine)
                    SectionHeader(title: "리뷰 요청", count: rr.count, collapsed: $reviewCollapsed)
                    if !reviewCollapsed {
                        ForEach(rr) { row($0, review: true, now: now) }
                        if rr.isEmpty && pr.lastRefresh != nil {
                            Text("✓ 밀린 리뷰 없어요").font(.system(size: 11.5 * scale)).foregroundStyle(.secondary).padding(.vertical, 8)
                        }
                    }
                    SectionHeader(title: "내 PR", count: mine.count, collapsed: $mineCollapsed)
                    if !mineCollapsed {
                        ForEach(mine) { row($0, review: false, now: now) }
                        if mine.isEmpty && pr.lastRefresh != nil {
                            Text("열린 PR 이 없어요").font(.system(size: 11.5 * scale)).foregroundStyle(.secondary).padding(.vertical, 8)
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .task {
            if !ghOn && !bbOn { await pr.probeGitHub() }
            await pr.refreshIfStale()
        }
        // 4초 이상 보고 있었으면 "봤다" 로. 패널이 숨겨진 채로 받은 새 PR 은 표시하지 않는다.
        .task(id: pr.reviewRequests.map(\.id)) {
            guard (try? await Task.sleep(nanoseconds: 4_000_000_000)) != nil,
                  NSApp.windows.contains(where: { $0 is FloatingPanel && $0.isVisible }) else { return }
            pr.markSeen()
        }
        .onDisappear { pr.markSeen() }
        .onChange(of: ghOn) { _, _ in Task { await pr.refresh() } }
        .onChange(of: bbOn) { _, _ in Task { await pr.refresh() } }
    }

    // MARK: - 위쪽

    private var errors: [String] {
        var r: [String] = []
        if ghOn, let e = pr.githubError { r.append("GitHub 불러오기 실패 · \(e)") }
        else if ghOn, case .error(let e) = pr.githubStatus { r.append("GitHub 불러오기 실패 · \(e)") }
        if bbOn, let e = pr.bitbucketError { r.append("Bitbucket 불러오기 실패 · \(e)") }
        else if bbOn, case .error(let e) = pr.bitbucketStatus { r.append("Bitbucket 불러오기 실패 · \(e)") }
        return r
    }

    private func errorLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11 * scale)).foregroundStyle(.red).lineLimit(2)
            .padding(.horizontal, 8).padding(.vertical, 4).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.red.opacity(0.1)))
            .padding(.top, 4)
    }

    private func notConnected(_ name: String) -> some View {
        HStack(spacing: 8) {
            Text("\(name) 이 아직 연결 안 됐어요").font(.system(size: 11.5 * scale)).foregroundStyle(.secondary)
            Spacer()
            Button { openSettings() } label: { AccentChip(icon: "gearshape", text: "설정", style: .soft) }.buttonStyle(.plain)
        }
        .padding(8)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .padding(.top, 6)
    }

    private func openSettings() { NotificationCenter.default.post(name: .openSettings, object: "pr") }

    private func count(_ p: PRProvider) -> Int {
        (pr.reviewRequests + pr.mine).filter { $0.provider == p }.count
    }

    private var topRow: some View {
        HStack(spacing: 6) {
            if ghOn && bbOn {
                filterChip("전체", "all")
                filterChip("GitHub \(count(.github))", "github")
                filterChip("Bitbucket \(count(.bitbucket))", "bitbucket")
            }
            Spacer()
            if let t = pr.lastRefresh {
                Text(t.formatted(date: .omitted, time: .shortened)).font(.system(size: 10.5 * scale)).foregroundStyle(.secondary)
            }
            if pr.loading {
                ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 14, height: 14)
            } else {
                Button { Task { await pr.refresh() } } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10 * scale))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("새로고침")
            }
        }
        .padding(.top, 8)
    }

    private func filterChip(_ text: String, _ id: String) -> some View {
        let on = effectiveFilter == id
        return Button { filter = id } label: {
            Text(text).font(.system(size: 11 * scale, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? accent : Color.secondary)
                .padding(.horizontal, 8).padding(.vertical, 2.5)
                .background(Capsule().fill(on ? accent.opacity(0.16) : Color.primary.opacity(0.05)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 연결 카드

    private var connectCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.triangle.pull").font(.system(size: 28 * scale)).foregroundStyle(accent)
            Text("PR 을 연결해 보세요").font(.system(size: 14 * scale, weight: .medium))
            Text("나한테 온 리뷰 요청과 내가 올린 PR 의 승인 상태를 모아 보고, 승인되면 알려줘요.")
                .font(.system(size: 11.5 * scale)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 6) {
                connectRow("GitHub", githubHint) {
                    if case .ok = pr.githubStatus {
                        Button { Settings.shared.prGitHubEnabled = true } label: { AccentChip(icon: "power", text: "켜기", style: .solid) }.buttonStyle(.plain)
                    } else {
                        Button { openSettings() } label: { AccentChip(icon: "gearshape", text: "설정", style: .soft) }.buttonStyle(.plain)
                    }
                }
                connectRow("Bitbucket", "API 토큰으로 연결해요") {
                    Button { openSettings() } label: { AccentChip(icon: "link", text: "연결하기", style: .soft) }.buttonStyle(.plain)
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 36).padding(.horizontal, 6)
    }

    private var githubHint: String {
        switch pr.githubStatus {
        case .ok(let l): return "gh 로그인됨 · \(l)"
        case .ghMissing: return "gh 가 없어요"
        case .loggedOut: return "gh 로그인이 필요해요"
        case .error(let e): return e
        case .off: return "확인 중…"
        }
    }

    private func connectRow<T: View>(_ name: String, _ hint: String, @ViewBuilder _ action: () -> T) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 12 * scale, weight: .semibold))
                Text(hint).font(.system(size: 10.5 * scale)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            action()
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }

    // MARK: - 행

    private func row(_ p: PullRequest, review: Bool, now: Date) -> some View {
        PRRow(pr: p, review: review, now: now, staleDays: staleDays, isNew: review && !pr.seen.contains(p.id),
              expanded: expanded == p.id, model: pr) {
            withAnimation(.easeInOut(duration: 0.15)) { expanded = expanded == p.id ? nil : p.id }
        }
    }
}

// MARK: - 행 하나

private struct PRRow: View {
    let pr: PullRequest
    let review: Bool
    let now: Date
    let staleDays: Int
    let isNew: Bool
    let expanded: Bool
    @ObservedObject var model: PRModel
    let toggle: () -> Void
    @EnvironmentObject var state: AppState
    @Environment(\.fontScale) private var scale
    @Environment(\.atmAccent) private var accent
    @State private var hovering = false
    @State private var copied: String?
    @State private var confirmApprove = false
    @State private var confirmUndo = false

    private var approval: PRApproval { PRLogic.approval(pr) }
    private var reviewedQuiet: Bool { review && pr.myReviewAt != nil && !PRLogic.hasNewCommitsSinceMyReview(pr) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Text(pr.provider == .github ? "GH" : "BB")
                    .font(.system(size: 8.5 * scale, weight: .bold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)))
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pr.title)
                        .font(.system(size: 12.5 * scale)).lineLimit(1)
                        .truncationHelp(pr.title, hint: "더블클릭하면 브라우저에서 열기")
                    HStack(spacing: 5) {
                        Text(meta).font(.system(size: 11 * scale)).foregroundStyle(.secondary).lineLimit(1)
                        badges
                    }
                }
                Spacer(minLength: 4)
                if let a = pr.additions, let d = pr.deletions, a > 0 || d > 0 {
                    HStack(spacing: 3) {
                        if a > 0 { Text("+\(a)").foregroundStyle(.green) }
                        if d > 0 { Text("−\(d)").foregroundStyle(.red) }
                    }
                    .font(.system(size: 10.5 * scale)).monospacedDigit().padding(.top, 2)
                }
            }
            if expanded { detail.padding(.leading, 30).padding(.bottom, 4) }
        }
        .padding(.vertical, 4).padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(hovering ? 0.05 : 0)))
        .opacity(reviewedQuiet ? 0.75 : 1)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { model.open(pr) }
        .onTapGesture { toggle() }
        .contextMenu {
            Button("열기") { model.open(pr) }
            Button("브랜치 복사") { model.copyBranch(pr) }
            Button("체크아웃 명령 복사") { model.copyCheckout(pr) }
            Button("할 일로 보내기") { sendToTodo() }
            if review, canApprove { Button("승인…") { if !expanded { toggle() }; confirmApprove = true } }
            Divider()
            Button("이 저장소 숨기기") { model.hideRepo(pr) }
        }
    }

    private var meta: String {
        let age = PRLogic.relative(pr.createdAt, now: now)
        return review ? "\(pr.repo) · \(pr.author) · \(age)" : "\(pr.repo) · \(age)"
    }

    // MARK: 알약들

    @ViewBuilder
    private var badges: some View {
        if pr.isDraft { pill("Draft", .secondary) }
        if review {
            if isNew { Text("NEW").font(.system(size: 9 * scale, weight: .bold)).foregroundStyle(.white)
                .padding(.horizontal, 5).padding(.vertical, 1).background(Capsule().fill(accent)).fixedSize() }
            if PRLogic.isStale(pr, now: now, days: staleDays) { pill("\(PRLogic.waitDays(pr, now: now))일째 대기", .red) }
            if pr.myReviewAt != nil {
                pill("✓ 리뷰함", .secondary)
                if PRLogic.hasNewCommitsSinceMyReview(pr) { pill("새 커밋", .orange) }
            }
        } else {
            switch approval {
            case .approved(let n, let m): pill("✓ 승인 \(n)/\(m)", .green); Text("머지 가능").font(.system(size: 10.5 * scale)).foregroundStyle(.green).fixedSize()
            case .waiting(let n, let m):
                pill("승인 \(n)/\(m)", .orange)
                if PRLogic.isStale(pr, now: now, days: staleDays) { pill("\(PRLogic.waitDays(pr, now: now))일째 대기", .red) }
            case .changesRequested: pill("변경 요청", .red)
            case .noReviewers: pill("리뷰어 없음", .secondary)
            }
            HStack(spacing: -3) {
                ForEach(Array(pr.reviewers.prefix(5).enumerated()), id: \.offset) { _, r in reviewerDot(r) }
            }
        }
    }

    private func pill(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 9.5 * scale, weight: .medium)).foregroundStyle(color)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.14))).lineLimit(1).fixedSize()
    }

    private func color(_ s: ReviewState) -> Color {
        switch s {
        case .approved: return .green
        case .changesRequested: return .red
        case .pending, .commented: return .gray
        }
    }

    private func label(_ s: ReviewState) -> String {
        switch s {
        case .approved: return "승인"
        case .changesRequested: return "변경 요청"
        case .pending: return "대기"
        case .commented: return "코멘트"
        }
    }

    private func reviewerDot(_ r: PRReviewer) -> some View {
        Text(String(r.name.first ?? "?").uppercased())
            .font(.system(size: 8.5 * scale, weight: .semibold)).foregroundStyle(color(r.state))
            .frame(width: 16 * scale, height: 16 * scale)
            .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
            .overlay(Circle().strokeBorder(color(r.state), lineWidth: 1.2))
            .help("\(r.name) · \(label(r.state))")
    }

    // MARK: 펼침

    private var detail: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !pr.reviewers.isEmpty {
                ForEach(Array(pr.reviewers.enumerated()), id: \.offset) { _, r in
                    HStack(spacing: 6) {
                        Text(r.name).font(.system(size: 11 * scale))
                        Text(label(r.state)).font(.system(size: 11 * scale)).foregroundStyle(color(r.state))
                        if let at = r.at { Text(PRLogic.relative(at, now: now)).font(.system(size: 10.5 * scale)).foregroundStyle(.secondary) }
                    }
                }
            }
            if !pr.sourceBranch.isEmpty {
                info("브랜치") { Text("\(pr.sourceBranch) → \(pr.targetBranch)").font(.system(size: 10.5 * scale, design: .monospaced)).textSelection(.enabled) }
            }
            if let f = pr.changedFiles {
                info("변경") {
                    Text("\(f)개 파일" + Self.diffText(pr))
                        .font(.system(size: 11 * scale))
                }
            }
            info("올린 지") { Text(PRLogic.relative(pr.createdAt, now: now)).font(.system(size: 11 * scale)) }
            HStack(spacing: 6) {
                Button { model.open(pr) } label: { AccentChip(icon: "arrow.up.right.square", text: "열기", style: .solid) }.buttonStyle(.plain)
                if review { approveControls }
                Button { model.copyBranch(pr) } label: {
                    AccentChip(icon: "doc.on.doc", text: "브랜치 복사", style: .soft)
                }.buttonStyle(.plain)
                Button { sendToTodo(); flash("todo") } label: {
                    AccentChip(icon: "checkmark.square", text: copied == "todo" ? "추가됨" : "할 일로", style: .soft)
                }.buttonStyle(.plain)
            }
            .padding(.top, 2)
            if let e = model.actionError[pr.id] { Text(e).font(.system(size: 10.5 * scale)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
        }
    }

    /// 승인 버튼을 보여도 되는가 (이미 승인했거나, Bitbucket 쓰기 권한이 없으면 아니오)
    private var canApprove: Bool {
        !model.approvedByMe(pr) && !(pr.provider == .bitbucket && model.bbNoWrite) && !model.acting.contains(pr.id)
    }

    @ViewBuilder
    private var approveControls: some View {
        if model.acting.contains(pr.id) {
            ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 16, height: 16)
        } else if model.approvedByMe(pr) {
            pill("✓ 승인함", .green)
            if pr.provider == .bitbucket && !model.bbNoWrite {
                Button { confirmUndo = true } label: { AccentChip(icon: "arrow.uturn.backward", text: "승인 취소", style: .plain) }
                    .buttonStyle(.plain)
                    .popover(isPresented: $confirmUndo, arrowEdge: .bottom) {
                        ConfirmPopover(heading: "승인을 취소할까요?", pr: pr, primary: "승인 취소") {
                            confirmUndo = false; Task { await model.unapprove(pr) }
                        } cancel: { confirmUndo = false }
                    }
            }
        } else if pr.provider == .bitbucket && model.bbNoWrite {
            Text("승인하려면 토큰에 쓰기 권한이 필요해요").font(.system(size: 10.5 * scale)).foregroundStyle(.secondary)
            Button { NotificationCenter.default.post(name: .openSettings, object: "pr") } label: {
                Text("설정").font(.system(size: 10.5 * scale)).foregroundStyle(accent)
            }.buttonStyle(.plain)
        } else {
            Button { confirmApprove = true } label: { AccentChip(icon: "checkmark.circle", text: "✓ 승인", style: .soft) }
                .buttonStyle(.plain)
                .popover(isPresented: $confirmApprove, arrowEdge: .bottom) {
                    ConfirmPopover(heading: "이 PR 을 승인할까요?", pr: pr, primary: "승인") {
                        confirmApprove = false; Task { await model.approve(pr) }
                    } cancel: { confirmApprove = false }
                }
        }
    }

    private static func diffText(_ pr: PullRequest) -> String {
        guard let a = pr.additions, let d = pr.deletions, a > 0 || d > 0 else { return "" }
        return " · " + [a > 0 ? "+\(a)" : nil, d > 0 ? "−\(d)" : nil].compactMap { $0 }.joined(separator: " ")
    }

    private func info<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.system(size: 10.5 * scale)).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
            c()
        }
    }

    private func flash(_ key: String) {
        copied = key
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { if copied == key { copied = nil } }
    }

    private func sendToTodo() {
        state.addTodo(PRLogic.todoTitle(pr, isReviewRequest: review), memo: pr.url)
    }
}

/// 승인·승인 취소 확인 팝오버. 사용자가 "승인" 을 눌러야만 요청이 나간다.
private struct ConfirmPopover: View {
    let heading: String
    let pr: PullRequest
    let primary: String
    let confirm: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(heading).font(.system(size: 12.5, weight: .semibold))
            Text(pr.title).font(.system(size: 11.5)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Text("\(pr.repo) · #\(pr.number)").font(.system(size: 10.5)).foregroundStyle(.secondary)
            PopoverButtons(primary: primary, cancel: cancel, submit: confirm).padding(.top, 4)
        }
        .padding(12)
        .frame(width: 280, alignment: .leading)
        .themedPopover()
    }
}
