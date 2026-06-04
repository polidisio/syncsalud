import SwiftUI
import SwiftData
#if canImport(BackgroundTasks)
import BackgroundTasks
#endif

/// Sección del vault embebida en Settings.
/// Muestra el estado del vault (local + iCloud), los meses disponibles, y botones para refrescar / abrir la carpeta.
struct VaultSectionView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var index: VaultIndex?
    @State private var isRefreshing: Bool = false
    @State private var refreshError: String?
    @State private var shareItems: [URL] = []
    @State private var showShareSheet: Bool = false
    @State private var selection: Set<String> = []
    #if os(iOS)
    @State private var editMode: EditMode = .inactive
    #endif
    @State private var vaultEnabled: Bool = false
    @State private var iCloudMirroring: Bool = VaultManager.shared.isICloudMirroring

    private var isVaultEmpty: Bool {
        (index?.months.isEmpty ?? true)
    }

    var body: some View {
        Section {
            statusRow

            if let lastRefresh = index?.lastRefresh, lastRefresh > .distantPast {
                HStack {
                    Text("Última actualización")
                    Spacer()
                    Text(lastRefresh, style: .relative)
                        .foregroundStyle(.secondary)
                }
            }

            Toggle("Refrescar automáticamente en background", isOn: $vaultEnabled)
                .onChange(of: vaultEnabled) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: "vaultEnabled")
                    #if os(iOS)
                    if newValue {
                        scheduleBackgroundExport()
                    } else {
                        cancelBackgroundExport()
                    }
                    #endif
                }

            if let months = index?.sortedMonths, !months.isEmpty {
                monthsList(months: months)
            } else {
                emptyState
            }

            actionsRow

            if let err = refreshError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Vault local")
        } footer: {
            Text("El vault guarda un snapshot por mes en JSON. Se mantiene actualizado automáticamente y se espeja a iCloud Drive cuando estás logueado.")
                .font(.caption2)
        }
        #if os(iOS)
        .environment(\.editMode, $editMode)
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: shareItems)
        }
        #endif
    }

    // MARK: - Subviews

    private var statusRow: some View {
        HStack {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("Almacenamiento local")
                    .font(.subheadline)
                Text(iCloudMirroring ? "Local + iCloud Drive" : "Solo local (sin iCloud)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isRefreshing {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
    }

    private func monthsList(months: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Meses disponibles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                #if os(iOS)
                if editMode.isEditing && !selection.isEmpty {
                    Button("Compartir \(selection.count)") {
                        shareSelectedMonths(months: months)
                    }
                    .font(.caption)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                EditButton()
                    .font(.caption)
                #endif
            }
            ForEach(months, id: \.self) { ym in
                monthRow(yearMonth: ym)
            }
        }
    }

    private func monthRow(yearMonth: String) -> some View {
        let isSelected = selection.contains(yearMonth)
        return HStack {
            #if os(iOS)
            if editMode.isEditing {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
            }
            #endif
            VStack(alignment: .leading, spacing: 2) {
                Text(formatYearMonth(yearMonth))
                    .foregroundStyle(.primary)
                if let entry = index?.months[yearMonth] {
                    Text("\(entry.workoutCount) workouts · \(formatBytes(entry.byteSize))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            #if os(iOS)
            if editMode.isEditing {
                toggleSelection(yearMonth: yearMonth)
            } else {
                shareSingleMonth(yearMonth: yearMonth)
            }
            #else
            shareSingleMonth(yearMonth: yearMonth)
            #endif
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Vacío")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Sincronizá HealthKit primero. Después tocá Refrescar.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var actionsRow: some View {
        HStack {
            Button {
                Task { await refresh() }
            } label: {
                Label("Refrescar ahora", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(isRefreshing)

            Spacer()

            #if os(iOS)
            // Solo visible antes del primer refresh — es una acción one-shot de setup.
            if isVaultEmpty {
                Button {
                    shareVaultFolder()
                } label: {
                    Label("Compartir carpeta", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }
            #else
            Button {
                _ = VaultManager.shared.openInFinder()
            } label: {
                Label("Abrir en Finder", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            #endif
        }
    }

    // MARK: - Actions

    private func loadState() {
        index = VaultManager.shared.loadIndex()
        iCloudMirroring = VaultManager.shared.isICloudMirroring
        vaultEnabled = UserDefaults.standard.bool(forKey: "vaultEnabled")
    }

    private func refresh() async {
        isRefreshing = true
        refreshError = nil
        defer { isRefreshing = false }
        do {
            _ = try await VaultManager.shared.refreshAll(modelContext: modelContext)
            index = VaultManager.shared.loadIndex()
            iCloudMirroring = VaultManager.shared.isICloudMirroring
        } catch {
            refreshError = "Error refrescando vault: \(error.localizedDescription)"
        }
    }

    private func toggleSelection(yearMonth: String) {
        if selection.contains(yearMonth) {
            selection.remove(yearMonth)
        } else {
            selection.insert(yearMonth)
        }
    }

    private func shareSingleMonth(yearMonth: String) {
        guard let url = VaultManager.shared.readMonth(yearMonth) else { return }
        shareItems = [url]
        showShareSheet = true
    }

    private func shareSelectedMonths(months: [String]) {
        let selected = months.filter { selection.contains($0) }
        let urls = VaultManager.shared.readMonthsInRange(selected)
        guard !urls.isEmpty else { return }
        shareItems = urls
        showShareSheet = true
    }

    private func shareVaultFolder() {
        guard let url = VaultManager.shared.localVaultURLForSharing() else { return }
        shareItems = [url]
        showShareSheet = true
    }

    // MARK: - BG scheduling helpers

    #if os(iOS)
    private func scheduleBackgroundExport() {
        guard vaultEnabled else { return }
        let saved = UserDefaults.standard.double(forKey: "exportInterval")
        let interval = saved > 0 ? saved : 6 * 3600
        let request = BGProcessingTaskRequest(identifier: "com.syncsalud.export")
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            refreshError = "No se pudo programar background: \(error.localizedDescription)"
        }
    }

    private func cancelBackgroundExport() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: "com.syncsalud.export")
    }
    #endif

    // MARK: - Formatting

    private func formatYearMonth(_ ym: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM"
        guard let date = parser.date(from: ym) else { return ym }
        let display = DateFormatter()
        display.dateFormat = "LLLL yyyy"
        display.locale = Locale(identifier: "es_AR")
        return display.string(from: date).capitalized
    }

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
