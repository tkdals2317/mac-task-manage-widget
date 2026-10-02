import SwiftUI
import TaskWidgetCore

struct SummaryView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.fontScale) private var scale
    @State private var day = Date()

    private let refreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(dayLabel).font(.system(size: 12.5 * scale, weight: .medium))
                Spacer()
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
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
        .onAppear { state.loadSummary(for: day) }
        .onChange(of: day) { _, d in state.loadSummary(for: d) }
        .onReceive(refreshTimer) { _ in
            if Calendar.current.isDateInToday(day) && !state.summaryGenerating { state.loadSummary(for: day) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let s = state.summary {
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
                Button("로그") { openLog() }.controlSize(.mini)
            } else if let s = state.summary {
                Text("\(s.generatedAt.formatted(date: .omitted, time: .shortened)) 생성")
            }
            Spacer()
            Button("복사") { copy() }
                .controlSize(.mini)
                .disabled(currentMarkdown == nil)
            Button(state.summary == nil ? "생성" : "다시 생성") {
                Task { await state.generateSummary(for: day, force: state.summary != nil) }
            }
            .controlSize(.mini)
            .disabled(state.summaryGenerating)
            Button("일지") { NSWorkspace.shared.open(Worklog.fileURL(for: day)) }
                .controlSize(.mini)
                .disabled(state.worklogRaw == nil)
        }
        .font(.system(size: 10.5 * scale))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var currentMarkdown: String? { state.summary?.markdown ?? state.worklogRaw }

    private func shift(_ days: Int) {
        day = Calendar.current.date(byAdding: .day, value: days, to: day)!
    }

    private func copy() {
        guard let m = currentMarkdown else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(m, forType: .string)
    }

    private func openLog() {
        NSWorkspace.shared.open(Paths.logsDir.appendingPathComponent("summary-\(DayKey.string(from: day)).log"))
    }

    private var dayLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "yyyy-MM-dd (E)"
        return f.string(from: day)
    }
}
