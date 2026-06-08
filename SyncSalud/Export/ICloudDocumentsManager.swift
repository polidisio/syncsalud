import Foundation
#if os(iOS)
import UIKit
#endif

/// Manager para acceder a iCloud Drive Documents usando DocumentPicker (más confiable)
final class ICloudDocumentsManager {
    static let shared = ICloudDocumentsManager()

    private let syncSaludFolderName = "SyncSalud"

    private init() {}

    // MARK: - iCloud Status (más flexible)

    /// Verifica si iCloud Drive parece estar configurado
    /// Usamos una verificación más flexible: solo el token
    var isICloudDriveConfigured: Bool {
        return FileManager.default.ubiquityIdentityToken != nil
    }

    /// Mensaje de diagnóstico
    func diagnosticStatus() -> String {
        let token = FileManager.default.ubiquityIdentityToken != nil
        return "iCloud token: \(token)"
    }

    /// Sugiere fixes basado en el estado actual
    func checkAndSuggestFixes() -> String {
        if FileManager.default.ubiquityIdentityToken == nil {
            return """
            iCloud no está disponible. Verificá:
            1. Estés logueado en tu cuenta Apple (Ajustes > [tu nombre])
            2. iCloud Drive esté habilitado: Ajustes > [tu nombre] > iCloud > iCloud Drive
            """
        }
        return "iCloud OK"
    }

    // MARK: - Para uso con ShareSheet

    /// Prepara un archivo JSON para guardar en iCloud via ShareSheet
    /// Retorna la URL del archivo temporal en Documents
    func prepareFileForSharing(fileName: String, jsonData: Data) -> URL? {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileURL = documentsPath.appendingPathComponent(fileName)

        do {
            try jsonData.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            print("Error guardando archivo para compartir: \(error)")
            return nil
        }
    }
}