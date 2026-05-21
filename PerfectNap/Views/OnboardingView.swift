import SwiftUI

struct OnboardingView: View {
    @Environment(SleepStore.self) private var store

    @State private var name: String = ""
    @State private var birthDate: Date = Calendar.current.date(byAdding: .month, value: -4, to: .now) ?? .now

    var body: some View {
        ZStack {
            Theme.awakeGradient.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                VStack(spacing: 8) {
                    Text("Perfect Nap")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    Text("One tap. Right time. Every nap.")
                        .font(.title3)
                        .opacity(0.7)
                }
                Spacer()

                VStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Baby's name (optional)").font(.subheadline.weight(.medium)).opacity(0.7)
                        TextField("Baby", text: $name)
                            .textInputAutocapitalization(.words)
                            .padding()
                            .background(.white.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Birth date").font(.subheadline.weight(.medium)).opacity(0.7)
                        DatePicker("", selection: $birthDate, in: ...Date.now, displayedComponents: .date)
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                            .background(.white.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(.horizontal, 8)

                Spacer()

                Button {
                    store.setupBaby(name: name.isEmpty ? "Baby" : name, birthDate: birthDate)
                } label: {
                    Text("Start tracking")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color(red: 0.20, green: 0.18, blue: 0.45))
                        .clipShape(Capsule())
                }
                .buttonStyle(PressButtonStyle())
                .padding(.horizontal)
                Spacer().frame(height: 12)
            }
            .padding(24)
            .foregroundStyle(Color(red: 0.20, green: 0.15, blue: 0.10))
        }
    }
}
