import SwiftUI

struct AutomationsSection: View {
    @State private var masterEnabled: Bool = UserDefaults.standard.bool(forKey: "automation_enabled")
    @State private var showConfigPlugin: String?
    @State private var showConfig: Bool = false
    @State private var isRunning: Set<String> = []

    private var plugins: [any ExportPlugin] {
        AutomationManager.shared.plugins
    }

    var body: some View {
        Section {
            Toggle("Habilitar automatizaciones", isOn: $masterEnabled)
                .onChange(of: masterEnabled) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: "automation_enabled")
                }

            if masterEnabled {
                ForEach(plugins, id: \.id) { plugin in
                    pluginRow(plugin)
                }
            }
        } header: {
            Text("Automatizaciones")
        } footer: {
            Text("Después de cada refresh del vault, las automatizaciones seleccionadas envían los archivos a los servicios configurados.")
                .font(.caption2)
        }
        .sheet(isPresented: $showConfig) {
            if let pluginId = showConfigPlugin,
               let plugin = plugins.first(where: { $0.id == pluginId }) {
                PluginConfigSheet(plugin: plugin)
            }
        }
    }

    @ViewBuilder
    private func pluginRow(_ plugin: any ExportPlugin) -> some View {
        let pluginId = plugin.id
        let isEnabled = UserDefaults.standard.bool(forKey: "plugin_\(pluginId)_enabled")
        let lastResult = AutomationManager.shared.lastResult(for: pluginId)

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: iconFor(plugin.id))
                    .foregroundStyle(colorFor(plugin.id))
                    .frame(width: 20)

                Text(plugin.displayName)
                    .font(.subheadline)

                Spacer()

                Toggle("", isOn: Binding(
                    get: { isEnabled },
                    set: { newValue in
                        UserDefaults.standard.set(newValue, forKey: "plugin_\(pluginId)_enabled")
                    }
                ))
                .labelsHidden()
                .disabled(!masterEnabled)
            }

            HStack(spacing: 8) {
                statusBadge(pluginId: pluginId, lastResult: lastResult)

                Spacer()

                Button {
                    Task {
                        isRunning.insert(pluginId)
                        await AutomationManager.shared.runNow(pluginId: pluginId, vaultURLs: AutomationManager.shared.currentVaultURLs)
                        isRunning.remove(pluginId)
                    }
                } label: {
                    if isRunning.contains(pluginId) {
                        ProgressView().scaleEffect(0.6)
                    } else {
                        Text("Ejecutar")
                    }
                }
                .font(.caption2)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!masterEnabled || !plugin.isConfigured)

                Button("Configurar") {
                    showConfigPlugin = pluginId
                    showConfig = true
                }
                .font(.caption2)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!plugin.isConfigured)
            }
        }
        .padding(.vertical, 4)
    }

    private func statusBadge(pluginId: String, lastResult: PluginRunResult?) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(lastResult == nil ? Color.gray : (lastResult!.success ? Color.green : Color.red))
                .frame(width: 6, height: 6)

            if let result = lastResult {
                Text(result.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if !result.message.isEmpty && result.message != "OK" {
                    Text("· \(result.message)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("Nunca ejecutado")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func iconFor(_ pluginId: String) -> String {
        switch pluginId {
        case "rest_api": return "globe"
        case "home_assistant": return "house.fill"
        case "google_drive": return "folder.fill"
        case "dropbox": return "shippingbox.fill"
        case "icloud": return "icloud.fill"
        default: return "square.grid.2x2"
        }
    }

    private func colorFor(_ pluginId: String) -> Color {
        switch pluginId {
        case "rest_api": return .blue
        case "home_assistant": return .orange
        case "google_drive": return .green
        case "dropbox": return .indigo
        case "icloud": return .cyan
        default: return .secondary
        }
    }
}

struct PluginConfigSheet: View {
    @Environment(\.dismiss) private var dismiss
    let plugin: any ExportPlugin

    var body: some View {
        NavigationStack {
            plugin.buildConfigView()
                .navigationTitle(plugin.displayName)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Listo") { dismiss() }
                    }
                }
        }
    }
}