import SwiftUI
import SwiftData

struct WorkoutListView: View {
    @Environment(HealthSyncManager.self) private var syncManager
    @Query(sort: \WorkoutRecord.startDate, order: .reverse) private var workouts: [WorkoutRecord]

    @State private var searchText: String = ""
    @State private var selectedType: WorkoutType?

    var body: some View {
        #if os(iOS)
        NavigationStack {
            listContent
                .navigationTitle("workouts.title".localized())
                .navigationBarTitleDisplayMode(.large)
                .searchable(text: $searchText, prompt: "Buscar por tipo")
                .toolbar {
                    toolbarSyncButton
                }
        }
        #else
        listContent
            .navigationTitle("workouts.title".localized())
            .toolbar {
                toolbarSyncButton
            }
        #endif
    }

    private var listContent: some View {
        Group {
            if filteredWorkouts.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(filteredWorkouts) { workout in
                        WorkoutRowCompact(workout: workout)
                    }
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                #endif
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarSyncButton: some ToolbarContent {
        ToolbarItem(placement: syncButtonPlacement) {
            Button {
                Task { await syncManager.syncFromHealthKit() }
            } label: {
                if syncManager.isSyncing {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .disabled(syncManager.isSyncing)
        }
    }

    private var syncButtonPlacement: ToolbarItemPlacement {
        #if os(iOS)
        return .topBarTrailing
        #else
        return .primaryAction
        #endif
    }

    private var filteredWorkouts: [WorkoutRecord] {
        var result = workouts

        if let type = selectedType {
            result = result.filter { $0.workoutType == type.rawValue }
        }

        if !searchText.isEmpty {
            result = result.filter {
                $0.typeEnum.displayName.localizedCaseInsensitiveContains(searchText)
            }
        }

        return result
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("workouts.empty".localized())
                .font(.headline)
                .foregroundStyle(.secondary)
            if !searchText.isEmpty {
                Text("workouts.empty.search".localized())
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Text("workouts.empty.instruction".localized())
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    NavigationStack {
        WorkoutListView()
    }
    .modelContainer(for: [WorkoutRecord.self], inMemory: true)
    .environment(HealthSyncManager())
}
