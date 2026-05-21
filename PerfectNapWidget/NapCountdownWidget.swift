import WidgetKit
import SwiftUI

struct NapCountdownEntry: TimelineEntry {
    let date: Date
    let snapshot: SharedSnapshot?
}

struct NapCountdownProvider: TimelineProvider {
    func placeholder(in context: Context) -> NapCountdownEntry {
        NapCountdownEntry(date: .now, snapshot: previewSnapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (NapCountdownEntry) -> Void) {
        let snap = SharedSnapshotStore.read() ?? previewSnapshot
        completion(NapCountdownEntry(date: .now, snapshot: snap))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NapCountdownEntry>) -> Void) {
        let snapshot = SharedSnapshotStore.read()
        let entry = NapCountdownEntry(date: .now, snapshot: snapshot)
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private var previewSnapshot: SharedSnapshot {
        SharedSnapshot(
            babyName: "Baby",
            ageDescription: "4 months old",
            activeStartedAt: nil,
            activeKind: nil,
            nextNapAt: Calendar.current.date(byAdding: .minute, value: 90, to: .now),
            earliestNapAt: Calendar.current.date(byAdding: .minute, value: 75, to: .now),
            latestNapAt: Calendar.current.date(byAdding: .minute, value: 120, to: .now),
            napsTodayCount: 1,
            lastNapEndedAt: Calendar.current.date(byAdding: .minute, value: -10, to: .now),
            lastNapDurationMinutes: 45
        )
    }
}

struct NapCountdownWidget: Widget {
    let kind: String = "NapCountdownWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NapCountdownProvider()) { entry in
            NapCountdownView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Perfect Nap")
        .description("Countdown to the next nap, on your home or lock screen.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

private struct NapCountdownView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NapCountdownEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            inlineView
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    @ViewBuilder
    private var smallView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: phaseIcon).foregroundStyle(phaseTint)
                Text(entry.snapshot?.babyName ?? "Perfect Nap")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer()
            }
            Spacer(minLength: 2)
            mainText
            captionText
        }
        .padding(10)
    }

    @ViewBuilder
    private var mediumView: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: phaseIcon).foregroundStyle(phaseTint)
                    Text(entry.snapshot?.babyName ?? "Perfect Nap")
                        .font(.caption.weight(.semibold))
                }
                mainText
                captionText
            }
            Spacer()
            if let s = entry.snapshot {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(s.napsTodayCount)").font(.title2.weight(.bold)).monospacedDigit()
                    Text("naps today").font(.caption2).foregroundStyle(.secondary)
                    if let last = s.lastNapEndedAt {
                        Text("Last \(s.lastNapDurationMinutes)m at \(timeFormatter.string(from: last))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: phaseIcon).foregroundStyle(phaseTint)
                Text(entry.snapshot?.babyName ?? "Perfect Nap").font(.headline)
            }
            mainText
            captionText
        }
    }

    @ViewBuilder
    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let active = entry.snapshot?.activeStartedAt {
                VStack(spacing: 0) {
                    Image(systemName: "moon.zzz.fill").font(.caption)
                    Text(timerInterval: active...Date.distantFuture, countsDown: false)
                        .font(.caption2.weight(.bold)).monospacedDigit()
                }
            } else if let next = entry.snapshot?.nextNapAt, next > .now {
                VStack(spacing: 0) {
                    Image(systemName: "sun.max.fill").font(.caption)
                    Text(timerInterval: .now...next, countsDown: true)
                        .font(.caption2.weight(.bold)).monospacedDigit()
                }
            } else {
                Image(systemName: "zzz").font(.title2)
            }
        }
    }

    @ViewBuilder
    private var inlineView: some View {
        if let active = entry.snapshot?.activeStartedAt {
            Label {
                Text(timerInterval: active...Date.distantFuture, countsDown: false)
            } icon: { Image(systemName: "moon.zzz.fill") }
        } else if let next = entry.snapshot?.nextNapAt, next > .now {
            Label {
                Text(timerInterval: .now...next, countsDown: true)
            } icon: { Image(systemName: "sun.max.fill") }
        } else {
            Label("Window open", systemImage: "exclamationmark.circle.fill")
        }
    }

    @ViewBuilder
    private var mainText: some View {
        if let active = entry.snapshot?.activeStartedAt {
            Text(timerInterval: active...Date.distantFuture, countsDown: false)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
        } else if let next = entry.snapshot?.nextNapAt {
            if next > .now {
                Text(timerInterval: .now...next, countsDown: true)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
            } else {
                Text("Window open")
                    .font(.headline.weight(.semibold)).foregroundStyle(.orange)
            }
        } else {
            Text("Open app").font(.headline)
        }
    }

    @ViewBuilder
    private var captionText: some View {
        if entry.snapshot?.activeStartedAt != nil {
            Text("Napping").font(.caption).foregroundStyle(.secondary)
        } else if let next = entry.snapshot?.nextNapAt {
            Text(next > .now ? "until next nap" : "right now").font(.caption).foregroundStyle(.secondary)
        } else {
            Text("Tap to set up").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var phaseIcon: String {
        entry.snapshot?.activeStartedAt != nil ? "moon.zzz.fill" : "sun.max.fill"
    }
    private var phaseTint: Color {
        entry.snapshot?.activeStartedAt != nil ? .indigo : .orange
    }

    private var timeFormatter: DateFormatter {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; return f
    }
}
