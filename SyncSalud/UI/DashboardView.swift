import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(HealthKitService.self) private var healthService
    @Environment(HealthSyncManager.self) private var syncManager
    @Query private var workouts: [WorkoutRecord]

    @State private var isSyncing = false

    private let calendar = Calendar.current

    var body: some View {
        #if os(iOS)
        NavigationStack {
            scrollContent
                .navigationTitle("Dashboard")
                .navigationBarTitleDisplayMode(.large)
                .refreshable {
                    await syncManager.syncFromHealthKit()
                }
        }
        #else
        scrollContent
            .navigationTitle("Dashboard")
        #endif
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                healthStatusCard

                if !workouts.isEmpty {
                    summarySection
                    streakSection
                    recentWorkoutsSection

                    #if os(macOS)
                    apiInfoCard
                    #endif
                } else if healthService.isAuthorized {
                    emptyState
                } else {
                    noPermissionsState
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        #if os(iOS)
        .refreshable {
            await syncManager.syncFromHealthKit()
        }
        #endif
    }

    // MARK: - Health Status Card

    private var healthStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "heart.fill")
                    .font(.title3)
                    .foregroundStyle(.red)
                Text("HealthKit")
                    .font(.headline)
                Spacer()
                statusBadge
            }

            Divider()

            HStack {
                Label("\(workouts.count) workouts", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(workouts.isEmpty ? Color.secondary : Color.green)
                    .font(.subheadline)
                Spacer()
                if isSyncing || syncManager.isSyncing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("dashboard.status.syncing".localized())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
    }

    private var statusBadge: some View {
        Group {
            switch healthService.authorizationState {
            case .authorized:
                Label("dashboard.status.connected".localized(), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                    .labelStyle(.titleAndIcon)
            case .denied:
                Label("dashboard.status.noAccess".localized(), systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            case .notRequested:
                Label("dashboard.status.notConnected".localized(), systemImage: "questionmark.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            case .notAvailable:
                Label("dashboard.status.notAvailable".localized(), systemImage: "minus.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            case .error:
                Label("dashboard.status.error".localized(), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        }
    }

    // MARK: - Summary Section

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("dashboard.summary.title".localized(), systemImage: "chart.bar.fill")

            LazyVGrid(columns: gridColumns, spacing: 12) {
                summaryCard(
                    title: "dashboard.summary.today".localized(),
                    value: "\(todayWorkouts.count)",
                    subtitle: "dashboard.summary.workouts".localized(),
                    icon: "figure.run",
                    color: .blue
                )
                summaryCard(
                    title: "dashboard.summary.thisWeek".localized(),
                    value: "\(weekWorkouts.count)",
                    subtitle: "dashboard.summary.workouts".localized(),
                    icon: "calendar",
                    color: .green
                )
                summaryCard(
                    title: "dashboard.summary.calories".localized(),
                    value: "\(Int(weekCalories))",
                    subtitle: "dashboard.summary.calories.week".localized(),
                    icon: "flame.fill",
                    color: .orange
                )
                summaryCard(
                    title: "dashboard.summary.duration".localized(),
                    value: weekDurationFormatted,
                    subtitle: "dashboard.summary.duration.week".localized(),
                    icon: "clock.fill",
                    color: .purple
                )
            }
        }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 140), spacing: 12)]
    }

    private func summaryCard(title: String, value: String, subtitle: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title)
                    .fontWeight(.bold)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Streak Section

    private var streakSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("dashboard.streak.title".localized(), systemImage: "flame.fill", tint: .orange)

            HStack(spacing: 16) {
                StreakBadge(value: streak.current, label: "dashboard.streak.current".localized())
                StreakBadge(value: streak.longest, label: "dashboard.streak.longest".localized())
            }

            if streak.isActiveToday {
                Label("dashboard.streak.today".localized(), systemImage: "star.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            } else if !workouts.isEmpty {
                Text(String(format: "dashboard.streak.lastWorkout".localized(), lastWorkoutDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
    }

    private struct StreakBadge: View {
        let value: Int
        let label: String

        var body: some View {
            VStack(spacing: 4) {
                Text("\(value)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Recent Workouts

    private var recentWorkoutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("dashboard.recent.title".localized(), systemImage: "clock.arrow.circlepath")

            ForEach(recentWorkouts.prefix(5)) { workout in
                WorkoutRowCompact(workout: workout)
                if workout.id != recentWorkouts.prefix(5).last?.id {
                    Divider()
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - API Info (macOS)

    #if os(macOS)
    private var apiInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("dashboard.api.title".localized(), systemImage: "network", tint: .blue)

            HStack {
                Circle()
                    .fill(LocalAPIServer.shared.isRunning ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                Text(LocalAPIServer.shared.isRunning ? "dashboard.api.active".localized() : "dashboard.api.inactive".localized())
                    .font(.subheadline)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("dashboard.api.agents".localized())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("• GET /v1/workouts")
                    .font(.caption2.monospaced())
                Text("• GET /v1/workouts/latest")
                    .font(.caption2.monospaced())
                Text("• GET /v1/summary")
                    .font(.caption2.monospaced())
                Text("• GET /v1/export")
                    .font(.caption2.monospaced())
            }
            .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
    }
    #endif

    // MARK: - Empty States

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.run")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("dashboard.empty.title".localized())
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("dashboard.empty.instruction".localized())
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button {
                Task {
                    isSyncing = true
                    await syncManager.syncFromHealthKit()
                    isSyncing = false
                }
            } label: {
                Label("dashboard.empty.button".localized(), systemImage: "arrow.clockwise")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isSyncing || syncManager.isSyncing)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }

    private var noPermissionsState: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.slash")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("dashboard.empty.noPermissions".localized())
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("dashboard.empty.noPermissions.instruction".localized())
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, systemImage: String, tint: Color = .primary) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(title)
                .font(.headline)
        }
    }

    private var todayWorkouts: [WorkoutRecord] {
        let today = calendar.startOfDay(for: Date())
        return workouts.filter { $0.startDate >= today }
    }

    private var weekWorkouts: [WorkoutRecord] {
        guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) else {
            return []
        }
        return workouts.filter { $0.startDate >= weekStart }
    }

    private var recentWorkouts: [WorkoutRecord] {
        workouts.sorted { $0.startDate > $1.startDate }
    }

    private var weekCalories: Double {
        weekWorkouts.compactMap(\.calories).reduce(0, +)
    }

    private var weekDurationFormatted: String {
        let totalSeconds = weekWorkouts.map(\.duration).reduce(0, +)
        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private var streak: (current: Int, longest: Int, isActiveToday: Bool) {
        let workoutDays = Set(workouts.map { calendar.startOfDay(for: $0.startDate) })
        let sortedDays = workoutDays.sorted(by: >)

        guard !sortedDays.isEmpty else { return (0, 0, false) }

        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let isActiveToday = workoutDays.contains(today)

        var currentStreak = 0
        var checkDate = isActiveToday ? today : yesterday

        for day in sortedDays {
            if calendar.isDate(day, inSameDayAs: checkDate) {
                currentStreak += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
            } else if day < checkDate {
                break
            }
        }

        var longestStreak = 0
        var tempStreak = 1
        for i in 1..<sortedDays.count {
            let diff = calendar.dateComponents([.day], from: sortedDays[i], to: sortedDays[i-1]).day ?? 0
            if diff == 1 {
                tempStreak += 1
            } else {
                longestStreak = max(longestStreak, tempStreak)
                tempStreak = 1
            }
        }
        longestStreak = max(longestStreak, tempStreak)

        return (currentStreak, longestStreak, isActiveToday)
    }

    private var lastWorkoutDate: String {
        guard let last = workouts.max(by: { $0.startDate < $1.startDate }) else {
            return "dashboard.unknown".localized()
        }
        return last.startDate.formatted(date: .abbreviated, time: .omitted)
    }
}

// MARK: - Workout Row Component (compartido con WorkoutListView)

struct WorkoutRowCompact: View {
    let workout: WorkoutRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: workout.typeEnum.sfSymbol)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 40, height: 40)
                .background(Color.blue.opacity(0.15), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(workout.typeEnum.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(workout.dateFormatted)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(workout.durationFormatted)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let cals = workout.calories {
                        Text("\(Int(cals)) kcal")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let dist = workout.distance, dist > 0 {
                        Text(dist >= 1000 ? String(format: "%.1fkm", dist / 1000) : "\(Int(dist))m")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        DashboardView()
    }
    .modelContainer(for: [WorkoutRecord.self], inMemory: true)
    .environment(HealthKitService())
    .environment(HealthSyncManager())
}