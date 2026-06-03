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
        BackgroundSyncManager.shared.registerBackgroundTask()
        BackgroundSyncManager.shared.scheduleBackgroundSync()

        // Registrar export en background también
        if let exporter = sharedExporter {
            exporter.registerBackgroundExport()
            if exporter.isScheduledExportEnabled {
                exporter.scheduleBackgroundExport()
            }
        }

        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        BackgroundSyncManager.shared.scheduleBackgroundSync()
        if let exporter = sharedExporter, exporter.isScheduledExportEnabled {
            exporter.scheduleBackgroundExport()
        }
    }

    private var sharedExporter: JSONExporter? {
        // El AppDelegate no tiene acceso al ModelContext directamente
        // El JSONExporter se configura desde SettingsView
        nil
    }
}
#endif

