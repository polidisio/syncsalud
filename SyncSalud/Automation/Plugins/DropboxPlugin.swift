import Foundation
import SwiftUI

final class DropboxPlugin: ExportPlugin {
    static let shared = DropboxPlugin()

    private let defaults = UserDefaults.standard

    var id: String { "dropbox" }
    var displayName: String { "Dropbox" }

    var accessToken: String {
        get { defaults.string(forKey: "plugin_dropbox_access_token") ?? "" }
        set { defaults.set(newValue, forKey: "plugin_dropbox_access_token") }
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: "plugin_dropbox_enabled") }
        set { defaults.set(newValue, forKey: "plugin_dropbox_enabled") }
    }

    var isConfigured: Bool { !accessToken.isEmpty }

    func run(vaultURLs: [URL]) async -> Result<Void, ExportError> {
        guard isConfigured else { return .failure(.notConfigured("Access token no configurado")) }

        let token = accessToken

        // Ensure /SyncSalud exists
        do {
            try await ensureFolder(path: "/SyncSalud", token: token)
        } catch {
            return .failure(.networkError("No se pudo crear carpeta SyncSalud en Dropbox"))
        }

        for url in vaultURLs {
            guard let data = try? Data(contentsOf: url) else { continue }
            let filePath = "/SyncSalud/\(url.lastPathComponent)"

            let uploadURL = URL(string: "https://content.dropboxapi.com/2/files/upload")!
            var request = URLRequest(url: uploadURL)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

            let arg: [String: Any] = ["path": filePath, "mode": "overwrite", "autorename": false, "mute": true]
            request.setValue(String(data: try! JSONSerialization.data(withJSONObject: arg), encoding: .utf8)!, forHTTPHeaderField: "Dropbox-API-Arg")

            var success = false
            for attempt in 0..<3 {
                do {
                    let (_, response) = try await URLSession.shared.upload(for: request, from: data)
                    if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                        print("Dropbox: ✓ \(url.lastPathComponent)")
                        success = true
                        break
                    }
                } catch {
                    print("Dropbox: retry \(attempt+1)/3 \(url.lastPathComponent): \(error.localizedDescription)")
                }
                if attempt < 2 { try? await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt)) * 1_000_000_000)) }
            }
            if !success { return .failure(.networkError("Fallo al subir \(url.lastPathComponent) a Dropbox")) }
        }
        return .success(())
    }

    private func ensureFolder(path: String, token: String) async throws {
        let listURL = URL(string: "https://api.dropboxapi.com/2/files/list_folder")!
        var req = URLRequest(url: listURL)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["path": path])

        let (data, response) = try await URLSession.shared.data(for: req)
        let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        if parsed?["error"] != nil {
            // Create folder
            let createURL = URL(string: "https://api.dropboxapi.com/2/files/create_folder_v2")!
            var createReq = URLRequest(url: createURL)
            createReq.httpMethod = "POST"
            createReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            createReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            createReq.httpBody = try JSONSerialization.data(withJSONObject: ["path": path, "autorename": false])
            let (_, createResponse) = try await URLSession.shared.data(for: createReq)
            if let http = createResponse as? HTTPURLResponse, http.statusCode != 200 {
                throw NSError(domain: "Dropbox", code: http.statusCode)
            }
        }
    }

    func buildConfigView() -> AnyView {
        AnyView(VStack(alignment: .leading, spacing: 8) {
            Text("Dropbox Access Token").font(.caption).foregroundStyle(.secondary)
            SecureField("sl.B...", text: Binding(get: { self.accessToken }, set: { self.accessToken = $0 }))
                .textFieldStyle(.roundedBorder)
            Text("Generá un token en https://www.dropbox.com/developers/apps → OAuth 2 → Generated access token.")
                .font(.caption2).foregroundStyle(.secondary)
        }.padding())
    }
}