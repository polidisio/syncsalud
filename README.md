# SyncSalud

> App local-first que extrae tus datos de entrenamiento de Apple Health y los sincroniza entre iPhone y Mac para que tus agentes de IA los consulten.

## ¿Qué hace?

- 📱 Lee tus workouts de **Apple Health / HealthKit**
- 💾 Los guarda en **SQLite local** (SwiftData)
- ☁️ Los sincroniza entre iPhone y Mac vía **CloudKit privado** (gratis)
- 🌐 Expone una **API REST local** en macOS (`http://127.0.0.1:8080`) para que tus agentes consulten los datos
- 📄 Permite **exportar a JSON** con un tap
- 🔄 Se sincroniza **al abrir la app**, **con un botón** y **en background** cada N horas

**Costo total: $0** (más el Apple Developer Program si querés distribuir, $99/año).

## Stack

| Capa | Tecnología |
|---|---|
| Cliente | Swift + SwiftUI (iOS 17+ / macOS 14+) |
| Base de datos | SwiftData (SQLite) |
| Sincronización | CloudKit (`NSPersistentCloudKitContainer`) |
| API local | `NWListener` (Network framework) |
| Fuente de datos | HealthKit |
| Background sync | `BGTaskScheduler` |

## Estructura del proyecto

```
SyncSalud/
├── Docs/                        # Documentación
│   ├── PRD.md                   # Product Requirements
│   ├── ARCHITECTURE.md          # Arquitectura técnica
│   ├── DATA_MODEL.md            # Modelo de datos
│   └── IMPLEMENTATION_PLAN.md   # Plan de implementación
└── SyncSalud/                   # Código fuente
    ├── SyncSaludApp.swift       # App entry point
    ├── Models/                  # SwiftData @Model classes
    │   ├── WorkoutRecord.swift
    │   ├── WorkoutMetric.swift
    │   └── SyncLog.swift
    ├── Health/                  # HealthKit integration
    │   └── HealthKitService.swift
    ├── Sync/                    # Lógica de sincronización
    │   ├── HealthSyncManager.swift
    │   └── BackgroundSyncManager.swift
    ├── API/                     # API REST local (macOS)
    │   └── LocalAPIServer.swift
    ├── Export/                  # Exportación JSON
    │   └── JSONExporter.swift
    ├── UI/                      # Vistas SwiftUI
    │   ├── ContentView.swift
    │   ├── DashboardView.swift
    │   ├── WorkoutListView.swift
    │   └── SettingsView.swift
    ├── Info.plist
    └── SyncSalud.entitlements
```

## API Local (macOS)

Una vez que la app está abierta en macOS, tus agentes pueden consultar:

| Endpoint | Descripción |
|---|---|
| `GET /v1/health` | Health check |
| `GET /v1/workouts?type=running&from=...&to=...&limit=50` | Lista de workouts |
| `GET /v1/workouts/{uuid}` | Workout específico |
| `GET /v1/workouts/latest` | Último workout |
| `GET /v1/summary` | Resumen (hoy, semana, mes, racha) |
| `GET /v1/export` | Export completo en JSON |

### Ejemplo desde un agente en el Mac

```bash
# Obtener el último workout
curl http://127.0.0.1:8080/v1/workouts/latest

# Obtener workouts de running de la última semana
curl "http://127.0.0.1:8080/v1/workouts?type=running&limit=10"

# Resumen rápido
curl http://127.0.0.1:8080/v1/summary
```

### Ejemplo desde Python (tu agente)

```python
import requests

response = requests.get("http://127.0.0.1:8080/v1/workouts/latest")
workout = response.json()

print(f"Último entrenamiento: {workout['type']}")
print(f"Duración: {workout['duration']} segundos")
print(f"Calorías: {workout.get('calories', 'N/A')}")
```

## Setup

1. Abrí el proyecto en Xcode 15+
2. Configurá tu Team en los targets iOS y macOS
3. Asegurate de que el iCloud Container esté en tu cuenta
4. Corré en simulador o dispositivo real
5. Habilitá permisos de HealthKit al primer inicio

### Requisitos

- macOS Sonoma (14.0+) con Xcode 15+
- iOS 17+ (iPhone)
- Apple ID con iCloud (para sync entre dispositivos)
- Apple Developer Program (solo si vas a distribuir — $99/año, opcional para uso propio)

## Documentación

- [PRD.md](Docs/PRD.md) — Qué construimos y por qué
- [ARCHITECTURE.md](Docs/ARCHITECTURE.md) — Decisiones técnicas y componentes
- [DATA_MODEL.md](Docs/DATA_MODEL.md) — Modelo de datos SwiftData + HealthKit
- [IMPLEMENTATION_PLAN.md](Docs/IMPLEMENTATION_PLAN.md) — Plan por fases

## Privacidad

- **Todos los datos viven en tu dispositivo y en tu iCloud privado**
- No hay backend, no hay tracking, no hay telemetría
- La API local solo escucha en `127.0.0.1` — no es accesible desde la red
- CloudKit usa el contenedor privado de tu Apple ID (cifrado de extremo a extremo)
- El código está en este repo — auditable y modificable

## Licencia

Uso personal.
