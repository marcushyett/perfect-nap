import SwiftUI
import Charts

struct DaySleepBlock: Identifiable {
    let id = UUID()
    let start: Date
    let end: Date
    let kind: SleepKind
}

struct DayTotal: Identifiable {
    let id = UUID()
    let day: Date
    let dayLabel: String
    let totalMinutes: Double
    let napCount: Int
}

/// Horizontal timeline of today's sleep across 24 hours. Each block is a nap or night segment.
struct TodayTimelineChart: View {
    let sessions: [NapSession]
    private let dayStart: Date
    private let dayEnd: Date

    init(sessions: [NapSession], now: Date = .now) {
        self.sessions = sessions
        let cal = Calendar.current
        self.dayStart = cal.startOfDay(for: now)
        self.dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? now
    }

    private var blocks: [DaySleepBlock] {
        sessions.compactMap { session in
            let end = session.endedAt ?? .now
            let clampedStart = max(session.startedAt, dayStart)
            let clampedEnd = min(end, dayEnd)
            guard clampedEnd > clampedStart else { return nil }
            return DaySleepBlock(start: clampedStart, end: clampedEnd, kind: session.kind)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Today's rhythm").font(.subheadline.weight(.semibold))
                Spacer()
                Text(totalLabel).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Chart {
                ForEach(blocks) { block in
                    BarMark(
                        xStart: .value("Start", block.start),
                        xEnd: .value("End", block.end),
                        y: .value("Today", "")
                    )
                    .foregroundStyle(block.kind == .night ? .indigo : .orange)
                    .cornerRadius(4)
                }
            }
            .chartXScale(domain: dayStart...dayEnd)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .narrow)))
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 56)
        }
    }

    private var totalLabel: String {
        let total = blocks.reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) }
        let h = Int(total) / 3600
        let m = (Int(total) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m total" : "\(m)m total"
    }
}

/// Last 7 days bar chart: total daytime sleep per day, plus the AAP/AASM target band overlay.
struct WeeklyDaySleepChart: View {
    let sessions: [NapSession]
    let baby: Baby

    private var days: [DayTotal] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let formatter = DateFormatter(); formatter.dateFormat = "EEE"
        return (0..<7).reversed().map { offset in
            let day = cal.date(byAdding: .day, value: -offset, to: today) ?? today
            let dayEnd = cal.date(byAdding: .day, value: 1, to: day) ?? day
            let dayNaps = sessions.filter { $0.kind == .nap && $0.startedAt >= day && $0.startedAt < dayEnd && $0.endedAt != nil }
            let totalMinutes = dayNaps.reduce(0.0) { $0 + $1.duration } / 60.0
            return DayTotal(
                day: day,
                dayLabel: cal.isDateInToday(day) ? "Today" : formatter.string(from: day),
                totalMinutes: totalMinutes,
                napCount: dayNaps.count
            )
        }
    }

    private var profile: AgeProfile { WakeWindowTable.profile(forAgeDays: baby.ageInDays) }
    private var targetLow: Double { profile.totalDaySleepHours.lowerBound * 60 }
    private var targetHigh: Double { profile.totalDaySleepHours.upperBound * 60 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Day sleep — last 7 days").font(.subheadline.weight(.semibold))
                Spacer()
                Text("Target \(format(targetLow))–\(format(targetHigh))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Chart {
                RectangleMark(
                    xStart: .value("", days.first?.dayLabel ?? ""),
                    xEnd: .value("", days.last?.dayLabel ?? ""),
                    yStart: .value("Min", targetLow),
                    yEnd: .value("Max", targetHigh)
                )
                .foregroundStyle(.green.opacity(0.10))

                ForEach(days) { day in
                    BarMark(
                        x: .value("Day", day.dayLabel),
                        y: .value("Minutes", day.totalMinutes)
                    )
                    .foregroundStyle(barColor(for: day.totalMinutes))
                    .cornerRadius(6)
                    .annotation(position: .top, alignment: .center) {
                        if day.totalMinutes > 0 {
                            Text(format(day.totalMinutes))
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .stride(by: 60)) { value in
                    AxisGridLine()
                    if let mins = value.as(Double.self) {
                        AxisValueLabel { Text("\(Int(mins / 60))h") }
                    }
                }
            }
            .frame(height: 200)
        }
    }

    private func barColor(for minutes: Double) -> Color {
        if minutes == 0 { return .gray.opacity(0.3) }
        if minutes < targetLow { return .orange }
        if minutes > targetHigh { return .pink }
        return .green
    }

    private func format(_ minutes: Double) -> String {
        let h = Int(minutes) / 60
        let m = Int(minutes) % 60
        return h > 0 ? "\(h)h\(m > 0 ? "\(m)m" : "")" : "\(m)m"
    }
}

/// Last 7 days average wake window between naps, compared to clinical baseline.
struct WeeklyWakeWindowChart: View {
    let sessions: [NapSession]
    let baby: Baby

    private struct DayWW: Identifiable {
        let id = UUID()
        let dayLabel: String
        let averageMinutes: Double
    }

    private var data: [DayWW] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let formatter = DateFormatter(); formatter.dateFormat = "EEE"
        return (0..<7).reversed().map { offset in
            let day = cal.date(byAdding: .day, value: -offset, to: today) ?? today
            let dayEnd = cal.date(byAdding: .day, value: 1, to: day) ?? day
            let dayNaps = sessions
                .filter { $0.kind == .nap && $0.endedAt != nil && $0.startedAt >= day && $0.startedAt < dayEnd }
                .sorted { $0.startedAt < $1.startedAt }

            var gaps: [TimeInterval] = []
            for (prev, curr) in zip(dayNaps, dayNaps.dropFirst()) {
                if let prevEnd = prev.endedAt {
                    gaps.append(curr.startedAt.timeIntervalSince(prevEnd))
                }
            }
            let averageMin = gaps.isEmpty ? 0 : (gaps.reduce(0, +) / Double(gaps.count)) / 60
            return DayWW(
                dayLabel: cal.isDateInToday(day) ? "Today" : formatter.string(from: day),
                averageMinutes: averageMin
            )
        }
    }

    private var baseline: Int {
        WakeWindowTable.profile(forAgeDays: baby.ageInDays).window.typicalMinutes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Average wake window").font(.subheadline.weight(.semibold))
                Spacer()
                Text("Baseline \(baseline)m").font(.caption).foregroundStyle(.secondary)
            }
            Chart {
                RuleMark(y: .value("Baseline", Double(baseline)))
                    .foregroundStyle(.gray.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

                ForEach(data) { day in
                    if day.averageMinutes > 0 {
                        LineMark(
                            x: .value("Day", day.dayLabel),
                            y: .value("Minutes", day.averageMinutes)
                        )
                        .symbol(.circle)
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(.indigo)
                    }
                }
            }
            .frame(height: 140)
        }
    }
}
