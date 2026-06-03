import Foundation
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
        scheduleBackgroundSync()

        let operation = Task {
            do {
                let syncManager = HealthSyncManager()
                await syncManager.syncFromHealthKit()

                if let error = syncManager.lastError {
                    throw SyncError.syncFailed(error)
                }

                task.setTaskCompleted(success: true)
            } catch {
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

        // Ejecutar el export
        let operation = Task {
            if let url = JSONExporterDirect.performBackgroundExport() {
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

/// Wrapper estático para acceder a UserDefaults desde el AppDelegate
/// (que no tiene acceso al ModelContext)
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

    /// Esta función hace un export "best effort" sin ModelContext.
    /// Devuelve la URL del último export si existe.
    static func performBackgroundExport() -> URL? {
        // Sin ModelContext no podemos acceder a los datos aquí.
        // El export real lo hace el usuario desde la app abierta.
        // Esta función queda como hook para futuras versiones.
        return nil
    }
}
#endif

