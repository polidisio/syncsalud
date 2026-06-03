import Foundation
import SwiftData
import UniformTypeIdentifiers
#if os(iOS)
import BackgroundTasks
#endif

/// Maneja la exportación de datos a JSON
final class JSONExporter {
    // MARK: - Properties

    private let modelContext: ModelContext

    private(set) var lastExportURL: URL?
    private(set) var lastExportError: String?

    // MARK: - Init

    init(context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - Export to Documents

    /// Exporta todos los workouts a un archivo JSON en el directorio de documentos
    func exportToJSON() -> URL? {
        guard let records = try? modelContext.fetch(FetchDescriptor<WorkoutRecord>()) else {
            lastExportError = "No se pudieron leer los datos"
            return nil
        }

        guard let jsonData = buildExportJSON(records) else { return nil }

        do {
            let fileName = "syncsalud_\(Int(Date().timeIntervalSince1970)).json"
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let fileURL = documentsPath.appendingPathComponent(fileName)

            try jsonData.write(to: fileURL, options: .atomic)

            lastExportURL = fileURL
            lastExportError = nil
            print("📄 Exportado a: \(fileURL.path)")
            return fileURL
        } catch {
            lastExportError = "Error al exportar: \(error.localizedDescription)"
            print(lastExportError ?? "")
            return nil
        }
    }

    // MARK: - Export to iCloud Drive

    /// Exporta a iCloud Drive para que esté disponible en todos tus dispositivos
    func exportToiCloudDrive() -> URL? {
        guard let records = try? modelContext.fetch(FetchDescriptor<WorkoutRecord>()) else {
            lastExportError = "No se pudieron leer los datos"
            return nil
        }

        guard let jsonData = buildExportJSON(records) else { return nil }

        // Obtener la URL de iCloud Drive
        guard let iCloudURL = FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents") else {
            lastExportError = "iCloud Drive no está configurado. Iniciá sesión en iCloud en Ajustes."
            return nil
        }

        // Crear carpeta SyncSalud en iCloud Drive
        let syncSaludFolder = iCloudURL.appendingPathComponent("SyncSalud", isDirectory: true)
        try? FileManager.default.createDirectory(at: syncSaludFolder, withIntermediateDirectories: true)

        let fileName = "syncsalud_\(Int(Date().timeIntervalSince1970)).json"
        let fileURL = syncSaludFolder.appendingPathComponent(fileName)

        do {
            try jsonData.write(to: fileURL, options: .atomic)

            lastExportURL = fileURL
            lastExportError = nil
            print("📄 Exportado a iCloud Drive: \(fileURL.path)")
            return fileURL
        } catch {
            lastExportError = "Error al exportar a iCloud Drive: \(error.localizedDescription)"
            print(lastExportError ?? "")
            return nil
        }
    }

    // MARK: - Scheduled Export (iOS background)

    /// Configura exportación automática a iCloud Drive según un intervalo
    /// - Parameter interval: Intervalo en segundos (default: 6 horas)
    func enableScheduledExport(interval: TimeInterval = 6 * 3600) {
        UserDefaults.standard.set(interval, forKey: "exportInterval")
        UserDefaults.standard.set(true, forKey: "scheduledExportEnabled")
        print("✅ Export automático habilitado (intervalo: \(Int(interval/3600))h)")
        #if os(iOS)
        // NO programar inmediatamente — esperar a que se llame a scheduleBackgroundExport()
        // desde el lugar que tiene acceso al modelContext
        #endif
    }

    func disableScheduledExport() {
        UserDefaults.standard.set(false, forKey: "scheduledExportEnabled")
        print("⏸️ Export automático deshabilitado")
        #if os(iOS)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: "com.syncsalud.export")
        #endif
    }

    var isScheduledExportEnabled: Bool {
        UserDefaults.standard.bool(forKey: "scheduledExportEnabled")
    }

    var scheduledExportInterval: TimeInterval {
        get {
            let saved = UserDefaults.standard.double(forKey: "exportInterval")
            return saved > 0 ? saved : 6 * 3600
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "exportInterval")
        }
    }

    #if os(iOS)
    /// Programa la próxima ejecución. Debe llamarse desde un lugar que tenga
    /// acceso al ModelContext para que el background task funcione.
    func scheduleBackgroundExport() {
        guard isScheduledExportEnabled else {
            print("⏸️ Export no programado: deshabilitado")
            return
        }

        let request = BGProcessingTaskRequest(identifier: "com.syncsalud.export")
        request.earliestBeginDate = Date(timeIntervalSinceNow: scheduledExportInterval)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
            print("📅 Export programado para: \(request.earliestBeginDate!)")
        } catch {
            print("⚠️ Error al programar export: \(error.localizedDescription)")
        }
    }
    #endif

    // MARK: - Helpers

    private func buildExportJSON(_ records: [WorkoutRecord]) -> Data? {
        let formatter = ISO8601DateFormatter()

        let workoutsArray: [[String: Any]] = records.map { record in
            var dict: [String: Any] = [
                "id": record.id.uuidString,
                "type": record.workoutType,
                "startDate": formatter.string(from: record.startDate),
                "endDate": formatter.string(from: record.endDate),
                "duration": record.duration,
                "source": record.source
            ]
            if let cal = record.calories { dict["calories"] = cal }
            if let dist = record.distance { dict["distance"] = dist }
            if let avg = record.avgHeartRate { dict["avgHeartRate"] = avg }
            if let max = record.maxHeartRate { dict["maxHeartRate"] = max }
            return dict
        }

        let dates = records.compactMap(\.startDate).sorted()
        let fromDate = dates.first.map { formatter.string(from: $0) } ?? ""
        let toDate = dates.last.map { formatter.string(from: $0) } ?? ""

        let exportDict: [String: Any] = [
            "exportedAt": formatter.string(from: Date()),
            "source": "SyncSalud",
            "version": "1.0",
            "workouts": workoutsArray,
            "summary": [
                "totalWorkouts": records.count,
                "totalCalories": records.compactMap(\.calories).reduce(0, +),
                "totalDuration": records.map(\.duration).reduce(0, +),
                "totalDistance": records.compactMap(\.distance).reduce(0, +),
                "dateRange": [
                    "from": fromDate,
                    "to": toDate
                ]
            ]
        ]

        return try? JSONSerialization.data(withJSONObject: exportDict, options: [.prettyPrinted, .sortedKeys])
    }
}
