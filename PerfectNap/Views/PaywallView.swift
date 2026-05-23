import SwiftUI
import StoreKit

/// The trial / subscription offer. Kept low-friction: one primary CTA (start the free trial), a clear
/// "cancel anytime" safety net, annual pre-selected as best value, and an explicit free-version
/// escape so people who don't convert still stay in the funnel (and can invite a partner).
struct PaywallView: View {
    @Environment(SubscriptionManager.self) private var sub
    @Environment(\.colorScheme) private var colorScheme
    let babyName: String
    let onDone: () -> Void
    var headline: String = "Unlock the full sleep plan"

    @State private var annualSelected = true
    @State private var working = false

    private let accent = Color(red: 0.20, green: 0.18, blue: 0.45)

    var body: some View {
        ZStack {
            Theme.awakeBackground(for: colorScheme).ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 18) {
                        Image(systemName: "moon.stars.fill").font(.system(size: 46)).foregroundStyle(accent).padding(.top, 16)
                        Text(headline).font(.title.weight(.bold)).multilineTextAlignment(.center)
                        Text("Free for 7 days. Cancel anytime.").font(.headline.weight(.medium)).opacity(0.75)

                        VStack(alignment: .leading, spacing: 12) {
                            benefit("Personalised predictions that learn \(babyName)")
                            benefit("Bedtime planning, daily schedule & wake-up timing")
                            benefit("Resettle help, jet-lag & daylight-saving easing")
                            benefit("Insights, forecasts & multiple children")
                            benefit("Your partner gets it free — one subscription per family")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                        planOption(annual: true)
                        planOption(annual: false)

                        Text("7-day free trial, then your plan auto-renews until cancelled. Cancel anytime in Settings.")
                            .font(.caption2).opacity(0.6).multilineTextAlignment(.center).padding(.horizontal, 8)
                    }
                    .padding(.horizontal, 22)
                }
                VStack(spacing: 10) {
                    Button(action: startTrial) {
                        HStack {
                            if working { ProgressView().tint(.white) }
                            Text(working ? "Starting…" : "Start my 7-day free trial")
                        }
                        .font(.title3.weight(.semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 17)
                        .background(accent).clipShape(Capsule())
                    }
                    .disabled(working)
                    .accessibilityIdentifier("paywall.startTrial")
                    HStack(spacing: 18) {
                        Button("Restore") { Task { await sub.restore(); if sub.isPremium { onDone() } } }
                        Button("Continue with the free version") { onDone() }
                            .accessibilityIdentifier("paywall.continueFree")
                    }
                    .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 8)
            }
            .foregroundStyle(colorScheme == .dark ? Color(red: 0.96, green: 0.91, blue: 0.82) : Color(red: 0.20, green: 0.15, blue: 0.10))
        }
    }

    private func benefit(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(accent)
            Text(text).font(.subheadline)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func planOption(annual: Bool) -> some View {
        let selected = annualSelected == annual
        let price = annual ? (sub.annual?.displayPrice ?? "$29.99") : (sub.monthly?.displayPrice ?? "$4.99")
        Button { annualSelected = annual; Haptics.tap() } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle").foregroundStyle(selected ? accent : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(annual ? "Yearly" : "Monthly").font(.headline)
                        if annual {
                            Text("BEST VALUE — SAVE 50%").font(.caption2.weight(.bold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(accent.opacity(0.15), in: Capsule()).foregroundStyle(accent)
                        }
                    }
                    Text(annual ? "\(price) / year · about $2.50 / month" : "\(price) / month")
                        .font(.subheadline).opacity(0.7)
                }
                Spacer()
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? accent : .clear, lineWidth: 2))
        }.buttonStyle(.plain)
    }

    private func startTrial() {
        let product = annualSelected ? sub.annual : sub.monthly
        guard let product else {
            // No StoreKit product (e.g. config missing) — don't trap the user in onboarding.
            if SubscriptionManager.isComplimentary { onDone() }
            return
        }
        working = true
        Task {
            let ok = await sub.purchase(product)
            working = false
            if ok || SubscriptionManager.isComplimentary { onDone() }
        }
    }
}
