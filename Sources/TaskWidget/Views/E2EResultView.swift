import AppKit
import SwiftUI
import TaskWidgetCore

/// 검증 결과 상세: 요약 → 이슈 카드 → 시나리오(단계·기대·실제·스크린샷).
struct E2EResultView: View {
    @ObservedObject var e2e: E2EModel
    let job: E2EJob
    @Environment(\.fontScale) private var scale
    @Environment(\.atmAccent) private var accent
    @State private var confirmDelete = false
    @State private var confirmPR = false
    /// Jira 댓글로 남길지 묻는 중인 이슈
    @State private var commentTarget: E2EIssueResult?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                topBar
                header
                if e2e.isActive(job.id) {
                    HStack(spacing: 6) {
                        E2EJobStatusView(e2e: e2e, job: job)
                        Spacer()
                        Button { e2e.cancel(job.id) } label: { AccentChip(icon: "stop.fill", text: "취소", style: .soft) }
                            .buttonStyle(.plain)
                    }
                }
                if let error = job.error {
                    // 알아본 실패 원인이면 할 일과 버튼을 같이 보여준다
                    if job.status == .failed, let kind = E2EFailureKind.allCases.first(where: { $0.message == error }) {
                        failureHelp(kind)
                    } else {
                        errorBox(error)
                    }
                }
                content
                Text("자동 검증 결과는 참고용이에요. 가정과 스크린샷을 같이 확인해 주세요.")
                    .font(.system(size: 10 * scale)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .confirmationDialog(commentTarget.map { "\($0.key) 이슈에 검증 결과를 댓글로 남길까요?" } ?? "",
                                isPresented: Binding(get: { commentTarget != nil }, set: { if !$0 { commentTarget = nil } }),
                                presenting: commentTarget) { issue in
                let shots = e2e.commentScreenshots(job.id, issue: issue).count
                Button("댓글 남기기") { postComment(issue, withScreenshots: false) }
                if shots > 0 { Button("댓글 + 스크린샷 \(shots)장 첨부") { postComment(issue, withScreenshots: true) } }
                Button("취소", role: .cancel) {}
            } message: { issue in
                Text("Jira 에 내 이름으로 댓글이 달리고, 이슈를 보는 사람에게 알림이 갈 수 있어요. 판정·시나리오·기대·실제 결과와 환경 주소가 들어가요."
                     + (job.jiraComments[issue.key] == nil ? "" : "\n이 결과는 이미 한 번 남겼어요."))
            }
        }
        .themedScrollbar()
        .e2ePRConfirm(isPresented: $confirmPR) { retry() }
        .confirmationDialog("이 검증 기록을 지울까요?", isPresented: $confirmDelete) {
            Button("삭제", role: .destructive) { e2e.delete(job.id) }
            Button("취소", role: .cancel) {}
        } message: {
            Text("결과와 스크린샷 폴더가 함께 지워져요.")
        }
    }

    /// 좁은 창에서는 폴더·로그를 아이콘만으로 줄여 한 줄에 넣는다.
    private var topBar: some View {
        ViewThatFits(in: .horizontal) {
            topBarRow(compact: false)
            topBarRow(compact: true)
        }
    }

    private func topBarRow(compact: Bool) -> some View {
        HStack(spacing: 6) {
            Button { e2e.openJobId = nil } label: { AccentChip(icon: "chevron.left", text: "목록", style: .plain) }
                .buttonStyle(.plain)
            Spacer()
            if !e2e.isActive(job.id) {
                retryButton(style: job.status == .done ? .plain : .soft)
                Button { e2e.exportReport(job.id) } label: {
                    AccentChip(icon: "square.and.arrow.up", text: e2e.exporting ? "내보내는 중…" : "내보내기", style: .plain)
                }
                .buttonStyle(.plain).disabled(e2e.exporting)
                .help("결과를 HTML 파일 하나로 바탕화면에 저장 (스크린샷 포함 · 이슈 첨부용)")
            }
            Button { e2e.revealInFinder(job.id) } label: { AccentChip(icon: "folder", text: compact ? nil : "폴더", style: .plain) }
                .buttonStyle(.plain).help("job 폴더를 Finder 에서 열기")
            Button { e2e.openLog(job.id) } label: { AccentChip(icon: "doc.text", text: compact ? nil : "로그", style: .plain) }
                .buttonStyle(.plain).help("run.log 열기")
            if !e2e.isActive(job.id) {
                Button { confirmDelete = true } label: { AccentChip(icon: "trash", text: nil, style: .plain) }
                    .buttonStyle(.plain).help("삭제")
            }
        }
    }

    private func retryButton(style: AccentChip.Style) -> some View {
        Button { if job.env.forcesReadOnly { confirmPR = true } else { retry() } } label: {
            AccentChip(icon: "arrow.clockwise", text: "다시 실행", style: style)
        }
        .buttonStyle(.plain).disabled(e2e.submitting).help("같은 이슈·추가 요청사항으로 다시 실행 (지금 고른 모델로)")
    }

    /// 다시 실행하면 목록으로 돌아가 새 job 이 도는 걸 보여준다.
    private func retry() {
        let id = job.id
        Task { if await e2e.retry(id) { e2e.openJobId = nil } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                E2EEnvTag(env: job.env)
                Text(job.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11 * scale)).foregroundStyle(.secondary)
                if job.readOnly { Text("조회만").font(.system(size: 10 * scale)).foregroundStyle(.orange) }
                Spacer()
                if !e2e.isActive(job.id) { E2EJobStatusView(e2e: e2e, job: job) }
            }
            Text(job.baseUrl).font(.system(size: 10.5 * scale)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            Text("모델: \(e2e.modelName(job.model))").font(.system(size: 10.5 * scale)).foregroundStyle(.secondary)
            if let e = e2e.submitError {
                Text(e).font(.system(size: 11 * scale)).foregroundStyle(.red).lineLimit(3)
            }
            if !job.notes.isEmpty {
                Text("추가 요청사항: \(job.notes)").font(.system(size: 11 * scale)).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch e2e.results[job.id] {
        case .ok(let r):
            if let block = r.loginBlocked, !e2e.isActive(job.id) { loginHelp(block) }
            summary(r)
            ForEach(Array(r.issues.enumerated()), id: \.offset) { _, issue in issueCard(issue) }
        case .invalid(let m):
            errorBox("result.json 을 읽지 못했어요 (\(m))")
            logTail
        case .missing, .none:
            if !e2e.isActive(job.id) {
                if job.error == nil { Text("결과가 없어요").font(.system(size: 11.5 * scale)).foregroundStyle(.secondary) }
                logTail
            } else {
                ForEach(job.issues) { i in
                    Text("\(i.key) \(i.title)").font(.system(size: 11.5 * scale)).lineLimit(1)
                }
            }
        }
    }

    private func summary(_ r: E2EResult) -> some View {
        let counts = r.counts
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                ForEach(E2EVerdict.displayOrder, id: \.self) { v in
                    if let n = counts[v] { E2EVerdictBadge(verdict: v, count: n) }
                }
            }
            if !r.summary.isEmpty {
                Text(r.summary).font(.system(size: 12 * scale)).textSelection(.enabled)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }

    /// 환경 로그인에 막혔을 때: 이유와 Aside 에서 할 일, 로그인 페이지 열기·다시 실행.
    private func loginHelp(_ block: E2ELoginBlock) -> some View {
        // 열 주소는 ATM 설정에서 온 환경 주소만 쓴다 (result.json 의 주소는 쓰지 않는다).
        let site = E2EWebURL.parse(job.baseUrl)
        let canOpen = site != nil && AsideBrowser.appURL != nil
        let steps = block.steps(account: job.username.isEmpty ? "테스트 계정" : "테스트 계정(\(job.username))")
        return helpBox("환경 로그인에서 막혔어요", icon: "key.fill", reason: block.reason, steps: steps,
                       note: "비밀번호는 Aside 에서 직접 입력해요. ATM 과 Aside 에이전트는 비밀번호를 보지 않아요.") {
            Button { if let site { AsideBrowser.open(site) } } label: {
                AccentChip(icon: "arrow.up.right.square", text: "Aside 에서 로그인 페이지 열기", style: .soft)
            }
            .buttonStyle(.plain).disabled(!canOpen)
            .help(canOpen ? (site?.host ?? "") : "환경 주소나 Aside 브라우저를 찾지 못했어요")
            retryButton(style: .plain)
        }
    }

    /// 실행 자체가 실패했을 때 (구버전 CLI·로그아웃·Aside 창 닫힘 등): 이유와 할 일, 그 단계를 푸는 버튼·다시 실행.
    private func failureHelp(_ kind: E2EFailureKind) -> some View {
        helpBox("검증을 돌리지 못했어요", icon: "exclamationmark.triangle.fill", reason: kind.message, steps: kind.steps) {
            if let fix = kind.fix {
                Button { e2e.perform(fix, env: job.env) } label: { AccentChip(icon: fix.icon, text: fix.label, style: .soft) }
                    .buttonStyle(.plain)
            }
            retryButton(style: .plain)
        }
    }

    private func helpBox<Buttons: View>(_ title: String, icon: String, reason: String, steps: [String], note: String = "",
                                        @ViewBuilder buttons: () -> Buttons) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.system(size: 12 * scale, weight: .semibold)).foregroundStyle(.orange)
            Text(reason).font(.system(size: 11.5 * scale)).textSelection(.enabled)
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                Text("\(i + 1). \(step)").font(.system(size: 11 * scale)).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) { buttons() }
                .padding(.top, 2)
            if !note.isEmpty {
                Text(note).font(.system(size: 10 * scale)).foregroundStyle(.tertiary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
    }

    private func issueCard(_ issue: E2EIssueResult) -> some View {
        let ref = job.issues.first { $0.key == issue.key }
        // Aside 가 쓴 result.json 의 url 은 열지 않는다. ATM 이 만든 Jira 주소만 쓴다.
        let url = ref?.webURL
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button { if let url { NSWorkspace.shared.open(url) } } label: {
                    Text(issue.key).font(.system(size: 11 * scale, design: .monospaced)).foregroundStyle(accent)
                }
                .buttonStyle(.plain).disabled(url == nil).help("Jira 에서 열기")
                Text(issue.title.isEmpty ? (ref?.title ?? "") : issue.title)
                    .font(.system(size: 12 * scale, weight: .semibold)).lineLimit(2)
                Spacer(minLength: 4)
                E2EVerdictBadge(verdict: issue.verdict)
            }
            if !issue.assumptions.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("가정").font(.system(size: 10 * scale, weight: .semibold))
                    ForEach(Array(issue.assumptions.enumerated()), id: \.offset) { _, a in
                        Text("· \(a)").font(.system(size: 11 * scale))
                    }
                }
                .foregroundStyle(.orange)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.1)))
            }
            ForEach(Array(issue.scenarios.enumerated()), id: \.offset) { _, s in scenario(s) }
            if !issue.notes.isEmpty {
                Text(issue.notes).font(.system(size: 11 * scale)).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if url != nil, !e2e.isActive(job.id) { commentRow(issue) }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }

    /// 이 이슈의 결과를 Jira 댓글로 남기는 버튼. 남긴 적이 있으면 언제 남겼는지 보여준다.
    private func commentRow(_ issue: E2EIssueResult) -> some View {
        let id = E2EModel.commentId(job.id, issue.key)
        let posted = job.jiraComments[issue.key].flatMap(E2EDate.parse)
        return VStack(alignment: .trailing, spacing: 3) {
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                if let posted {
                    Text("\(posted.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour().minute())) 댓글 남김")
                        .font(.system(size: 10.5 * scale)).foregroundStyle(.secondary)
                }
                Button { commentTarget = issue } label: {
                    AccentChip(icon: posted == nil ? "text.bubble" : "checkmark",
                               text: e2e.commenting == id ? "남기는 중…" : (posted == nil ? "Jira 댓글로 남기기" : "한 번 더"), style: .plain)
                }
                .buttonStyle(.plain).disabled(e2e.commenting != nil)
                .help("이 이슈의 검증 결과를 Jira 댓글로 남겨요 (누르면 한 번 더 물어봐요)")
            }
            if let note = e2e.commentNote, note.id == id {
                Text(note.text).font(.system(size: 11 * scale)).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func postComment(_ issue: E2EIssueResult, withScreenshots: Bool) {
        let id = job.id, key = issue.key
        Task { await e2e.postComment(id, key: key, withScreenshots: withScreenshots) }
    }

    private func scenario(_ s: E2EScenario) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Divider()
            HStack(spacing: 6) {
                Text(s.name).font(.system(size: 11.5 * scale, weight: .medium))
                Spacer(minLength: 4)
                E2EVerdictBadge(verdict: s.verdict)
            }
            ForEach(Array(s.steps.enumerated()), id: \.offset) { i, step in
                Text("\(i + 1). \(step)").font(.system(size: 11 * scale)).foregroundStyle(.secondary)
            }
            if !s.expected.isEmpty { labeled("기대", s.expected) }
            if !s.actual.isEmpty { labeled("실제", s.actual) }
            let shots = s.screenshots.compactMap { e2e.store.screenshotURL(job.id, name: $0) }
            if !shots.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) { ForEach(shots, id: \.self) { E2EThumbnail(url: $0) } }
                }
            }
        }
        .padding(.top, 2)
    }

    private func labeled(_ label: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label).font(.system(size: 10 * scale, weight: .semibold)).foregroundStyle(.secondary).frame(width: 24, alignment: .leading)
            Text(text).font(.system(size: 11.5 * scale)).textSelection(.enabled)
        }
    }

    private func errorBox(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11 * scale)).foregroundStyle(.red)
            .textSelection(.enabled)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.red.opacity(0.1)))
    }

    @ViewBuilder
    private var logTail: some View {
        let tail = e2e.logTail(job.id)
        if !tail.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text("run.log 마지막 부분").font(.system(size: 10 * scale, weight: .semibold)).foregroundStyle(.secondary)
                Text(tail)
                    .font(.system(size: 10 * scale, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
            }
        }
    }
}

/// 스크린샷 썸네일. 누르면 미리보기 앱으로 크게 연다.
private struct E2EThumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Button { NSWorkspace.shared.open(url) } label: {
            Group {
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Color.primary.opacity(0.06)
                }
            }
            .frame(height: 72)
            .frame(maxWidth: 128)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help(url.lastPathComponent)
        .task(id: url) {
            let u = url
            image = await Task.detached { NSImage(contentsOf: u) }.value
        }
    }
}
