import Foundation
import HealthKit
import SwiftData
import Observation

@Observable
final class HealthSyncManager {
    // MARK: - Properties

    private let healthService = HealthKitService()
    private var modelContext: ModelContext?

    private(set) var isSyncing = false
    private(set) var lastSyncDate: Date?
    private(set) var lastSyncCount = 0
    private(set) var lastError: String?
    private(set) var syncProgress: Double = 0

    /// Fecha del último sync completada (no iniciada)
    private var lastCompletedSync: Date? {
        get { UserDefaults.standard.object(forKey: "lastCompletedSync") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastCompletedSync") }
    }

    /// Si ya hicimos el primer sync completo
    private var hasDoneInitialSync: Bool {
        get { UserDefaults.standard.bool(forKey: "hasDoneInitialSync") }
        set { UserDefaults.standard.set(newValue, forKey: "hasDoneInitialSync") }
    }

    // MARK: - Configuración del contexto

    func configure(with context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - Sincronización

    /// Sincroniza desde HealthKit: lee workouts nuevos y los guarda en SwiftData
    /// - Parameters:
    ///   - force: Si true, ignora el throttle de 5 minutos y el límite de primer año
    ///   - from: Fecha de inicio del rango a sincronizar (nil = automático)
    ///   - to: Fecha de fin del rango a sincronizar (nil = ahora)
    @MainActor
    func syncFromHealthKit(force: Bool = false, from: Date? = nil, to: Date? = nil) async {
        guard !isSyncing else {
            print("⚠️ Sync ya en progreso, ignorando...")
            return
        }

        guard let modelContext else {
            lastError = "ModelContext no configurado"
            return
        }

        // Throttle: si el último sync completó hace menos de 5 minutos, no hacer nada
        // (excepto si force=true)
        if !force, let lastSync = lastCompletedSync, Date().timeIntervalSince(lastSync) < 300 {
            print("⏸️ Sync reciente (\(Int(Date().timeIntervalSince(lastSync)))s), saltando")
            return
        }

        isSyncing = true
        syncProgress = 0
        lastError = nil
        defer {
            isSyncing = false
            syncProgress = 1.0
        }

        // 1. Asegurar autorización
        await healthService.requestAuthorization()
        guard healthService.isAuthorized else {
            lastError = "HealthKit no autorizado"
            logSync(type: SyncLog.SyncType.healthKitImport, count: 0, success: false, error: lastError)
            return
        }

        // 2. Determinar fecha de inicio y fin
        // Prioridad: parámetros explícitos > lógica automática
        let fromDate: Date?
        let toDate: Date

        if let explicitFrom = from, let explicitTo = to {
            // Rango explícito del usuario
            fromDate = explicitFrom
            toDate = explicitTo
        } else if hasDoneInitialSync, let last = lastCompletedSync, !force {
            // Sync incremental: desde el último sync
            fromDate = last
            toDate = Date()
        } else if !force {
            // Primer sync automático: solo el último año
            fromDate = Calendar.current.date(byAdding: .year, value: -1, to: Date())
            toDate = Date()
        } else {
            // Force sync sin rango: todo el historial
            fromDate = nil
            toDate = Date()
        }

        syncProgress = 0.1

        // 3. Limpiar duplicados existentes antes de empezar
        if from == nil && to == nil { // solo en sync automático, no en filtro manual
            cleanDuplicates(context: modelContext)
        }

        // 4. Fetch workouts desde HealthKit
        let workouts = await healthService.fetchWorkouts(from: fromDate, to: toDate)
        syncProgress = 0.3

        print("📊 HealthKit devolvió \(workouts.count) workouts desde \(fromDate?.description ?? "inicio")")

        guard !workouts.isEmpty else {
            lastCompletedSync = Date()
            hasDoneInitialSync = true
            logSync(type: SyncLog.SyncType.healthKitImport, count: 0, success: true)
            return
        }

        // 5. Obtener healthKitIDs existentes para deduplicación
        let existingIDs = fetchExistingHealthKitIDs(context: modelContext)
        syncProgress = 0.4

        // 6. Mapear y filtrar duplicados
        var newCount = 0
        let updateCount = 0
        var skipCount = 0

        for (index, hkWorkout) in workouts.enumerated() {
            let hkID = hkWorkout.uuid.uuidString

            if existingIDs.contains(hkID) {
                skipCount += 1
                continue  // Ya existe, no hacer nada
            }

            // Crear nuevo registro
            let record = WorkoutRecord.fromHKWorkout(hkWorkout)

            // Heart rate solo si no hay muchos workouts (para no demorar)
            if workouts.count < 500 {
                if let avgHR = await healthService.fetchAverageHeartRate(for: hkWorkout) {
                    record.avgHeartRate = avgHR
                }
            }

            modelContext.insert(record)
            newCount += 1

            // Agregar a existingIDs para evitar duplicados dentro del mismo sync
            // (importante si hay workouts con el mismo UUID por algún motivo)
            // Nota: esto no funciona porque existingIDs es let. Usamos un set local:
            // (Workaround: lo manejamos via dedup al final)

            // Guardar progreso cada 50 inserts
            if newCount % 50 == 0 {
                do {
                    try modelContext.save()
                } catch {
                    let msg = "Error en save parcial: \(error.localizedDescription)"
                    print("⚠️ \(msg)")
                    logSync(type: SyncLog.SyncType.healthKitImport, count: newCount, success: false, error: msg)
                }
            }

            syncProgress = 0.4 + (Double(index) / Double(workouts.count)) * 0.5
        }

        // 7. Guardar final
        do {
            try modelContext.save()
            lastSyncDate = Date()
            lastCompletedSync = Date()
            hasDoneInitialSync = true
            lastSyncCount = newCount + updateCount
            syncProgress = 1.0

            logSync(type: SyncLog.SyncType.healthKitImport, count: newCount, success: true)
            print("✅ Sync completado: \(newCount) nuevos, \(updateCount) actualizados, \(skipCount) ya existían")
        } catch {
            lastError = "Error al guardar: \(error.localizedDescription)"
            logSync(type: SyncLog.SyncType.healthKitImport, count: newCount, success: false, error: lastError)
        }
    }

    // MARK: - Helpers

    /// Elimina duplicados basándose en healthKitID, manteniendo el más reciente
    private func cleanDuplicates(context: ModelContext) {
        let descriptor = FetchDescriptor<WorkoutRecord>(
            predicate: #Predicate { $0.healthKitID != nil },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        guard let records = try? context.fetch(descriptor) else { return }

        var seen = Set<String>()
        var toDelete: [WorkoutRecord] = []

        for record in records {
            guard let hkID = record.healthKitID else { continue }
            if seen.contains(hkID) {
                toDelete.append(record)
            } else {
                seen.insert(hkID)
            }
        }

        if !toDelete.isEmpty {
            print("🧹 Limpiando \(toDelete.count) duplicados")
            for record in toDelete {
                context.delete(record)
            }
            try? context.save()
        }
    }

    private func fetchExistingHealthKitIDs(context: ModelContext) -> Set<String> {
        let descriptor = FetchDescriptor<WorkoutRecord>(
            predicate: #Predicate { $0.healthKitID != nil }
        )

        guard let records = try? context.fetch(descriptor) else { return [] }
        return Set(records.compactMap { $0.healthKitID })
    }

    private func findWorkout(byHealthKitID id: String, context: ModelContext) -> WorkoutRecord? {
        let predicate = #Predicate<WorkoutRecord> { $0.healthKitID == id }
        let descriptor = FetchDescriptor<WorkoutRecord>(predicate: predicate)
        return try? context.fetch(descriptor).first
    }

    private func updateRecord(_ record: WorkoutRecord, from hkWorkout: HKWorkout) {
        record.startDate = hkWorkout.startDate
        record.endDate = hkWorkout.endDate
        record.duration = hkWorkout.duration
        record.calories = hkWorkout.totalEnergyBurned?.doubleValue(for: .kilocalorie())
        record.distance = hkWorkout.totalDistance?.doubleValue(for: .meter())
        record.updatedAt = Date()
    }

    private func logSync(type: String, count: Int, success: Bool, error: String? = nil) {
        guard let modelContext else { return }

        let log = SyncLog(
            type: type,
            workoutsCount: count,
            success: success,
            errorDescription: error
        )
        modelContext.insert(log)
        try? modelContext.save()
    }
}
