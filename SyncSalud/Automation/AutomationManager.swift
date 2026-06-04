import Foundation
import SwiftData
import SwiftUI

/// Singleton que orquesta los plugins de automatización.
///after cada refresh del vault, corre todos los plugins habilitados.
final class AutomationManager {
    static let shared = AutomationManager()

    private init() {}

    // MARK: - Plugin registry

    var plugins: [any ExportPlugin] {
        [
            RESTAPIPlugin(),
            HomeAssistantPlugin(),
            GoogleDrivePlugin(),
            DropboxPlugin(),
            ICloudAutomationPlugin()
        ]
    }

    // MARK: - Run after vault refresh

    /// Llamado por VaultManager tras escribir los snapshots y guardar el index.
    /// - Parameter writtenURLs: URLs de los archivos que se acaban de escribir.
    func afterVaultRefresh(writtenURLs: [URL]) async {
        guard isAutomationEnabled else { return }
        for plugin in plugins where plugin.isEnabled {
            let result = await plugin.run(vaultURLs: writtenURLs)
            saveResult(pluginId: plugin.id, result: result)
        }
    }

    // MARK: - Run manually

    func runNow(pluginId: String, vaultURLs: [URL]) async {
        guard let plugin = plugins.first(where: { $0.id == pluginId }) else { return }
        let result = await plugin.run(vaultURLs: vaultURLs)
        saveResult(pluginId: plugin.id, result: result)
    }

    // MARK: - Vault URLs

    var currentVaultURLs: [URL] {
        let months = VaultManager.shared.availableMonths()
        return months.compactMap { VaultManager.shared.readMonth($0) }
    }

    // MARK: - Master toggle

    var isAutomationEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "automation_enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "automation_enabled") }
    }

    // MARK: - Result persistence

    private func resultKey(for pluginId: String) -> String {
        "plugin_result_\(pluginId)"
    }

    func lastResult(for pluginId: String) -> PluginRunResult? {
        guard let data = UserDefaults.standard.data(forKey: resultKey(for: pluginId)) else { return nil }
        return try? JSONDecoder().decode(PluginRunResult.self, from: data)
    }

    private func saveResult(pluginId: String, result: Result<Void, ExportError>) {
        let runResult: PluginRunResult
        switch result {
        case .success:
            runResult = .ok(message: "OK", filesUploaded: 0)
        case .failure(let error):
            runResult = .fail(message: error.localizedDescription)
        }
        if let data = try? JSONEncoder().encode(runResult) {
            UserDefaults.standard.set(data, forKey: resultKey(for: pluginId))
        }
    }

    // MARK: - Plugin state helpers

    func setEnabled(_ enabled: Bool, for pluginId: String) {
        UserDefaults.standard.set(enabled, forKey: "plugin_\(pluginId)_enabled")
    }

    func isEnabled(pluginId: String) -> Bool {
        UserDefaults.standard.bool(forKey: "plugin_\(pluginId)_enabled")
    }
}

// MARK: - iCloud plugin (reuses existing VaultManager state)

final class ICloudAutomationPlugin: ExportPlugin {
    var id: String { "icloud" }
    var displayName: String { "iCloud Drive" }

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "plugin_icloud_enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "plugin_icloud_enabled") }
    }

    var isConfigured: Bool { VaultManager.shared.isICloudMirroring }

    func run(vaultURLs: [URL]) async -> Result<Void, ExportError> {
        return .success(())
    }

    func buildConfigView() -> AnyView { AnyView(EmptyView()) }
}