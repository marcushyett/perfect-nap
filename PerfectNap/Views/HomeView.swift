import SwiftUI
import UIKit

struct HomeView: View {
    @Environment(SleepStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @State private var showHistory = false
    @State private var showSettings = false
    @State private var showRationale = false
    @State private var editingActiveStart = false
    @State private var draftStartDate: Date = .now
    @State private var showStopTrackingConfirm = false
    @State private var showAddMissedNap = false
    @State private var showBedtimeEditor = false
    @State private var showAddBaby = false

    private func overdueSubtext(_ prediction: NapPrediction, overtired: Bool, now: Date) -> String {
        if overtired {
            return isPreBedtime(prediction, now: now)
                ? "Overtired before bed — settle them soon to protect the night."
                : "Past the window — a cortisol second wind now makes settling harder."
        }
        return "Still within a healthy window — aim to settle by \(CountdownFormatter.clock(prediction.latestStart))."
    }

    /// True in the final stretch before the target bedtime — when overtiredness most damages the
    /// night (bedtime battles, fragmented sleep, early waking).
    private func isPreBedtime(_ prediction: NapPrediction, now: Date) -> Bool {
        guard let bedtime = store.baby?.targetBedtime(on: now) else { return false }
        return now >= bedtime.addingTimeInterval(-3.5 * 3600) && now <= bedtime.addingTimeInterval(3600)
    }

    private func wakeReasonText(_ reason: WakeSuggestion.Reason) -> String {
        switch reason {
        case .protectBedtime: return "to protect tonight's bedtime"
        case .balanceDaySleep: return "to keep day sleep balanced"
        }
    }

    private func durationText(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }

    private func babyMenuLabel(_ baby: Baby) -> String {
        if store.isShared(baby), let owner = SharingCoordinator.shared.ownerDisplayName(for: baby) {
            return "\(baby.displayName) — shared by \(owner)"
        }
        return baby.displayName
    }

    private var mode: HomeMode {
        if store.activeSession != nil { return .napping }
        guard let prediction = store.prediction else { return .noPrediction }
        // Warning background only once truly overtired — the sweet spot stays calm.
        return prediction.status() == .overtired ? .overdue : .countingDown
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let now = timeline.date
            ZStack {
                Theme.background(for: mode, colorScheme: colorScheme).ignoresSafeArea()
                VStack(spacing: 0) {
                    topBar
                    missedNapBanner
                    Spacer(minLength: 12)
                    centerStack(now: now)
                    Spacer()
                    primaryButton
                        .padding(.bottom, 16)
                    bedtimeControl
                        .padding(.bottom, 14)
                    bottomStrip
                    stopTrackingLink
                }
                .padding(.horizontal, 22)
                .foregroundStyle(Theme.foreground(for: mode, colorScheme: colorScheme))
            }
        }
        .sheet(isPresented: $showHistory) { HistoryView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showRationale) {
            if let rationale = store.prediction?.rationale {
                RationaleSheet(rationale: rationale)
                    .presentationDetents([.medium])
            }
        }
        .sheet(isPresented: $editingActiveStart) {
            EditStartSheet(start: $draftStartDate) { newStart in
                store.adjustActiveStart(to: newStart)
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showAddMissedNap) {
            if let inference = store.skippedNapInference {
                AddMissedNapSheet(start: inference.likelyStart, end: inference.likelyEnd) { start, end in
                    store.addNap(start: start, end: end)
                    showAddMissedNap = false
                }
                .presentationDetents([.medium])
            }
        }
        .sheet(isPresented: $showAddBaby) {
            AddBabySheet { name, birthDate in
                store.addBaby(name: name, birthDate: birthDate)
                showAddBaby = false
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showBedtimeEditor) {
            BedtimeEditorSheet(
                currentMinutes: Int(store.baby?.targetBedtimeMinutes ?? 0)
            ) { minutes in
                store.setTargetBedtime(minutesFromMidnight: minutes)
                showBedtimeEditor = false
            }
            .presentationDetents([.medium])
        }
        .confirmationDialog(
            "Stop tracking?",
            isPresented: $showStopTrackingConfirm,
            titleVisibility: .visible
        ) {
            Button("Stop tracking", role: .destructive) {
                Haptics.tap()
                store.stopTracking()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Ends any active nap and removes the lock-screen timer. You won't be reminded about the next wake window until you start another nap.")
        }
    }

    @ViewBuilder
    private var bedtimeControl: some View {
        if store.baby != nil {
            Button { showBedtimeEditor = true; Haptics.tap() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "bed.double.fill").font(.footnote)
                    if let bedtime = store.baby?.targetBedtime() {
                        Text("Bedtime \(CountdownFormatter.clock(bedtime))")
                            .font(.subheadline.weight(.medium))
                    } else {
                        Text("Set a bedtime")
                            .font(.subheadline.weight(.medium))
                    }
                    Image(systemName: "pencil").font(.caption2).opacity(0.7)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var missedNapBanner: some View {
        if let inference = store.skippedNapInference, store.activeSession == nil {
            Button { showAddMissedNap = true; Haptics.tap() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "moon.zzz.fill")
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Did \(store.baby?.displayName ?? "baby") nap and you forgot to log it?")
                            .font(.footnote.weight(.semibold))
                        Text("Looks like a nap around \(CountdownFormatter.clock(inference.likelyStart)). Tap to add it.")
                            .font(.caption)
                            .opacity(0.8)
                    }
                    Spacer()
                    Image(systemName: "plus.circle.fill")
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var stopTrackingLink: some View {
        if store.activeSession != nil || store.prediction != nil {
            Button { showStopTrackingConfirm = true } label: {
                Label("Stop tracking", systemImage: "stop.circle")
                    .font(.caption.weight(.medium))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 14)
            }
            .opacity(0.55)
            .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private var topBar: some View {
        HStack {
            Menu {
                ForEach(store.babies, id: \.objectID) { b in
                    Button {
                        store.selectBaby(b)
                        Haptics.tap()
                    } label: {
                        if b.objectID == store.baby?.objectID {
                            Label(babyMenuLabel(b), systemImage: "checkmark")
                        } else {
                            Text(babyMenuLabel(b))
                        }
                    }
                }
                Divider()
                Button { showAddBaby = true } label: { Label("Add baby…", systemImage: "plus") }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(store.baby?.displayName ?? "Baby")
                            .font(.title3.weight(.semibold))
                        Image(systemName: "chevron.down").font(.caption2).opacity(0.6)
                    }
                    if let baby = store.baby, store.isShared(baby), let owner = SharingCoordinator.shared.ownerDisplayName(for: baby) {
                        Text("Shared by \(owner)").font(.caption).opacity(0.7)
                    } else {
                        Text(store.baby?.ageDescription ?? "").font(.subheadline).opacity(0.7)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Button { showHistory = true } label: {
                Image(systemName: "list.bullet.rectangle")
                    .font(.title2)
                    .padding(10)
            }
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.title2)
                    .padding(10)
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func centerStack(now: Date) -> some View {
        if let session = store.activeSession {
            VStack(spacing: 10) {
                Text(session.kind == .night ? "Sleeping (overnight)" : "Napping")
                    .font(.subheadline.weight(.medium))
                    .opacity(0.75)
                Text(CountdownFormatter.longString(from: now.timeIntervalSince(session.start)))
                    .font(.system(size: 96, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                Button {
                    draftStartDate = session.start
                    editingActiveStart = true
                    Haptics.tap()
                } label: {
                    Label("Started at \(CountdownFormatter.clock(session.start))", systemImage: "pencil")
                        .font(.footnote)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .opacity(0.85)
                if session.kind == .nap, let est = store.estimatedNap {
                    Text("Usually naps ~\(durationText(est.minutes)) · \(est.confidencePercent)% confident")
                        .font(.footnote).opacity(0.6)
                }
                if session.kind == .nap, let sug = store.wakeSuggestion {
                    if now >= sug.wakeBy {
                        Label("Time to wake — \(wakeReasonText(sug.reason))", systemImage: "sun.max.fill")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(Color.orange.opacity(0.9), in: Capsule())
                            .padding(.top, 4)
                    } else {
                        Text("Suggested wake by ~\(CountdownFormatter.clock(sug.wakeBy)) \(wakeReasonText(sug.reason))")
                            .font(.footnote).opacity(0.6)
                    }
                }
            }
        } else if let prediction = store.prediction {
            let overdue = now >= prediction.recommendedStart
            let overtired = now > prediction.latestStart
            VStack(spacing: 10) {
                if !overdue {
                    Text("Next nap in")
                        .font(.subheadline.weight(.medium)).opacity(0.75)
                    Text(CountdownFormatter.string(from: max(0, prediction.recommendedStart.timeIntervalSince(now))))
                        .font(.system(size: 88, weight: .heavy, design: .rounded))
                        .monospacedDigit().contentTransition(.numericText())
                } else {
                    if overtired {
                        Label("Overtired", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(Color.red.opacity(0.85), in: Capsule())
                    } else {
                        Text("Past the ideal time")
                            .font(.subheadline.weight(.semibold)).opacity(0.85)
                    }
                    Text("Overdue by \(prediction.minutesOverdue(at: now)) min")
                        .font(.system(size: 56, weight: .heavy, design: .rounded))
                        .monospacedDigit().contentTransition(.numericText())
                    Text(overdueSubtext(prediction, overtired: overtired, now: now))
                        .font(.footnote.weight(.medium))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                if !overdue {
                    Text("Ideal ~\(CountdownFormatter.clock(prediction.recommendedStart)) (\(CountdownFormatter.clock(prediction.earliestStart)) – \(CountdownFormatter.clock(prediction.latestStart)))")
                        .font(.footnote).opacity(0.75).multilineTextAlignment(.center)
                }
                if let lastEnded = store.lastCompletedSleep?.endedAt {
                    Text("Last woke at \(CountdownFormatter.clock(lastEnded))")
                        .font(.footnote).opacity(0.6)
                }
                if let est = store.estimatedNap {
                    Text("This nap usually lasts ~\(durationText(est.minutes)) · \(est.confidencePercent)% confident")
                        .font(.footnote).opacity(0.6)
                } else {
                    Text("Learning nap lengths — needs about a day of logs")
                        .font(.caption).opacity(0.45)
                }
                Button { showRationale = true; Haptics.tap() } label: {
                    Label("Why this time?", systemImage: "info.circle")
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .padding(.top, 6)
            }
        } else {
            VStack(spacing: 8) {
                Text("Ready when you are")
                    .font(.title2.weight(.semibold))
                Text("Press play when nap starts.")
                    .opacity(0.7)
            }
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        let isActive = store.activeSession != nil
        Button {
            if isActive {
                Haptics.success()
                store.stopNap()
            } else {
                Haptics.medium()
                store.startNap()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(isActive ? .white.opacity(0.95) : Color(red: 0.20, green: 0.18, blue: 0.45))
                    .frame(width: 220, height: 220)
                    .shadow(color: .black.opacity(0.18), radius: 30, x: 0, y: 14)
                Image(systemName: isActive ? "pause.fill" : "play.fill")
                    .font(.system(size: 78, weight: .heavy))
                    .foregroundStyle(isActive ? Color(red: 0.20, green: 0.18, blue: 0.45) : .white)
                    .offset(x: isActive ? 0 : 5)
            }
            .accessibilityLabel(isActive ? "Pause nap" : "Start nap")
        }
        .buttonStyle(PressButtonStyle())
    }

    @ViewBuilder
    private var bottomStrip: some View {
        if let last = store.lastCompletedSleep, store.activeSession == nil {
            HStack(spacing: 16) {
                stat("Last \(last.kind == .night ? "night" : "nap")", CountdownFormatter.longString(from: last.duration))
                Divider().frame(height: 36).opacity(0.4)
                stat("Naps today", "\(store.napsToday.filter { $0.kind == .nap }.count)")
                Divider().frame(height: 36).opacity(0.4)
                stat("Day total", totalDaySleepString)
            }
            .padding(.bottom, 18)
        } else {
            EmptyView()
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption).opacity(0.7)
        }.frame(maxWidth: .infinity)
    }

    private var totalDaySleepString: String {
        let total = store.napsToday.filter { $0.kind == .nap }.reduce(0.0) { $0 + $1.duration }
        return CountdownFormatter.longString(from: total)
    }
}

struct RationaleSheet: View {
    let rationale: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Why this time?")
                    .font(.title2.weight(.bold))
                Spacer()
            }
            Text(rationale)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Text("Grounded in the AAP/AASM sleep duration consensus, the two-process sleep model, and practitioner ranges from Karp, Weissbluth, Taking Cara Babies, and Huckleberry. See Settings → Sources.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }
}

struct AddBabySheet: View {
    let onAdd: (String, Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var birthDate = Calendar.current.date(byAdding: .month, value: -4, to: .now) ?? .now

    var body: some View {
        NavigationStack {
            Form {
                Section("Baby") {
                    TextField("Name", text: $name).textInputAutocapitalization(.words)
                    DatePicker("Birth date", selection: $birthDate, in: ...Date.now, displayedComponents: .date)
                }
            }
            .navigationTitle("Add baby")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") { onAdd(name, birthDate); Haptics.tap() }.fontWeight(.semibold)
                }
            }
        }
    }
}

struct BedtimeEditorSheet: View {
    @State private var enabled: Bool
    @State private var time: Date
    let onSave: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    init(currentMinutes: Int, onSave: @escaping (Int) -> Void) {
        self.onSave = onSave
        _enabled = State(initialValue: currentMinutes > 0)
        let minutes = currentMinutes > 0 ? currentMinutes : 19 * 60
        _time = State(initialValue: Calendar.current.date(from: DateComponents(hour: minutes / 60, minute: minutes % 60)) ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Optimise naps for a bedtime", isOn: $enabled)
                    if enabled {
                        DatePicker("Target bedtime", selection: $time, displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    Text("Naps are timed backward from this so the day lands at the bedtime sweet spot — late enough to settle easily, early enough to avoid an overtired second wind.")
                }
            }
            .navigationTitle("Bedtime")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        if enabled {
                            let c = Calendar.current.dateComponents([.hour, .minute], from: time)
                            onSave((c.hour ?? 19) * 60 + (c.minute ?? 0))
                        } else {
                            onSave(0)
                        }
                        Haptics.tap()
                    }.fontWeight(.semibold)
                }
            }
        }
    }
}

struct AddMissedNapSheet: View {
    @State private var start: Date
    @State private var end: Date
    let onSave: (Date, Date) -> Void
    @Environment(\.dismiss) private var dismiss

    init(start: Date, end: Date, onSave: @escaping (Date, Date) -> Void) {
        _start = State(initialValue: start)
        _end = State(initialValue: end)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Add a nap you forgot to log. Adjust the times if needed — this also improves future predictions.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Nap times") {
                    DatePicker("Started", selection: $start, in: ...Date.now)
                    DatePicker("Ended", selection: $end, in: start...Date.now)
                }
            }
            .navigationTitle("Add missed nap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        onSave(start, end)
                        Haptics.tap()
                    }
                    .fontWeight(.semibold)
                    .disabled(end <= start)
                }
            }
        }
    }
}

struct EditStartSheet: View {
    @Binding var start: Date
    let onSave: (Date) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("When did this nap start?")
                    .font(.headline)
                DatePicker("", selection: $start, in: ...Date.now, displayedComponents: [.hourAndMinute])
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                Text("Useful if you forgot to press play right away.")
                    .font(.footnote).foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .navigationTitle("Adjust start")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave(start)
                        Haptics.tap()
                        dismiss()
                    }.fontWeight(.semibold)
                }
            }
        }
    }
}

enum Haptics {
    static func tap() {
        let g = UIImpactFeedbackGenerator(style: .light); g.impactOccurred()
    }
    static func medium() {
        let g = UIImpactFeedbackGenerator(style: .medium); g.impactOccurred()
    }
    static func success() {
        let g = UINotificationFeedbackGenerator(); g.notificationOccurred(.success)
    }
}
