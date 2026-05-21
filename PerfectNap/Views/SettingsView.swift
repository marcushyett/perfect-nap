import SwiftUI

struct SettingsView: View {
    @Environment(SleepStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showResetConfirm = false
    @State private var editName: String = ""
    @State private var editBirth: Date = .now

    var body: some View {
        NavigationStack {
            Form {
                Section("Baby") {
                    if let baby = store.baby {
                        TextField("Name", text: $editName)
                            .onAppear { editName = baby.name }
                        DatePicker("Birth date", selection: $editBirth, in: ...Date.now, displayedComponents: .date)
                            .onAppear { editBirth = baby.birthDate }
                        Text(baby.ageDescription).font(.footnote).foregroundStyle(.secondary)
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

                Section {
                    Text("All data stays on this device. No accounts, no servers, no tracking.")
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
        }
    }

    private func saveEdits() {
        store.setupBaby(name: editName.isEmpty ? "Baby" : editName, birthDate: editBirth)
        dismiss()
    }
}
