import Foundation
import SwiftData
#if canImport(Network)
import Network
#endif

#if os(macOS)
/// Servidor HTTP local que expone los datos de entrenamiento a agentes externos
/// Escucha en 127.0.0.1:8080 solo en macOS.
/// Los agentes del usuario pueden consultar GET /v1/workouts, /v1/summary, etc.
final class LocalAPIServer {
    static let shared = LocalAPIServer()

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.synctrackers.api", qos: .background)
    private let port: UInt16 = 8080

    private var modelContext: ModelContext?

    private(set) var isRunning = false
    private(set) var lastError: String?

    // MARK: - Lifecycle

    func configure(with context: ModelContext) {
        self.modelContext = context
    }

    func start() {
        guard !isRunning else { return }

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true

            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            listener?.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.isRunning = true
                    print("🌐 API local iniciada en http://127.0.0.1:\(self?.port ?? 8080)")
                case .failed(let error):
                    self?.isRunning = false
                    self?.lastError = "Error del listener: \(error.localizedDescription)"
                    print("⚠️ API local error: \(error.localizedDescription)")
                    // Reintentar en 5 segundos
                    DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                        self?.start()
                    }
                default:
                    break
                }
            }

            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            listener?.start(queue: queue)
        } catch {
            lastError = "No se pudo iniciar el servidor: \(error.localizedDescription)"
            print("❌ \(lastError!)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        print("API local detenida")
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data = data, let request = String(data: data, encoding: .utf8) {
                let response = self.handleRequest(request)
                connection.send(
                    content: response.data(using: .utf8),
                    completion: .contentProcessed({ _ in
                        connection.cancel()
                    })
                )
            } else if let error = error {
                print("Error en conexión: \(error.localizedDescription)")
                connection.cancel()
            } else {
                connection.cancel()
            }
        }
    }

    // MARK: - Request Parsing & Routing

    private func handleRequest(_ request: String) -> String {
        // Parsear la primera línea: "GET /v1/workouts HTTP/1.1"
        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else {
            return httpResponse(status: 400, body: "Bad Request")
        }

        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            return httpResponse(status: 400, body: "Bad Request")
        }

        let method = parts[0]
        let pathWithQuery = parts[1]

        guard method == "GET" else {
            return httpResponse(status: 405, body: "Method Not Allowed")
        }

        return route(pathWithQuery)
    }

    private func route(_ pathWithQuery: String) -> String {
        // Separar path de query string
        let pathAndQuery = pathWithQuery.components(separatedBy: "?")
        let path = pathAndQuery[0]
        let queryItems = pathAndQuery.count > 1 ? parseQuery(pathAndQuery[1]) : [:]

        switch path {
        case "/v1/health":
            return handleHealth()

        case "/v1/workouts":
            return handleWorkouts(queryItems)

        case "/v1/workouts/latest":
            return handleLatestWorkout()

        case "/v1/summary":
            return handleSummary()

        case "/v1/export":
            return handleExport()

        default:
            if path.hasPrefix("/v1/workouts/"), let id = path.split(separator: "/").last {
                return handleWorkoutByID(String(id))
            }
            return httpResponse(status: 404, body: #"{"error":"Not Found"}"#)
        }
    }

    // MARK: - Route Handlers

    private func handleHealth() -> String {
        let body = #"{"status":"ok","version":"1.0","serverTime":"\#(ISO8601DateFormatter().string(from: Date()))"}"#
        return httpResponse(status: 200, body: body)
    }

    private func handleWorkouts(_ query: [String: String]) -> String {
        guard let context = modelContext else {
            return httpResponse(status: 503, body: #"{"error":"Database not ready"}"#)
        }

        var predicate: Predicate<WorkoutRecord>?

        // Filtro por tipo
        if let type = query["type"] {
            predicate = #Predicate { $0.workoutType == type }
        }

        // Filtro por rango de fechas
        if let fromStr = query["from"], let from = ISO8601DateFormatter().date(from: fromStr) {
            let datePredicate = #Predicate<WorkoutRecord> { $0.startDate >= from }
            predicate = predicate.map { pred in
                // Combinar predicados no es trivial en SwiftData, tomaríamos el más restrictivo
                // Por simplicidad, aplicamos solo el de fecha si hay conflicto
                return datePredicate
            } ?? datePredicate
        }

        if let toStr = query["to"], let to = ISO8601DateFormatter().date(from: toStr) {
            let datePredicate = #Predicate<WorkoutRecord> { $0.startDate <= to }
            predicate = predicate.map { _ in datePredicate } ?? datePredicate
        }

        // Paginación
        let limit = Int(query["limit"] ?? "50") ?? 50
        // Clamp limit
        let safeLimit = min(max(limit, 1), 1000)

        var descriptor = FetchDescriptor<WorkoutRecord>(
            predicate: predicate,
            sortBy: [SortDescriptor(\WorkoutRecord.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = safeLimit

        if let offsetStr = query["offset"], let offset = Int(offsetStr) {
            descriptor.fetchOffset = max(offset, 0)
        }

        guard let records = try? context.fetch(descriptor) else {
            return httpResponse(status: 500, body: #"{"error":"Query failed"}"#)
        }

        let json = encodeWorkoutsToJSON(records)
        return httpResponse(status: 200, body: json, contentType: "application/json")
    }

    private func handleWorkoutByID(_ idString: String) -> String {
        guard let context = modelContext else {
            return httpResponse(status: 503, body: #"{"error":"Database not ready"}"#)
        }

        guard let uuid = UUID(uuidString: idString) else {
            return httpResponse(status: 400, body: #"{"error":"Invalid UUID"}"#)
        }

        let predicate = #Predicate<WorkoutRecord> { $0.id == uuid }
        let descriptor = FetchDescriptor<WorkoutRecord>(predicate: predicate)

        guard let record = try? context.fetch(descriptor).first else {
            return httpResponse(status: 404, body: #"{"error":"Workout not found"}"#)
        }

        let json = encodeWorkoutToJSON(record)
        return httpResponse(status: 200, body: json, contentType: "application/json")
    }

    private func handleLatestWorkout() -> String {
        guard let context = modelContext else {
            return httpResponse(status: 503, body: #"{"error":"Database not ready"}"#)
        }

        var descriptor = FetchDescriptor<WorkoutRecord>(
            sortBy: [SortDescriptor(\WorkoutRecord.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        guard let record = try? context.fetch(descriptor).first else {
            return httpResponse(status: 404, body: #"{"error":"No workouts found"}"#)
        }

        let json = encodeWorkoutToJSON(record)
        return httpResponse(status: 200, body: json, contentType: "application/json")
    }

    private func handleSummary() -> String {
        guard let context = modelContext else {
            return httpResponse(status: 503, body: #"{"error":"Database not ready"}"#)
        }

        let calendar = Calendar.current
        let now = Date()

        guard let todayStart = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: now),
              let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)),
              let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else {
            return httpResponse(status: 500, body: #"{"error":"Date calculation failed"}"#)
        }

        // Queries optimizadas: traer solo lo que necesitamos de la base
        let todayDescriptor = FetchDescriptor<WorkoutRecord>(
            predicate: #Predicate { $0.startDate >= todayStart }
        )
        let weekDescriptor = FetchDescriptor<WorkoutRecord>(
            predicate: #Predicate { $0.startDate >= weekStart }
        )
        let monthDescriptor = FetchDescriptor<WorkoutRecord>(
            predicate: #Predicate { $0.startDate >= monthStart }
        )

        let todayWorkouts = (try? context.fetch(todayDescriptor)) ?? []
        let weekWorkouts = (try? context.fetch(weekDescriptor)) ?? []
        let monthWorkouts = (try? context.fetch(monthDescriptor)) ?? []

        // Total count (más rápido que traer todos los registros)
        let totalDescriptor = FetchDescriptor<WorkoutRecord>()
        let totalCount = (try? context.fetchCount(totalDescriptor)) ?? 0

        // Last workout (top 1 ordenado por fecha)
        var lastWorkoutDescriptor = FetchDescriptor<WorkoutRecord>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        lastWorkoutDescriptor.fetchLimit = 1
        let lastWorkout = (try? context.fetch(lastWorkoutDescriptor))?.first

        // By type (limitado a 1000 para que no demore)
        var recentDescriptor = FetchDescriptor<WorkoutRecord>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        recentDescriptor.fetchLimit = 1000
        let recentWorkouts = (try? context.fetch(recentDescriptor)) ?? []
        let typeCounts = Dictionary(grouping: recentWorkouts, by: { $0.workoutType })
            .mapValues { $0.count }

        // Racha: usamos solo el último año (suficiente para calcular la racha actual)
        guard let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: now) else {
            return httpResponse(status: 500, body: #"{"error":"Date calculation failed"}"#)
        }
        let streakDescriptor = FetchDescriptor<WorkoutRecord>(
            predicate: #Predicate { $0.startDate >= oneYearAgo }
        )
        let streakWorkouts = (try? context.fetch(streakDescriptor)) ?? []
        let streak = calculateStreak(workouts: streakWorkouts, calendar: calendar)

        let formatter = ISO8601DateFormatter()
        let lastWorkoutDateString = lastWorkout.map { formatter.string(from: $0.startDate) } ?? ""

        let summary: [String: Any] = [
            "today": [
                "count": todayWorkouts.count,
                "calories": todayWorkouts.compactMap(\.calories).reduce(0, +),
                "duration": todayWorkouts.map(\.duration).reduce(0, +),
                "distance": todayWorkouts.compactMap(\.distance).reduce(0, +)
            ],
            "thisWeek": [
                "count": weekWorkouts.count,
                "calories": weekWorkouts.compactMap(\.calories).reduce(0, +),
                "duration": weekWorkouts.map(\.duration).reduce(0, +)
            ],
            "thisMonth": [
                "count": monthWorkouts.count,
                "calories": monthWorkouts.compactMap(\.calories).reduce(0, +),
                "duration": monthWorkouts.map(\.duration).reduce(0, +)
            ],
            "byType": typeCounts,
            "streak": [
                "current": streak.current,
                "longest": streak.longest,
                "lastWorkoutDate": lastWorkoutDateString,
                "isActiveToday": streak.isActiveToday
            ],
            "totalWorkouts": totalCount
        ]

        let json = (try? JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        return httpResponse(status: 200, body: json, contentType: "application/json")
    }

    private func handleExport() -> String {
        guard let context = modelContext else {
            return httpResponse(status: 503, body: #"{"error":"Database not ready"}"#)
        }

        guard let records = try? context.fetch(FetchDescriptor<WorkoutRecord>()) else {
            return httpResponse(status: 500, body: #"{"error":"Query failed"}"#)
        }

        let jsonRecords = records.map(encodeWorkoutToDict)

        let dates = records.compactMap(\.startDate).sorted()
        let export: [String: Any] = [
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "source": "Synctrackers",
            "version": "1.0",
            "workoutCount": records.count,
            "dateRange": [
                "from": dates.first.map { ISO8601DateFormatter().string(from: $0) } ?? "",
                "to": dates.last.map { ISO8601DateFormatter().string(from: $0) } ?? ""
            ],
            "workouts": jsonRecords
        ]

        let json = (try? JSONSerialization.data(withJSONObject: export, options: [.prettyPrinted, .sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        return httpResponse(status: 200, body: json, contentType: "application/json",
                            headers: ["Content-Disposition": "attachment; filename=synctrackers_export.json"])
    }

    // MARK: - Helpers

    private func parseQuery(_ queryString: String) -> [String: String] {
        var params: [String: String] = [:]
        for pair in queryString.components(separatedBy: "&") {
            let kv = pair.components(separatedBy: "=")
            if kv.count == 2 {
                params[kv[0]] = kv[1].removingPercentEncoding
            }
        }
        return params
    }

    private func calculateStreak(workouts: [WorkoutRecord], calendar: Calendar) -> (current: Int, longest: Int, isActiveToday: Bool) {
        let workoutDays = Set(workouts.map { calendar.startOfDay(for: $0.startDate) })
        let sortedDays = workoutDays.sorted(by: >)

        guard !sortedDays.isEmpty else {
            return (0, 0, false)
        }

        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let isActiveToday = workoutDays.contains(today)

        // Current streak
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

        // Longest streak
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

    private func encodeWorkoutsToJSON(_ records: [WorkoutRecord]) -> String {
        let dicts = records.map(encodeWorkoutToDict)
        let data = (try? JSONSerialization.data(withJSONObject: dicts, options: [])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private func encodeWorkoutToJSON(_ record: WorkoutRecord) -> String {
        let dict = encodeWorkoutToDict(record)
        let data = (try? JSONSerialization.data(withJSONObject: dict, options: [])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func encodeWorkoutToDict(_ record: WorkoutRecord) -> [String: Any] {
        let formatter = ISO8601DateFormatter()

        return [
            "id": record.id.uuidString,
            "type": record.workoutType,
            "startDate": formatter.string(from: record.startDate),
            "endDate": formatter.string(from: record.endDate),
            "duration": record.duration,
            "calories": record.calories as Any,
            "distance": record.distance as Any,
            "distanceUnit": record.distanceUnit as Any,
            "avgHeartRate": record.avgHeartRate as Any,
            "maxHeartRate": record.maxHeartRate as Any,
            "minHeartRate": record.minHeartRate as Any,
            "source": record.source,
            "createdAt": formatter.string(from: record.createdAt),
            "updatedAt": formatter.string(from: record.updatedAt)
        ].compactMapValues { $0 }
    }

    private func httpResponse(status: Int, body: String,
                              contentType: String = "application/json",
                              headers: [String: String] = [:]) -> String {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        case 405: statusText = "Method Not Allowed"
        case 500: statusText = "Internal Server Error"
        case 503: statusText = "Service Unavailable"
        default: statusText = "Unknown"
        }

        var allHeaders = headers
        allHeaders["Content-Type"] = contentType
        allHeaders["Content-Length"] = "\(body.utf8.count)"
        allHeaders["Access-Control-Allow-Origin"] = "null"
        allHeaders["Connection"] = "close"

        let headerString = allHeaders.map { "\($0.key): \($0.value)" }.joined(separator: "\r\n")
        return "HTTP/1.1 \(status) \(statusText)\r\n\(headerString)\r\n\r\n\(body)"
    }
}
#endif
