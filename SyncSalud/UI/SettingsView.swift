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

    @State private var dateFilterEnabled = false
    @State private var syncFromDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var syncToDate = Date()

    @State private var shareItem: ShareItem?
    @State private var showShareSheet: Bool = false

    @State private var showExportFilterSheet: Bool = false
    @State private var exportFromDate: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var exportToDate: Date = Date()
    @State private var exportUseDateFilter: Bool = false
    @State private var exportSummaryOnly: Bool = false
    @State private var selectedWorkoutTypes: Set<String> = []

    @State private var iCloudAvailable: Bool = false

    struct ShareItem: Identifiable {
        let id = UUID()
        let url: URL
    }

    private let workoutTypes = ["running", "cycling", "walking", "swimming", "hiking", "yoga", "other"]

    @ViewBuilder
    private var healthStatusView: some View {
        switch healthService.authorizationState {
        case .authorized:
            Label("settings.health.connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .notRequested:
            Button("settings.health.connect") {
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
                Label("settings.health.noAccess", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                #if os(iOS)
                Button("settings.health.openSettings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                #endif
            }
        case .notAvailable:
            Label("settings.health.notAvailable", systemImage: "minus.circle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
        case .error(let msg):
            VStack(alignment: .trailing) {
                Label("settings.health.error", systemImage: "exclamationmark.triangle.fill")
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
                Section {
                    HStack {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.red)
                        Text("HealthKit")
                        Spacer()
                        healthStatusView
                    }

                    if !healthService.isAvailable {
                        Label("settings.health.simulatorWarning", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    if let error = healthService.lastError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("settings.permissions.title".localized())
                }

                Section {
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
                            Text(dateFilterEnabled ? "settings.sync.range".localized() : "settings.sync.all".localized())
                            Spacer()
                            if syncManager.isSyncing {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(syncManager.isSyncing)

                    if let last = syncManager.lastSyncDate {
                        HStack {
                            Text("settings.sync.lastSync".localized())
                            Spacer()
                            Text(last, style: .relative)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Toggle("settings.sync.dateFilter", isOn: $dateFilterEnabled)

                    if dateFilterEnabled {
                        DatePicker(
                            "settings.sync.from",
                            selection: $syncFromDate,
                            displayedComponents: [.date]
                        )
                        .datePickerStyle(.compact)

                        DatePicker(
                            "settings.sync.to",
                            selection: $syncToDate,
                            in: syncFromDate...Date(),
                            displayedComponents: [.date]
                        )
                        .datePickerStyle(.compact)

                        Text("settings.sync.dateFilter.hint".localized())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    #if os(iOS)
                    Toggle("settings.sync.background", isOn: $backgroundSyncEnabled)
                        .onChange(of: backgroundSyncEnabled) { _, newValue in
                            BackgroundSyncManager.shared.isBackgroundSyncEnabled = newValue
                        }

                    if backgroundSyncEnabled {
                        VStack(alignment: .leading) {
                            HStack {
                                Text("settings.sync.interval".localized())
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
                    if syncManager.isBackfilling {
                        HStack {
                            ProgressView().scaleEffect(0.8)
                            Text(String(format: "settings.backfill.progress".localized(), syncManager.backfillProgress))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("settings.backfill.cancel".localized()) {
                                syncManager.cancelHeartRateBackfill()
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    } else {
                        Button {
                            syncManager.startHeartRateBackfill(context: modelContext)
                        } label: {
                            Label("settings.backfill.start".localized(), systemImage: "heart.fill")
                        }
                        .disabled(syncManager.isSyncing)
                    }
                } header: {
                    Text("settings.sync.title".localized())
                }

                Section {
                    Button {
                        showExportFilterSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("settings.export.adhoc".localized())
                            Spacer()
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("settings.export.hint".localized())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("settings.export.title".localized())
                }

                VaultSectionView()

                #if os(macOS)
                Section {
                    HStack {
                        Image(systemName: "network")
                        Text("dashboard.api.title".localized())
                        Spacer()
                        Circle()
                            .fill(LocalAPIServer.shared.isRunning ? Color.green : Color.red)
                            .frame(width: 10, height: 10)
                    }

                    if LocalAPIServer.shared.isRunning {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("settings.export.agents".localized())
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
                        Button("settings.export.startApi") {
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
                    Text("settings.export.api.title".localized())
                }
                #endif

                Section {
                    HStack {
                        Text("settings.about.version".localized())
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("settings.about.dataModel".localized())
                        Spacer()
                        Text("SwiftData + CloudKit")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                } header: {
                    Text("settings.about.title".localized())
                }
            }
            .navigationTitle("settings.title".localized())
            .onAppear {
                iCloudAvailable = FileManager.default.ubiquityIdentityToken != nil
            }
            .alert("settings.export.error", isPresented: .constant(exportError != nil)) {
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
                    Toggle("settings.filter.dateRange", isOn: $useDateFilter)

                    if useDateFilter {
                        DatePicker("settings.sync.from", selection: $fromDate, displayedComponents: [.date])
                            .datePickerStyle(.compact)

                        DatePicker("settings.sync.to", selection: $toDate, in: fromDate...Date(), displayedComponents: [.date])
                            .datePickerStyle(.compact)
                    }
                } header: {
                    Text("settings.filter.dateRange".localized())
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
                    Text("settings.filter.workoutTypes".localized())
                } footer: {
                    Text("settings.filter.workoutTypes.hint".localized())
                }

                Section {
                    Toggle("settings.filter.summaryOnly", isOn: $summaryOnly)
                } header: {
                    Text("settings.filter.options".localized())
                } footer: {
                    Text("settings.filter.summaryOnly.hint".localized())
                }
            }
            .navigationTitle("settings.filter.title".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("settings.filter.cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("settings.filter.export") {
                        performExport()
                        dismiss()
                    }
                }
            }
        }
    }

    private func performExport() {
        let exporter = JSONExporter(context: modelContext)

        let from = useDateFilter ? fromDate : nil
        let to = useDateFilter ? toDate : nil
        let types = selectedWorkoutTypes.isEmpty ? nil : Array(selectedWorkoutTypes)

        let url = exporter.exportFilteredJSON(from: from, to: to, workoutTypes: types, summaryOnly: summaryOnly)
        onExport(url)
    }
}
#endif

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
