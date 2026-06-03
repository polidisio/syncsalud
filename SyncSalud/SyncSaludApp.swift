
import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

@main
struct SyncSaludApp: App {
    @State private var healthService = HealthKitService()
    @State private var syncManager = HealthSyncManager()

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
                cloudKitDatabase: .private("iCloud.com.saraiba.syncsalud.app")
            )

            container = try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("No se pudo inicializar ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(container)
                .environment(healthService)
                .environment(syncManager)
                .onAppear {
                    setupApp()
                }
        }
        #if os(macOS)
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        #endif
    }

    private func setupApp() {
        Task {
            // 1. Pedir autorización HealthKit
            await healthService.requestAuthorization()

            // 2. Sincronizar al abrir (con throttle interno, no se hace más de 1 vez cada 5 min)
            if healthService.isAuthorized {
                await syncManager.syncFromHealthKit()
            }

            // 3. Iniciar API local solo en macOS
            #if os(macOS)
            LocalAPIServer.shared.start()
            #endif

            // 4. Configurar export automático a iCloud Drive si está habilitado (iOS)
            #if os(iOS)
            await setupScheduledExportIfNeeded()
            #endif
        }
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
