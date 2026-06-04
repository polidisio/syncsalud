import Foundation
import SwiftUI

final class RESTAPIPlugin: ExportPlugin {
    static let shared = RESTAPIPlugin()

    private let defaults = UserDefaults.standard

    var id: String { "rest_api" }
    var displayName: String { "REST API / Webhook" }

    var endpointURL: String {
        get { defaults.string(forKey: "plugin_rest_api_url") ?? "" }
        set { defaults.set(newValue, forKey: "plugin_rest_api_url") }
    }

    var apiKey: String? {
        get { defaults.string(forKey: "plugin_rest_api_key") }
        set { defaults.set(newValue, forKey: "plugin_rest_api_key") }
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: "plugin_rest_api_enabled") }
        set { defaults.set(newValue, forKey: "plugin_rest_api_enabled") }
    }

    var isConfigured: Bool { !endpointURL.isEmpty }

    func run(vaultURLs: [URL]) async -> Result<Void, ExportError> {
        guard isConfigured else { return .failure(.notConfigured("Endpoint URL no configurada")) }

        let urlString = endpointURL
        let authKey = apiKey

        for url in vaultURLs {
            guard let data = try? Data(contentsOf: url) else { continue }
            guard let reqURL = URL(string: urlString) else { return .failure(.notConfigured("URL inválida")) }

            var request = URLRequest(url: reqURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let key = authKey, !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }

            var success = false
            var lastError = "desconocido"

            for attempt in 0..<3 {
                do {
                    let (respData, response) = try await URLSession.shared.upload(for: request, from: data)
                    if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                        print("REST API: ✓ \(url.lastPathComponent) → \(http.statusCode)")
                        success = true
                        break
                    } else {
                        let body = String(data: respData, encoding: .utf8) ?? ""
                        lastError = "HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1): \(body.prefix(100))"
                    }
                } catch {
                    lastError = error.localizedDescription
                    print("REST API: retry \(attempt+1)/3 \(url.lastPathComponent): \(lastError)")
                }
                if attempt < 2 { try? await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt)) * 1_000_000_000)) }
            }
            if !success { return .failure(.networkError(lastError)) }
        }
        return .success(())
    }

    func buildConfigView() -> AnyView {
        AnyView(VStack(alignment: .leading, spacing: 8) {
            Text("Endpoint URL").font(.caption).foregroundStyle(.secondary)
            TextField("https://...", text: Binding(get: { self.endpointURL }, set: { self.endpointURL = $0 }))
                .textContentType(.URL).autocorrectionDisabled().textFieldStyle(.roundedBorder)
            Text("API Key (opcional)").font(.caption).foregroundStyle(.secondary)
            SecureField("Bearer token...", text: Binding(get: { self.apiKey ?? "" }, set: { self.apiKey = $0.isEmpty ? nil : $0 }))
                .textFieldStyle(.roundedBorder)
            Text("Dejá la API key vacía si no requiere auth.").font(.caption2).foregroundStyle(.secondary)
        }.padding())
    }
}