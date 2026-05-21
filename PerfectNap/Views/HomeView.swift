import SwiftUI
import UIKit

struct HomeView: View {
    @Environment(SleepStore.self) private var store
    @State private var showHistory = false
    @State private var showSettings = false
    @State private var showRationale = false
    @State private var editingActiveStart = false
    @State private var draftStartDate: Date = .now

    private var mode: HomeMode {
        if store.activeSession != nil { return .napping }
        guard let prediction = store.prediction else { return .noPrediction }
        return prediction.isOverdue ? .overdue : .countingDown
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let now = timeline.date
            ZStack {
                Theme.background(for: mode).ignoresSafeArea()
                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 12)
                    centerStack(now: now)
                    Spacer()
                    primaryButton
                        .padding(.bottom, 30)
                    bottomStrip
                }
                .padding(.horizontal, 22)
                .foregroundStyle(Theme.foreground(for: mode))
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
    }

    @ViewBuilder
    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.baby?.name ?? "Baby")
                    .font(.title3.weight(.semibold))
                Text(store.baby?.ageDescription ?? "")
                    .font(.subheadline)
                    .opacity(0.7)
            }
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
                Text(CountdownFormatter.longString(from: now.timeIntervalSince(session.startedAt)))
                    .font(.system(size: 96, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                Button {
                    draftStartDate = session.startedAt
                    editingActiveStart = true
                    Haptics.tap()
                } label: {
                    Label("Started at \(CountdownFormatter.clock(session.startedAt))", systemImage: "pencil")
                        .font(.footnote)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .opacity(0.85)
            }
        } else if let prediction = store.prediction {
            VStack(spacing: 10) {
                Text(prediction.isOverdue ? "Sleep window is open" : "Next nap in")
                    .font(.subheadline.weight(.medium))
                    .opacity(0.75)
                Text(CountdownFormatter.string(from: prediction.recommendedStart.timeIntervalSince(now)))
                    .font(.system(size: 88, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("Recommended ~\(CountdownFormatter.clock(prediction.recommendedStart)) (\(CountdownFormatter.clock(prediction.earliestStart)) – \(CountdownFormatter.clock(prediction.latestStart)))")
                    .font(.footnote)
                    .opacity(0.75)
                    .multilineTextAlignment(.center)
                Button { showRationale = true; Haptics.tap() } label: {
                    Label("Why this time?", systemImage: "info.circle")
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
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
                Image(systemName: isActive ? "stop.fill" : "play.fill")
                    .font(.system(size: 78, weight: .heavy))
                    .foregroundStyle(isActive ? Color(red: 0.20, green: 0.18, blue: 0.45) : .white)
                    .offset(x: isActive ? 0 : 5)
            }
            .accessibilityLabel(isActive ? "Stop nap" : "Start nap")
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
