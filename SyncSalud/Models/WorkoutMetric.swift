import Foundation
import SwiftData

@Model
final class WorkoutMetric {
    var id: UUID = UUID()

    /// Workout padre (no usamos .unique por CloudKit)
    var workout: WorkoutRecord?

    /// Timestamp de la medición
    var timestamp: Date = Date()

    /// Heart rate en ese momento (bpm)
    var heartRate: Double? = nil

    /// Cadencia (spm — steps per minute)
    var cadence: Double? = nil

    /// Velocidad (m/s)
    var speed: Double? = nil

    /// Potencia (vatios)
    var power: Double? = nil

    /// Altitud (metros)
    var altitude: Double? = nil

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        heartRate: Double? = nil,
        cadence: Double? = nil,
        speed: Double? = nil,
        power: Double? = nil,
        altitude: Double? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.heartRate = heartRate
        self.cadence = cadence
        self.speed = speed
        self.power = power
        self.altitude = altitude
    }
}
