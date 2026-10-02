import SwiftUI
import TaskWidgetCore

struct DuePopover: View {
    @State private var date: Date
    let onPick: (String?) -> Void
    @Environment(\.dismiss) private var dismiss

    init(due: String?, onPick: @escaping (String?) -> Void) {
        // 시각을 떼고 자정으로 맞춘 날짜만 쓴다. 마감 없는 항목의 "오늘"은 달력 클릭이 값 변화가 아니라 저장되지 않으므로 "오늘" 버튼이 담당.
        _date = State(initialValue: Calendar.current.startOfDay(for: due.flatMap { DayKey.date(from: $0) } ?? Date()))
        self.onPick = onPick
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Button("오늘") { pick(Calendar.current.startOfDay(for: Date()), dismissAfter: true) }
                Button("내일") { pick(Calendar.current.date(byAdding: .day, value: 1, to: Date())!, dismissAfter: true) }
                Button("다음 주 월") {
                    pick(Calendar.current.nextDate(after: Date(), matching: DateComponents(weekday: 2), matchingPolicy: .nextTime)!, dismissAfter: true)
                }
                Button("마감 없음") {
                    onPick(nil)
                    dismiss()
                }
            }
            .controlSize(.small)
            DatePicker("", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .onChange(of: date) { _, d in pick(d, dismissAfter: false) }   // 달력 클릭 즉시 저장, 팝오버는 유지 (스펙 6.1)
        }
        .padding(12)
        .frame(width: 260)
    }

    private func pick(_ d: Date, dismissAfter: Bool) {
        onPick(DayKey.string(from: d))
        if dismissAfter { dismiss() }
    }
}
