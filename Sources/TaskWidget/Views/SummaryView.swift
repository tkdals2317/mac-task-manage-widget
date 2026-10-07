import SwiftUI
import TaskWidgetCore

struct SummaryView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.fontScale) private var scale
    @State private var day = Date()
    @State private var weekly = UserDefaults.standard.bool(forKey: "summaryWeekly")

    private let refreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $weekly) {
                    Text("일간").tag(false)
                    Text("주간").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 80)
                Spacer()
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(dayLabel).font(.system(size: 12.5 * scale, weight: .medium))
                Spacer()
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
                Spacer().frame(width: 80)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            ScrollView {
                content
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
        }
        .onAppear { reload() }
        .onChange(of: day) { _, _ in reload() }
        .onChange(of: weekly) { _, w in
            UserDefaults.standard.set(w, forKey: "summaryWeekly")
            state.summaryError = nil
            reload()
        }
        .onReceive(refreshTimer) { _ in
            if Calendar.current.isDateInToday(day) && !state.summaryGenerating { reload() }
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

    private var footer: some View {
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
                Text("\(s.generatedAt.formatted(date: .omitted, time: .shortened)) 생성")
            }
            Spacer()
            Button("복사") { copy() }
                .controlSize(.mini)
                .disabled(currentMarkdown == nil)
            Button(shown == nil ? "생성" : "다시 생성") {
                Task {
                    if weekly { await state.generateWeekly(for: day, force: shown != nil) }
                    else { await state.generateSummary(for: day, force: shown != nil) }
                }
            }
            .controlSize(.mini)
            .disabled(state.summaryGenerating)
            if !weekly {
                Button("일지") { NSWorkspace.shared.open(Worklog.fileURL(for: day)) }
                    .controlSize(.mini)
                    .disabled(state.worklogRaw == nil)
            }
        }
        .font(.system(size: 10.5 * scale))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
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
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(m, forType: .string)
    }

    private func openLog() {
        let name = weekly ? "week-" + state.summaryService.weekDays(containing: day).key : DayKey.string(from: day)
        NSWorkspace.shared.open(Paths.logsDir.appendingPathComponent("summary-\(name).log"))
    }

    private var dayLabel: String {
        if weekly { return state.summaryService.weekLabel(containing: day) }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "yyyy-MM-dd (E)"
        return f.string(from: day)
    }
}
