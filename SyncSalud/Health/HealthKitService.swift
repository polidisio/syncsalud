import Foundation
import HealthKit
import Observation

/// States de autorización expuestos a la UI
enum HealthKitAuthorizationState: Equatable {
    case notRequested
    case authorized
    case denied
    case notAvailable
    case error(String)
}

@Observable
final class HealthKitService {
    // MARK: - Properties

    private let healthStore = HKHealthStore.isHealthDataAvailable() ? HKHealthStore() : nil

    private(set) var authorizationState: HealthKitAuthorizationState = .notRequested
    private(set) var isLoading = false
    private(set) var lastError: String?

    /// Workout types que SyncSalud lee de HealthKit
    private let workoutTypesToRead: Set<HKWorkoutActivityType> = [
        .running, .cycling, .swimming, .walking, .hiking,
        .yoga, .traditionalStrengthTraining, .functionalStrengthTraining,
        .danceInspiredTraining, .elliptical, .rowing, .stairClimbing,
        .pilates, .kickboxing, .surfingSports, .tennis,
        .soccer, .basketball, .other
    ]

    /// Los tipos de cantidad que SyncSalud puede leer
    private var quantityTypesToRead: Set<HKQuantityType> {
        [
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.distanceCycling),
            HKQuantityType(.runningSpeed),
            HKQuantityType(.runningPower),
            HKQuantityType(.cyclingPower),
            HKQuantityType(.vo2Max)
        ]
    }

    var isAuthorized: Bool {
        authorizationState == .authorized
    }

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    /// Versión estática para usar desde background tasks (AppDelegate)
    static var isAvailableStatic: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    // MARK: - Autorización

    /// Solicita autorización a HealthKit
    @MainActor
    func requestAuthorization() async {
        print("🏥 Solicitando autorización HealthKit...")
        print("   - isAvailable: \(isAvailable)")
        print("   - healthStore: \(healthStore != nil)")

        guard isAvailable else {
            print("❌ HealthKit no disponible en este dispositivo")
            authorizationState = .notAvailable
            return
        }

        guard let healthStore else {
            print("❌ No se pudo crear HKHealthStore")
            authorizationState = .notAvailable
            return
        }

        // Construir tipos a leer: workouts + quantity types
        var readTypes: Set<HKObjectType> = [HKObjectType.workoutType()]
        readTypes.formUnion(quantityTypesToRead)

        do {
            try await healthStore.requestAuthorization(
                toShare: [],  // Solo lectura, no escribimos datos
                read: readTypes
            )

            // HealthKit NO informa si la autorización fue otorgada o denegada
            // (es privado por diseño). Asumimos que si no hubo error, está disponible.
            // La verificación real ocurre cuando intentamos leer datos.
            authorizationState = .authorized
            lastError = nil
            print("✅ Autorización HealthKit solicitada correctamente")
        } catch {
            print("❌ Error en requestAuthorization: \(error.localizedDescription)")
            authorizationState = .error(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    /// Verifica el estado de autorización actual
    @MainActor
    private func checkAuthorizationStatus() async {
        guard let healthStore else { return }

        // HealthKit no tiene una API directa para verificar si un tipo específico está autorizado.
        // Intentamos ejecutar una query simple como prueba.
        let runningType = HKObjectType.workoutType()

        let status = healthStore.authorizationStatus(for: runningType)

        switch status {
        case .sharingAuthorized:
            authorizationState = .authorized
        case .sharingDenied:
            authorizationState = .denied
        case .notDetermined:
            authorizationState = .notRequested
        @unknown default:
            authorizationState = .notRequested
        }
    }

    // MARK: - Lectura de Workouts

    /// Lee todos los workouts desde HealthKit en un rango de fechas
    /// - Returns: Workouts de HealthKit, vacío si hay error o sin permisos
    func fetchWorkouts(from startDate: Date? = nil, to endDate: Date = Date()) async -> [HKWorkout] {
        guard isAvailable, isAuthorized, let healthStore else {
            lastError = "HealthKit no disponible o no autorizado"
            return []
        }

        isLoading = true
        defer { isLoading = false }

        let predicate: NSPredicate
        if let start = startDate {
            predicate = HKQuery.predicateForSamples(withStart: start, end: endDate, options: .strictStartDate)
        } else {
            // Si no hay fecha de inicio, traemos todo
            predicate = HKQuery.predicateForSamples(withStart: nil, end: endDate, options: [])
        }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    self.lastError = "Error fetching workouts: \(error.localizedDescription)"
                    continuation.resume(returning: [])
                    return
                }

                let workouts = samples as? [HKWorkout] ?? []
                continuation.resume(returning: workouts)
            }

            healthStore.execute(query)
        }
    }

    /// Obtener frecuencia cardíaca promedio para un workout específico
    func fetchAverageHeartRate(for workout: HKWorkout) async -> Double? {
        guard isAvailable, isAuthorized, let healthStore else { return nil }

        let heartRateType = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: heartRateType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, _ in
                let avg = statistics?.averageQuantity()?
                    .doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                continuation.resume(returning: avg)
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Observación en vivo

    /// Configura un observer para detectar nuevos workouts en HealthKit
    /// Llama al closure cuando detecta cambios
    func startObserver(forUpdate handler: @escaping () -> Void) {
        guard isAvailable, isAuthorized, let healthStore else { return }

        let query = HKObserverQuery(sampleType: .workoutType(), predicate: nil) { _, completionHandler, error in
            if error == nil {
                handler()
            }
            completionHandler()
        }

        healthStore.execute(query)
    }
}
