import AppKit
import SwiftUI
import UserNotifications
import TaskWidgetCore

/// Bitbucket 연결 입력·확인. 설정 > PR 과 설정 도우미가 함께 쓴다. 값은 같은 곳(Settings·SecretStore)에 저장한다.
@MainActor
final class BitbucketSetup: ObservableObject {
    @Published var email: String
    @Published var token = ""
    @Published var hasToken = false
    @Published var status = ""
    @Published var ok = false
    @Published var busy = false
    @Published var workspaces: [BBWorkspace] = []
    @Published var workspace: String
    private let pr: PRModel

    init(pr: PRModel) {
        self.pr = pr
        let s = Settings.shared
        email = s.prBitbucketEmail.isEmpty ? s.jiraEmail : s.prBitbucketEmail
        workspace = s.prBitbucketWorkspace
    }

    /// 저장된 토큰이 있는지 보고, 있으면 조용히 연결을 확인해 워크스페이스 목록을 채운다.
    func load() async {
        let e = email.trimmingCharacters(in: .whitespaces)
        let saved = e.isEmpty ? nil : await pr.bitbucketToken(for: e)
        hasToken = saved != nil
        if hasToken, Settings.shared.prBitbucketEmail == e { await test() }
    }

    /// 입력한 이메일·토큰으로 먼저 확인하고, 성공했을 때만 저장한다 (틀린 값이 설정에 남지 않게).
    func test() async {
        busy = true; defer { busy = false }
        ok = false
        let e = email.trimmingCharacters(in: .whitespaces)
        if e.isEmpty { status = "이메일을 입력하세요"; return }
        let typed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let saved = typed.isEmpty ? await pr.bitbucketToken(for: e) : nil
        guard let tok = typed.isEmpty ? saved : typed else { status = "API 토큰을 붙여넣으세요 (한글 입력 소스에서는 ⌘V 로)"; return }
        status = "확인 중…"
        do {
            let r = try await pr.testBitbucket(email: e, token: tok)
            try await pr.commitBitbucket(email: e, token: typed.isEmpty ? nil : typed)
            token = ""; hasToken = true
            workspaces = r.workspaces
            // 저장된 워크스페이스가 없을 때만 첫 번째를 고른다 (있으면 저장소 선택을 지우지 않는다)
            if workspace.isEmpty { selectWorkspace(r.workspaces.first?.slug ?? "") }
            status = "✓ \(r.user.displayName) · 워크스페이스 \(r.workspaces.count)개"
            ok = true
        } catch {
            status = (error as? PRError)?.userMessage ?? error.localizedDescription
            if case .unauthorized = error as? PRError { status += " — 토큰·이메일·권한(읽기 4개)을 확인하세요" }
        }
    }

    func selectWorkspace(_ slug: String) {
        guard slug != Settings.shared.prBitbucketWorkspace else { workspace = slug; return }
        Settings.shared.prBitbucketRepos = ""   // 다른 워크스페이스의 저장소 선택은 무효
        workspace = slug
        Settings.shared.prBitbucketWorkspace = slug
    }
}

/// gh 상태 한 줄 + (문제 있을 때) 명령 복사 / 다시 확인. 설정과 도우미 공용.
struct GitHubStatusLine: View {
    @ObservedObject var pr: PRModel
    @Environment(\.fontScale) private var scale
    @State private var checking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch pr.githubStatus {
            case .ok(let l): line("gh 로그인됨 · \(l)", .green)
            case .loggedOut:
                line("gh 는 있는데 로그인이 안 돼 있어요 — 터미널에서 gh auth login", .orange)
                actions("gh auth login")
            case .ghMissing:
                line("gh 가 없어요 — brew install gh 후 gh auth login", .red)
                actions("brew install gh && gh auth login")
            case .error(let e):
                line("확인 실패 · \(e)", .red)
                actions(nil)
            case .off: line(checking ? "확인 중…" : "아직 확인 안 함", .secondary)
            }
        }
        .task { await check() }
    }

    private func line(_ s: String, _ c: Color) -> some View {
        Text(s).font(.system(size: 11 * scale)).foregroundStyle(c).fixedSize(horizontal: false, vertical: true)
    }

    private func actions(_ command: String?) -> some View {
        HStack(spacing: 6) {
            if let command {
                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(command, forType: .string) } label: {
                    AccentChip(icon: "doc.on.doc", text: "명령 복사", style: .soft)
                }.buttonStyle(.plain)
            }
            Button { Task { await check(force: true) } } label: { AccentChip(icon: "arrow.clockwise", text: "다시 확인", style: .soft) }
                .buttonStyle(.plain).disabled(checking)
        }
    }

    private func check(force: Bool = false) async {
        checking = true; defer { checking = false }
        await pr.probeGitHub(force: force)
    }
}

/// Bitbucket 클론을 찾을 폴더 고르기 (설정 > PR 과 저장소 고르기 공용).
enum CloneFolders {
    /// 설정 창·비활성 패널 어디서든 뜨도록 앱을 앞으로 가져온 뒤 모달로 연다.
    @MainActor static func pick() -> [String] {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "추가"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.map(\.path)
    }

    /// 고른 폴더를 저장 목록에 합친다 (중복은 encodeList 가 지운다).
    @MainActor static func add(_ paths: [String]) {
        Settings.shared.prCloneRootList = Settings.shared.prCloneRootList + paths
    }

    static func short(_ path: String) -> String { (path as NSString).abbreviatingWithTildeInPath }
}

/// 설정 > PR. Form 안에서 Section 들로 펼쳐진다.
struct PRSettingsSections: View {
    @ObservedObject var pr: PRModel
    @StateObject private var bb: BitbucketSetup
    @AppStorage(SettingsKey.prGitHubEnabled) private var ghOn = false
    @AppStorage(SettingsKey.prBitbucketEnabled) private var bbOn = false
    @AppStorage(SettingsKey.prBitbucketWorkspace) private var workspace = ""
    @AppStorage(SettingsKey.prBitbucketRepos) private var reposCSV = ""
    @AppStorage(SettingsKey.prHiddenRepos) private var hiddenCSV = ""
    @AppStorage(SettingsKey.prNotifyNewReview) private var notifyNew = true
    @AppStorage(SettingsKey.prNotifyApproved) private var notifyApproved = true
    @AppStorage(SettingsKey.prNotifyChanges) private var notifyChanges = true
    @AppStorage(SettingsKey.prNotifyComments) private var notifyComments = true
    @AppStorage(SettingsKey.prStaleDays) private var staleDays = 2
    @AppStorage(SettingsKey.prHideDrafts) private var hideDrafts = false
    @AppStorage(SettingsKey.prRefreshMinutes) private var refreshMinutes = 5
    /// 값이 바뀌면 화면을 다시 그리게 하려는 용도 (실제 목록은 Settings.prCloneRootList).
    @AppStorage(SettingsKey.prCloneRoots) private var cloneRootsRaw: String?
    @State private var cloneCounts: [String: Int] = [:]
    @State private var editRepos = false
    @State private var notifDenied = false
    @State private var draftRepos: Set<String> = []

    init(pr: PRModel) {
        self.pr = pr
        _bb = StateObject(wrappedValue: BitbucketSetup(pr: pr))
    }

    /// 안내 문구는 NotesSettings 처럼 왼쪽 정렬.
    private func note(_ s: String) -> some View {
        Text(s).font(.caption).foregroundStyle(.secondary)
            .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 클론 찾을 폴더: 폴더별로 찾은 저장소 수를 보여주고 추가·삭제한다.
    @ViewBuilder
    private var cloneFolders: some View {
        let roots = Settings.shared.prCloneRootList
        Text("클론 찾을 폴더").font(.subheadline.weight(.semibold)).padding(.top, 4)
        ForEach(roots, id: \.self) { r in
            HStack(spacing: 6) {
                Image(systemName: "folder").foregroundStyle(.secondary)
                Text(CloneFolders.short(r)).font(.system(.caption, design: .monospaced))
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 8)
                let n = cloneCounts[r] ?? 0
                Text(n > 0 ? "저장소 \(n)개" : "0개").font(.caption)
                    .foregroundStyle(n > 0 ? Color.green : Color.secondary)
                Button { Settings.shared.prCloneRootList = roots.filter { $0 != r } } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless).help("목록에서 빼기")
            }
        }
        Button("폴더 추가…") { CloneFolders.add(CloneFolders.pick()) }
        note("고른 폴더 아래 두 단계까지 Bitbucket 클론을 찾아요. 찾은 저장소는 저장소 고르기에서 자동으로 선택돼요.")
            .task(id: roots.joined(separator: "\n") + "|" + workspace) {
                let ws = workspace
                cloneCounts = await Task.detached {
                    Dictionary(uniqueKeysWithValues: roots.map { ($0, LocalRepos.count(workspace: ws, root: URL(fileURLWithPath: $0))) })
                }.value
            }
    }

    var body: some View {
        Section("GitHub") {
            Toggle("사용", isOn: $ghOn)
                .onChange(of: ghOn) { _, _ in Task { await pr.refresh() } }
            GitHubStatusLine(pr: pr)
        }
        Section {
            // 켜는 것은 연결 확인이 성공해야 저장된다.
            Toggle("사용", isOn: Binding(get: { bbOn }, set: { on in
                if !on { bbOn = false; return }
                if bb.ok { bbOn = true; return }
                Task { await bb.test(); if bb.ok { bbOn = true } }
            }))
            .onChange(of: bbOn) { _, _ in Task { await pr.refresh() } }
            TextField("이메일", text: $bb.email, prompt: Text("name@company.com"))
            HStack {
                SecureField(bb.hasToken ? "API 토큰 (저장됨 · 바꾸려면 입력)" : "API 토큰", text: $bb.token, prompt: Text(bb.hasToken ? "저장됨 · 바꾸려면 입력" : "API 토큰"))
                    .noPasswordSuggestions()
                Link("토큰 만드는 법 ↗", destination: Links.bitbucketToken)
            }
            note("Atlassian 계정 > 보안 > 범위가 있는 API 토큰 만들기 → 앱 Bitbucket → 읽기 권한 4개 (저장소·PR·계정·워크스페이스). 승인 버튼을 쓰려면 write:pullrequest:bitbucket 도 체크")
            HStack {
                Button("연결 확인") { Task { await bb.test() } }.disabled(bb.busy)
                Text(bb.status).foregroundStyle(bb.ok ? Color.green : Color.secondary).lineLimit(2)
            }
            if !bb.workspaces.isEmpty {
                Picker("워크스페이스", selection: Binding(get: { workspace }, set: { bb.selectWorkspace($0) })) {
                    ForEach(bb.workspaces) { Text($0.name).tag($0.slug) }
                }
            }
            if !workspace.isEmpty {
                LabeledContent("리뷰 요청 볼 저장소") {
                    HStack {
                        Text("\(Settings.csv(reposCSV).count)개").foregroundStyle(.secondary)
                        Button("편집") { draftRepos = Set(Settings.csv(reposCSV)); editRepos = true }
                    }
                }
                cloneFolders
            }
        } header: {
            Text("Bitbucket")
        } footer: {
            note("Bitbucket 은 저장소 단위로 리뷰 요청을 찾아서, 볼 저장소를 골라야 해요.")
        }
        Section("알림") {
            Toggle("새 리뷰 요청", isOn: $notifyNew)
            Toggle("내 PR 승인 (한 명씩)", isOn: $notifyApproved)
            Toggle("내 PR 변경 요청", isOn: $notifyChanges)
            Toggle("내 PR 새 댓글·리뷰", isOn: $notifyComments)
            // macOS 에서 ATM 알림이 꺼져 있으면 위 설정이 켜져 있어도 아무것도 안 뜬다.
            if notifDenied {
                HStack {
                    Text("macOS 에서 ATM 알림이 꺼져 있어요").font(.caption).foregroundStyle(.orange)
                    Spacer()
                    Button("시스템 설정 열기") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                    }
                }
            }
        }
        .task {
            guard Bundle.main.bundleIdentifier != nil else { return }
            let st = await UNUserNotificationCenter.current().notificationSettings()
            notifDenied = st.authorizationStatus == .denied
        }
        Section {
            Picker("오래 대기 표시", selection: $staleDays) {
                ForEach([1, 2, 3, 5, 7], id: \.self) { Text("\($0)일").tag($0) }
            }
            Toggle("Draft PR 숨기기", isOn: $hideDrafts)
                .onChange(of: hideDrafts) { _, _ in pr.reapplyFilters() }
            Picker("새로고침", selection: $refreshMinutes) {
                ForEach([2, 5, 10, 15], id: \.self) { Text("\($0)분").tag($0) }
            }
            let hidden = Settings.decodeList(hiddenCSV)
            if !hidden.isEmpty {
                ForEach(hidden, id: \.self) { r in
                    LabeledContent("숨긴 저장소 · \(r.drop(while: { $0 != ":" }).dropFirst())") { Button("다시 보기") { pr.unhideRepo(r) } }
                }
            }
        } header: {
            Text("표시")
        } footer: {
            note("토큰은 설정 > 일반에서 고른 곳(키체인/파일)에 저장돼요.")
        }
        .task { await bb.load() }
        .sheet(isPresented: $editRepos) {
            VStack(spacing: 10) {
                BitbucketRepoPicker(pr: pr, workspace: workspace, selection: $draftRepos)
                HStack {
                    Spacer()
                    Button("취소") { editRepos = false }.keyboardShortcut(.cancelAction)
                    Button("저장") {
                        Settings.shared.prBitbucketRepoList = Array(draftRepos)
                        editRepos = false
                        Task { await pr.refresh() }
                    }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(16).frame(width: 460, height: 520)
        }
    }
}

/// Bitbucket 에서 리뷰 요청을 볼 저장소 고르기 (설정 시트·설정 도우미 공용).
/// 이 Mac 에 클론된 저장소와 최근 30일 내 리뷰어로 들어간 저장소는 처음부터 골라 둔다(저장된 선택이 없을 때).
struct BitbucketRepoPicker: View {
    @ObservedObject var pr: PRModel
    let workspace: String
    @Binding var selection: Set<String>
    @Environment(\.fontScale) private var scale
    @Environment(\.atmAccent) private var accent
    @State private var query = ""
    @State private var all: [BBRepo] = []
    @State private var local: [String] = []
    @State private var roots: [String] = Settings.shared.prCloneRootList
    @State private var scanned = false
    @State private var recent: Set<String> = []
    @State private var loading = true
    @State private var progress: (done: Int, total: Int)?
    @State private var error: String?
    /// 사용자가 직접 건드린 것: 나중에 도착한 추천이 되돌리지 않게.
    @State private var touched: Set<String> = []
    @State private var autoPick = false

    private var allSlugs: Set<String> { Set(all.map(\.slug)) }
    private var localList: [String] { local.filter(match) }
    private var recentList: [String] { recent.subtracting(local).sorted().filter(match) }
    private var others: [String] { allSlugs.subtracting(local).subtracting(recent).sorted().filter(match) }
    private func match(_ s: String) -> Bool { query.isEmpty || s.localizedCaseInsensitiveContains(query) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ThemedTextField(prompt: "저장소 검색", text: $query)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if let error { Text(error).font(.system(size: 11 * scale)).foregroundStyle(.red) }
                    if loading && all.isEmpty { ProgressView().controlSize(.small) }
                    localSection
                    section(progress.map { "최근 30일 내 리뷰어로 들어간 저장소 · 찾는 중… \($0.done)/\($0.total)" } ?? "최근 30일 내 리뷰어로 들어간 저장소",
                            recentList, tag: "추천")
                    section("그 밖의 저장소 (\(others.count))", others, tag: nil)
                }
            }
            Text("\(selection.count)개 선택").font(.system(size: 11 * scale)).foregroundStyle(.secondary)
        }
        .task(id: workspace) { await load() }
    }

    /// 클론이 있으면 목록(+폴더 추가), 없으면 폴더를 바로 추가할 수 있는 카드.
    @ViewBuilder
    private var localSection: some View {
        if !local.isEmpty {
            HStack {
                Text("이 Mac 에 클론된 저장소 (\(local.count))").font(.system(size: 10.5 * scale, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Button("폴더 추가…") { addFolder() }
                    .buttonStyle(.plain).font(.system(size: 10.5 * scale)).foregroundStyle(accent)
            }
            .padding(.top, 6)
            ForEach(localList, id: \.self) { row($0, tag: nil) }
        } else if scanned && !workspace.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("클론 폴더를 못 찾았어요").font(.system(size: 12 * scale, weight: .semibold))
                Text(roots.isEmpty ? "찾을 폴더가 없어요" : roots.map(CloneFolders.short).joined(separator: " · ") + " 에서 찾아봤어요")
                    .font(.system(size: 11 * scale)).foregroundStyle(.secondary)
                Button("폴더 추가…") { addFolder() }
                    .buttonStyle(.plain).font(.system(size: 11 * scale, weight: .medium)).foregroundStyle(accent)
                    .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(accent.opacity(0.15)))
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(10)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4])))
            .padding(.top, 6)
        }
    }

    /// 목록은 Bitbucket 에서 불러온 저장소가 있을 때만 거른다 (불러오기 실패·빈 목록이면 클론을 그대로 보여준다).
    private func existing(_ slugs: [String]) -> [String] {
        all.isEmpty ? slugs : slugs.filter(allSlugs.contains)
    }

    /// 폴더를 고르면 다시 훑고, 새로 찾은 저장소만 선택에 더한다 (기존 선택은 건드리지 않는다).
    private func addFolder() {
        let picked = CloneFolders.pick()
        guard !picked.isEmpty else { return }
        CloneFolders.add(picked)
        roots = Settings.shared.prCloneRootList
        Task { await rescan(selectNew: true) }
    }

    private func rescan(selectNew: Bool) async {
        let ws = workspace
        let urls = roots.map { URL(fileURLWithPath: $0) }
        let l = existing(await Task.detached { LocalRepos.bitbucketSlugs(workspace: ws, roots: urls) }.value)
        let added = Set(l).subtracting(local)
        local = l
        scanned = true
        if selectNew { selection.formUnion(added) }
    }

    @ViewBuilder
    private func section(_ title: String, _ slugs: [String], tag: String?) -> some View {
        if !slugs.isEmpty {
            Text(title).font(.system(size: 10.5 * scale, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 6)
            ForEach(slugs, id: \.self) { row($0, tag: tag) }
        }
    }

    private func row(_ slug: String, tag: String?) -> some View {
        let on = selection.contains(slug)
        return Button {
            touched.insert(slug)
            if on { selection.remove(slug) } else { selection.insert(slug) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: on ? "checkmark.square.fill" : "square").foregroundStyle(on ? accent : .secondary)
                Text(slug).font(.system(size: 12 * scale))
                if let tag, recent.contains(slug) {
                    Text(tag).font(.system(size: 9.5 * scale, weight: .medium)).foregroundStyle(accent)
                        .padding(.horizontal, 5).padding(.vertical, 1).background(Capsule().fill(accent.opacity(0.15)))
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        guard !workspace.isEmpty else { loading = false; return }
        loading = true; error = nil
        autoPick = selection.isEmpty
        let ws = workspace
        roots = Settings.shared.prCloneRootList
        let urls = roots.map { URL(fileURLWithPath: $0) }
        let l = await Task.detached { LocalRepos.bitbucketSlugs(workspace: ws, roots: urls) }.value
        local = l
        scanned = true
        if autoPick { selection.formUnion(l.filter { !touched.contains($0) }) }
        do {
            all = try await pr.repositories(workspace: ws).sorted { ($0.updatedOn ?? .distantPast) > ($1.updatedOn ?? .distantPast) }
            // 클론은 남아 있어도 Bitbucket 에서 없어진 저장소는 빼고 보여준다.
            local = existing(l)
        } catch {
            self.error = "저장소 목록을 못 불러왔어요 · \((error as? PRError)?.userMessage ?? error.localizedDescription)"
            loading = false
            return
        }
        loading = false
        // 최근 갱신된 저장소부터 최대 200개만 훑는다 (요청이 저장소 수만큼 나간다)
        let slugs = Array(all.prefix(200).map(\.slug))
        progress = (0, slugs.count)
        let found = await pr.recentReviewed(workspace: ws, slugs: slugs) { done, total in
            DispatchQueue.main.async { progress = (done, total) }
        }
        progress = nil
        recent = Set(found)
        if autoPick { selection.formUnion(found.filter { !touched.contains($0) }) }
    }
}
