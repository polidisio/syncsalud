import Foundation
import CoreData
import Observation

/// Observa las notificaciones de NSPersistentCloudKitContainer para exponer el
/// estado de la sincronización con iCloud del store de SwiftData/CloudKit.
/// Funciona aunque el container lo administre SwiftData internamente, ya que
/// la notificación es global y no requiere una referencia directa al container.
@Observable
final class CloudSyncStatusMonitor {
    private(set) var lastSuccessfulSync: Date?
    private(set) var lastError: String?
    private(set) var isSyncing = false

    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handle(notification: notification)
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func handle(notification: Notification) {
        guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else {
            return
        }

        guard event.endDate != nil else {
            isSyncing = true
            return
        }

        isSyncing = false

        if let error = event.error {
            lastError = error.localizedDescription
        } else if event.succeeded {
            lastError = nil
            lastSuccessfulSync = event.endDate
        }
    }
}
