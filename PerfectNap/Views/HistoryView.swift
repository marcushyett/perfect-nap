import SwiftUI
import CoreData

enum HistoryTab: String, CaseIterable {
    case patterns = "Patterns"
    case list = "List"
}

struct HistoryView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(SleepStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "startedAt", ascending: false)],
        animation: .default
    )
    private var sessions: FetchedResults<NapSession>

    @State private var editing: NapSession?
    @State private var tab: HistoryTab = .patterns

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    ForEach(HistoryTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)

                Group {
                    switch tab {
                    case .patterns: patternsView
                    case .list:     listView
                    }
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editing) { session in
                EditSessionSheet(
                    session: session,
                    onSave: { start, end, kind in
                        store.updateSession(session, start: start, end: end, kind: kind)
                        editing = nil
                    },
                    onSplit: { awakeStart, awakeEnd in
                        store.splitSession(session, awakeStart: awakeStart, awakeEnd: awakeEnd)
                        editing = nil
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var patternsView: some View {
        if sessions.isEmpty {
            ContentUnavailableView(
                "No data yet",
                systemImage: "chart.bar.xaxis",
                description: Text("Charts will appear after the first nap is logged.")
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    TodayTimelineChart(sessions: todayAndOvernight)
                    if let baby = store.baby {
                        WeeklyDaySleepChart(sessions: weekSessions, baby: baby)
                        WeeklyWakeWindowChart(sessions: weekSessions, baby: baby)
                        adaptationCard(baby: baby)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 30)
            }
        }
    }

    @ViewBuilder
    private func adaptationCard(baby: Baby) -> some View {
        let factor = baby.adaptationFactor
        let confidence = baby.adaptationConfidence
        VStack(alignment: .leading, spacing: 8) {
            Text("Personalisation").font(.subheadline.weight(.semibold))
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "×%.2f", factor))
                    .font(.title.weight(.bold)).monospacedDigit()
                Text(factor > 1.02 ? "longer windows" : factor < 0.98 ? "shorter windows" : "matches baseline")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ProgressView(value: confidence)
                .tint(.indigo)
            Text("Confidence \(Int(confidence * 100))% • learned from \(napsLearnedFrom) naps")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var napsLearnedFrom: Int {
        sessions.filter { $0.kind == .nap && $0.endedAt != nil && $0.durationMinutes >= 25 }.count
    }

    @ViewBuilder
    private var listView: some View {
        if sessions.isEmpty {
            ContentUnavailableView(
                "No naps yet",
                systemImage: "moon.zzz",
                description: Text("Press the play button to log the first nap.")
            )
        } else {
            List {
                ForEach(grouped, id: \.0) { day, items in
                    Section(day) {
                        ForEach(items) { session in
                            Button { editing = session } label: { row(session) }
                                .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            for offset in offsets { store.delete(items[offset]) }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ session: NapSession) -> some View {
        HStack {
            Image(systemName: session.kind == .night ? "moon.fill" : "z.square.fill")
                .foregroundStyle(session.kind == .night ? .indigo : .orange)
            VStack(alignment: .leading) {
                Text(CountdownFormatter.clock(session.start) +
                     (session.endedAt.map { " → \(CountdownFormatter.clock($0))" } ?? " → …"))
                    .font(.body.weight(.medium))
                Text(session.endedAt == nil ? "In progress" : CountdownFormatter.longString(from: session.duration))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary).font(.caption)
        }
        .contentShape(Rectangle())
    }

    private var todayAndOvernight: [NapSession] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: .now)
        let earliest = dayStart.addingTimeInterval(-18 * 3600)
        return sessions.filter { $0.start >= earliest }
    }

    private var weekSessions: [NapSession] {
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: .now)) ?? .now
        return sessions.filter { $0.start >= cutoff }
    }

    private var grouped: [(String, [NapSession])] {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        let dict = Dictionary(grouping: sessions) { session -> String in
            formatter.string(from: session.start)
        }
        return dict.sorted { lhs, rhs in
            let l = lhs.value.first?.start ?? .distantPast
            let r = rhs.value.first?.start ?? .distantPast
            return l > r
        }
    }
}

struct EditSessionSheet: View {
    let session: NapSession
    let onSave: (Date, Date?, SleepKind) -> Void
    let onSplit: (Date, Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var end: Date
    @State private var hasEnd: Bool
    @State private var kind: SleepKind
    @State private var showSplit = false
    @State private var wokeAt: Date
    @State private var backAsleepAt: Date

    init(session: NapSession,
         onSave: @escaping (Date, Date?, SleepKind) -> Void,
         onSplit: @escaping (Date, Date) -> Void) {
        self.session = session
        self.onSave = onSave
        self.onSplit = onSplit
        let s = session.start
        let e = session.endedAt ?? .now
        _start = State(initialValue: s)
        _end = State(initialValue: e)
        _hasEnd = State(initialValue: session.endedAt != nil)
        _kind = State(initialValue: session.kind)
        // Default the wake gap to the middle third of the sleep.
        let third = e.timeIntervalSince(s) / 3
        _wokeAt = State(initialValue: s.addingTimeInterval(third))
        _backAsleepAt = State(initialValue: s.addingTimeInterval(third * 2))
    }

    private var canSplit: Bool {
        hasEnd && wokeAt > start && backAsleepAt < end && backAsleepAt > wokeAt
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Kind", selection: $kind) {
                        Text("Nap").tag(SleepKind.nap)
                        Text("Night sleep").tag(SleepKind.night)
                    }
                    .pickerStyle(.segmented)
                }
                Section("Start") {
                    DatePicker("Start", selection: $start, in: ...Date.now)
                }
                Section("End") {
                    Toggle("Ended", isOn: $hasEnd)
                    if hasEnd {
                        DatePicker("End", selection: $end, in: start...Date.now)
                    }
                }

                if session.endedAt != nil {
                    Section("Woke in the middle?") {
                        if !showSplit {
                            Button {
                                showSplit = true
                            } label: {
                                Label("Split into two sleeps", systemImage: "scissors")
                            }
                        } else {
                            DatePicker("Woke at", selection: $wokeAt, in: start...end)
                            DatePicker("Back asleep at", selection: $backAsleepAt, in: wokeAt...end)
                            Text("Splits this into \(CountdownFormatter.clock(start))–\(CountdownFormatter.clock(wokeAt)) and \(CountdownFormatter.clock(backAsleepAt))–\(CountdownFormatter.clock(end)).")
                                .font(.footnote).foregroundStyle(.secondary)
                            Button {
                                onSplit(wokeAt, backAsleepAt)
                                Haptics.tap()
                                dismiss()
                            } label: {
                                Label("Split sleep", systemImage: "scissors")
                            }
                            .disabled(!canSplit)
                            Button("Cancel split", role: .cancel) { showSplit = false }
                        }
                    }
                }

                Section {
                    Text("Adjusting times will refresh the next-nap prediction and the personalised learning.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit sleep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave(start, hasEnd ? end : nil, kind)
                        Haptics.tap()
                        dismiss()
                    }.fontWeight(.semibold)
                }
            }
        }
    }
}
