import Foundation
import SwiftData

@Model
final class Baby {
    var name: String
    var birthDate: Date
    var createdAt: Date

    var adaptationFactor: Double
    var adaptationConfidence: Double

    init(name: String = "Baby", birthDate: Date, createdAt: Date = .now) {
        self.name = name
        self.birthDate = birthDate
        self.createdAt = createdAt
        self.adaptationFactor = 1.0
        self.adaptationConfidence = 0.0
    }

    var ageInDays: Int {
        Calendar.current.dateComponents([.day], from: birthDate, to: .now).day ?? 0
    }

    var ageInWeeks: Int { ageInDays / 7 }
    var ageInMonths: Int {
        Calendar.current.dateComponents([.month], from: birthDate, to: .now).month ?? 0
    }

    var ageDescription: String {
        let months = ageInMonths
        if months < 1 {
            let weeks = ageInWeeks
            return weeks <= 1 ? "\(ageInDays) days old" : "\(weeks) weeks old"
        }
        if months < 24 { return "\(months) month\(months == 1 ? "" : "s") old" }
        let years = months / 12
        let remainderMonths = months % 12
        if remainderMonths == 0 { return "\(years) year\(years == 1 ? "" : "s") old" }
        return "\(years)y \(remainderMonths)m old"
    }
}
