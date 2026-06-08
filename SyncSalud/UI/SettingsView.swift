import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(HealthKitService.self) private var healthService
    @Environment(HealthSyncManager.self) private var syncManager
    @Environment(\.modelContext) private var modelContext

    @State private var backgroundSyncEnabled: Bool = BackgroundSyncManager.shared.isBackgroundSyncEnabled
    @State private var syncIntervalHours: Double = BackgroundSyncManager.shared.minimumSyncInterval / 3600
    @State private var exportError: String?
    @State private var showAPIError: Bool = false

    @State private var isAuthorizing = false

    // Date range filter for sync
    @State private var dateFilterEnabled = false
    @State private var syncFromDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var syncToDate = Date()

    // Auto export — ahora vive dentro de VaultSectionView
    // Share sheet
    @State private var shareItem: ShareItem?
    @State private var showShareSheet: Bool = false

    // Export filter sheet
    @State private var showExportFilterSheet: Bool = false
    @State private var exportFromDate: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var exportToDate: Date = Date()
    @State private var exportUseDateFilter: Bool = false
    @State private var exportSummaryOnly: Bool = false
    @State private var selectedWorkoutTypes: Set<String> = []

    // iCloud status
    @State private var iCloudAvailable: Bool = false

    // MARK: - Share Sheet Types (defined here so they're visible to the State vars above)

    struct ShareItem: Identifiable {
        let id = UUID()
        let url: URL
    }

    // Workout types available for filtering
    private let workoutTypes = ["running", "cycling", "walking", "swimming", "hiking", "yoga", "other"]

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
                    HStack {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        Text("Carpeta en iCloud Drive")
                        Spacer()
                        TextField("SyncSalud", text: $iCloudFolderName)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 160)
                    }

                    Button {
                        showExportFilterSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Exportar y compartir JSON (ad-hoc)")
                            Spacer()
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("Para exportar meses o rangos pre-calculados usá el Vault más abajo.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Exportar")
                }

                // MARK: - Vault
                VaultSectionView()

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
            .onAppear {
                // Check iCloud availability
                iCloudAvailable = FileManager.default.ubiquityIdentityToken != nil
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
            .sheet(isPresented: $showExportFilterSheet) {
                ExportFilterSheet(
                    fromDate: $exportFromDate,
                    toDate: $exportToDate,
                    useDateFilter: $exportUseDateFilter,
                    summaryOnly: $exportSummaryOnly,
                    selectedWorkoutTypes: $selectedWorkoutTypes,
                    workoutTypes: workoutTypes,
                    onExport: { filteredURL in
                        if let url = filteredURL {
                            shareItem = ShareItem(url: url)
                            showShareSheet = true
                        }
                    }
                )
            }
            #endif
        }
    }
}

// MARK: - Export Filter Sheet

#if os(iOS)
struct ExportFilterSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var fromDate: Date
    @Binding var toDate: Date
    @Binding var useDateFilter: Bool
    @Binding var summaryOnly: Bool
    @Binding var selectedWorkoutTypes: Set<String>

    let workoutTypes: [String]
    let onExport: (URL?) -> Void

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Filtrar por rango de fechas", isOn: $useDateFilter)

                    if useDateFilter {
                        DatePicker("Desde", selection: $fromDate, displayedComponents: [.date])
                            .datePickerStyle(.compact)

                        DatePicker("Hasta", selection: $toDate, in: fromDate...Date(), displayedComponents: [.date])
                            .datePickerStyle(.compact)
                    }
                } header: {
                    Text("Rango de fechas")
                }

                Section {
                    ForEach(workoutTypes, id: \.self) { type in
                        Toggle(type.capitalized, isOn: Binding(
                            get: { selectedWorkoutTypes.contains(type) },
                            set: { isSelected in
                                if isSelected {
                                    selectedWorkoutTypes.insert(type)
                                } else {
                                    selectedWorkoutTypes.remove(type)
                                }
                            }
                        ))
                    }
                } header: {
                    Text("Tipos de entrenamiento")
                } footer: {
                    Text("Dejá todos sin seleccionar para incluir todos los tipos.")
                }

                Section {
                    Toggle("Solo resumen (sin detalles)", isOn: $summaryOnly)
                } header: {
                    Text("Opciones")
                } footer: {
                    Text("Solo exporta las estadísticas agregadas, sin la lista de workouts.")
                }
            }
            .navigationTitle("Filtrar exportación")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Exportar") {
                        performExport()
                        dismiss()
                    }
                }
            }
        }
    }

    private func performExport() {
        let exporter = JSONExporter(context: modelContext)

        // Determine filter parameters
        let from = useDateFilter ? fromDate : nil
        let to = useDateFilter ? toDate : nil
        let types = selectedWorkoutTypes.isEmpty ? nil : Array(selectedWorkoutTypes)

        let url = exporter.exportFilteredJSON(from: from, to: to, workoutTypes: types, summaryOnly: summaryOnly)
        onExport(url)
    }
}
#endif

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