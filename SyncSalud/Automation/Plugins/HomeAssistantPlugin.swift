import Foundation
import SwiftUI

final class HomeAssistantPlugin: ExportPlugin {
    static let shared = HomeAssistantPlugin()

    private let defaults = UserDefaults.standard

    var id: String { "home_assistant" }
    var displayName: String { "Home Assistant" }

    var webhookURL: String {
        get { defaults.string(forKey: "plugin_ha_webhook_url") ?? "" }
        set { defaults.set(newValue, forKey: "plugin_ha_webhook_url") }
    }

    var isConfigured: Bool { !webhookURL.isEmpty }

    var isEnabled: Bool {
        get { defaults.bool(forKey: "plugin_ha_enabled") }
        set { defaults.set(newValue, forKey: "plugin_ha_enabled") }
    }

    func run(vaultURLs: [URL]) async -> Result<Void, ExportError> {
        guard isConfigured else { return .failure(.notConfigured("Webhook URL no configurada")) }
        guard let targetURL = URL(string: webhookURL) else { return .failure(.notConfigured("Webhook URL inválida")) }

        let months = VaultManager.shared.availableMonths()
        let idx = VaultManager.shared.loadIndex()
        let totalWorkouts = months.compactMap { idx?.months[$0]?.workoutCount }.reduce(0, +)
        let totalBytes = months.compactMap { idx?.months[$0]?.byteSize }.reduce(0, +)

        let payload: [String: Any] = [
            "source": "SyncSalud",
            "trigger": "vault_refresh",
            "months_count": months.count,
            "total_workouts": totalWorkouts,
            "total_bytes": totalBytes,
            "files": vaultURLs.map { $0.lastPathComponent },
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            return .failure(.unknown("No se pudo serializar payload"))
        }

        var request = URLRequest(url: targetURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        for attempt in 0..<3 {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                    print("Home Assistant: ✓ trigger, status \(http.statusCode)")
                    return .success(())
                } else {
                    let body = String(data: data, encoding: .utf8) ?? ""
                    print("Home Assistant: ✗ \(body.prefix(100))")
                }
            } catch {
                print("Home Assistant: retry \(attempt+1)/3: \(error.localizedDescription)")
            }
            if attempt < 2 { try? await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt)) * 1_000_000_000)) }
        }
        return .failure(.networkError("HA webhook no respondió tras 3 intentos"))
    }

    func buildConfigView() -> AnyView {
        AnyView(VStack(alignment: .leading, spacing: 8) {
            Text("Webhook URL").font(.caption).foregroundStyle(.secondary)
            TextField("https://...", text: Binding(get: { self.webhookURL }, set: { self.webhookURL = $0 }))
                .textContentType(.URL).autocorrectionDisabled().textFieldStyle(.roundedBorder)
            Text("Creá un webhook en HA: Settings → Automations → Helpers → Create Trigger → Webhook.")
                .font(.caption2).foregroundStyle(.secondary)
        }.padding())
    }
}