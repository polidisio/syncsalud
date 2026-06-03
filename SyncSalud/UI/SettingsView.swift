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

    // Date range filter for sync
    @State private var dateFilterEnabled = false
    @State private var syncFromDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var syncToDate = Date()

    // Auto export
    @State private var autoExportEnabled: Bool = false
    @State private var exportIntervalHours: Double = 6

    // Share sheet
    @State private var shareItem: ShareItem?
    @State private var showShareSheet: Bool = false

    private var exporter: JSONExporter { JSONExporter(context: modelContext) }

    // MARK: - Share Sheet Types (defined here so they're visible to the State vars above)

    struct ShareItem: Identifiable {
        let id = UUID()
        let url: URL
    }

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
                    // Full sync button
                    Button {
                        Task {
                            if dateFilterEnabled {
                                await syncManager.syncFromHealthKit(force: true, from: syncFromDate, to: syncToDate)
                            } else {
                                await syncManager.syncFromHealthKit(force: true)
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text(dateFilterEnabled ? "Sincronizar rango seleccionado" : "Sincronizar ahora (todo)")
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

                    Toggle("Filtrar por rango de fechas", isOn: $dateFilterEnabled)

                    if dateFilterEnabled {
                        DatePicker(
                            "Desde",
                            selection: $syncFromDate,
                            displayedComponents: [.date]
                        )
                        .datePickerStyle(.compact)

                        DatePicker(
                            "Hasta",
                            selection: $syncToDate,
                            in: syncFromDate...Date(),
                            displayedComponents: [.date]
                        )
                        .datePickerStyle(.compact)

                        Text("Se sincronizarán solo los workouts entre las fechas seleccionadas.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                        exportAndShare()
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Exportar y compartir JSON")
                        }
                    }

                    Button {
                        exportToiCloudDrive()
                    } label: {
                        HStack {
                            Image(systemName: "icloud.and.arrow.up")
                            Text("Exportar a iCloud Drive")
                        }
                    }

                    Text("• Compartir: AirDrop, Mail, Files, etc.\n• iCloud Drive: queda disponible en todos tus dispositivos Apple")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Exportar")
                }

                // MARK: - Exportación automática (iOS)
                #if os(iOS)
                Section {
                    Toggle("Exportar automáticamente", isOn: $autoExportEnabled)
                        .onChange(of: autoExportEnabled) { _, newValue in
                            if newValue {
                                exporter.enableScheduledExport(interval: exportIntervalHours * 3600)
                            } else {
                                exporter.disableScheduledExport()
                            }
                        }

                    if autoExportEnabled {
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Intervalo")
                                Spacer()
                                Text("\(Int(exportIntervalHours))h")
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $exportIntervalHours, in: 1...24, step: 1)
                                .onChange(of: exportIntervalHours) { _, newValue in
                                    exporter.scheduledExportInterval = newValue * 3600
                                }
                        }

                        Text("El archivo se guarda automáticamente en iCloud Drive → SyncSalud/")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Exportación automática")
                }
                #endif

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
                Text("Archivo guardado correctamente")
            }
            .alert("Error de exportación", isPresented: .constant(exportError != nil)) {
                Button("OK", role: .cancel) { exportError = nil }
            } message: {
                if let error = exportError {
                    Text(error)
                }
            }
            #if os(iOS)
            .sheet(item: $shareItem) { item in
                ShareSheet(items: [item.url])
            }
            #endif
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

    private func exportAndShare() {
        if let url = exporter.exportToJSON() {
            #if os(iOS)
            shareItem = ShareItem(url: url)
            showShareSheet = true
            #else
            showExportSuccess = true
            #endif
        } else {
            exportError = exporter.lastExportError ?? "Error desconocido"
        }
    }

    private func exportToiCloudDrive() {
        if let url = exporter.exportToiCloudDrive() {
            showExportSuccess = true
            print("✅ iCloud Drive: \(url.path)")
        } else {
            exportError = exporter.lastExportError ?? "Error desconocido"
        }
    }
}

// MARK: - Share Sheet (iOS)

#if os(iOS)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

#Preview {
    SettingsView()
        .modelContainer(for: [WorkoutRecord.self], inMemory: true)
        .environment(HealthKitService())
        .environment(HealthSyncManager())
}
