import SwiftUI

/// Manual jet-lag trip setup. Works whether you're planning ahead or already at your destination,
/// for a baby, a child, or an adult.
struct TripSetupSheet: View {
    @Environment(SleepStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let existing: Trip?

    @State private var alreadyLanded = false
    @State private var originID = TimeZone.current.identifier
    @State private var destinationID = TimeZone.current.identifier
    @State private var departure = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
    @State private var arrival = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
    @State private var hasReturn = false
    @State private var returnDate = Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now
    @State private var strategy: TripStrategy = .adaptAfter
    @State private var loaded = false

    private var canAdaptBefore: Bool { !alreadyLanded && departure > .now }
    private var sameZone: Bool { originID == destinationID }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("We've already arrived", isOn: $alreadyLanded)
                } footer: {
                    Text(alreadyLanded
                         ? "You're at your destination now. Tell us where you flew from and when you landed."
                         : "Planning ahead. We can ease the schedule before you fly, or after you land.")
                }

                Section(alreadyLanded ? "Flew from" : "Home (origin)") {
                    NavigationLink {
                        TimeZonePickerView(selection: $originID)
                    } label: {
                        zoneRow(label: "Time zone", id: originID)
                    }
                }

                Section(alreadyLanded ? "Now in" : "Destination") {
                    NavigationLink {
                        TimeZonePickerView(selection: $destinationID)
                    } label: {
                        zoneRow(label: "Time zone", id: destinationID)
                    }
                    if !sameZone {
                        LabeledContent("Time difference", value: shiftDescription)
                    }
                }

                Section("Dates") {
                    if alreadyLanded {
                        DatePicker("Arrived", selection: $arrival, in: ...Date.now, displayedComponents: [.date])
                    } else {
                        DatePicker("Departure", selection: $departure, in: Date.now..., displayedComponents: [.date])
                            .onChange(of: departure) { _, v in if arrival < v { arrival = v } }
                        DatePicker("Arrival", selection: $arrival, in: departure..., displayedComponents: [.date])
                    }
                    Toggle("Round trip", isOn: $hasReturn)
                    if hasReturn {
                        DatePicker("Return home", selection: $returnDate,
                                   in: (alreadyLanded ? arrival : arrival)..., displayedComponents: [.date])
                    }
                }

                if canAdaptBefore {
                    Section {
                        Picker("Approach", selection: $strategy) {
                            Text("Ease in before").tag(TripStrategy.adaptBefore)
                            Text("Adjust after landing").tag(TripStrategy.adaptAfter)
                        }
                        .pickerStyle(.segmented)
                    } footer: {
                        Text(strategy == .adaptBefore
                             ? "We'll start shifting the schedule a few days before you fly, so the new time zone feels smaller on arrival."
                             : "We'll keep your normal schedule until you land, then shift about an hour a day toward local time.")
                    }
                }

                if sameZone {
                    Section {
                        Text("Pick a destination in a different time zone to plan jet-lag easing.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(existing == nil ? "Plan a trip" : "Edit trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }.disabled(sameZone).fontWeight(.semibold)
                }
            }
            .onAppear(perform: prefill)
            .onChange(of: alreadyLanded) { _, landed in
                // When "already arrived", destination is where you are now; origin is where you flew from.
                if landed {
                    destinationID = TimeZone.current.identifier
                    strategy = .adaptAfter
                    if arrival > .now { arrival = .now }
                } else {
                    originID = TimeZone.current.identifier
                }
            }
        }
    }

    @ViewBuilder
    private func zoneRow(label: String, id: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(cityLabel(id)).foregroundStyle(.secondary)
        }
    }

    private func cityLabel(_ id: String) -> String {
        guard let tz = TimeZone(identifier: id) else { return id }
        return "\(JetLagPlanner.cityName(tz)) (\(gmtLabel(tz)))"
    }

    private func gmtLabel(_ tz: TimeZone) -> String {
        let h = Double(tz.secondsFromGMT()) / 3600
        if h == 0 { return "GMT" }
        return h == h.rounded() ? String(format: "GMT%+d", Int(h)) : String(format: "GMT%+.1f", h)
    }

    private var shiftDescription: String {
        guard let o = TimeZone(identifier: originID), let d = TimeZone(identifier: destinationID) else { return "" }
        let mins = JetLagPlanner.normalisedShift((d.secondsFromGMT() - o.secondsFromGMT()) / 60)
        if mins == 0 { return "Same time" }
        let h = abs(mins) / 60, m = abs(mins) % 60
        let hm = m == 0 ? "\(h)h" : "\(h)h \(m)m"
        return "\(hm) \(mins > 0 ? "ahead (east)" : "behind (west)")"
    }

    private func prefill() {
        guard !loaded, let t = existing else { loaded = true; return }
        alreadyLanded = t.alreadyLanded
        originID = t.originTZ ?? originID
        destinationID = t.destinationTZ ?? destinationID
        departure = t.departureDate ?? departure
        arrival = t.arrivalDate ?? arrival
        if let r = t.returnDate { hasReturn = true; returnDate = r }
        strategy = t.strategy
        loaded = true
    }

    private func save() {
        let dep = alreadyLanded ? arrival : departure
        store.createTrip(
            originTZ: originID, destinationTZ: destinationID,
            departure: dep, arrival: arrival,
            returnDate: hasReturn ? returnDate : nil,
            strategy: canAdaptBefore ? strategy : .adaptAfter,
            alreadyLanded: alreadyLanded)
        dismiss()
    }
}

/// Searchable list of IANA time zones, showing city + current GMT offset.
struct TimeZonePickerView: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var ids: [String] {
        let all = TimeZone.knownTimeZoneIdentifiers.filter { !$0.hasPrefix("Etc/") }
        guard !query.isEmpty else { return all }
        let q = query.lowercased()
        return all.filter { $0.lowercased().contains(q) }
    }

    var body: some View {
        List {
            ForEach(ids, id: \.self) { id in
                Button {
                    selection = id
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(displayCity(id)).foregroundStyle(.primary)
                            Text(id).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(offset(id)).font(.caption).foregroundStyle(.secondary)
                        if id == selection { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Search cities / regions")
        .navigationTitle("Time zone")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func displayCity(_ id: String) -> String {
        guard let tz = TimeZone(identifier: id) else { return id }
        let region = id.split(separator: "/").first.map(String.init) ?? ""
        return "\(JetLagPlanner.cityName(tz))\(region.isEmpty ? "" : " · \(region)")"
    }

    private func offset(_ id: String) -> String {
        guard let tz = TimeZone(identifier: id) else { return "" }
        let h = Double(tz.secondsFromGMT()) / 3600
        if h == 0 { return "GMT" }
        return h == h.rounded() ? String(format: "GMT%+d", Int(h)) : String(format: "GMT%+.1f", h)
    }
}
