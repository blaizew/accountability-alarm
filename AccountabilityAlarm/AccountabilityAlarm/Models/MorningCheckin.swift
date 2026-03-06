import Foundation
import SwiftData

@Model
final class MorningCheckin {
    var date: Date = Date()
    var energyRating: Int = 5
    var sleepDurationEstimate: Double = 7.0
    var notes: String?

    init(energyRating: Int = 5, sleepDurationEstimate: Double = 7.0) {
        self.date = Date()
        self.energyRating = energyRating
        self.sleepDurationEstimate = sleepDurationEstimate
    }
}
