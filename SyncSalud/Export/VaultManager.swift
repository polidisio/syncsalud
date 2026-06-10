import Foundation
import SwiftData
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Manager del vault local de Synctrackers.
///
/// Mantiene un folder estructurado en `Application Support/Synctrackers/Vault/` con un snapshot
/// por mes (`vault-YYYY-MM.json`) más un `index.json` que actúa de manifiesto. En iOS, si el
/// usuario está logueado en iCloud, cada snapshot se espeja al container de iCloud Documents
/// (el usuario lo ve en Files.app como `iCloud Drive → Synctrackers → Vault → snapshots → …`).
///
/// Estrategia:
/// - Dual write (local + iCloud) — el local es autoritativo; si iCloud falla, reintenta 3x con backoff
/// - Idempotente: la BG task reescribe solo los meses cuyo `lastUpdatedAt` cambió
/// - Writes atómicos via `.tmp` + rename POSIX para sobrevivir crashes
/// - No usa `setUbiquitous` — escribe directo al path del ubiquity container
@Observable
final class VaultManager {
    static let shared = VaultManager()

    private let fm = FileManager.default
    private let folderName = "SyncSalud"
    private let vaultSubpath = "Vault"
    private let snapshotsSubpath = "snapshots"
    private let indexFileName = "index.json"

    private let indexFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM"
        return f
    }()

    private init() {
        _ = ensureDirectories()
    }

    // MARK: - Public paths

    /// Root local del vault (siempre presente, puede ser nil si Application Support no es escribible).
    var localVaultURL: URL? {
        guard let base = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else { return nil }
        return base.appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent(vaultSubpath, isDirectory: true)
    }

    /// Root de snapshots local.
    var localSnapshotsURL: URL? {
        localVaultURL?.appendingPathComponent(snapshotsSubpath, isDirectory: true)
    }

    /// Root del mirror iCloud (nil hasta que `resolveICloudContainerIfNeeded()` corra en background).
    var iCloudVaultURL: URL? {
        guard fm.ubiquityIdentityToken != nil else { return nil }
        guard let container = _cachedICloudContainerURL else { return nil }
        return container
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent(vaultSubpath, isDirectory: true)
    }

    var iCloudSnapshotsURL: URL? {
        iCloudVaultURL?.appendingPathComponent(snapshotsSubpath, isDirectory: true)
    }

    var isICloudMirroring: Bool { iCloudSnapshotsURL != nil }

    /// Resuelve el container iCloud una sola vez. Llamar SOLO desde contexto async/background.
    private func resolveICloudContainerIfNeeded() {
        guard _cachedICloudContainerURL == nil,
              fm.ubiquityIdentityToken != nil else { return }
        _cachedICloudContainerURL = fm.url(forUbiquityContainerIdentifier: nil)
    }

    private(set) var lastICloudError: String?
    private(set) var lastICloudSyncDate: Date?
    // BUG-004: cache resuelto en background; url(forUbiquityContainerIdentifier:) es lento
    private var _cachedICloudContainerURL: URL?

    // MARK: - Index

    private var localIndexURL: URL? {
        localVaultURL?.appendingPathComponent(indexFileName)
    }

    func loadIndex() -> VaultIndex? {
        guard let url = localIndexURL, fm.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(VaultIndex.self, from: data)
        } catch {
            print("Vault: error leyendo index: \(error)")
            return nil
        }
    }

    private func saveIndex(_ index: VaultIndex) throws {
        guard let url = localIndexURL else { throw VaultError.noLocalRoot }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(index)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Reads

    /// Devuelve la URL local del snapshot de un mes (o nil si no existe).
    func readMonth(_ yearMonth: String) -> URL? {
        guard let snapshots = localSnapshotsURL else { return nil }
        let url = snapshots.appendingPathComponent("vault-\(yearMonth).json")
        return fm.fileExists(atPath: url.path) ? url : nil
    }

    /// Devuelve las URLs locales de los meses solicitados (en orden cronológico, omitiendo los que faltan).
    func readMonthsInRange(_ months: [String]) -> [URL] {
        months.compactMap { readMonth($0) }
    }

    /// Lista los meses disponibles, ordenados.
    func availableMonths() -> [String] {
        loadIndex()?.sortedMonths ?? []
    }

    // MARK: - Reveal in Finder / Files

    /// macOS: revela el vault en Finder.
    @discardableResult
    func openInFinder() -> Bool {
        #if canImport(AppKit)
        guard let url = localVaultURL else { return false }
        _ = ensureDirectories()
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return true
        #else
        return false
        #endif
    }

    /// iOS: comparte la URL del vault para que el usuario pueda "Guardar en Archivos" o similar.
    /// Devuelve la URL para pasársela a un `ShareSheet` si el caller lo quiere hacer manualmente.
    func localVaultURLForSharing() -> URL? {
        guard let url = localVaultURL else { return nil }
        _ = ensureDirectories()
        return url
    }

    // MARK: - Refresh

    /// Resultado de un refresh, útil para logging/UI.
    struct VaultRefreshResult {
        var monthsWritten: [String]
        var monthsSkipped: [String]
        var totalMonths: Int
        var iCloudMirrored: Bool
        var writtenURLs: [URL]
    }

    /// Recorre todos los meses con datos y reescribe solo los que cambiaron.
    /// Llamar desde foreground o desde la BG task.
    @discardableResult
    func refreshAll(modelContext: ModelContext) async throws -> VaultRefreshResult {
        resolveICloudContainerIfNeeded()
        _ = ensureDirectories()

        // 1. Bounds: mes más antiguo con datos → mes actual.
        let bounds = try computeMonthBounds(modelContext: modelContext)
        guard let (fromYearMonth, toYearMonth) = bounds else {
            // No hay datos. Escribir index vacío igualmente.
            try? saveIndex(VaultIndex(lastRefresh: Date(), months: [:]))
            return VaultRefreshResult(monthsWritten: [], monthsSkipped: [], totalMonths: 0, iCloudMirrored: isICloudMirroring, writtenURLs: [])
        }

        var index = loadIndex() ?? .empty()
        var written: [String] = []
        var skipped: [String] = []
        var writtenURLs: [URL] = []

        // 2. Iterar meses en orden cronológico.
        let months = monthRange(from: fromYearMonth, to: toYearMonth)
        for ym in months {
            let (start, end) = try monthInterval(yearMonth: ym)

            // latestUpdatedAt para este mes
            let descriptor = FetchDescriptor<WorkoutRecord>(
                predicate: #Predicate { $0.startDate >= start && $0.startDate < end },
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
            let records = (try? modelContext.fetch(descriptor)) ?? []
            let latest = records.first?.updatedAt ?? .distantPast
            let count = records.count

            // ¿Necesita reescribirse?
            let prevEntry = index.months[ym]
            // BUG-006: tolerancia 1s — ISO8601 trunca fracciones de segundo
            // BUG-002: no saltar si iCloud está activo y este mes aún no se espejó
            let iCloudPending = isICloudMirroring && prevEntry?.iCloudSyncedAt == nil
            if let prev = prevEntry,
               abs(prev.lastUpdatedAt.timeIntervalSince(latest)) < 1,
               count == prev.workoutCount,
               fm.fileExists(atPath: (readMonth(ym)?.path) ?? ""),
               !iCloudPending {
                skipped.append(ym)
                continue
            }

            // Reescribir
            guard let jsonData = buildMonthJSON(month: ym, records: records) else {
                print("Vault: no se pudo serializar mes \(ym)")
                continue
            }

            do {
                let iCloudSynced = try await writeSnapshot(yearMonth: ym, data: jsonData)
                let size = jsonData.count
                let range: VaultRecordRange
                if let first = records.map(\.startDate).min(), let last = records.map(\.startDate).max() {
                    range = VaultRecordRange(from: first, to: last)
                } else {
                    range = VaultRecordRange(from: start, to: end)
                }
                let syncedAt = iCloudSynced ? Date() : prevEntry?.iCloudSyncedAt
                index.months[ym] = VaultMonth(workoutCount: count, byteSize: size, lastUpdatedAt: latest, recordRange: range, iCloudSyncedAt: syncedAt)
                written.append(ym)
                if let url = readMonth(ym) { writtenURLs.append(url) }
            } catch {
                print("Vault: error escribiendo mes \(ym): \(error)")
            }
        }

        // 3. Reescribir index.
        index.lastRefresh = Date()
        try? saveIndex(index)

        return VaultRefreshResult(monthsWritten: written, monthsSkipped: skipped, totalMonths: months.count, iCloudMirrored: isICloudMirroring, writtenURLs: writtenURLs)
    }

    /// Fuerza la reescritura de un mes puntual. Devuelve la URL local del snapshot resultante.
    @discardableResult
    func refreshMonth(_ yearMonth: String, modelContext: ModelContext) async throws -> URL? {
        resolveICloudContainerIfNeeded()
        _ = ensureDirectories()
        let (start, end) = try monthInterval(yearMonth: yearMonth)
        let descriptor = FetchDescriptor<WorkoutRecord>(
            predicate: #Predicate { $0.startDate >= start && $0.startDate < end },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let records = (try? modelContext.fetch(descriptor)) ?? []
        guard let jsonData = buildMonthJSON(month: yearMonth, records: records) else { return nil }
        let iCloudSynced = try await writeSnapshot(yearMonth: yearMonth, data: jsonData)

        var index = loadIndex() ?? .empty()
        let latest = records.map(\.updatedAt).max() ?? .distantPast
        let range: VaultRecordRange
        if let first = records.map(\.startDate).min(), let last = records.map(\.startDate).max() {
            range = VaultRecordRange(from: first, to: last)
        } else {
            range = VaultRecordRange(from: start, to: end)
        }
        let prevSyncedAt = index.months[yearMonth]?.iCloudSyncedAt
        index.months[yearMonth] = VaultMonth(workoutCount: records.count, byteSize: jsonData.count, lastUpdatedAt: latest, recordRange: range, iCloudSyncedAt: iCloudSynced ? Date() : prevSyncedAt)
        index.lastRefresh = Date()
        try? saveIndex(index)

        return readMonth(yearMonth)
    }

    // MARK: - Background container helper

    /// Crea un ModelContainer independiente — útil para BG tasks que no pueden usar el del app foreground.
    static func makeBackgroundContainer() throws -> (container: ModelContainer, context: ModelContext) {
        let schema = Schema([WorkoutRecord.self, WorkoutMetric.self, SyncLog.self])
        let config = ModelConfiguration(
            cloudKitDatabase: .private("iCloud.com.saraiba.synctrackers")
        )
        let container = try ModelContainer(for: schema, configurations: config)
        let context = ModelContext(container)
        return (container, context)
    }

    // MARK: - Private

    private func buildMonthJSON(month: String, records: [WorkoutRecord]) -> Data? {
        return JSONExporter.buildJSONData(records: records, summaryOnly: false, month: month)
    }

    // BUG-001/007: usa writeWithCoordinator para coordinar con bird; retorna éxito iCloud (BUG-002)
    private func writeSnapshot(yearMonth: String, data: Data) async throws -> Bool {
        guard let localSnapshots = localSnapshotsURL else { throw VaultError.noLocalRoot }
        let finalURL = localSnapshots.appendingPathComponent("vault-\(yearMonth).json")
        try writeWithCoordinator(data: data, to: finalURL)

        guard let iCloudSnapshots = iCloudSnapshotsURL else { return false }
        return await writeICloudWithRetry(data: data, yearMonth: yearMonth, to: iCloudSnapshots)
    }

    private func writeICloudWithRetry(data: Data, yearMonth: String, to iCloudSnapshots: URL) async -> Bool {
        let finalURL = iCloudSnapshots.appendingPathComponent("vault-\(yearMonth).json")

        for attempt in 0..<3 {
            do {
                // BUG-001: NSFileCoordinator coordina con bird; BUG-007: tmp fuera del container
                try writeWithCoordinator(data: data, to: finalURL)
                lastICloudError = nil
                lastICloudSyncDate = Date()
                return true
            } catch {
                if attempt < 2 {
                    let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                    try? await Task.sleep(nanoseconds: delay)
                } else {
                    lastICloudError = error.localizedDescription
                    print("Vault: mirror iCloud falló para \(yearMonth) tras 3 intentos: \(error.localizedDescription)")
                }
            }
        }
        return false
    }

    /// Escribe `data` a `finalURL` usando NSFileCoordinator para coordinar con iCloud (bird).
    /// El archivo temporal se crea en `temporaryDirectory`, fuera del ubiquity container (BUG-007).
    private func writeWithCoordinator(data: Data, to finalURL: URL) throws {
        let tmpURL = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json.tmp")
        var coordinatorError: NSError?
        var accessorError: Error?

        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(writingItemAt: finalURL, options: .forReplacing, error: &coordinatorError) { coordURL in
            do {
                try data.write(to: tmpURL, options: .atomic)
                if fm.fileExists(atPath: coordURL.path) {
                    _ = try fm.replaceItemAt(coordURL, withItemAt: tmpURL)
                } else {
                    try fm.createDirectory(at: coordURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.moveItem(at: tmpURL, to: coordURL)
                }
            } catch {
                accessorError = error
            }
            try? fm.removeItem(at: tmpURL)
        }

        if let err = coordinatorError { throw err }
        if let err = accessorError { throw err }
    }

    private func ensureDirectories() -> Bool {
        var ok = true
        if let local = localSnapshotsURL {
            do {
                try fm.createDirectory(at: local, withIntermediateDirectories: true)
                // Excluir el root local del iCloud backup
                if let root = localVaultURL {
                    var resource = URLResourceValues()
                    resource.isExcludedFromBackup = true
                    var mutableRoot = root
                    try? mutableRoot.setResourceValues(resource)
                }
            } catch {
                print("Vault: error creando dir local: \(error)")
                ok = false
            }
        }
        if let iCloud = iCloudSnapshotsURL {
            do {
                try fm.createDirectory(at: iCloud, withIntermediateDirectories: true)
            } catch {
                print("Vault: error creando dir iCloud: \(error)")
                // No fatal — local es autoritativo
            }
        }
        // Limpiar .tmp huérfanos
        cleanupTempFiles()
        return ok
    }

    private func cleanupTempFiles() {
        for dir in [localSnapshotsURL, iCloudSnapshotsURL].compactMap({ $0 }) {
            guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for url in entries where url.lastPathComponent.hasSuffix(".json.tmp") {
                try? fm.removeItem(at: url)
            }
        }
    }

    /// Calcula el rango (from, to) de meses con datos, en formato "YYYY-MM".
    /// Devuelve nil si no hay workouts.
    private func computeMonthBounds(modelContext: ModelContext) throws -> (from: String, to: String)? {
        var descriptor = FetchDescriptor<WorkoutRecord>(
            sortBy: [SortDescriptor(\.startDate, order: .forward)]
        )
        descriptor.fetchLimit = 1
        guard let first = (try? modelContext.fetch(descriptor))?.first?.startDate else {
            return nil
        }
        let now = Date()
        return (indexFormatter.string(from: first), indexFormatter.string(from: now))
    }

    private func monthRange(from: String, to: String) -> [String] {
        var result: [String] = []
        guard let fromDate = indexFormatter.date(from: from),
              let toDate = indexFormatter.date(from: to) else { return [from, to] }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "GMT")!
        var current = fromDate
        while current <= toDate {
            result.append(indexFormatter.string(from: current))
            guard let next = cal.date(byAdding: .month, value: 1, to: current) else { break }
            current = next
        }
        return result
    }

    private func monthInterval(yearMonth: String) throws -> (start: Date, to: Date) {
        guard let monthStart = indexFormatter.date(from: yearMonth) else {
            throw VaultError.badMonthString(yearMonth)
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "GMT")!
        guard let next = cal.date(byAdding: .month, value: 1, to: monthStart) else {
            throw VaultError.badMonthString(yearMonth)
        }
        return (monthStart, next)
    }

    enum VaultError: Error, LocalizedError {
        case noLocalRoot
        case badMonthString(String)

        var errorDescription: String? {
            switch self {
            case .noLocalRoot: return "Vault: no se pudo obtener Application Support"
            case .badMonthString(let s): return "Vault: mes inválido '\(s)'"
            }
        }
    }
}
