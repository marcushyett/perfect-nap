import SwiftUI
import ActivityKit
import CloudKit

struct SettingsView: View {
    @Environment(SleepStore.self) private var store
    @Environment(SubscriptionManager.self) private var sub
    @Environment(\.dismiss) private var dismiss
    @State private var showPaywall = false
    @State private var showResetConfirm = false
    @State private var editName: String = ""
    @State private var editBirth: Date = .now

    @State private var shareInvite: ShareInvite?
    @State private var preparingShare = false
    @State private var shareError: String?

    @State private var bedtimeEnabled = false
    @State private var bedtimeTime = Calendar.current.date(from: DateComponents(hour: 19, minute: 0)) ?? .now
    @State private var babyToRemove: Baby?
    @State private var showAddBaby = false
    @State private var weeksPremature = 0
    @State private var useCustomSchedule = false
    @State private var scheduleTimes: [Date] = []
    @State private var showTripSheet = false

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
                currentBabySection
                premiumSection
                if store.baby != nil { prematuritySection }
                babiesSection
                if store.baby != nil {
                    bedtimeSection
                    scheduleSection
                    travelSection
                    sharingSection
                }
                personalisationSection
                tonightSection
                sourcesSection
                actionsSection
                diagnosticsSection
                privacySection
            }
            .navigationTitle("Settings")
            // Per-baby fields are loaded into @State via .onAppear (which fires once). Switching baby
            // inside Settings must reload them, or the form shows the previous baby's values.
            .onChange(of: store.baby?.objectID) { _, _ in
                guard let baby = store.baby else { return }
                editName = baby.displayName
                editBirth = baby.birthDate ?? .now
                weeksPremature = Int(baby.weeksPremature)
                loadBedtime()
                loadSchedule()
            }
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
            .sheet(item: $shareInvite) { invite in
                ActivityShareSheet(invite: invite)
            }
            .sheet(isPresented: $showTripSheet) {
                TripSetupSheet(existing: store.trip)
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(babyName: store.baby?.displayName ?? "your baby",
                            onDone: { showPaywall = false },
                            headline: "Unlock Perfect Nap Premium")
            }
        }
    }

    @ViewBuilder
    private var currentBabySection: some View {
        Section("Current baby") {
            if let baby = store.baby {
                TextField("Name", text: $editName)
                    .onAppear { editName = baby.displayName }
                DatePicker("Birth date", selection: $editBirth, in: ...Date.now, displayedComponents: .date)
                    .onAppear { editBirth = baby.birthDate ?? .now }
                Text(baby.ageDescription).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var prematuritySection: some View {
        Section {
            Stepper("Born \(weeksPremature) week\(weeksPremature == 1 ? "" : "s") early", value: $weeksPremature, in: 0...18)
                .onAppear { weeksPremature = Int(store.baby?.weeksPremature ?? 0) }
                .onChange(of: weeksPremature) { _, v in store.setWeeksPremature(v) }
                .accessibilityIdentifier("settings.prematurityStepper")
                .accessibilityValue("\(weeksPremature)")
        } header: {
            Text("Prematurity")
        } footer: {
            Text(weeksPremature > 0
                 ? "Predictions use a corrected age of \(correctedAgeText) (chronological minus \(weeksPremature) week\(weeksPremature == 1 ? "" : "s")), per pediatric guidance through ~2 years."
                 : "If your baby arrived early, set how many weeks early. Sleep predictions then use corrected age.")
        }
    }

    @ViewBuilder
    private var babiesSection: some View {
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
                .accessibilityIdentifier("settingsBaby.\(b.displayName)")
            }
            Button {
                if store.canAddBaby { showAddBaby = true } else { showPaywall = true }
            } label: {
                Label(store.canAddBaby ? "Add another baby" : "Add another baby (Premium)",
                      systemImage: store.canAddBaby ? "plus.circle.fill" : "lock.circle.fill")
            }
            .accessibilityIdentifier("settings.addBaby")
        }
    }

    @ViewBuilder
    private var bedtimeSection: some View {
        Section("Bedtime") {
            Toggle("Optimise naps for a bedtime", isOn: $bedtimeEnabled)
            if bedtimeEnabled {
                DatePicker("Target bedtime", selection: $bedtimeTime, displayedComponents: .hourAndMinute)
                Text("Naps will be timed backward from this so the day lands in the ideal bedtime window — late enough for easy settling, early enough to avoid an overtired second wind.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .onAppear { loadBedtime() }
        .onChange(of: bedtimeEnabled) { _, _ in saveBedtime() }
        .onChange(of: bedtimeTime) { _, _ in saveBedtime() }
    }

    @ViewBuilder
    private var scheduleSection: some View {
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
    }

    @ViewBuilder
    private var personalisationSection: some View {
        Section("Personalisation") {
            if let baby = store.baby {
                LabeledContent("Adapted factor", value: String(format: "×%.2f", baby.adaptationFactor))
                LabeledContent("Confidence", value: "\(Int(baby.adaptationConfidence * 100))%")
                Text("Perfect Nap adjusts its predictions for this baby using a Bayesian-style exponential moving average over your last few logged naps.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var tonightSection: some View {
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
    }

    @ViewBuilder
    private var sourcesSection: some View {
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
    }

    @ViewBuilder
    private var actionsSection: some View {
        Section {
            Button("Save changes") { saveEdits() }
            Button(role: .destructive) { showResetConfirm = true } label: { Text("Reset everything") }
        }
    }

    @ViewBuilder
    private var diagnosticsSection: some View {
        Section("Live Activity diagnostics") {
            Text(liveActivityStatus)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var privacySection: some View {
        Section {
            Text("Your data stays private to you and anyone you explicitly invite, synced over your iCloud. No third-party servers, no tracking.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var premiumSection: some View {
        Section {
            if sub.isPremium {
                Label(SubscriptionManager.isComplimentary ? "Premium · complimentary" : "Premium active", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.tint)
                Text(SubscriptionManager.isComplimentary
                     ? "Full access on this build (tester/developer)."
                     : "Thanks for supporting Perfect Nap — every smart feature is unlocked.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("You're on the free plan. Premium unlocks personalised predictions, the daily schedule, resettle help, travel mode, charts and multiple children.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button { showPaywall = true } label: {
                    Label("Start 7-day free trial", systemImage: "sparkles")
                }
                .accessibilityIdentifier("settings.upgrade")
            }
        } header: { Text("Perfect Nap Premium") }
    }

    @ViewBuilder
    private var sharingSection: some View {
        if let baby = store.baby {
            Section("Share with a partner") {
                let state = SharingCoordinator.shared.shareState(for: baby)
                let isParticipant: Bool = { if case .shared(_, let isOwner) = state { return !isOwner }; return false }()
                if isParticipant {
                    Label("Shared with you", systemImage: "person.2.fill")
                    Text("You both see \(baby.displayName)'s naps and can log sleep — synced live.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("Invite the other parent — they get a link to view \(baby.displayName)'s naps and log sleep too, synced live over iCloud. One subscription covers you both.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button { invitePartner(baby: baby) } label: {
                        if preparingShare {
                            HStack(spacing: 8) { ProgressView(); Text("Preparing link…") }
                        } else {
                            Label("Invite partner", systemImage: "person.2.badge.plus")
                        }
                    }
                    .disabled(preparingShare)
                    .accessibilityIdentifier("settings.invitePartner")
                    if case .shared = state {
                        Button("Stop sharing", role: .destructive) {
                            Task { try? await SharingCoordinator.shared.stopSharing(baby) }
                        }
                    }
                }
                if let shareError {
                    Text(shareError).font(.caption).foregroundStyle(.red)
                }
            }
        }
    }

    @ViewBuilder
    private var travelSection: some View {
        Section("Travel & jet lag") {
            if let trip = store.trip, let origin = trip.originTimeZone, let dest = trip.destinationTimeZone {
                HStack {
                    Image(systemName: "airplane").foregroundStyle(.tint)
                    Text("\(JetLagPlanner.cityName(origin)) → \(JetLagPlanner.cityName(dest))")
                        .font(.subheadline.weight(.medium))
                }
                if let plan = store.jetLagPlan {
                    Text(plan.headline).font(.footnote.weight(.medium))
                    Text(plan.detail).font(.caption).foregroundStyle(.secondary)
                }
                Button("Edit trip") { showTripSheet = true }
                Button("End trip", role: .destructive) { store.clearTrip() }
            } else {
                Text("Crossing time zones? Set up a trip and we'll gently shift \(store.baby?.displayName ?? "your child")'s schedule toward your destination — before you fly or after you land.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button {
                    if store.isPremium { showTripSheet = true } else { showPaywall = true }
                } label: {
                    Label(store.isPremium ? "Plan a trip" : "Plan a trip (Premium)",
                          systemImage: store.isPremium ? "airplane.departure" : "lock.circle.fill")
                }
                .accessibilityIdentifier("settings.planTrip")
            }
        }
    }

    private func invitePartner(baby: Baby) {
        preparingShare = true
        shareError = nil
        Task {
            do {
                let url = try await SharingCoordinator.shared.shareURL(for: baby)
                let message = "Join me on Perfect Nap to follow \(baby.displayName)'s naps and log sleep together:"
                shareInvite = ShareInvite(message: message, url: url)
            } catch {
                shareError = error.localizedDescription
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
