import Foundation
import HealthKit
import Observation

/// Garantiza que una CheckedContinuation se resume exactamente una vez,
/// aunque compitan un timeout y un completion handler de HealthKit.
private final class OnceResumer<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    private let continuation: CheckedContinuation<T, Never>
    private let fallback: T

    init(_ continuation: CheckedContinuation<T, Never>, default fallback: T) {
        self.continuation = continuation
        self.fallback = fallback
    }

    func finish(_ value: T?) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        continuation.resume(returning: value ?? fallback)
    }
}

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

    /// Workout types que Synctrackers lee de HealthKit
    private let workoutTypesToRead: Set<HKWorkoutActivityType> = [
        .running, .cycling, .swimming, .walking, .hiking,
        .yoga, .traditionalStrengthTraining, .functionalStrengthTraining,
        .socialDance, .cardioDance, .barre, .pilates, .elliptical, .rowing, .stairClimbing,
        .pilates, .kickboxing, .surfingSports, .tennis,
        .soccer, .basketball, .other
    ]

    /// Los tipos de cantidad que Synctrackers consulta de verdad.
    /// Solo heartRate: calorías/distancia salen del objeto HKWorkout directo.
    /// Menos tipos = permission sheet más rápido.
    private var quantityTypesToRead: Set<HKQuantityType> {
        [
            HKQuantityType(.heartRate)
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
        guard !isLoading else { return }  // evita peticiones concurrentes por taps múltiples
        isLoading = true
        defer { isLoading = false }

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
            let t0 = Date()
            try await healthStore.requestAuthorization(
                toShare: [],  // Solo lectura, no escribimos datos
                read: readTypes
            )
            print("⏱️ requestAuthorization tardó \(String(format: "%.2f", Date().timeIntervalSince(t0)))s")

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

    // NOTA: authorizationStatus(for:) comprueba permisos de ESCRITURA, no de lectura.
    // Esta app solo solicita lectura (toShare: []), por lo que siempre devolvería .sharingDenied.
    // No hay API pública en HealthKit para verificar permisos de lectura — se detecta
    // intentando un fetch real y observando si devuelve resultados.

    // MARK: - Lectura de Workouts

    /// Lee todos los workouts desde HealthKit en un rango de fechas
    /// - Returns: Workouts de HealthKit, vacío si hay error o sin permisos
    func fetchWorkouts(from startDate: Date? = nil, to endDate: Date = Date()) async -> [HKWorkout] {
        guard isAvailable, isAuthorized, let healthStore else {
            await MainActor.run { lastError = "HealthKit no disponible o no autorizado" }
            return []
        }

        await MainActor.run { isLoading = true }
        defer { Task { @MainActor in isLoading = false } }

        let predicate: NSPredicate
        if let start = startDate {
            predicate = HKQuery.predicateForSamples(withStart: start, end: endDate, options: .strictStartDate)
        } else {
            // Si no hay fecha de inicio, traemos todo
            predicate = HKQuery.predicateForSamples(withStart: nil, end: endDate, options: [])
        }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let store = healthStore
            let resumer = OnceResumer(continuation, default: [HKWorkout]())
            // 30s timeout — fetch de workouts es el más largo
            Task { try? await Task.sleep(for: .seconds(30)); resumer.finish(nil) }

            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                resumer.finish(error != nil ? nil : samples as? [HKWorkout])
            }

            store.execute(query)
        }
    }

    /// Obtener frecuencia cardíaca promedio para un workout específico
    func fetchAverageHeartRate(for workout: HKWorkout) async -> Double? {
        guard isAvailable, isAuthorized, let healthStore else { return nil }

        let heartRateType = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate, end: workout.endDate, options: .strictStartDate
        )

        return await withCheckedContinuation { continuation in
            let resumer = OnceResumer(continuation, default: nil as Double?)
            // 5s timeout por query individual
            Task { try? await Task.sleep(for: .seconds(5)); resumer.finish(nil) }

            let query = HKStatisticsQuery(
                quantityType: heartRateType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, _ in
                let avg = statistics?.averageQuantity()?
                    .doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                resumer.finish(avg)
            }
            healthStore.execute(query)
        }
    }

    /// Obtener frecuencia cardíaca promedio para un rango de fechas (backfill, sin HKWorkout en memoria)
    func fetchAverageHeartRate(from startDate: Date, to endDate: Date) async -> Double? {
        guard isAvailable, isAuthorized, let healthStore else { return nil }

        let heartRateType = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate, end: endDate, options: .strictStartDate
        )

        return await withCheckedContinuation { continuation in
            let resumer = OnceResumer(continuation, default: nil as Double?)
            Task { try? await Task.sleep(for: .seconds(5)); resumer.finish(nil) }

            let query = HKStatisticsQuery(
                quantityType: heartRateType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, _ in
                let avg = statistics?.averageQuantity()?
                    .doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                resumer.finish(avg)
            }
            healthStore.execute(query)
        }
    }
}
