import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(HealthKitService.self) private var healthService
    @Environment(HealthSyncManager.self) private var syncManager
    @Environment(\.modelContext) private var modelContext

    @State private var backgroundSyncEnabled: Bool = BackgroundSyncManager.shared.isBackgroundSyncEnabled
    @State private var syncIntervalHours: Double = BackgroundSyncManager.shared.minimumSyncInterval / 3600
    @State private var showExportSuccess: Bool = false
    @State private var exportError: String?
    @State private var showAPIError: Bool = false

    @State private var isAuthorizing = false

    @ViewBuilder
    private var healthStatusView: some View {
        switch healthService.authorizationState {
        case .authorized:
            Label("Conectado", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .notRequested:
            Button("Conectar") {
                isAuthorizing = true
                Task {
                    await healthService.requestAuthorization()
                    isAuthorizing = false
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isAuthorizing)
            .overlay {
                if isAuthorizing {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
        case .denied:
            HStack {
                Label("Sin acceso", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                #if os(iOS)
                Button("Abrir Ajustes") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                #endif
            }
        case .notAvailable:
            Label("No disponible en este dispositivo", systemImage: "minus.circle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
        case .error(let msg):
            VStack(alignment: .trailing) {
                Label("Error", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text(msg)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - HealthKit
                Section {
                    HStack {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.red)
                        Text("HealthKit")
                        Spacer()
                        healthStatusView
                    }

                    if !healthService.isAvailable {
                        Label("HealthKit no está disponible en este dispositivo (no funciona en simulador ni en la mayoría de Macs).", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    if let error = healthService.lastError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Permisos")
                }

                // MARK: - Sincronización
                Section {
                    Button {
                        Task { await syncManager.syncFromHealthKit() }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Sincronizar ahora")
                            Spacer()
                            if syncManager.isSyncing {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(syncManager.isSyncing)

                    if let last = syncManager.lastSyncDate {
                        HStack {
                            Text("Último sync")
                            Spacer()
                            Text(last, style: .relative)
                                .foregroundStyle(.secondary)
                        }
                    }

                    #if os(iOS)
                    Toggle("Sincronización en background", isOn: $backgroundSyncEnabled)
                        .onChange(of: backgroundSyncEnabled) { _, newValue in
                            BackgroundSyncManager.shared.isBackgroundSyncEnabled = newValue
                        }

                    if backgroundSyncEnabled {
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Intervalo")
                                Spacer()
                                Text("\(Int(syncIntervalHours))h")
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $syncIntervalHours, in: 1...24, step: 1)
                                .onChange(of: syncIntervalHours) { _, newValue in
                                    BackgroundSyncManager.shared.minimumSyncInterval = newValue * 3600
                                }
                        }
                    }
                    #endif
                } header: {
                    Text("Sincronización")
                }

                // MARK: - Exportación
                Section {
                    Button {
                        exportJSON()
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Exportar todos los datos a JSON")
                        }
                    }

                    Text("El archivo se guarda en Documents/ y podés compartirlo desde la app Archivos.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Exportar")
                }

                // MARK: - API Local (macOS)
                #if os(macOS)
                Section {
                    HStack {
                        Image(systemName: "network")
                        Text("API Local")
                        Spacer()
                        Circle()
                            .fill(LocalAPIServer.shared.isRunning ? Color.green : Color.red)
                            .frame(width: 10, height: 10)
                    }

                    if LocalAPIServer.shared.isRunning {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Tu agente puede consultar:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("• GET http://127.0.0.1:8080/v1/workouts")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("• GET http://127.0.0.1:8080/v1/workouts/latest")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("• GET http://127.0.0.1:8080/v1/summary")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("• GET http://127.0.0.1:8080/v1/export")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Button("Iniciar API local") {
                            LocalAPIServer.shared.configure(with: modelContext)
                            LocalAPIServer.shared.start()
                        }
                    }

                    if let error = LocalAPIServer.shared.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("API para Agentes")
                }
                #endif

                // MARK: - Información
                Section {
                    HStack {
                        Text("Versión")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Modelo de datos")
                        Spacer()
                        Text("SwiftData + CloudKit")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                } header: {
                    Text("Acerca de")
                }
            }
            .navigationTitle("Ajustes")
            .alert("Exportación exitosa", isPresented: $showExportSuccess) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Archivo guardado en Documents/")
            }
            .alert("Error de exportación", isPresented: .constant(exportError != nil)) {
                Button("OK", role: .cancel) { exportError = nil }
            } message: {
                if let error = exportError {
                    Text(error)
                }
            }
        }
    }

    private func exportJSON() {
        let exporter = JSONExporter(context: modelContext)
        if let url = exporter.exportToJSON() {
            print("Exportado a: \(url)")
            showExportSuccess = true
        } else {
            exportError = exporter.lastExportError ?? "Error desconocido"
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [WorkoutRecord.self], inMemory: true)
        .environment(HealthKitService())
        .environment(HealthSyncManager())
}
