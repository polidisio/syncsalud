
import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

@main
struct SynctrackersApp: App {
    @State private var healthService = HealthKitService()
    @State private var syncManager = HealthSyncManager()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    let container: ModelContainer

    #if os(iOS)
    @UIApplicationDelegateAdaptor(SyncAppDelegate.self) var appDelegate
    #endif

    init() {
        do {
            let schema = Schema([
                WorkoutRecord.self,
                WorkoutMetric.self,
                SyncLog.self
            ])

            // CloudKit: sync automático entre iPhone y Mac via iCloud
            let configuration = ModelConfiguration(
                cloudKitDatabase: .private("iCloud.com.saraiba.synctrackers")
            )

            container = try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("No se pudo inicializar ModelContainer: \(error)")
        }
    }

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
