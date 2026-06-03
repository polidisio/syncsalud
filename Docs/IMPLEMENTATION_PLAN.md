# IMPLEMENTATION PLAN — SyncSalud

---

## Fase 1: MVP Funcional (2-3 semanas)

### Objetivo
App que lee workouts de HealthKit, los guarda en SQLite, los sincroniza via CloudKit entre iPhone y Mac, y expone API local + export JSON.

### Semana 1 — Fundación

| Día | Tarea | Archivos | Dependencias |
|---|---|---|---|
| 1-2 | **Proyecto Xcode + Configuración** | `SyncSaludApp.swift`, `Info.plist` | — |
| | Crear target iOS + macOS (SwiftUI) | | |
| | Configurar entitlements (HealthKit, iCloud, Network) | | |
| | Configurar SwiftData + CloudKit container | | |
| 2-3 | **Modelos SwiftData** | `Models/WorkoutRecord.swift`, `Models/WorkoutMetric.swift`, `Models/SyncLog.swift` | Día 1-2 |
| | Definir `@Model` classes | | |
| | Configurar `NSPersistentCloudKitContainer` | | |
| | Prueba: insertar registro y verificar persistencia | | |
| 3-4 | **HealthKit Service** | `Health/HealthKitService.swift`, `Health/HealthKitAuthorizationView.swift` | Día 2-3 |
| | Solicitar autorización HealthKit | | |
| | Leer histórico completo (`HKSampleQuery`) | | |
| | Mapeo HKWorkout → WorkoutRecord | | |
| | Deduplicación por `healthKitID` | | |
| 5 | **Sync Manager** | `Sync/HealthSyncManager.swift` | Día 3-4 |
| | Sincronizar al abrir la app | | |
| | Botón "Sincronizar ahora" | | |
| | Observer para nuevos workouts en HealthKit | | |
| 5-6 | **UI Básica** | `UI/DashboardView.swift`, `UI/WorkoutListView.swift` | Día 3-4 |
| | Dashboard: total de entrenamientos, calorías, racha | | |
| | Lista de workouts con filtro por tipo | | |
| | Pull-to-refresh para sincronizar | | |
| 7 | **Settings + Permisos** | `UI/SettingsView.swift` | Día 3-4 |
| | Botón "Conectar HealthKit" | | |
| | Preferencias de sincronización | | |
| | Información del sistema | | |

### Semana 2 — API Local + Export + Background Sync

| Día | Tarea | Archivos | Dependencias |
|---|---|---|---|
| 8-9 | **Local API Server** | `API/LocalAPIServer.swift`, `API/WorkoutRoutes.swift` | Día 5-6 |
| | Servidor HTTP en `127.0.0.1:8080` | | |
| | Endpoints del modelo de datos | | |
| | Arrancar/parar con el ciclo de vida de la app | | |
| | Solo en macOS | | |
| 10 | **JSON Exporter** | `Export/JSONExporter.swift` | Día 5-6 |
| | Exportar todos los workouts a JSON | | |
| | Share Sheet / guardar archivo | | |
| | Formato documentado | | |
| 11 | **Background Sync (iOS)** | `Sync/BackgroundSyncManager.swift` | Día 5-6 |
| | `BGTaskScheduler` para sync periódica | | |
| | Configurar intervalo (default: 6h) | | |
| | Manejar wake-up en background | | |
| 12 | **Pruebas de integración** | | Todo lo anterior |
| | Probar sync iPhone → Mac via CloudKit | | |
| | Probar API local desde terminal (`curl`) | | |
| | Probar export JSON | | |
| 13 | **Bugs + Pulido** | Varios | Día 12 |
| | Manejo de casos edge (sin permisos, sin iCloud, sin internet) | | |
| | Estados vacíos, errores, loading states | | |
| 14 | **Documentación API + README** | `README.md` | Día 13 |
| | Documentar endpoints de la API local | | |
| | Instrucciones de setup | | |

### Semana 3 — Pulido macOS + Estabilidad

| Día | Tarea | Descripción |
|---|---|---|
| 15 | **Adaptación macOS** | UI responsive para Mac (menú, ventanas, toolbar) |
| 16-17 | **Control de errores** | Logging, SyncLog, recovery de fallos de HealthKit |
| 18-19 | **Testing** | Pruebas manuales en ambos dispositivos, edge cases |
| 20-21 | **Documentación final + release** | Build, firmado, documentación completa |

---

## Fase 2: Escalable (post-MVP)

| Item | Descripción | Prioridad |
|---|---|---|
| Dashboard avanzado | Gráficos, tendencias semanales, comparativas | Alta |
| WorkoutMetric detallado | Heart rate por intervalo del workout | Media |
| Filtros avanzados API | Por tipo, fecha, duración mínima/máxima | Media |
| Webhook endpoint | La app puede enviar datos a una URL externa | Baja |
| Widget iOS | Ver resumen de entrenamiento semanal | Baja |
| Apple Watch SDK | Leer workouts directamente desde el Watch | Baja |

---

## 2. Configuración Inicial del Proyecto

### 2.1 Xcode Project Setup

- **Template:** Multiplatform App (iOS + macOS)
- **Minimum deployments:** iOS 17+, macOS 14+ (requisito de SwiftData)
- **Team:** Cuenta de Apple Developer (para HealthKit y CloudKit)

### 2.2 Entitlements Necesarios

| Entitlement | Propósito |
|---|---|
| `com.apple.developer.healthkit` | Leer datos de HealthKit |
| `com.apple.developer.healthkit.access` | Para lectura en background (opcional) |
| `com.apple.developer.ubiquity-kvstore` | iCloud Key-Value (para settings) |
| `com.apple.developer.icloud-container` | CloudKit container |
| `com.apple.developer.networking.networkextension` | Para NWListener (API local, macOS) |

### 2.3 Info.plist Keys

```xml
<key>NSHealthShareUsageDescription</key>
<string>SyncSalud necesita acceso a tus datos de entrenamiento para sincronizarlos con tus agentes.</string>
<key>NSHealthUpdateUsageDescription</key>
<string>SyncSalud necesita permiso para leer tus datos de salud.</string>
```

---

## 3. Dependencias Externas

| Librería | Propósito | Método | ¿Obligatoria? |
|---|---|---|---|
| Vapor (Routing + HTTP) | API local en macOS | SPM | **Sí** (MVP) |
| No más dependencias en v1. Todo el resto es nativo de Apple. | | | |

Si se quiere evitar Vapor, se puede implementar la API con `NWListener` + `Codable`, pero agregaría ~3-4 días de desarrollo.

---

## 4. Timeline Estimado

| Hito | Tiempo | Resultado |
|---|---|---|
| MVP (Fase 1) | 3 semanas | App funcional: HealthKit → SwiftData → CloudKit → API + JSON |
| Fase 2 | +4-6 semanas | Dashboard avanzado, métricas detalladas, webhooks |
| Producción estable | 8-10 semanas | App completa y pulida |

---

## 5. Riesgos y Mitigaciones

| Riesgo | Probabilidad | Impacto | Mitigación |
|---|---|---|---|
| CloudKit sync lento o falla intermitente | Media | Alto | Logging detallado, botón de re-sync manual, indicador de estado |
| Permisos de HealthKit denegados | Alta | Alto | UI clara pidiendo permisos, estado de "sin conexión" graceful |
| Background sync no se ejecuta (iOS restrictions) | Media | Medio | Sincronización al abrir la app como fallback siempre disponible |
| SwiftData + CloudKit bugs en versiones nuevas de iOS | Baja | Alto | Testing en beta, mantener opción de export JSON como backup |
| API local en macOS bloqueada por firewall | Baja | Medio | Solo escucha en localhost, documentar configuración |
