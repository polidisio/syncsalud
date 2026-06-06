# CLAUDE.md — SyncSalud

> App local-first que extrae datos de entrenamiento de Apple Health y los sincroniza entre iPhone y Mac para que agentes de IA los consulten.

---

## Proyecto

**Nombre:** SyncSalud
**Tipo:** App nativa (iOS + macOS)
**Descripción:** Lee workouts de Apple Health → guarda en SQLite (SwiftData) → sincroniza entre dispositivos via CloudKit privado → expone API REST local en macOS (`127.0.0.1:8080`) para agentes externos.
**Repo:** `https://github.com/polidisio/syncsalud`
**Owner:** @polidisio

---

## Tech Stack

| Capa | Tecnología |
|------|------------|
| Cliente | Swift 5.9 + SwiftUI (iOS 17+ / macOS 14+) |
| Base de datos | SwiftData (SQLite) |
| Sincronización | CloudKit (`NSPersistentCloudKitContainer`) — contenedor privado, gratis |
| API local | `NWListener` (Network framework) en macOS, puerto `8080` |
| Fuente de datos | HealthKit |
| Background sync | `BGTaskScheduler` (iOS) |
| Reports | Resend (email mensual) |

**Targets Xcode:**
- `SyncSalud iOS` → `com.saraiba.syncsalud.app`
- `SyncSaludMac` → `com.saraiba.syncsalud.mac`
- Development Team: `DQ7D6387N8`

---

## Estructura del Proyecto

```
syncsalud/
├── Docs/
│   ├── PRD.md              # Product Requirements
│   ├── ARCHITECTURE.md      # Arquitectura técnica (leer primero)
│   ├── DATA_MODEL.md        # Modelo de datos SwiftData + HealthKit
│   └── IMPLEMENTATION_PLAN.md
├── SyncSalud/
│   ├── SyncSaludApp.swift   # Entry point
│   ├── Models/
│   │   ├── WorkoutRecord.swift   # Entidad principal
│   │   ├── WorkoutMetric.swift   # Métricas por intervalo (opcional)
│   │   └── SyncLog.swift         # Auditoría de sync
│   ├── Health/
│   │   └── HealthKitService.swift  # Lectura de workouts
│   ├── Sync/
│   │   ├── HealthSyncManager.swift    # Sync HealthKit → SwiftData
│   │   └── BackgroundSyncManager.swift # BGTaskScheduler
│   ├── API/
│   │   └── LocalAPIServer.swift   # NWListener — solo macOS
│   ├── Export/
│   │   └── JSONExporter.swift
│   └── UI/
│       ├── ContentView.swift
│       ├── DashboardView.swift
│       ├── WorkoutListView.swift
│       └── SettingsView.swift
└── CLAUDE.md  # ← este archivo
```

---

## API Local (macOS)

La API corre en `http://127.0.0.1:8080`. Solo escucha en localhost — no es accesible desde la red.

**Endpoints:**

| Método | Ruta | Descripción |
|--------|------|-------------|
| GET | `/v1/health` | Health check |
| GET | `/v1/workouts` | Lista (params: `type`, `from`, `to`, `limit`, `offset`) |
| GET | `/v1/workouts/:uuid` | Workout individual |
| GET | `/v1/workouts/latest` | Último workout |
| GET | `/v1/workouts/range?from=&to=` | Rango de fechas |
| GET | `/v1/summary` | Resumen (hoy, semana, mes, racha) |
| GET | `/v1/export` | Export completo a JSON |

**Ejemplo de uso (agente):**
```bash
curl http://127.0.0.1:8080/v1/workouts/latest
curl "http://127.0.0.1:8080/v1/workouts?type=running&limit=10"
curl http://127.0.0.1:8080/v1/summary
```

---

## Modelo de Datos

**WorkoutRecord** (principal):
- `id` (UUID PK), `workoutType` (String), `startDate`, `endDate`, `duration`
- `calories`?, `distance`?, `distanceUnit`?
- `avgHeartRate`?, `maxHeartRate`?, `minHeartRate`?
- `source`, `healthKitID` (para dedup), `metadata` (JSON blob)
- `syncStatus`: `"synced"` | `"pending"` | `"failed"`

**WorkoutMetric** (opcional, por intervalo):
- `heartRate`, `cadence`, `speed`, `power`, `altitude`, `locationLat/Lng`

**Deduplicación:** Se usa `healthKitID` (UUID de HealthKit). Si ya existe, se actualiza en vez de insertar.

---

## Patrones de Prompting (Boris/Claude Code)

### Para features nuevas:
```
"Before you write code, make a plan and run it by me for approval."
```

### Para iteración con tests:
```
"Build this feature and run the test suite. Iterate until all tests pass."
```

### Para commits automáticos:
```
"I want to think with this one, this commit push here."
```

---

## Workflow

### Para tareas simples
Sé directo: "Añade validación al form" — no necesitas explicar contexto.

### Para tareas complejas (>3 pasos)
1. Agent propone plan primero
2. Usuario confirma
3. Agent ejecuta
4. Agent verifica con tests

### Para cada tarea
1. **Plan** → Si son >3 pasos, escribir en `tasks/todo.md`
2. **Verify** → Confirmar antes de cambios grandes
3. **Execute** → Cambio más pequeño posible
4. **Test** → Ejecutar tests, verificar regression
5. **Document** → Actualizar si es necesario

---

## Code Quality

### SIEMPRE
- Código legible y mantenible
- Seguir convenciones Swift (async/await, optionals, SwiftData macros)
- DRY — no duplicar lógica
- Validar input antes de procesar
- Manejar errores de HealthKit (permisos, disponibilidad)

### NUNCA
- Hardcodear credenciales o tokens — usar environment variables
- "Hacky fixes" sin justificación
- Duplicar código sin razón
- Commits sin mensaje descriptivo
- Subir carpetas enteras al contexto — solo archivos necesarios

---

## Seguridad

- **NUNCA hardcodear** credenciales — usar `.env` y nunca commitearlo
- **NUNCA exponer** tokens en logs o errores
- La API local solo escucha en `127.0.0.1` — no exponer a red
- Resend API key: configurar via environment variable

---

## Recursos

**Documentación del proyecto:**
- `Docs/ARCHITECTURE.md` — Arquitectura y ADRs (leer antes de tocar código)
- `Docs/DATA_MODEL.md` — Modelo de datos completo

**Vault Saraiba (contexto personal):**
- `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Saraiba/`
- Skills en: `~/.hermes/skills/`

---

## Agente SyncSalud Coach

El agente que conecta con la API:
- Script: `~/.hermes/scripts/syncsalud/send_monthly_report.py`
- API endpoint: `http://192.168.1.201:8080/v1` (fallback: vault snapshot)
- Resumen en español → Telegram + Obsidian

---

## Contacto

**Jose Maudisio** — @polidisio
**Issues:** Abrir en GitHub o preguntar en Telegram

---

*Último actualizado: 2026-06-06*
*Basado en video de Boris (Anthropic) + documentación del proyecto*