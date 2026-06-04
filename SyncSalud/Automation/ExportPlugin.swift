import Foundation
import SwiftUI

protocol ExportPlugin: Identifiable {
    var id: String { get }
    var displayName: String { get }
    var isEnabled: Bool { get set }
    var isConfigured: Bool { get }
    func run(vaultURLs: [URL]) async -> Result<Void, ExportError>
    func buildConfigView() -> AnyView
}

enum ExportError: Error, LocalizedError {
    case notConfigured(String)
    case networkError(String)
    case authError(String)
    case httpError(Int, String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let msg): return "No configurado: \(msg)"
        case .networkError(let msg): return "Error de red: \(msg)"
        case .authError(let msg): return "Error de auth: \(msg)"
        case .httpError(let code, let msg): return "HTTP \(code): \(msg)"
        case .unknown(let msg): return "Error: \(msg)"
        }
    }
}

struct PluginRunResult: Codable {
    var success: Bool
    var timestamp: Date
    var message: String
    var filesUploaded: Int

    static func ok(message: String, filesUploaded: Int) -> PluginRunResult {
        PluginRunResult(success: true, timestamp: Date(), message: message, filesUploaded: filesUploaded)
    }

    static func fail(message: String) -> PluginRunResult {
        PluginRunResult(success: false, timestamp: Date(), message: message, filesUploaded: 0)
    }
}