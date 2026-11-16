import SwiftUI

/// A small month calendar. Days that have an edition are bold with a dot and can be clicked.
struct CalendarGrid: View {
    @EnvironmentObject var store: EditionStore
    @State private var month: Date = Date()
    /// Called after the reader picks a day (or Today), so the host can close the calendar.
    var onDone: (() -> Void)? = nil

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 1
        return c
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.system(.subheadline, design: .serif).weight(.semibold))
                Spacer()
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.borderless)
            }
            let symbols = cal.veryShortWeekdaySymbols
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 4) {
                ForEach(0..<7, id: \.self) { i in
                    Text(symbols[i]).font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(Array(cells().enumerated()), id: \.offset) { _, day in
                    if let day { dayCell(day) } else { Color.clear.frame(height: 26) }
                }
            }
            HStack {
                Button {
                    store.goToLatest()
                    month = Date()
                    onDone?()
                } label: { Label("Today", systemImage: "arrow.uturn.backward") }
                .disabled(store.latestKey == nil)
                Spacer()
                if let onDone {
                    Button("Close") { onDone() }
                        .keyboardShortcut(.cancelAction)
                }
            }
            .controlSize(.small)
            .padding(.top, 4)
        }
        .onAppear {
            if let k = store.selectedKey, let d = EditionStore.keyFormatter.date(from: k) { month = d }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let key = EditionStore.keyFormatter.string(from: day)
        let has = store.dates.contains(key)
        let selected = store.selectedKey == key
        let isToday = cal.isDateInToday(day)
        return Button {
            if has {
                store.select(key)
                onDone?()
            }
        } label: {
            VStack(spacing: 1) {
                Text("\(cal.component(.day, from: day))")
                    .font(.system(size: 12, weight: has ? .bold : .regular))
                    .foregroundStyle(selected ? Color.white : (has ? Color.primary : Color.secondary.opacity(0.6)))
                Circle()
                    .fill(has ? (selected ? Color.white : Color.accentColor) : .clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 26)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selected ? Color.accentColor : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isToday && !selected ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!has)
        .help(has ? EditionStore.longDate(key) : "No edition")
    }

    private func shiftMonth(_ delta: Int) {
        month = cal.date(byAdding: .month, value: delta, to: month) ?? month
    }

    private func cells() -> [Date?] {
        guard let interval = cal.dateInterval(of: .month, for: month),
              let days = cal.range(of: .day, in: .month, for: month) else { return [] }
        let lead = (cal.component(.weekday, from: interval.start) - cal.firstWeekday + 7) % 7
        var out: [Date?] = Array(repeating: nil, count: lead)
        for d in days {
            out.append(cal.date(byAdding: .day, value: d - 1, to: interval.start))
        }
        return out
    }
}
