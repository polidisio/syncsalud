import Foundation

/// Manifiesto del vault local: lista de meses disponibles con metadatos mínimos.
/// Permite decidir qué meses hay que reescribir sin re-leer cada JSON completo.
struct VaultIndex: Codable {
    var schemaVersion: Int
    var lastRefresh: Date
    var months: [String: VaultMonth]   // "YYYY-MM" -> entry

    init(schemaVersion: Int = 1, lastRefresh: Date = .distantPast, months: [String: VaultMonth] = [:]) {
        self.schemaVersion = schemaVersion
        self.lastRefresh = lastRefresh
        self.months = months
    }

    static func empty() -> VaultIndex {
        VaultIndex(schemaVersion: 1, lastRefresh: .distantPast, months: [:])
    }

    /// Meses ordenados cronológicamente.
    var sortedMonths: [String] {
        months.keys.sorted()
    }
}

/// Metadatos de un mes dentro del vault.
struct VaultMonth: Codable {
    var workoutCount: Int
    var byteSize: Int
    var lastUpdatedAt: Date
    var recordRange: VaultRecordRange
}

/// Rango de fechas cubierto por un snapshot mensual.
struct VaultRecordRange: Codable {
    var from: Date
    var to: Date
}
