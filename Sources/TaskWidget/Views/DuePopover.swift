import SwiftUI
import TaskWidgetCore

struct DuePopover: View {
    @State private var date: Date
    let onPick: (String?) -> Void

    init(due: String?, onPick: @escaping (String?) -> Void) {
        _date = State(initialValue: due.flatMap { DayKey.date(from: $0) } ?? Date())
        self.onPick = onPick
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Button("내일") { pick(Calendar.current.date(byAdding: .day, value: 1, to: Date())!) }
                Button("다음 주 월") {
                    pick(Calendar.current.nextDate(after: Date(), matching: DateComponents(weekday: 2), matchingPolicy: .nextTime)!)
                }
                Button("마감 없음") { onPick(nil) }
            }
            .controlSize(.small)
            DatePicker("", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .onChange(of: date) { _, d in pick(d) }   // 달력 클릭 즉시 저장 (스펙 6.1)
        }
        .padding(12)
        .frame(width: 260)
    }

    private func pick(_ d: Date) {
        onPick(DayKey.string(from: d))
    }
}
