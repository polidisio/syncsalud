# ARCHITECTURE — SyncSalud

---

## 1. Arquitectura General

```
┌─────────────────────────────────────────────────────────────┐
│                        iPhone                                │
│  ┌──────────┐    ┌──────────────┐    ┌───────────────────┐  │
│  │ HealthKit │───▶│ SwiftData    │───▶│ CloudKit          │  │
│  │ (workouts)│    │ (SQLite)     │    │ (sync privado)    │  │
│  └──────────┘    └──────────────┘    └─────────┬─────────┘  │
│                                                │             │
└────────────────────────────────────────────────┼─────────────┘
                                                 │ iCloud
┌────────────────────────────────────────────────┼─────────────┐
│                        Mac                     ▼             │
│  ┌──────────┐    ┌──────────────┐    ┌───────────────────┐  │
│  │ HealthKit │───▶│ SwiftData    │◀───│ CloudKit          │  │
│  │ (opcional)│   │ (SQLite)     │    │ (sync privado)    │  │
│  └──────────┘    └──────┬───────┘    └───────────────────┘  │
│                         │                                    │
│                    ┌────▼───────┐     ┌─────────────────┐   │
│                    │ Local API  │────▶│ Agente del      │   │
│                    │ :8080      │     │ usuario         │   │
│                    └────────────┘     └─────────────────┘   │
│                         │                                    │
│                    ┌────▼───────┐                            │
│                    │ Export     │ ◀── Botón en UI            │
│                    │ JSON       │                            │
│                    └────────────┘                            │
└──────────────────────────────────────────────────────────────┘
```

---

## 2. Componentes

### 2.1 HealthKit Service (iOS + macOS)

**Propósito:** Leer workouts desde HealthKit, manejar permisos, observar cambios en tiempo real.

**Responsabilidades:**
- Solicitar autorización de HealthKit al primer inicio
- Leer histórico completo de workouts
- Observar nuevos workouts mediante `HKObserverQuery`
- Manejar errores de permisos y disponibilidad
- Mapear tipos de HKWorkout a modelos propios

**Patrón:** Service + protocol (facilita testing con mocks)

### 2.2 SwiftData / SQLite

**Propósito:** Fuente de verdad local. Almacenamiento persistente sincronizable.

**Responsabilidades:**
- Modelar workouts y métricas asociadas
- Proveer queries para la API local
- Manejar migraciones de esquema
- Marcar registros con `syncStatus` para control de sincronización

**Framework elegido:** SwiftData sobre SQLite, con `NSPersistentCloudKitContainer` para sync.

### 2.3 CloudKit Sync

**Propósito:** Sincronizar datos entre iPhone y Mac sin servidor.

**Mecanismo:**
- `NSPersistentCloudKitContainer` sincroniza automáticamente el SQLite via CloudKit privado
- Usa el contenedor privado de iCloud del usuario (no requiere suscripción)
- Datos visibles solo en dispositivos del mismo Apple ID
- Latencia típica: segundos a minutos entre dispositivos

**Requisito:** El usuario debe tener iCloud iniciado sesión en ambos dispositivos.

### 2.4 Local API Server (solo macOS)

**Propósito:** Exponer datos de entrenamiento via HTTP local para agentes externos.

**Tecnología:** `NWListener` (Network framework de Apple) o Vapor embebido.

**Endpoints:**

| Método | Ruta | Descripción |
|---|---|---|
| `GET` | `/v1/health` | Health check del servidor |
| `GET` | `/v1/workouts` | Lista de workouts (paginada, filtrable) |
| `GET` | `/v1/workouts/:id` | Workout individual con métricas |
| `GET` | `/v1/workouts/range?from=&to=` | Workouts en rango de fechas |
| `GET` | `/v1/summary` | Resumen de actividad (hoy, semana, mes) |
| `GET` | `/v1/workouts/latest` | Último workout registrado |
| `GET` | `/v1/export` | Exportar todo a JSON (descarga) |

**Query params en `/v1/workouts`:**
- `type` — filtrar por tipo (running, cycling, swimming, etc.)
- `from` / `to` — rango de fechas (ISO 8601)
- `limit` / `offset` — paginación

**Seguridad:** Solo escucha en `127.0.0.1:8080`. Sin autenticación (es local). El servidor se inicia automáticamente al abrir la app en macOS y se detiene al cerrarla.

### 2.5 JSON Exporter

**Propósito:** Exportar datos a JSON para respaldo o procesamiento offline.

**Formato de salida:**
```json
{
  "exportedAt": "2026-06-03T10:00:00Z",
  "source": "SyncSalud",
  "version": "1.0",
  "workouts": [...],
  "summary": {
    "totalWorkouts": 123,
    "dateRange": { "from": "...", "to": "..." }
  }
}
```

### 2.6 Background Sync Manager

**Propósito:** Ejecutar sincronización programada incluso cuando la app no está en primer plano.

**Tecnología:** `BGTaskScheduler` en iOS.

**Configuración por defecto:** Sincronizar cada 6 horas (configurable en Settings).

---

## 3. Decisiones Arquitectónicas (ADRs)

### ADR-1: SwiftData vs Core Data

| Aspecto | SwiftData | Core Data |
|---|---|---|
| Sintaxis | Moderna, Swift native | Verbosa, Obj-C legacy |
| CloudKit sync | Nativo via `NSPersistentCloudKitContainer` | Nativo | 
| Thread safety | Automático (MainActor) | Manual |
| Migraciones | Automáticas (cambios compatibles) | Manual |

**Decisión:** SwiftData. Es el futuro de Apple, más simple, y soporta CloudKit sync nativamente.

### ADR-2: Local API con framework liviano

**Opción A: Vapor embebido** — Framework completo, routing declarativo, pero agrega ~10MB a la app.
**Opción B: `NWListener` + `Codable`** — Sin dependencias, liviano, pero más código manual.
**Opción C: `Swifter`** — Mini HTTP server en Swift. ~500 líneas.

**Decisión:** Vapor embebido en modo liviano (solo los módulos necesarios: Routing + HTTP). Es mantenible, extensible y bien documentado.

### ADR-3: No usar CloudKit como fuente de verdad

CloudKit es el canal de transporte, no la base primaria. SwiftData (SQLite local) es la fuente de verdad. Esto asegura:
- Funcionamiento offline
- Control de migraciones
- Que la app funcione sin iCloud (simplemente no sincroniza)

---

## 4. Alternativas Descartadas

### Opción A: Backend Supabase
Descartada por requerimiento de $0 y local-first. Agrega latencia, dependencia de internet, y costo mensual.

### Opción B: Firebase / Firestore
Descartada por vendor lock-in, costo variable, y requerimiento de cuenta Google. No tiene sincronización nativa con HealthKit.

### Opción C: Realm
Descartada porque MongoDB abandonó Realm para Swift. SwiftData es el reemplazo natural de Apple.

### Opción D: gRPC para la API local
Sobredimensionado para comunicación localhost. HTTP REST es más simple, debuggable, y compatible con cualquier lenguaje.
