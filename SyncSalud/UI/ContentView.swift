import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(HealthKitService.self) private var healthService
    @Environment(HealthSyncManager.self) private var syncManager
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTab: Tab = .dashboard

    enum Tab: String, CaseIterable, Hashable {
        case dashboard
        case workouts
        case settings

        var label: String {
            switch self {
            case .dashboard: return "Dashboard"
            case .workouts: return "Entrenamientos"
            case .settings: return "Ajustes"
            }
        }

        var icon: String {
            switch self {
            case .dashboard: return "chart.bar.fill"
            case .workouts: return "list.bullet"
            case .settings: return "gear"
            }
        }
    }

    var body: some View {
        #if os(macOS)
        macOSLayout
        #else
        iOSLayout
        #endif
    }

    // MARK: - iOS

    private var iOSLayout: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem {
                    Label { Text(verbatim: Tab.dashboard.label) } icon: { Image(systemName: Tab.dashboard.icon) }
                }
                .tag(Tab.dashboard)

            WorkoutListView()
                .tabItem {
                    Label { Text(verbatim: Tab.workouts.label) } icon: { Image(systemName: Tab.workouts.icon) }
                }
                .tag(Tab.workouts)

            SettingsView()
                .tabItem {
                    Label { Text(verbatim: Tab.settings.label) } icon: { Image(systemName: Tab.settings.icon) }
                }
                .tag(Tab.settings)
        }
        .tint(.accentColor)
        .onAppear {
            syncManager.configure(with: modelContext)
        }
    }

    // MARK: - macOS

    private var macOSLayout: some View {
        NavigationSplitView {
            #if os(macOS)
            List(Tab.allCases, id: \.self, selection: $selectedTab) { tab in
                Label { Text(verbatim: tab.label) } icon: { Image(systemName: tab.icon) }
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 180)
            #else
            List(Tab.allCases, id: \.self) { tab in
                Label { Text(verbatim: tab.label) } icon: { Image(systemName: tab.icon) }
                    .tag(tab)
            }
            .frame(minWidth: 180)
            #endif
        } detail: {
            switch selectedTab {
            case .dashboard:
                NavigationStack { DashboardView() }
            case .workouts:
                NavigationStack { WorkoutListView() }
            case .settings:
                NavigationStack { SettingsView() }
            }
        }
        .onAppear {
            syncManager.configure(with: modelContext)

            #if os(macOS)
            LocalAPIServer.shared.configure(with: modelContext)
            #endif
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [WorkoutRecord.self, WorkoutMetric.self, SyncLog.self], inMemory: true)
        .environment(HealthKitService())
        .environment(HealthSyncManager())
        .environment(CloudSyncStatusMonitor())
}
