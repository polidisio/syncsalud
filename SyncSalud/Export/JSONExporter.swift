import Foundation
import SwiftData
import UniformTypeIdentifiers

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

    // MARK: - Export

    /// Exporta todos los workouts a un archivo JSON en el directorio de documentos
    /// - Returns: URL del archivo exportado, nil si falla
    func exportToJSON() -> URL? {
        guard let records = try? modelContext.fetch(FetchDescriptor<WorkoutRecord>()) else {
            lastExportError = "No se pudieron leer los datos"
            return nil
        }

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

        let summary: [String: Any] = [
            "totalWorkouts": records.count,
            "totalCalories": records.compactMap(\.calories).reduce(0, +),
            "totalDuration": records.map(\.duration).reduce(0, +),
            "totalDistance": records.compactMap(\.distance).reduce(0, +),
            "dateRange": [
                "from": fromDate,
                "to": toDate
            ]
        ]

        let exportDict: [String: Any] = [
            "exportedAt": formatter.string(from: Date()),
            "source": "SyncSalud",
            "version": "1.0",
            "workouts": workoutsArray,
            "summary": summary
        ]

        do {
            let jsonData = try JSONSerialization.data(
                withJSONObject: exportDict,
                options: [.prettyPrinted, .sortedKeys]
            )

            let fileName = "syncsalud_\(Int(Date().timeIntervalSince1970)).json"
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let fileURL = documentsPath.appendingPathComponent(fileName)

            try jsonData.write(to: fileURL, options: .atomic)

            lastExportURL = fileURL
            lastExportError = nil

            print("Exportado exitosamente a: \(fileURL.path)")
            return fileURL
        } catch {
            lastExportError = "Error al exportar: \(error.localizedDescription)"
            print(lastExportError ?? "")
            return nil
        }
    }

    /// Devuelve el JSON como string (útil para previsualización)
    func exportToJSONString() -> String? {
        guard let records = try? modelContext.fetch(FetchDescriptor<WorkoutRecord>()) else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        let dicts: [[String: Any]] = records.map { record in
            var dict: [String: Any] = [
                "id": record.id.uuidString,
                "type": record.workoutType,
                "startDate": formatter.string(from: record.startDate),
                "endDate": formatter.string(from: record.endDate),
                "duration": record.duration
            ]
            if let cal = record.calories { dict["calories"] = cal }
            if let dist = record.distance { dict["distance"] = dist }
            if let avg = record.avgHeartRate { dict["avgHeartRate"] = avg }
            return dict
        }

        guard let data = try? JSONSerialization.data(withJSONObject: dicts, options: [.prettyPrinted, .sortedKeys]) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }
}
