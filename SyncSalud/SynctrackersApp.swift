
import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

/// Container SwiftData único compartido por la app y las background tasks.
/// NSPersistentCloudKitContainer debe ser singleton por store — crear un segundo
/// container sobre el mismo store CloudKit causa crash.
enum AppModelContainer {
    static let shared: ModelContainer = {
        let schema = Schema([
            WorkoutRecord.self,
            WorkoutMetric.self,
            SyncLog.self
        ])

        let cloudConfig = ModelConfiguration(
            cloudKitDatabase: .private("iCloud.com.saraiba.synctrackers")
        )

        if let cloudContainer = try? ModelContainer(for: schema, configurations: cloudConfig) {
            return cloudContainer
        }

        // Fallback: local sin CloudKit (iCloud no disponible o entitlement mismatch)
        let localConfig = ModelConfiguration(isStoredInMemoryOnly: false)
        guard let localContainer = try? ModelContainer(for: schema, configurations: localConfig) else {
            fatalError("SwiftData no puede inicializarse ni localmente")
        }
        return localContainer
    }()
}

@main
struct SynctrackersApp: App {
    @State private var healthService = HealthKitService()
    @State private var syncManager = HealthSyncManager()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    let container: ModelContainer = AppModelContainer.shared

    #if os(iOS)
    @UIApplicationDelegateAdaptor(SyncAppDelegate.self) var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    ContentView()
                        .onAppear { setupApp() }
                } else {
                    OnboardingView()
                        .onAppear { setupAPIOnly() }
                }
            }
                .modelContainer(container)
                .environment(healthService)
                .environment(syncManager)
        }
        #if os(macOS)
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        #endif
    }

    /// Setup completo (HealthKit auth + sync) — solo tras onboarding
    private func setupApp() {
        Task {
            await healthService.requestAuthorization()

            if healthService.isAuthorized {
                await syncManager.syncFromHealthKit()
            }

            #if os(macOS)
            LocalAPIServer.shared.start()
            #endif

            #if os(iOS)
            await setupScheduledExportIfNeeded()
            #endif
        }
    }

    /// Setup mínimo durante onboarding — solo API local (macOS)
    private func setupAPIOnly() {
        #if os(macOS)
        LocalAPIServer.shared.start()
        #endif
    }

    #if os(iOS)
    @MainActor
    private func setupScheduledExportIfNeeded() async {
        // El ModelContext se obtiene a través de syncManager que ya lo tiene
        // (necesitamos una referencia directa al contexto aquí)
        // Por ahora el export se programa desde SettingsView cuando el usuario lo activa
        // Esta función queda como hook futuro
    }
    #endif
}
