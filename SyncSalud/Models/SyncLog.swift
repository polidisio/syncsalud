import Foundation
import SwiftData

@Model
final class SyncLog {
    var id: UUID = UUID()

    /// Cuándo ocurrió
    var timestamp: Date = Date()

    /// Tipo de sincronización
    var type: String = ""

    /// Cantidad de workouts procesados
    var workoutsCount: Int = 0

    /// ¿Fue exitoso?
    var success: Bool = true

    /// Mensaje de error si falló
    var errorDescription: String? = nil

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        type: String,
        workoutsCount: Int = 0,
        success: Bool = true,
        errorDescription: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.workoutsCount = workoutsCount
        self.success = success
        self.errorDescription = errorDescription
    }
}

// MARK: - Tipos de sincronización

extension SyncLog {
    struct SyncType {
        static let healthKitImport = "healthkit_import"
        static let cloudKitSync = "cloudkit_sync"
        static let manualImport = "manual_import"
        static let backgroundSync = "background_sync"
        static let export = "export"
    }
}
