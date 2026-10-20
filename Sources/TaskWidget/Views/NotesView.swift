import LocalAuthentication
import SwiftUI
import TaskWidgetCore

/// 링크 목록 필터: 전체 / 직접 저장 / Confluence 별표.
private enum LinkFilter: String, CaseIterable {
    case all, direct, confl
    var title: String {
        switch self {
        case .all: return "전체"
        case .direct: return "직접"
        case .confl: return "★ 컨플"
        }
    }
}

struct NotesView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        NotesBody(notes: state.notes)
    }
}

private struct NotesBody: View {
    @ObservedObject var notes: NotesModel
    @EnvironmentObject var state: AppState
    @AppStorage(SettingsKey.notesMemoCollapsed) private var memoCollapsed = false
    @AppStorage(SettingsKey.notesLinkCollapsed) private var linkCollapsed = false
    @AppStorage(SettingsKey.notesLinkFilter) private var filterRaw = LinkFilter.all.rawValue
    @AppStorage(SettingsKey.confluenceBaseURL) private var confluenceBase = Settings.defaultConfluenceBaseURL
    @AppStorage(SettingsKey.jiraRefreshMinutes) private var refreshMinutes = 5
    @Environment(\.fontScale) private var scale
    @Environment(\.atmAccent) private var accent
    @State private var newTitle = ""
    @State private var newLink = ""
    @State private var shakeX: CGFloat = 0
    @FocusState private var addFocused: Bool
    @FocusState private var linkFocused: Bool

    private var filter: LinkFilter { LinkFilter(rawValue: filterRaw) ?? .all }
    private var confluenceOn: Bool { !confluenceBase.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        let memos = notes.orderedMemos
        let pages = (filter != .direct && confluenceOn) ? notes.starred : []
        let links = filter == .confl ? [] : notes.data.links.sorted { $0.createdAt > $1.createdAt }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "메모", count: memos.count, collapsed: $memoCollapsed)
                if !memoCollapsed { memoSection(memos) }

                SectionHeader(title: "링크", count: pages.count + links.count, collapsed: $linkCollapsed) {
                    filterChips
                    if confluenceOn {
                        Button {
                            Task { await state.refreshConfluence() }
                        } label: {
                            Image(systemName: "arrow.clockwise").font(.system(size: 10 * scale))
                        }
                        .buttonStyle(.plain)
                        .help("새로고침")
                    }
                }
                if !linkCollapsed { linkSection(pages, links) }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .themedScrollbar()
        // JiraSection 과 같은 방식: 나타날 때 한 번, 이후 갱신 주기마다 (패널이 보일 때만)
        .task(id: refreshMinutes) {
            // 패널이 숨겨져 있으면 요청하지 않는다. 주소는 요청 시점에 Settings 에서 읽는다.
            @MainActor func panelVisible() -> Bool { NSApp.windows.contains { $0 is FloatingPanel && $0.isVisible } }
            if panelVisible() { await state.refreshConfluence() }
            while !Task.isCancelled {
                guard (try? await Task.sleep(for: .seconds(max(1, refreshMinutes) * 60))) != nil else { break }
                guard panelVisible() else { continue }
                await state.refreshConfluence()
            }
        }
    }

    // MARK: - 메모

    private func inputField(_ prompt: String, text: Binding<String>, focused: FocusState<Bool>.Binding) -> some View {
        TextField(prompt, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 12 * scale))
            .focused(focused)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
            // 선택됐을 때만 테마 강조색 테두리 (TasksView 와 같은 모양)
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(focused.wrappedValue ? accent : Color.primary.opacity(0.12), lineWidth: focused.wrappedValue ? 1.5 : 0.5))
            .padding(.vertical, 4)
    }

    private func memoSection(_ memos: [Memo]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            inputField("메모 추가…", text: $newTitle, focused: $addFocused)
                .onSubmit {
                    notes.addMemo(newTitle)
                    newTitle = ""
                }
            ForEach(memos) { MemoRow(notes: notes, memo: $0) }
            if memos.isEmpty {
                Text("메모 없음").font(.system(size: 11.5 * scale)).foregroundStyle(.tertiary).padding(.vertical, 8)
            }
        }
    }

    // MARK: - 링크

    private var filterChips: some View {
        HStack(spacing: 3) {
            ForEach(LinkFilter.allCases, id: \.self) { f in
                if f != .confl || confluenceOn {
                    Button { filterRaw = f.rawValue } label: {
                        Text(f.title)
                            .font(.system(size: 10 * scale, weight: filter == f ? .semibold : .regular))
                            .padding(.horizontal, 6).padding(.vertical, 1.5)
                            .foregroundStyle(filter == f ? Color.white : Color.secondary)
                            .background(Capsule().fill(filter == f ? accent : Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func linkSection(_ pages: [StarredPage], _ links: [SavedLink]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            inputField("링크 붙여넣기…", text: $newLink, focused: $linkFocused)
                .offset(x: shakeX)
                .onSubmit { submitLink() }
            ForEach(pages) { ConfluenceRow(page: $0) }
            ForEach(links) { LinkRow(notes: notes, link: $0) }
            if pages.isEmpty && links.isEmpty {
                Text("링크 없음").font(.system(size: 11.5 * scale)).foregroundStyle(.tertiary).padding(.vertical, 8)
            }
            if confluenceOn { linkFooter }
        }
    }

    private func submitLink() {
        let t = newLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if notes.addLink(t) {
            newLink = ""
        } else {
            // 주소로 볼 수 없으면 입력은 두고 흔들어 알린다.
            withAnimation(.easeInOut(duration: 0.06).repeatCount(5, autoreverses: true)) { shakeX = 6 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { shakeX = 0 }
        }
    }

    private var linkFooter: some View {
        HStack(spacing: 6) {
            if let e = notes.starredError {
                Text(e).foregroundStyle(.red).lineLimit(1)
                Button("설정") { NotificationCenter.default.post(name: .openSettings, object: "notes") }
                    .controlSize(.mini)
            } else if let t = notes.starredUpdatedAt {
                Text("↻ \(t.formatted(date: .omitted, time: .shortened)) 갱신 · 별표는 Confluence에서")
            }
            Spacer()
            if notes.starredLoading { ProgressView().controlSize(.small) }
        }
        .font(.system(size: 10.5 * scale))
        .foregroundStyle(.secondary)
        .padding(.top, 6)
    }
}

// MARK: - 링크 줄

@MainActor private func copyLink(_ s: String) {
    CopyFeedback.shared.copy(s, message: "링크를 복사했어요")
}

/// 링크 줄 공통 모양: 왼쪽 출처 아이콘 상자 + 한 줄 제목 + 오른쪽 흐린 출처. 직접 저장한 링크와 Confluence 문서가 같은 모양.
private struct LinkLine<Trailing: View>: View {
    let icon: String
    let tint: Color
    let title: String
    let source: String
    @ViewBuilder let trailing: (Bool) -> Trailing
    @Environment(\.fontScale) private var scale
    @State private var hovering = false

    var body: some View {
        // 한 덩어리로 묶어야 바깥의 popover·contextMenu 가 구분선에 따로 붙지 않는다.
        VStack(spacing: 0) {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10.5 * scale, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 20 * scale, height: 20 * scale)
                .background(RoundedRectangle(cornerRadius: 5).fill(tint.opacity(0.14)))
            Text(title)
                .font(.system(size: 12.5 * scale))
                .lineLimit(1)
                .truncationHelp(title)
            Spacer(minLength: 4)
            if hovering {
                trailing(true)
            } else {
                Text(source).font(.system(size: 10.5 * scale)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        Divider()
        }
    }
}

/// 자주 쓰는 사이트는 알아보기 쉬운 아이콘으로, 나머지는 지구본. (사이트 아이콘을 받아 오면 사내 페이지는 대부분 실패한다.)
enum LinkSiteIcon {
    static func icon(for host: String?) -> String {
        let h = (host ?? "").lowercased()
        func has(_ s: String) -> Bool { h == s || h.hasSuffix("." + s) }
        if has("github.com") || has("bitbucket.org") || has("gitlab.com") { return "chevron.left.forwardslash.chevron.right" }
        if has("datadoghq.com") { return "chart.xyaxis.line" }
        if has("figma.com") { return "paintpalette" }
        if h.contains("jira") { return "ticket" }
        if has("atlassian.net") { return "doc.text" }
        if has("slack.com") { return "number" }
        if has("google.com") { return "doc.richtext" }
        if has("notion.so") || has("notion.site") { return "note.text" }
        return "globe"
    }
}

private struct LinkRow: View {
    @ObservedObject var notes: NotesModel
    let link: SavedLink
    @Environment(\.fontScale) private var scale
    @State private var editing = false

    var body: some View {
        let host = URL(string: link.url)?.host
        LinkLine(icon: LinkSiteIcon.icon(for: host), tint: .secondary, title: link.title, source: host ?? link.url) { _ in
            HStack(spacing: 7) {
                hoverButton("doc.on.doc", help: "주소 복사") { copyLink(link.url) }
                hoverButton("pencil", help: "수정") { editing = true }
                hoverButton("xmark", help: "삭제", bold: true) { notes.deleteLink(link.id) }
            }
        }
        .onTapGesture { open() }
        .popover(isPresented: $editing, arrowEdge: .bottom) {
            LinkEditPopover(notes: notes, link: link) { editing = false }
        }
        .contextMenu {
            Button("열기") { open() }
            Button("주소 복사") { copyLink(link.url) }
            Button("수정…") { editing = true }
            Divider()
            Button("삭제", role: .destructive) { notes.deleteLink(link.id) }
        }
    }

    private func hoverButton(_ icon: String, help: String, bold: Bool = false, tint: Color = .secondary, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9.5 * scale, weight: bold ? .bold : .regular))
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func open() {
        if let u = URL(string: link.url) { NSWorkspace.shared.open(u) }
    }
}

/// 링크 수정 창: 이름 + 주소. 이름을 비우면 새 주소의 페이지 제목을 받아 온다.
private struct LinkEditPopover: View {
    @ObservedObject var notes: NotesModel
    let link: SavedLink
    let done: () -> Void
    @State private var title: String
    @State private var url: String
    @State private var error = ""

    init(notes: NotesModel, link: SavedLink, done: @escaping () -> Void) {
        self.notes = notes; self.link = link; self.done = done
        _title = State(initialValue: link.title)
        _url = State(initialValue: link.url)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("이름").font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
            ThemedTextField(prompt: "비우면 페이지 제목", text: $title, autofocus: true, onSubmit: save)
            Text("주소").font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary).padding(.top, 2)
            ThemedTextField(prompt: "https://", text: $url, onSubmit: save)
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
            PopoverButtons(primary: "저장", cancel: done, submit: save).padding(.top, 4)
        }
        .padding(12)
        .frame(width: 280)
        .themedPopover()
    }

    private func save() {
        guard notes.updateLink(link.id, title: title, url: url) else { error = "주소로 볼 수 없어요"; return }
        done()
    }
}

private struct ConfluenceRow: View {
    let page: StarredPage
    @Environment(\.fontScale) private var scale

    var body: some View {
        LinkLine(icon: "doc.text", tint: .blue, title: page.title, source: page.spaceKey) { _ in
            HStack(spacing: 7) {
                if let d = page.updated {
                    Text(Self.agoText(d)).font(.system(size: 10.5 * scale)).foregroundStyle(.secondary)
                }
                Button { copyLink(page.url.absoluteString) } label: {
                    Image(systemName: "doc.on.doc").font(.system(size: 9.5 * scale)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("주소 복사")
            }
        }
        .onTapGesture { NSWorkspace.shared.open(page.url) }
        .contextMenu {
            Button("열기") { NSWorkspace.shared.open(page.url) }
            Button("주소 복사") { copyLink(page.url.absoluteString) }
        }
    }

    private static func agoText(_ d: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: d),
                                                   to: Calendar.current.startOfDay(for: Date())).day ?? 0
        return days <= 0 ? "오늘 수정" : "\(days)일 전 수정"
    }
}

// MARK: - 메모 줄

private struct MemoRow: View {
    @ObservedObject var notes: NotesModel
    let memo: Memo
    @Environment(\.fontScale) private var scale
    @Environment(\.atmAccent) private var accent
    @State private var hovering = false
    @State private var editing = false
    @State private var draft = ""
    @State private var popover: LockPopover?
    @FocusState private var titleFocused: Bool

    enum LockPopover: Identifiable {
        case create, verify
        var id: Int { self == .create ? 0 : 1 }
    }

    var body: some View {
        let expanded = notes.expanded.contains(memo.id)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: leadingIcon)
                    .font(.system(size: 11 * scale))
                    .foregroundStyle(memo.pinned || memo.locked ? accent : Color.secondary)
                    .frame(width: 16 * scale, height: 16 * scale)

                VStack(alignment: .leading, spacing: 2) {
                    if editing {
                        TextField("", text: $draft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12.5 * scale))
                            .focused($titleFocused)
                            .onSubmit { commitEdit() }
                            .onExitCommand { editing = false }
                            .onChange(of: titleFocused) { _, f in if !f && editing { commitEdit() } }
                    } else {
                        Text(memo.title)
                            .font(.system(size: 12.5 * scale))
                            .lineLimit(1)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { beginEdit() }
                            .onTapGesture { toggleExpanded() }
                            .truncationHelp(memo.title, hint: "더블클릭하면 수정")
                    }
                    if !expanded { subline }
                }

                Spacer(minLength: 4)
                    .contentShape(Rectangle())
                    .onTapGesture { toggleExpanded() }

                Group {
                    rowButton(memo.pinned ? "pin.slash" : "pin", help: memo.pinned ? "고정 해제" : "고정") { notes.togglePin(memo.id) }
                    rowButton(memo.locked ? "lock.open" : "lock", help: memo.locked ? (notes.isReadable(memo) ? "지금 잠그기" : "열기") : "잠그기") { lockTapped() }
                        .popover(item: $popover) { mode in
                            NotePasswordPopover(mode: mode == .create ? .create : .verify, notes: notes, memoId: memo.id) { popover = nil }
                        }
                    rowButton("xmark", help: "삭제", bold: true) { notes.delete(memo.id) }
                }
                .opacity(hovering || popover != nil ? 1 : 0)
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }

            if expanded { expandedBody }
        }
        .contextMenu {
            Button(memo.pinned ? "고정 해제" : "고정") { notes.togglePin(memo.id) }
            if memo.locked {
                Button("잠금 풀기") { notes.unlockPermanently(memo.id) }.disabled(!notes.isReadable(memo))
            } else {
                Button("잠그기") { lockTapped() }
            }
            Divider()
            Button("삭제", role: .destructive) { notes.delete(memo.id) }
        }
        Divider()
    }

    private var leadingIcon: String {
        if memo.pinned { return "pin.fill" }
        if memo.locked { return notes.isReadable(memo) ? "lock.open.fill" : "lock.fill" }
        return "note.text"
    }

    @ViewBuilder
    private var subline: some View {
        if memo.locked {
            if notes.isReadable(memo) {
                HStack(spacing: 4) {
                    Text("열림").font(.system(size: 11 * scale)).foregroundStyle(.secondary)
                    RelockLabel(notes: notes)
                }
            } else {
                Text("잠김").font(.system(size: 11 * scale)).foregroundStyle(.secondary)
            }
        } else if let p = notes.preview(memo) {
            Text(p).font(.system(size: 11 * scale)).foregroundStyle(.secondary).lineLimit(1)
                .contentShape(Rectangle())
                .onTapGesture { toggleExpanded() }
        }
    }

    private func rowButton(_ icon: String, help: String, bold: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9.5 * scale, weight: bold ? .bold : .regular))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: 펼친 본문

    @ViewBuilder
    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            if notes.isReadable(memo) {
                MemoEditor(text: notes.text(memo), autofocus: notes.focusMemo == memo.id) {
                    notes.setBody(memo.id, $0)
                } didFocus: {
                    notes.focusMemo = nil
                }
                .id("\(memo.id)-\(memo.locked)")
                if memo.locked {
                    HStack(spacing: 6) {
                        Button { notes.relockAll() } label: {
                            AccentChip(icon: "lock.fill", text: "지금 잠그기")
                        }
                        .buttonStyle(.plain)
                        RelockLabel(notes: notes)
                    }
                }
            } else {
                LockedPanel(notes: notes, memoId: memo.id)
            }
        }
        .padding(.leading, 16 * scale + 8)
        .padding(.bottom, 6)
    }

    // MARK: 동작

    private func toggleExpanded() {
        notes.toggleExpanded(memo.id)
        // 열쇠가 아직 메모리에 있으면 다시 묻지 않고 연다.
        if notes.expanded.contains(memo.id), memo.locked { notes.openIfKeyed(memo.id) }
    }

    private func lockTapped() {
        if memo.locked {
            if notes.isReadable(memo) { notes.relockAll() }
            else { if !notes.expanded.contains(memo.id) { toggleExpanded() } }
            return
        }
        if !notes.hasLock { popover = .create }
        else if notes.hasKey { notes.lock(memo.id) }
        else { popover = .verify }
    }

    private func beginEdit() {
        draft = memo.title
        editing = true
        DispatchQueue.main.async { titleFocused = true }
    }

    private func commitEdit() {
        guard editing else { return }
        editing = false
        notes.rename(memo.id, draft)
    }
}

/// "N분 뒤 잠김". 30초마다 다시 계산한다.
private struct RelockLabel: View {
    @ObservedObject var notes: NotesModel
    @Environment(\.fontScale) private var scale

    var body: some View {
        if let at = notes.relockAt {
            TimelineView(.periodic(from: .now, by: 30)) { ctx in
                let min = max(1, Int((at.timeIntervalSince(ctx.date) / 60).rounded(.up)))
                Text("\(min)분 뒤 잠김").font(.system(size: 10.5 * scale)).foregroundStyle(.tertiary)
            }
        }
    }
}

/// 여러 줄 본문 편집기 (TodoRow 메모 편집기와 같은 모양). 글자를 칠 때마다 모델에 넘기고 저장은 모델이 모아서 한다.
private struct MemoEditor: View {
    @State private var draft: String
    let autofocus: Bool
    let onChange: (String) -> Void
    let didFocus: () -> Void
    @Environment(\.fontScale) private var scale
    @FocusState private var focused: Bool

    init(text: String, autofocus: Bool, onChange: @escaping (String) -> Void, didFocus: @escaping () -> Void) {
        _draft = State(initialValue: text)
        self.autofocus = autofocus
        self.onChange = onChange
        self.didFocus = didFocus
    }

    var body: some View {
        TextEditor(text: $draft)
            .font(.system(size: 12 * scale))
            .scrollContentBackground(.hidden)
            .scrollIndicators(.never)   // 흰 스크롤바 띠가 남지 않게
            .focused($focused)
            .onExitCommand { focused = false }
            // ⌘↩ 로 편집을 마친다
            .onKeyPress(.return, phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                focused = false
                return .handled
            }
            .onChange(of: draft) { _, new in onChange(new) }
            .overlay(alignment: .topLeading) {
                if draft.isEmpty {
                    Text("내용 (여러 줄, ⌘↩ 로 마침)")
                        .font(.system(size: 12 * scale)).foregroundStyle(.tertiary)
                        .padding(.leading, 5).allowsHitTesting(false)
                }
            }
            .frame(minHeight: 12 * scale * 3 * 1.3, maxHeight: 12 * scale * 12 * 1.3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(4)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .onAppear {
                guard autofocus else { return }
                DispatchQueue.main.async { focused = true; didFocus() }
            }
    }
}

/// 잠긴 메모를 펼쳤을 때: "열기" 버튼 하나. Touch ID 를 켰으면 바로 지문을 묻고, 꺼져 있거나 취소·실패하면 비밀번호 팝오버.
private struct LockedPanel: View {
    @ObservedObject var notes: NotesModel
    let memoId: UUID
    @State private var askPassword = false
    @State private var error = ""
    @State private var busy = false

    var body: some View {
        Button { openTapped() } label: { AccentChip(icon: "lock.open.fill", text: "열기") }
            .buttonStyle(.plain)
            .disabled(busy)
            .popover(isPresented: $askPassword, arrowEdge: .bottom) {
                UnlockPopover(notes: notes, memoId: memoId, initialError: error) { askPassword = false }
            }
    }

    private func openTapped() {
        error = ""
        guard notes.touchIDEnabled && NotesModel.touchIDAvailable else { askPassword = true; return }
        busy = true
        Task {
            defer { busy = false }
            do { try await notes.unlockWithTouchID(memoId) }
            catch let e as LAError where e.code == .userFallback || e.code == .userCancel || e.code == .systemCancel {
                askPassword = true
            } catch {
                self.error = error.localizedDescription
                askPassword = true
            }
        }
    }
}

/// 잠긴 메모 열기용 비밀번호 팝오버.
private struct UnlockPopover: View {
    @ObservedObject var notes: NotesModel
    let memoId: UUID
    let done: () -> Void
    @State private var pw = ""
    @State private var error: String
    @State private var busy = false

    init(notes: NotesModel, memoId: UUID, initialError: String, done: @escaping () -> Void) {
        self.notes = notes; self.memoId = memoId; self.done = done
        _error = State(initialValue: initialError)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("비밀번호 입력").font(.system(size: 12.5, weight: .semibold))
            ThemedTextField(prompt: "비밀번호", text: $pw, secure: true, autofocus: true, onSubmit: submit)
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
            PopoverButtons(primary: "열기", busy: busy || pw.isEmpty, cancel: done, submit: submit).padding(.top, 2)
        }
        .padding(12)
        .frame(width: 230)
        .themedPopover()
    }

    private func submit() {
        guard !busy, !pw.isEmpty else { return }
        busy = true; error = ""
        Task {
            defer { busy = false }
            do { try await notes.unlock(memoId, password: pw); pw = ""; done() }
            catch { self.error = error.localizedDescription }
        }
    }
}

/// 메모 잠그기 흐름의 비밀번호 팝오버: 처음이면 만들기, 열쇠가 없으면 확인. 끝나면 그 메모를 잠근다.
private struct NotePasswordPopover: View {
    enum Mode { case create, verify }
    let mode: Mode
    @ObservedObject var notes: NotesModel
    let memoId: UUID
    let done: () -> Void
    @State private var pw = ""
    @State private var confirm = ""
    @State private var error = ""
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(mode == .create ? "잠금 비밀번호 만들기" : "비밀번호 확인").font(.system(size: 12.5, weight: .semibold))
            ThemedTextField(prompt: "비밀번호", text: $pw, secure: true, autofocus: true, onSubmit: submit)
            if mode == .create {
                ThemedTextField(prompt: "비밀번호 확인", text: $confirm, secure: true, onSubmit: submit)
                Text("비밀번호를 잊으면 잠긴 메모는 되살릴 수 없습니다.")
                    .font(.caption).foregroundStyle(.orange)
            }
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
            PopoverButtons(primary: mode == .create ? "만들고 잠그기" : "잠그기", busy: busy, cancel: done, submit: submit)
                .padding(.top, 2)
        }
        .padding(12)
        .frame(width: 250)
        .themedPopover()
    }

    private func submit() {
        guard !busy else { return }
        busy = true; error = ""
        Task {
            defer { busy = false }
            do {
                if mode == .create { try await notes.createPassword(pw, confirm: confirm) }
                else { try await notes.verify(password: pw) }
                notes.lock(memoId)
                done()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
