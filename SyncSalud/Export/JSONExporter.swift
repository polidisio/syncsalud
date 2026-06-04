import Foundation
import SwiftData
import UniformTypeIdentifiers
#if os(iOS)
import BackgroundTasks
import UIKit
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

    /// Exporta workouts filtrados a un archivo JSON en el directorio de documentos
    /// - Parameters:
    ///   - fromDate: fecha inicial del filtro (nil = sin límite inferior)
    ///   - toDate: fecha final del filtro (nil = sin límite superior)
    ///   - workoutTypes: tipos de workout a incluir (nil = todos)
    ///   - summaryOnly: si es true, solo incluye estadísticas agregadas sin detalles
    func exportFilteredJSON(from fromDate: Date? = nil, to toDate: Date? = nil, workoutTypes: [String]? = nil, summaryOnly: Bool = false) -> URL? {
        // Fetch all records and filter in memory (simpler and more reliable than complex predicates)
        guard var records = try? modelContext.fetch(FetchDescriptor<WorkoutRecord>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])) else {
            lastExportError = "No se pudieron leer los datos"
            return nil
        }

        // Apply date filters
        if let from = fromDate {
            records = records.filter { $0.startDate >= from }
        }
        if let to = toDate {
            records = records.filter { $0.startDate <= to }
        }

        // Filter by workout types if provided
        if let types = workoutTypes, !types.isEmpty {
            records = records.filter { types.contains($0.workoutType) }
        }

        guard let jsonData = buildExportJSON(records, summaryOnly: summaryOnly) else { return nil }

        do {
            let fileName = summaryOnly
                ? "syncsalud_resumen_\(Int(Date().timeIntervalSince1970)).json"
                : "syncsalud_\(Int(Date().timeIntervalSince1970)).json"
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let fileURL = documentsPath.appendingPathComponent(fileName)

            try jsonData.write(to: fileURL, options: .atomic)

            lastExportURL = fileURL
            lastExportError = nil
            print("📄 Exportado (filtrado) a: \(fileURL.path)")
            return fileURL
        } catch {
            lastExportError = "Error al exportar: \(error.localizedDescription)"
            print(lastExportError ?? "")
            return nil
        }
    }

    // MARK: - iCloud Availability Check

    /// Verifica si iCloud Drive está disponible y configurado
    var isICloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    /// Obtiene el mensaje de error detallado para iCloud
    func iCloudStatusMessage() -> String {
        if FileManager.default.ubiquityIdentityToken != nil {
            return "iCloud disponible"
        } else {
            return "iCloud Drive no está configurado. Iniciá sesión en iCloud en Ajustes → [tu nombre] → iCloud."
        }
    }

    // MARK: - Export to iCloud Drive

    /// Exporta a iCloud Drive usando ShareSheet (el flujo estándar de iOS)
    /// El usuario elige guardar en iCloud Drive via el selector de ubicación
    func exportToiCloudDrive() -> URL? {
        guard let records = try? modelContext.fetch(FetchDescriptor<WorkoutRecord>()) else {
            lastExportError = "No se pudieron leer los datos"
            return nil
        }

        guard let jsonData = buildExportJSON(records) else { return nil }

        // Verificar iCloud primero (solo token, no container)
        let manager = ICloudDocumentsManager.shared
        if !manager.isICloudDriveConfigured {
            lastExportError = "iCloud Drive no está configurado. Iniciá sesión en iCloud en Ajustes → [tu nombre] → iCloud."
            print("iCloud: \(manager.diagnosticStatus())")
            return nil
        }

        // Guardar en Documents local para poder compartir via ShareSheet
        let fileName = "syncsalud_\(Int(Date().timeIntervalSince1970)).json"
        guard let fileURL = manager.prepareFileForSharing(fileName: fileName, jsonData: jsonData) else {
            lastExportError = "Error preparando archivo para exportar"
            return nil
        }

        lastExportURL = fileURL
        lastExportError = nil
        print("📄 Exportado para compartir: \(fileURL.path)")
        return fileURL
    }

    /// Abre la carpeta SyncSalud en la app Archivos (Files)
    func openInFiles() {
        // No disponible con el enfoque ShareSheet
        print("iCloud: openInFiles no disponible con ShareSheet")
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
    /// Programa la próxima ejecución. El handler debe estar registrado previamente
    /// en el AppDelegate (ver SyncAppDelegate).
    func scheduleBackgroundExport() {
        // El handler ya está registrado en SyncAppDelegate.application(_:didFinishLaunchingWithOptions:)
        // Acá solo submiteamos la próxima ejecución
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

    private func buildExportJSON(_ records: [WorkoutRecord], summaryOnly: Bool = false, month: String? = nil) -> Data? {
        return JSONExporter.buildJSONData(records: records, summaryOnly: summaryOnly, month: month)
    }

    // MARK: - Static helper (sin ModelContext, para uso desde VaultManager y tests)

    /// Construye el JSON serializado a partir de un array de records, sin requerir un ModelContext.
    /// - Parameters:
    ///   - records: workouts a serializar
    ///   - summaryOnly: si true, omite el array `workouts` y deja solo el summary
    ///   - month: etiqueta opcional del mes (formato "YYYY-MM") para hacer el archivo self-describing
    /// - Returns: Data JSON pretty-printed con keys ordenadas, o nil si la serialización falla
    static func buildJSONData(records: [WorkoutRecord], summaryOnly: Bool = false, month: String? = nil) -> Data? {
        return JSONExporter.serializeRecords(records, summaryOnly: summaryOnly, month: month)
    }

    private static func serializeRecords(_ records: [WorkoutRecord], summaryOnly: Bool, month: String?) -> Data? {
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

        var exportDict: [String: Any] = [
            "exportedAt": formatter.string(from: Date()),
            "source": "SyncSalud",
            "version": "1.0",
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

        if let month {
            exportDict["month"] = month
        }

        if !summaryOnly {
            exportDict["workouts"] = workoutsArray
        }

        return try? JSONSerialization.data(withJSONObject: exportDict, options: [.prettyPrinted, .sortedKeys])
    }
}