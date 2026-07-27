# Changelog

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.0.0/).

## [Unreleased]

### Fixed
- `BackgroundSyncManager`: el toggle "Sincronización en background" no persistía entre relanzamientos de la app. `BGTaskScheduler.register()` se llamaba de nuevo en cada cambio del toggle además de en el arranque, lo cual es inválido en iOS y reseteaba la preferencia. Ahora el registro ocurre una sola vez al arranque (`SyncAppDelegate`) y el setter solo agenda/cancela la tarea.
- Background sync de HealthKit ahora viene activado por defecto en instalaciones nuevas.
- `VaultSectionView`: `loadState()` era código muerto — la sección Vault aparecía vacía hasta hacer refresh manual.
- `project.yml`: los targets iOS y macOS no tenían `SDKROOT` explícito. Con dos targets de plataforma distinta en el mismo proyecto, XcodeGen 2.45.4 no infiere el SDK por target, y Xcode resolvía el target iOS como macOS (el scheme "Synctrackers iOS" solo ofrecía destino "My Mac"). Bloqueaba cualquier build/archive de iOS. Agregado `SDKROOT: iphoneos` / `SDKROOT: macosx` por target.

### Added
- `CloudSyncStatusMonitor`: observa las notificaciones de evento de `NSPersistentCloudKitContainer` y lo muestra en Settings ("sincronizado hace Xm" / error) en vez de asumir que el sync funcionó.
- Vault: resumen colapsado (total de workouts, tamaño, último mes) con toggle "ver todos los meses" en lugar de renderizar todos los meses siempre.

### Removed
- Dos `.entitlements` huérfanos (`SyncSalud-macOS.entitlements`, `Synctrackers.entitlements`) que `project.yml` no referenciaba.
