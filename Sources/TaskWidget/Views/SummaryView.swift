import SwiftUI
import TaskWidgetCore

struct SummaryView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.fontScale) private var scale
    @State private var day = Date()
    @State private var weekly = UserDefaults.standard.bool(forKey: "summaryWeekly")
    @Environment(\.atmAccent) private var accent
    /// 수정 중인 요약. 날짜·주간 토글이 바뀐 뒤에도 원래 파일에 저장하려고 시작 시점을 기억한다.
    private struct Editing { let day: Date; let weekly: Bool; let original: String }
    @State private var editing: Editing?
    @State private var draft = ""
    @FocusState private var focused: Bool
    @Namespace private var modeNS
    @State private var confirmDiscard = false
    @State private var confirmRegenerate = false

    private let refreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            // 전환 버튼은 한 줄을 다 쓰고, 날짜는 아래 줄 정가운데 (한 줄에 두면 날짜가 한쪽으로 치우친다)
            VStack(spacing: 6) {
                HStack(spacing: 0) {
                    modeChip("일간", false)
                    modeChip("주간", true)
                }
                .padding(2)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
                HStack(spacing: 10) {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 20, height: 20).contentShape(Rectangle()) }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(dayLabel.title).font(.system(size: 13 * scale, weight: .semibold))
                        if let r = dayLabel.range { Text(r).font(.system(size: 11 * scale)).foregroundStyle(.secondary) }
                    }
                    .lineLimit(1)
                    Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 20, height: 20).contentShape(Rectangle()) }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            if editing != nil {
                editor
            } else {
                // 일간은 왼쪽, 주간은 오른쪽에 있다고 보고 전환 버튼처럼 옆으로 밀어 바꾼다
                ZStack {
                    ScrollView {
                        content
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .themedScrollbar()
                    .id(weekly)
                    .transition(.move(edge: weekly ? .trailing : .leading))
                }
                .clipped()
                // 아래 버튼 줄을 가리지 않게 그 바로 위에 띄운다
                .overlay(alignment: .bottom) { CopyToast().padding(.bottom, 8) }
            }
            Divider()
            footer
        }
        .onAppear { reload() }
        .onChange(of: day) { _, _ in finishEditing(save: true); reload() }
        .onChange(of: weekly) { _, w in
            finishEditing(save: true)
            UserDefaults.standard.set(w, forKey: "summaryWeekly")
            state.summaryError = nil
            reload()
        }
        .onReceive(refreshTimer) { _ in
            if Calendar.current.isDateInToday(day) && !state.summaryGenerating && editing == nil { reload() }
        }
        // 탭이 바뀌거나 패널이 숨겨져도 고치던 내용은 잃지 않게 조용히 저장
        .onDisappear { finishEditing(save: true) }
        .onReceive(NotificationCenter.default.publisher(for: .panelDidHide)) { _ in finishEditing(save: true) }
        .confirmationDialog("수정한 내용을 버릴까요?", isPresented: $confirmDiscard) {
            Button("버리기", role: .destructive) { finishEditing(save: false) }
            Button("계속 수정", role: .cancel) {}
        }
        .confirmationDialog("직접 수정한 내용이 사라져요. 다시 생성할까요?", isPresented: $confirmRegenerate) {
            Button("다시 생성") { regenerate() }
            Button("취소", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var content: some View {
        if weekly {
            if let s = state.weeklySummary {
                MarkdownText(markdown: s.markdown)
            } else {
                Text("주간 요약 없음").font(.system(size: 12 * scale)).foregroundStyle(.secondary).padding(.top, 20)
            }
        } else if let s = state.summary {
            MarkdownText(markdown: s.markdown)
        } else if let w = state.worklogRaw, !w.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("업무 일지 (요약 전)").font(.system(size: 10.5 * scale)).foregroundStyle(.secondary)
            MarkdownText(markdown: w)
        } else {
            Text("기록 없음").font(.system(size: 12 * scale)).foregroundStyle(.secondary).padding(.top, 20)
        }
    }

    /// 노트 링크 필터와 같은 모양: 선택은 강조색 알약 + 흰 글씨, 나머지는 옅은 알약.
    private func modeChip(_ title: String, _ value: Bool) -> some View {
        Button { withAnimation(.snappy(duration: 0.25)) { weekly = value } } label: {
            Text(title)
                .font(.system(size: 12 * scale, weight: weekly == value ? .semibold : .regular))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .foregroundStyle(weekly == value ? Color.white : Color.secondary)
                .background {
                    // 선택 표시가 다른 칸으로 미끄러져 가게 한 몸으로 둔다
                    if weekly == value { Capsule().fill(accent).matchedGeometryEffect(id: "modePill", in: modeNS) }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// 원본 Markdown 을 그대로 고치는 고정폭 입력칸. 영역을 가득 채우고 안에서 스크롤한다.
    private var editor: some View {
        TextEditor(text: $draft)
            .font(.system(size: 11.5 * scale, design: .monospaced))
            .scrollContentBackground(.hidden)
            .focused($focused)
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(focused ? accent : Color.primary.opacity(0.12), lineWidth: focused ? 1.5 : 0.5))
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var footer: some View {
        if editing != nil { editFooter } else { viewFooter }
    }

    private func chip(_ icon: String, _ text: String, _ style: AccentChip.Style = .soft, action: @escaping () -> Void) -> some View {
        Button(action: action) { AccentChip(icon: icon, text: text, style: style, large: true) }
            .buttonStyle(.plain)
    }

    private var editFooter: some View {
        HStack(spacing: 6) {
            Text("⌘↩ 저장 · esc 취소")
                .font(.system(size: 10.5 * scale))
                .foregroundStyle(.secondary)
            Spacer()
            chip("xmark", "취소", .plain) { cancelEdit() }
                .keyboardShortcut(.cancelAction)
            chip("checkmark", "저장", .solid) { finishEditing(save: true) }
                .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var viewFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if shown != nil && !state.summaryGenerating {
                    chip("pencil", "수정") { startEdit() }
                        .keyboardShortcut("e", modifiers: .command)
                }
                chip("doc.on.doc", "복사") { copy() }
                    .disabled(currentMarkdown == nil)
                chip("arrow.clockwise", shown == nil ? "생성" : "다시 생성") {
                    if editedAt != nil { confirmRegenerate = true } else { regenerate() }
                }
                .disabled(state.summaryGenerating)
                if !weekly {
                    chip("book.closed", "일지") { NSWorkspace.shared.open(Worklog.fileURL(for: day)) }
                        .disabled(state.worklogRaw == nil)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                if state.summaryGenerating {
                    ProgressView().controlSize(.small)
                    Text("생성 중…")
                } else if let e = state.summaryError {
                    Text(e).foregroundStyle(.red).lineLimit(1)
                    if e == SummaryError.claudeNotFound.userMessage {
                        Button("설정 열기") { NotificationCenter.default.post(name: .openSettings, object: "summary") }.controlSize(.mini)
                    }
                    Button("로그") { openLog() }.controlSize(.mini)
                } else if let s = shown {
                    Text("\(s.generatedAt.formatted(date: .omitted, time: .shortened)) 생성"
                         + (editedAt.map { " · \($0.formatted(date: .omitted, time: .shortened)) 수정" } ?? ""))
                }
            }
            .font(.system(size: 10.5 * scale))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var editedAt: Date? {
        shown == nil ? nil : SummaryEdits.editedAt(state.summaryFileName(for: day, weekly: weekly))
    }

    private func regenerate() {
        let d = day, w = weekly, force = shown != nil
        Task {
            if w { await state.generateWeekly(for: d, force: force) }
            else { await state.generateSummary(for: d, force: force) }
        }
    }

    private func startEdit() {
        guard let md = shown?.markdown else { return }
        draft = md
        editing = Editing(day: day, weekly: weekly, original: md)
        DispatchQueue.main.async { focused = true }
    }

    private func cancelEdit() {
        if let e = editing, draft != e.original { confirmDiscard = true } else { finishEditing(save: false) }
    }

    /// 수정 모드를 끝낸다. 바뀐 게 있을 때만 저장 (저장 실패하면 내용을 잃지 않게 수정 모드 유지).
    private func finishEditing(save: Bool) {
        guard let e = editing else { return }
        if save && draft != e.original {
            guard state.saveSummaryEdit(draft, for: e.day, weekly: e.weekly) else { return }
        }
        editing = nil
    }

    private var shown: Summary? { weekly ? state.weeklySummary : state.summary }
    private var currentMarkdown: String? { weekly ? state.weeklySummary?.markdown : (state.summary?.markdown ?? state.worklogRaw) }

    private func reload() {
        if weekly { state.loadWeekly(for: day) } else { state.loadSummary(for: day) }
    }

    private func shift(_ n: Int) {
        day = Calendar.current.date(byAdding: weekly ? .weekOfYear : .day, value: n, to: day)!
    }

    private func copy() {
        guard let m = currentMarkdown else { return }
        CopyFeedback.shared.copy(m, message: "요약을 복사했어요")
    }

    private func openLog() {
        let name = weekly ? "week-" + state.summaryService.weekDays(containing: day).key : DayKey.string(from: day)
        NSWorkspace.shared.open(Paths.logsDir.appendingPathComponent("summary-\(name).log"))
    }

    private var dayLabel: (title: String, range: String?) {
        if weekly {
            let w = state.summaryService.weekTitle(containing: day)
            return (w.title, w.range)
        }
        return (state.summaryService.dayTitle(day), nil)
    }
}
