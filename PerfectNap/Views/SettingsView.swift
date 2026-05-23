import SwiftUI
import ActivityKit
import CloudKit

struct SettingsView: View {
    @Environment(SleepStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showResetConfirm = false
    @State private var editName: String = ""
    @State private var editBirth: Date = .now

    @State private var sharePackage: SharePackage?
    @State private var preparingShare = false
    @State private var shareError: String?

    @State private var bedtimeEnabled = false
    @State private var bedtimeTime = Calendar.current.date(from: DateComponents(hour: 19, minute: 0)) ?? .now
    @State private var babyToRemove: Baby?
    @State private var showAddBaby = false
    @State private var weeksPremature = 0
    @State private var useCustomSchedule = false
    @State private var scheduleTimes: [Date] = []

    private var defaultNapTime: Date { Calendar.current.date(bySettingHour: 12, minute: 30, second: 0, of: .now) ?? .now }
    private func time(fromMinutes m: Int) -> Date { Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: .now) ?? .now }
    private func minutes(from date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date); return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
    private func defaultScheduleTimes() -> [Date] { [time(fromMinutes: 9 * 60 + 30), time(fromMinutes: 14 * 60)] }

    private func loadSchedule() {
        let mins = store.baby?.customNapMinutes ?? []
        useCustomSchedule = !mins.isEmpty
        scheduleTimes = mins.isEmpty ? [] : mins.map { time(fromMinutes: $0) }
    }
    private func saveSchedule() {
        store.setCustomSchedule(napMinutes: useCustomSchedule ? scheduleTimes.map { minutes(from: $0) } : [])
    }

    private var correctedAgeText: String {
        guard let baby = store.baby else { return "" }
        let days = baby.adjustedAgeInDays
        let months = days / 30
        return months >= 1 ? "\(months) month\(months == 1 ? "" : "s")" : "\(days / 7) week\(days / 7 == 1 ? "" : "s")"
    }

    private var liveActivityStatus: String {
        let defaults = UserDefaults(suiteName: SharedSnapshotStore.appGroupID) ?? .standard
        let stored = defaults.string(forKey: NapLiveActivityManager.lastStatusKey) ?? "No nap started yet on this build."
        let permission = ActivityAuthorizationInfo().areActivitiesEnabled
            ? "iOS authorization: enabled"
            : "iOS authorization: DISABLED — turn on Live Activities in Settings → Perfect Nap and Settings → Face ID & Passcode"
        return "\(permission)\n\nLast attempt: \(stored)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Current baby") {
                    if let baby = store.baby {
                        TextField("Name", text: $editName)
                            .onAppear { editName = baby.displayName }
                        DatePicker("Birth date", selection: $editBirth, in: ...Date.now, displayedComponents: .date)
                            .onAppear { editBirth = baby.birthDate ?? .now }
                        Text(baby.ageDescription).font(.footnote).foregroundStyle(.secondary)
                    }
                }

                if store.baby != nil {
                    Section {
                        Stepper("Born \(weeksPremature) week\(weeksPremature == 1 ? "" : "s") early", value: $weeksPremature, in: 0...18)
                            .onAppear { weeksPremature = Int(store.baby?.weeksPremature ?? 0) }
                            .onChange(of: weeksPremature) { _, v in store.setWeeksPremature(v) }
                    } header: {
                        Text("Prematurity")
                    } footer: {
                        Text(weeksPremature > 0
                             ? "Predictions use a corrected age of \(correctedAgeText) (chronological minus \(weeksPremature) week\(weeksPremature == 1 ? "" : "s")), per pediatric guidance through ~2 years."
                             : "If your baby arrived early, set how many weeks early. Sleep predictions then use corrected age.")
                    }
                }

                Section("Babies") {
                    ForEach(store.babies, id: \.objectID) { b in
                        Button {
                            store.selectBaby(b)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(b.displayName).foregroundStyle(.primary)
                                    if store.isShared(b), let owner = SharingCoordinator.shared.ownerDisplayName(for: b) {
                                        Text("Shared by \(owner)").font(.caption).foregroundStyle(.secondary)
                                    } else {
                                        Text(b.ageDescription).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if b.objectID == store.baby?.objectID {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                                if store.babies.count > 1 {
                                    Button(role: .destructive) { babyToRemove = b } label: {
                                        Image(systemName: store.isShared(b) ? "person.badge.minus" : "trash")
                                    }
                                    .buttonStyle(.borderless)
                                    .padding(.leading, 8)
                                }
                            }
                        }
                    }
                    Button { showAddBaby = true } label: {
                        Label("Add another baby", systemImage: "plus.circle.fill")
                    }
                }

                if store.baby != nil {
                    Section("Bedtime") {
                        Toggle("Optimise naps for a bedtime", isOn: $bedtimeEnabled)
                        if bedtimeEnabled {
                            DatePicker("Target bedtime", selection: $bedtimeTime, displayedComponents: .hourAndMinute)
                            Text("Naps will be timed backward from this so the day lands at the bedtime sweet spot — late enough for easy settling, early enough to avoid an overtired second wind.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .onAppear { loadBedtime() }
                    .onChange(of: bedtimeEnabled) { _, _ in saveBedtime() }
                    .onChange(of: bedtimeTime) { _, _ in saveBedtime() }
                }

                if let baby = store.baby {
                    Section {
                        Toggle("Set a custom nap schedule", isOn: $useCustomSchedule)
                        if useCustomSchedule {
                            ForEach(scheduleTimes.indices, id: \.self) { i in
                                HStack {
                                    DatePicker("Nap \(i + 1)", selection: $scheduleTimes[i], displayedComponents: .hourAndMinute)
                                    Button(role: .destructive) { scheduleTimes.remove(at: i); saveSchedule() } label: {
                                        Image(systemName: "minus.circle.fill")
                                    }.buttonStyle(.borderless)
                                }
                            }
                            Button {
                                scheduleTimes.append(scheduleTimes.last?.addingTimeInterval(3 * 3600) ?? defaultNapTime)
                                saveSchedule()
                            } label: { Label("Add a nap time", systemImage: "plus.circle.fill") }
                        }
                    } header: {
                        Text("Nap schedule")
                    } footer: {
                        if baby.adjustedAgeInDays < 120 {
                            Text("⚠️ Schedules aren't usually recommended before ~4 months — wake windows fit a developing rhythm better at this age. You can still set one if you'd like.")
                        } else if useCustomSchedule {
                            Text("Predictions blend toward these fixed nap times (more so as \(baby.displayName) gets older).")
                        } else {
                            Text("Automatic — learned from \(baby.displayName)'s recent nap times.")
                        }
                    }
                    .onAppear { loadSchedule() }
                    .onChange(of: useCustomSchedule) { _, on in
                        if on, scheduleTimes.isEmpty { scheduleTimes = defaultScheduleTimes() }
                        saveSchedule()
                    }
                    .onChange(of: scheduleTimes) { _, _ in saveSchedule() }
                }

                if let baby = store.baby {
                    Section("Share with a partner") {
                        switch SharingCoordinator.shared.shareState(for: baby) {
                        case .notShared:
                            Text("Invite the other parent so you both see naps, wake windows, and can log sleep — synced live over iCloud.")
                                .font(.footnote).foregroundStyle(.secondary)
                            Button {
                                invitePartner(baby: baby)
                            } label: {
                                if preparingShare {
                                    HStack { ProgressView(); Text("Preparing invite…") }
                                } else {
                                    Label("Invite partner", systemImage: "person.2.badge.plus")
                                }
                            }
                            .disabled(preparingShare)
                        case .shared(let count, let isOwner):
                            Label(count > 0 ? "Shared with \(count) other\(count == 1 ? "" : "s")" : "Share created — invite pending",
                                  systemImage: "person.2.fill")
                            Button(isOwner ? "Manage sharing" : "View sharing") {
                                invitePartner(baby: baby)
                            }
                        }
                        if let shareError {
                            Text(shareError).font(.caption).foregroundStyle(.red)
                        }
                    }
                }

                Section("Personalisation") {
                    if let baby = store.baby {
                        LabeledContent("Adapted factor", value: String(format: "×%.2f", baby.adaptationFactor))
                        LabeledContent("Confidence", value: "\(Int(baby.adaptationConfidence * 100))%")
                        Text("Perfect Nap adjusts its predictions for this baby using a Bayesian-style exponential moving average over your last few logged naps.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                if let baby = store.baby,
                   let suggestion = BedtimeAdvisor.suggest(baby: baby, lastSleep: store.lastCompletedSleep, napsToday: store.napsToday) {
                    Section("Tonight's bedtime") {
                        LabeledContent("Recommended", value: CountdownFormatter.clock(suggestion.recommendedBedtime))
                        LabeledContent("Day sleep so far", value: "\(suggestion.totalDaySleepMinutes) min")
                        LabeledContent("Target night sleep", value: String(format: "%.1f h", suggestion.targetNightHours))
                        Text(suggestion.rationale)
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section("Sources") {
                    ForEach(SleepSources.all) { source in
                        Link(destination: source.url) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.title).font(.subheadline.weight(.medium))
                                Text(source.author).font(.caption).foregroundStyle(.secondary)
                                Text(source.note).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Button("Save changes") { saveEdits() }
                    Button(role: .destructive) {
                        showResetConfirm = true
                    } label: {
                        Text("Reset everything")
                    }
                }

                Section("Live Activity diagnostics") {
                    Text(liveActivityStatus)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Section {
                    Text("Your data stays private to you and anyone you explicitly invite, synced over your iCloud. No third-party servers, no tracking.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Reset everything?", isPresented: $showResetConfirm) {
                Button("Delete all data", role: .destructive) {
                    store.resetBaby()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog(
                babyToRemove.map { store.isShared($0) ? "Leave \($0.displayName)?" : "Remove \($0.displayName)?" } ?? "",
                isPresented: Binding(get: { babyToRemove != nil }, set: { if !$0 { babyToRemove = nil } }),
                titleVisibility: .visible
            ) {
                if let b = babyToRemove {
                    Button(store.isShared(b) ? "Leave shared baby" : "Delete baby & its naps", role: .destructive) {
                        store.removeBaby(b)
                        babyToRemove = nil
                    }
                }
                Button("Cancel", role: .cancel) { babyToRemove = nil }
            } message: {
                if let b = babyToRemove, store.isShared(b) {
                    Text("You'll stop seeing this baby. The owner's data isn't affected.")
                } else {
                    Text("This permanently deletes this baby and all its logged sleep.")
                }
            }
            .sheet(isPresented: $showAddBaby) {
                AddBabySheet { name, birthDate in
                    store.addBaby(name: name, birthDate: birthDate)
                    showAddBaby = false
                    dismiss()
                }
                .presentationDetents([.medium])
            }
            .sheet(item: $sharePackage) { pkg in
                CloudSharingView(share: pkg.share, container: pkg.container)
                    .ignoresSafeArea()
            }
        }
    }

    private func invitePartner(baby: Baby) {
        preparingShare = true
        shareError = nil
        Task {
            do {
                let (share, container) = try await SharingCoordinator.shared.makeShare(for: baby)
                sharePackage = SharePackage(share: share, container: container)
            } catch {
                shareError = "Couldn't start sharing: \(error.localizedDescription)"
            }
            preparingShare = false
        }
    }

    private func loadBedtime() {
        guard let baby = store.baby else { return }
        let minutes = Int(baby.targetBedtimeMinutes)
        bedtimeEnabled = minutes > 0
        if minutes > 0 {
            bedtimeTime = Calendar.current.date(from: DateComponents(hour: minutes / 60, minute: minutes % 60)) ?? bedtimeTime
        }
    }

    private func saveBedtime() {
        guard store.baby != nil else { return }
        if bedtimeEnabled {
            let comps = Calendar.current.dateComponents([.hour, .minute], from: bedtimeTime)
            store.setTargetBedtime(minutesFromMidnight: (comps.hour ?? 19) * 60 + (comps.minute ?? 0))
        } else {
            store.setTargetBedtime(minutesFromMidnight: 0)
        }
    }

    private func saveEdits() {
        store.setupBaby(name: editName.isEmpty ? "Baby" : editName, birthDate: editBirth)
        dismiss()
    }
}
