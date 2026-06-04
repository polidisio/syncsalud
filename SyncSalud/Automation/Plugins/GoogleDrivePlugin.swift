import Foundation
import SwiftUI

final class GoogleDrivePlugin: ExportPlugin {
    static let shared = GoogleDrivePlugin()

    private let defaults = UserDefaults.standard

    var id: String { "google_drive" }
    var displayName: String { "Google Drive" }

    var apiKey: String {
        get { defaults.string(forKey: "plugin_gdrive_api_key") ?? "" }
        set { defaults.set(newValue, forKey: "plugin_gdrive_api_key") }
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: "plugin_gdrive_enabled") }
        set { defaults.set(newValue, forKey: "plugin_gdrive_enabled") }
    }

    var isConfigured: Bool { !apiKey.isEmpty }

    func run(vaultURLs: [URL]) async -> Result<Void, ExportError> {
        guard isConfigured else { return .failure(.notConfigured("API Key no configurada")) }

        let key = apiKey

        // Find or create SyncSalud folder
        guard let folderId = await findOrCreateFolder(name: "SyncSalud", apiKey: key) else {
            return .failure(.networkError("No se pudo obtener/crear carpeta SyncSalud en Drive"))
        }

        for url in vaultURLs {
            guard let data = try? Data(contentsOf: url) else { continue }
            let fileName = url.lastPathComponent

            let uploadURL = URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=media")!
            var request = URLRequest(url: uploadURL)
            request.httpMethod = "POST"
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            // Upload metadata + content as multipart
            let boundary = UUID().uuidString
            request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

            var body = Data()
            // Part 1: metadata
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
            let meta: [String: Any] = ["name": fileName, "parents": [folderId]]
            body.append((try? JSONSerialization.data(withJSONObject: meta)) ?? Data())
            body.append("\r\n".data(using: .utf8)!)
            // Part 2: content
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Type: application/json\r\n\r\n".data(using: .utf8)!)
            body.append(data)
            body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
            request.httpBody = body

            var success = false
            for attempt in 0..<3 {
                do {
                    let (respData, response) = try await URLSession.shared.data(for: request)
                    if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                        print("Google Drive: ✓ \(fileName)")
                        success = true
                        break
                    } else {
                        let b = String(data: respData, encoding: .utf8) ?? ""
                        print("Google Drive: ✗ \(fileName) → \(b.prefix(80))")
                    }
                } catch {
                    print("Google Drive: retry \(attempt+1)/3 \(fileName): \(error.localizedDescription)")
                }
                if attempt < 2 { try? await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt)) * 1_000_000_000)) }
            }
            if !success { return .failure(.networkError("Fallo al subir \(fileName) a Google Drive")) }
        }
        return .success(())
    }

    private func findOrCreateFolder(name: String, apiKey: String) async -> String? {
        // Search
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        components.queryItems = [
            URLQueryItem(name: "q", value: "name='\(name)' and mimeType='application/vnd.google-apps.folder'"),
            URLQueryItem(name: "spaces", value: "drive"),
            URLQueryItem(name: "fields", value: "files(id,name)")
        ]
        var searchReq = URLRequest(url: components.url!)
        searchReq.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: searchReq)
            if let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let files = parsed["files"] as? [[String: Any]],
               let first = files.first, let fid = first["id"] as? String {
                return fid
            }
        } catch {
            print("Google Drive: folder search error: \(error)")
        }

        // Create
        let createURL = URL(string: "https://www.googleapis.com/drive/v3/files")!
        var createReq = URLRequest(url: createURL)
        createReq.httpMethod = "POST"
        createReq.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        createReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["name": name, "mimeType": "application/vnd.google-apps.folder"]
        createReq.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, _) = try await URLSession.shared.data(for: createReq)
            if let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return parsed["id"] as? String
            }
        } catch {
            print("Google Drive: folder create error: \(error)")
        }
        return nil
    }

    func buildConfigView() -> AnyView {
        AnyView(VStack(alignment: .leading, spacing: 8) {
            Text("Google API Key").font(.caption).foregroundStyle(.secondary)
            SecureField("AIza...", text: Binding(get: { self.apiKey }, set: { self.apiKey = $0 }))
                .textFieldStyle(.roundedBorder)
            Text("Creá una API key en Google Cloud Console → Credentials. Habilitá 'Google Drive API'.")
                .font(.caption2).foregroundStyle(.secondary)
        }.padding())
    }
}