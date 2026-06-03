import Foundation
import SwiftData
import HealthKit

/// Tipo de entrenamiento como enum para tipo-safe
enum WorkoutType: String, CaseIterable, Codable {
    case running = "running"
    case cycling = "cycling"
    case swimming = "swimming"
    case walking = "walking"
    case hiking = "hiking"
    case yoga = "yoga"
    case strength = "strength"
    case functional = "functional"
    case dancing = "dancing"
    case elliptical = "elliptical"
    case rowing = "rowing"
    case stairClimbing = "stair_climbing"
    case pilates = "pilates"
    case kickboxing = "kickboxing"
    case surfing = "surfing"
    case tennis = "tennis"
    case soccer = "soccer"
    case basketball = "basketball"
    case other = "other"

    var displayName: String {
        switch self {
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .walking: return "Walking"
        case .hiking: return "Hiking"
        case .yoga: return "Yoga"
        case .strength: return "Strength Training"
        case .functional: return "Functional Training"
        case .dancing: return "Dancing"
        case .elliptical: return "Elliptical"
        case .rowing: return "Rowing"
        case .stairClimbing: return "Stair Climbing"
        case .pilates: return "Pilates"
        case .kickboxing: return "Kickboxing"
        case .surfing: return "Surfing"
        case .tennis: return "Tennis"
        case .soccer: return "Soccer"
        case .basketball: return "Basketball"
        case .other: return "Other"
        }
    }

    var sfSymbol: String {
        switch self {
        case .running: return "figure.run"
        case .cycling: return "figure.outdoor.cycle"
        case .swimming: return "figure.pool.swim"
        case .walking: return "figure.walk"
        case .hiking: return "figure.hiking"
        case .yoga: return "figure.yoga"
        case .strength: return "figure.strengthtraining.functional"
        case .functional: return "figure.cross.training"
        case .dancing: return "figure.dance"
        case .elliptical: return "figure.elliptical"
        case .rowing: return "figure.rower"
        case .stairClimbing: return "figure.stair.stepper"
        case .pilates: return "figure.pilates"
        case .kickboxing: return "figure.boxing"
        case .surfing: return "figure.surfing"
        case .tennis: return "figure.tennis"
        case .soccer: return "figure.soccer"
        case .basketball: return "figure.basketball"
        case .other: return "figure.mixed.cardio"
        }
    }
}

/// Estado de sincronización de un registro
enum SyncStatus: String, Codable {
    case synced = "synced"
    case pending = "pending"
    case failed = "failed"
}

@Model
final class WorkoutRecord {
    /// Identificador único (sin .unique por CloudKit, deduplicamos por healthKitID en código)
    var id: UUID = UUID()

    /// Tipo de entrenamiento
    var workoutType: String = WorkoutType.other.rawValue

    /// Fechas
    var startDate: Date = Date()
    var endDate: Date = Date()

    /// Duración en segundos
    var duration: Double = 0.0

    /// Calorías activas (kcal)
    var calories: Double? = nil

    /// Distancia en metros
    var distance: Double? = nil
    var distanceUnit: String? = nil

    /// Frecuencia cardíaca
    var avgHeartRate: Double? = nil
    var maxHeartRate: Double? = nil
    var minHeartRate: Double? = nil

    /// Origen del dato
    var source: String = "healthkit"

    /// UUID de HealthKit para deduplicación (índice, no unique)
    var healthKitID: String? = nil

    /// Metadatos extras en JSON
    var metadataData: Data? = nil

    /// Timestamps del sistema
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    /// Estado de sincronización CloudKit
    var syncStatus: String = SyncStatus.pending.rawValue

    /// Relación: métricas detalladas por intervalo
    @Relationship(deleteRule: .cascade) var metrics: [WorkoutMetric]? = []

    // MARK: - Inicializador

    init(
        id: UUID = UUID(),
        workoutType: String,
        startDate: Date,
        endDate: Date,
        duration: Double,
        calories: Double? = nil,
        distance: Double? = nil,
        distanceUnit: String? = nil,
        avgHeartRate: Double? = nil,
        maxHeartRate: Double? = nil,
        minHeartRate: Double? = nil,
        source: String = "healthkit",
        healthKitID: String? = nil,
        metadata: [String: Any]? = nil,
        syncStatus: String = SyncStatus.pending.rawValue
    ) {
        self.id = id
        self.workoutType = workoutType
        self.startDate = startDate
        self.endDate = endDate
        self.duration = duration
        self.calories = calories
        self.distance = distance
        self.distanceUnit = distanceUnit
        self.avgHeartRate = avgHeartRate
        self.maxHeartRate = maxHeartRate
        self.minHeartRate = minHeartRate
        self.source = source
        self.healthKitID = healthKitID
        if let metadata {
            self.metadataData = try? JSONSerialization.data(withJSONObject: metadata)
        }
        self.createdAt = Date()
        self.updatedAt = Date()
        self.syncStatus = syncStatus
    }
}

// MARK: - Conveniencia

extension WorkoutRecord {
    var typeEnum: WorkoutType {
        WorkoutType(rawValue: workoutType) ?? .other
    }

    var durationFormatted: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes) min"
    }

    var caloriesFormatted: String {
        guard let cals = calories else { return "—" }
        return "\(Int(cals)) kcal"
    }

    var distanceFormatted: String {
        guard let dist = distance else { return "—" }
        if dist >= 1000 {
            return String(format: "%.2f km", dist / 1000)
        }
        return "\(Int(dist)) m"
    }

    var dateFormatted: String {
        startDate.formatted(date: .abbreviated, time: .shortened)
    }

    var metadata: [String: Any]? {
        guard let data = metadataData else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

// MARK: - HealthKit Mapping

extension WorkoutRecord {
    static func fromHKWorkout(_ workout: HKWorkout) -> WorkoutRecord {
        let type = workout.workoutActivityType.syncSaludType

        let distance = workout.totalDistance?.doubleValue(for: .meter())
        let calories = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())

        return WorkoutRecord(
            workoutType: type.rawValue,
            startDate: workout.startDate,
            endDate: workout.endDate,
            duration: workout.duration,
            calories: calories,
            distance: distance,
            distanceUnit: distance != nil ? "meters" : nil,
            source: "healthkit",
            healthKitID: workout.uuid.uuidString,
            syncStatus: SyncStatus.pending.rawValue
        )
    }
}

// MARK: - Extensión de HKWorkoutActivityType

extension HKWorkoutActivityType {
    var syncSaludType: WorkoutType {
        switch self {
        case .running: return .running
        case .cycling: return .cycling
        case .swimming: return .swimming
        case .walking: return .walking
        case .hiking: return .hiking
        case .yoga: return .yoga
        case .traditionalStrengthTraining: return .strength
        case .functionalStrengthTraining: return .functional
        case .danceInspiredTraining: return .dancing
        case .elliptical: return .elliptical
        case .rowing: return .rowing
        case .stairClimbing: return .stairClimbing
        case .pilates: return .pilates
        case .kickboxing: return .kickboxing
        case .surfingSports: return .surfing
        case .tennis: return .tennis
        case .soccer: return .soccer
        case .basketball: return .basketball
        default: return .other
        }
    }
}
