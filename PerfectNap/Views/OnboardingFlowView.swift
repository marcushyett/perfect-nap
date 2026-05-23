import SwiftUI

/// Comprehensive onboarding. The order is deliberate (research-backed): collect a little personal
/// info first (investment / sunk cost + tailoring), explain outcomes (not features), establish
/// credibility via the science (we have no reviews yet), reveal the baby's *own* first prediction
/// (the payoff), then offer the 7-day free trial while motivation is highest.
struct OnboardingFlowView: View {
    @Environment(SleepStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    let onComplete: () -> Void

    enum Step: Int, CaseIterable { case welcome, aboutBaby, struggle, method, building, value, science, reveal, paywall }
    enum Struggle: String, CaseIterable, Identifiable { case shortNaps = "Short naps", overtired = "Overtiredness & meltdowns", bedtime = "Bedtime battles", unpredictable = "No predictable rhythm"; var id: String { rawValue } }
    enum Method: String, CaseIterable, Identifiable { case guessing = "Mostly guessing", clock = "Watching the clock", cues = "Reading sleepy cues", schedule = "A fixed schedule"; var id: String { rawValue } }

    @State private var step: Step = .welcome
    @State private var name = ""
    @State private var birthDate = Calendar.current.date(byAdding: .month, value: -4, to: .now) ?? .now
    @State private var bornEarly = false
    @State private var weeksEarly = 4
    @State private var struggle: Struggle?
    @State private var method: Method?

    private var babyName: String { name.isEmpty ? "your baby" : name }
    private var titleColor: Color {
        colorScheme == .dark ? Color(red: 0.96, green: 0.91, blue: 0.82) : Color(red: 0.20, green: 0.15, blue: 0.10)
    }

    var body: some View {
        ZStack {
            Theme.awakeBackground(for: colorScheme).ignoresSafeArea()
            VStack(spacing: 0) {
                if step.rawValue >= Step.aboutBaby.rawValue && step != .building && step != .paywall {
                    ProgressView(value: progress)
                        .tint(accent).padding(.horizontal, 28).padding(.top, 12)
                }
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
                    .id(step)
            }
            .foregroundStyle(titleColor)
        }
        .animation(.easeInOut(duration: 0.35), value: step)
        .onAppear {
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-onboardingStep"), i + 1 < args.count,
               let raw = Int(args[i + 1]), let s = Step(rawValue: raw) {
                if name.isEmpty { name = "Alice" }
                step = s
            }
            #endif
        }
    }

    private let accent = Color(red: 0.20, green: 0.18, blue: 0.45)
    private var progress: Double {
        let ordered: [Step] = [.aboutBaby, .struggle, .method, .value, .science, .reveal]
        guard let idx = ordered.firstIndex(of: step) else { return step == .building ? 0.55 : 0 }
        return Double(idx + 1) / Double(ordered.count + 1)
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome: welcome
        case .aboutBaby: aboutBaby
        case .struggle: choices("What's your biggest challenge right now?", Struggle.allCases, selected: struggle) { struggle = $0; advance() }
        case .method: choices("How do you decide when to put \(babyName) down today?", Method.allCases, selected: method) { method = $0; advance() }
        case .building: building
        case .value: value
        case .science: science
        case .reveal: reveal
        case .paywall:
            PaywallView(babyName: babyName,
                        onDone: finish,
                        headline: "Unlock \(babyName)'s full sleep plan")
        }
    }

    // MARK: steps

    private var welcome: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "moon.stars.fill").font(.system(size: 64)).foregroundStyle(accent)
            Text("Perfect Nap").font(.system(size: 40, weight: .bold, design: .rounded))
            Text("Know exactly when to put your baby down — and stop guessing.")
                .font(.title3).multilineTextAlignment(.center).opacity(0.75).padding(.horizontal, 32)
            Spacer()
            primaryButton("Get started") { advance() }
            Text("Takes about a minute").font(.footnote).opacity(0.6).padding(.bottom, 8)
        }.padding(24)
    }

    private var aboutBaby: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepTitle("Tell us about your baby", "We'll tailor every prediction to them.")
            field("Baby's name") {
                TextField("Alice", text: $name).textInputAutocapitalization(.words)
                    .padding().background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius: 14))
                    .accessibilityIdentifier("onboarding.name")
            }
            field("Birth date") {
                DatePicker("", selection: $birthDate, in: ...Date.now, displayedComponents: .date)
                    .datePickerStyle(.compact).labelsHidden()
            }
            Toggle("Born early?", isOn: $bornEarly.animation())
            if bornEarly {
                Stepper("\(weeksEarly) weeks early", value: $weeksEarly, in: 1...16)
                    .font(.subheadline)
            }
            Spacer()
            primaryButton("Continue") { advance() }
        }.padding(24)
    }

    private var building: some View {
        VStack(spacing: 22) {
            Spacer()
            ProgressView().scaleEffect(1.6).tint(accent)
            Text("Building \(babyName)'s sleep profile…").font(.title3.weight(.semibold))
            Text(struggle.map { "Tuning for \($0.rawValue.lowercased())" } ?? "Matching to \(babyName)'s age")
                .font(.subheadline).opacity(0.7)
            Spacer()
        }.padding(24)
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-onboardingStep") { return }  // hold for screenshots
            #endif
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            advance()
        }
    }

    private var value: some View {
        VStack(spacing: 0) {
            TabView {
                valueCard("target", "Time it just right",
                          "We count you down to the exact window when \(babyName) will settle easiest — no more guessing or overtired meltdowns.")
                valueCard("brain.head.profile", "Tuned to \(babyName)",
                          "Perfect Nap learns \(babyName)'s real rhythm from every nap you log, so the timing gets sharper each day.")
                valueCard("clock.arrow.2.circlepath", "For the hard moments too",
                          "Early-morning resettles, the 2am wake-up, bedtime, even travel across time zones.")
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            primaryButton("Continue") { advance() }.padding(24)
        }
    }

    private var science: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer().frame(height: 8)
            Image(systemName: "books.vertical.fill").font(.system(size: 44)).foregroundStyle(accent)
            Text("Grounded in the research\npediatricians trust").font(.title.weight(.bold))
            Text("No fads. Perfect Nap's timing comes from the same science used in clinics and the leading sleep programs:")
                .font(.subheadline).opacity(0.8)
            VStack(alignment: .leading, spacing: 10) {
                scienceRow("Two-process model of sleep", "The clinical basis (Process S × C)")
                scienceRow("AAP / AASM consensus", "Safe 24-hour sleep guardrails")
                scienceRow("Iglowstein et al., Pediatrics", "Normative curves, 493 children")
                scienceRow("Practitioner consensus", "Weissbluth, Karp, Taking Cara Babies")
            }
            Spacer()
            primaryButton("Continue") { advance() }
        }.padding(24)
    }

    private var reveal: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "sparkles").font(.system(size: 44)).foregroundStyle(accent)
            Text("\(babyName)'s plan is ready").font(.system(size: 30, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
            VStack(spacing: 6) {
                Text("Ideal wake window, ~after each wake").font(.subheadline).opacity(0.7)
                Text(previewWindow).font(.system(size: 52, weight: .heavy, design: .rounded)).foregroundStyle(accent)
                Text("for a \(ageText) baby").font(.subheadline).opacity(0.7)
            }
            .padding(.vertical, 18).padding(.horizontal, 28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Text("Start your free trial to get it live on your home screen and lock screen — learning \(babyName)'s rhythm from day one.")
                .font(.footnote).multilineTextAlignment(.center).opacity(0.8).padding(.horizontal, 24)
            Spacer()
            primaryButton("See my free trial") { advance() }
        }.padding(24)
    }

    // MARK: building blocks

    private func choices<T: Identifiable & RawRepresentable>(_ title: String, _ options: [T], selected: T?, pick: @escaping (T) -> Void) -> some View where T.RawValue == String {
        VStack(alignment: .leading, spacing: 16) {
            Spacer().frame(height: 8)
            Text(title).font(.title2.weight(.bold)).padding(.bottom, 4)
            ForEach(options) { option in
                Button { pick(option) } label: {
                    HStack {
                        Text(option.rawValue).font(.headline.weight(.medium))
                        Spacer()
                        Image(systemName: selected?.id == option.id ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected?.id == option.id ? accent : .secondary)
                    }
                    .padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }.buttonStyle(.plain)
            }
            Spacer()
        }.padding(24)
    }

    private func valueCard(_ icon: String, _ title: String, _ body: String) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: icon).font(.system(size: 64)).foregroundStyle(accent)
            Text(title).font(.title.weight(.bold)).multilineTextAlignment(.center)
            Text(body).font(.title3).multilineTextAlignment(.center).opacity(0.78).padding(.horizontal, 28)
            Spacer()
        }.padding(.bottom, 40)
    }

    private func scienceRow(_ title: String, _ sub: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(sub).font(.caption).opacity(0.7)
            }
        }
    }

    private func stepTitle(_ title: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title2.weight(.bold))
            Text(sub).font(.subheadline).opacity(0.7)
        }.padding(.top, 8)
    }

    private func field<V: View>(_ label: String, @ViewBuilder _ control: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.subheadline.weight(.medium)).opacity(0.7)
            control()
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            Text(title).font(.title3.weight(.semibold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 17)
                .background(accent).clipShape(Capsule())
        }
        .accessibilityIdentifier("onboarding.continue")
    }

    // MARK: logic

    private var ageDays: Int { max(0, Calendar.current.dateComponents([.day], from: birthDate, to: .now).day ?? 0) }
    private var correctedDays: Int { bornEarly ? max(0, ageDays - weeksEarly * 7) : ageDays }
    private var ageText: String {
        let m = correctedDays / 30
        return m >= 1 ? "\(m)-month-old" : "\(max(1, correctedDays / 7))-week-old"
    }
    private var previewWindow: String {
        let p = WakeWindowTable.profile(forAgeDays: correctedDays)
        let mins = Int(Double(p.window.typicalMinutes) * p.firstWindowFactor)
        let h = mins / 60, m = mins % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { finish(); return }
        step = next
    }

    private func finish() {
        store.setupBaby(name: name.isEmpty ? "Baby" : name, birthDate: birthDate)
        if bornEarly { store.setWeeksPremature(weeksEarly) }
        onComplete()
    }
}
