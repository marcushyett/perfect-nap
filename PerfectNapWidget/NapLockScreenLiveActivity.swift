import WidgetKit
import ActivityKit
import SwiftUI
import AppIntents

struct NapLockScreenLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NapActivityAttributes.self) { context in
            LockScreenView(state: context.state, babyName: context.attributes.babyName)
                .activityBackgroundTint(.indigo.opacity(0.15))
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.attributes.babyName).font(.headline)
                    } icon: {
                        Image(systemName: context.state.phase == .napping ? "moon.zzz.fill" : "sun.max.fill")
                            .foregroundStyle(context.state.phase == .napping ? .indigo : .orange)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    expandedTrailing(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    expandedBottom(state: context.state)
                }
            } compactLeading: {
                Image(systemName: context.state.phase == .napping ? "moon.zzz.fill" : "sun.max.fill")
                    .foregroundStyle(context.state.phase == .napping ? .indigo : .orange)
            } compactTrailing: {
                compactTrailing(state: context.state)
            } minimal: {
                Image(systemName: context.state.phase == .napping ? "moon.fill" : "sun.max")
                    .foregroundStyle(context.state.phase == .napping ? .indigo : .orange)
            }
            .widgetURL(URL(string: "perfectnap://"))
        }
    }

    @ViewBuilder
    private func expandedTrailing(state: NapActivityAttributes.ContentState) -> some View {
        switch state.phase {
        case .napping:
            if let start = state.sessionStart {
                Text(timerInterval: start...Date.distantFuture, countsDown: false)
                    .font(.title2.weight(.semibold)).monospacedDigit()
            }
        case .awake:
            if let next = state.nextNapAt {
                if next > .now {
                    Text(timerInterval: .now...next, countsDown: true)
                        .font(.title2.weight(.semibold)).monospacedDigit()
                } else {
                    Text("Window open")
                        .font(.headline).foregroundStyle(.orange)
                }
            }
        }
    }

    @ViewBuilder
    private func expandedBottom(state: NapActivityAttributes.ContentState) -> some View {
        HStack {
            switch state.phase {
            case .napping:
                Text(state.sleepKind == "night" ? "Sleeping (overnight)" : "Napping")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button(intent: StopNapIntent()) {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .tint(.indigo)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            case .awake:
                if let next = state.nextNapAt {
                    Text(next > .now ? "Next ~\(formatted(next))" : "Window open")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button(intent: StartNapIntent()) {
                    Label("Start nap", systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .tint(.indigo)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func compactTrailing(state: NapActivityAttributes.ContentState) -> some View {
        switch state.phase {
        case .napping:
            if let start = state.sessionStart {
                Text(timerInterval: start...Date.distantFuture, countsDown: false)
                    .monospacedDigit()
                    .frame(maxWidth: 56)
            }
        case .awake:
            if let next = state.nextNapAt, next > .now {
                Text(timerInterval: .now...next, countsDown: true)
                    .monospacedDigit()
                    .frame(maxWidth: 56)
            } else {
                Text("Now").font(.caption.weight(.bold)).foregroundStyle(.orange)
            }
        }
    }

    private func formatted(_ date: Date) -> String {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
        return f.string(from: date)
    }
}

private struct LockScreenView: View {
    let state: NapActivityAttributes.ContentState
    let babyName: String

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(state.phase == .napping ? Color.indigo.opacity(0.2) : Color.orange.opacity(0.2))
                    .frame(width: 56, height: 56)
                Image(systemName: state.phase == .napping ? "moon.zzz.fill" : "sun.max.fill")
                    .font(.title2)
                    .foregroundStyle(state.phase == .napping ? .indigo : .orange)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(babyName).font(.headline)
                content
                trailingTime
            }
            Spacer()
            actionButton
        }
        .padding(16)
    }

    @ViewBuilder
    private var content: some View {
        switch state.phase {
        case .napping:
            Text(state.sleepKind == "night" ? "Sleeping overnight" : "Napping")
                .font(.subheadline).foregroundStyle(.secondary)
        case .awake:
            if let next = state.nextNapAt {
                if next > .now {
                    Text("Next nap suggestion")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Text("Sleep window open")
                        .font(.subheadline).foregroundStyle(.orange)
                }
            }
        }
    }

    @ViewBuilder
    private var trailingTime: some View {
        switch state.phase {
        case .napping:
            if let start = state.sessionStart {
                Text(timerInterval: start...Date.distantFuture, countsDown: false)
                    .font(.title.weight(.bold)).monospacedDigit()
            }
        case .awake:
            if let next = state.nextNapAt, next > .now {
                Text(timerInterval: .now...next, countsDown: true)
                    .font(.title.weight(.bold)).monospacedDigit()
            } else {
                Text("Now")
                    .font(.title.weight(.bold)).foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch state.phase {
        case .napping:
            Button(intent: StopNapIntent()) {
                ZStack {
                    Circle().fill(Color.white)
                        .frame(width: 54, height: 54)
                        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                    Image(systemName: "stop.fill")
                        .font(.title2)
                        .foregroundStyle(.indigo)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop nap")
        case .awake:
            Button(intent: StartNapIntent()) {
                ZStack {
                    Circle().fill(Color.indigo)
                        .frame(width: 54, height: 54)
                        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                    Image(systemName: "play.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .offset(x: 2)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start nap")
        }
    }
}
