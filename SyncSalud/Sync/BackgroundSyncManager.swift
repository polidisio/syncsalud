import Foundation
import SwiftData
#if os(iOS)
import BackgroundTasks
import UIKit
#endif

/// Gestiona la sincronización programada en background (solo iOS)
/// En macOS se provee un stub para que el código compile.
final class BackgroundSyncManager {
    static let shared = BackgroundSyncManager()

    #if os(iOS)
    private let backgroundTaskID = "com.syncsalud.sync"
    #endif

    /// Intervalo mínimo entre sincronizaciones en background (en segundos)
    /// Default: 6 horas
    var minimumSyncInterval: TimeInterval {
        get {
            let saved = UserDefaults.standard.double(forKey: "backgroundSyncInterval")
            return saved > 0 ? saved : 6 * 3600
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "backgroundSyncInterval")
            #if os(iOS)
            registerBackgroundTask()
            #endif
        }
    }

    /// Si la sincronización en background está habilitada
    var isBackgroundSyncEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "backgroundSyncEnabled") }
        set {
            UserDefaults.standard.set(newValue, forKey: "backgroundSyncEnabled")
            #if os(iOS)
            if newValue {
                registerBackgroundTask()
            } else {
                cancelBackgroundTask()
            }
            #endif
        }
    }

    // MARK: - Setup (solo iOS)

    #if os(iOS)
    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundTaskID, using: nil) { task in
            self.handleBackgroundTask(task as! BGProcessingTask)
        }
    }

    func scheduleBackgroundSync() {
        guard isBackgroundSyncEnabled else { return }

        let request = BGProcessingTaskRequest(identifier: backgroundTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: minimumSyncInterval)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
            print("Background sync programada para: \(request.earliestBeginDate!)")
        } catch {
            print("Error al programar background sync: \(error.localizedDescription)")
        }
    }

    func cancelBackgroundTask() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: backgroundTaskID)
    }

    private func handleBackgroundTask(_ task: BGProcessingTask) {
        // Reprogramar la próxima ejecución
        scheduleBackgroundSync()

        // En background no podemos crear un HealthSyncManager fresco sin modelContext.
        // Solo marcamos que la app debería sincronizar al próximo abrir.
        // El sync real ocurre al abrir la app por setupApp() en SyncSaludApp.

        // Hacer un sync "best effort" si hay datos en disco
        let operation = Task {
            do {
                // Intentar un sync rápido sin acceso a UI
                let success = await BackgroundSyncHelper.performQuickSync()
                task.setTaskCompleted(success: success)
            } catch {
                print("⚠️ Background sync falló: \(error.localizedDescription)")
                task.setTaskCompleted(success: false)
            }
        }

        task.expirationHandler = {
            operation.cancel()
        }
    }
    #else
    // Stubs para macOS — no hay background tasks
    func registerBackgroundTask() {}
    func scheduleBackgroundSync() {}
    func cancelBackgroundTask() {}
    #endif
}

enum SyncError: Error {
    case syncFailed(String)
    case healthKitNotAuthorized

    var localizedDescription: String {
        switch self {
        case .syncFailed(let msg): return "Sync falló: \(msg)"
        case .healthKitNotAuthorized: return "HealthKit no autorizado"
        }
    }
}

// MARK: - Background Sync Helper

/// Helper que ejecuta un sync "best effort" desde background.
/// Accede a la base de datos SwiftData local sin pasar por UI.
enum BackgroundSyncHelper {
    /// Realiza un sync rápido sin interacción de UI.
    /// - Returns: true si el sync fue exitoso
    static func performQuickSync() async -> Bool {
        // En background, no podemos pedir permisos de HealthKit ni mostrar UI
        // Solo verificamos que ya estén autorizados y leemos los nuevos workouts
        guard HealthKitService.isAvailableStatic else {
            print("⏸️ Background sync: HealthKit no disponible")
            return false
        }

        // Crear un container SwiftData independiente (background)
        do {
            let schema = Schema([WorkoutRecord.self, WorkoutMetric.self, SyncLog.self])
            let config = ModelConfiguration(
                cloudKitDatabase: .private("iCloud.com.saraiba.syncsalud.app")
            )
            let container = try ModelContainer(for: schema, configurations: config)
            let context = ModelContext(container)

            let syncManager = HealthSyncManager()
            syncManager.configure(with: context)
            await syncManager.syncFromHealthKit(force: false)

            if let error = syncManager.lastError {
                print("⚠️ Background sync error: \(error)")
                return false
            }

            print("✅ Background sync completado: \(syncManager.lastSyncCount) workouts")
            return true
        } catch {
            print("❌ Background sync: error al crear container: \(error.localizedDescription)")
            return false
        }
    }
}

// MARK: - AppDelegate (solo iOS)

#if os(iOS)
class SyncAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Registrar handlers UNA SOLA VEZ al iniciar la app
        BackgroundSyncManager.shared.registerBackgroundTask()

        // El handler del export también se registra acá
        registerExportHandler()

        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        BackgroundSyncManager.shared.scheduleBackgroundSync()
    }

    private func registerExportHandler() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.syncsalud.export", using: nil) { task in
            self.handleExportTask(task as! BGProcessingTask)
        }
    }

    private func handleExportTask(_ task: BGProcessingTask) {
        // Reprogramar la próxima ejecución
        if JSONExporterDirect.isScheduledExportEnabled {
            JSONExporterDirect.scheduleBackgroundExport()
        }

        // Ejecutar el export real en background
        let operation = Task {
            let url = await JSONExporterDirect.performBackgroundExport()
            if let url {
                print("📤 Export background completado: \(url.lastPathComponent)")
                task.setTaskCompleted(success: true)
            } else {
                print("⚠️ Export background falló")
                task.setTaskCompleted(success: false)
            }
        }

        task.expirationHandler = {
            operation.cancel()
        }
    }
}

/// Wrapper estático para el export en background desde el AppDelegate.
/// Crea su propio ModelContainer — mismo patrón que BackgroundSyncHelper.
enum JSONExporterDirect {
    static var isScheduledExportEnabled: Bool {
        UserDefaults.standard.bool(forKey: "scheduledExportEnabled")
    }

    static func scheduleBackgroundExport() {
        guard isScheduledExportEnabled else { return }

        let saved = UserDefaults.standard.double(forKey: "exportInterval")
        let interval = saved > 0 ? saved : 6 * 3600

        let request = BGProcessingTaskRequest(identifier: "com.syncsalud.export")
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
            print("📅 Export programado para: \(request.earliestBeginDate!)")
        } catch {
            print("⚠️ Error al programar export: \(error.localizedDescription)")
        }
    }

    /// Crea un ModelContainer propio y exporta a iCloud Drive.
    static func performBackgroundExport() async -> URL? {
        do {
            let schema = Schema([WorkoutRecord.self, WorkoutMetric.self, SyncLog.self])
            let config = ModelConfiguration(
                cloudKitDatabase: .private("iCloud.com.saraiba.syncsalud.app")
            )
            let container = try ModelContainer(for: schema, configurations: config)
            let context = ModelContext(container)

            let folderName = UserDefaults.standard.string(forKey: "iCloudFolderName") ?? "SyncSalud"
            let exporter = JSONExporter(context: context)
            return await exporter.exportToiCloudDrive(folderName: folderName)
        } catch {
            print("❌ Background export: error al crear container: \(error.localizedDescription)")
            return nil
        }
    }
}
#endif

