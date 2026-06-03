# DATA MODEL — SyncSalud

---

## 1. Modelo de Datos (SwiftData)

### 1.1 `WorkoutRecord`

Entidad principal que representa un entrenamiento individual.

| Atributo | Tipo | Descripción | Ejemplo |
|---|---|---|---|
| `id` | `UUID` (PK) | Identificador único | `"E621E1F8-C36C-495A-93FC-0C247A3E6E5F"` |
| `workoutType` | `String` | Tipo de entrenamiento (HKWorkoutActivityType rawValue) | `"running"` |
| `startDate` | `Date` | Inicio del entrenamiento | `2026-06-03T07:30:00Z` |
| `endDate` | `Date` | Fin del entrenamiento | `2026-06-03T08:15:00Z` |
| `duration` | `Double` | Duración en segundos | `2700.0` |
| `calories` | `Double?` | Calorías activas (kcal) | `320.5` |
| `distance` | `Double?` | Distancia en metros | `5000.0` |
| `distanceUnit` | `String?` | Unidad de distancia | `"meters"` |
| `avgHeartRate` | `Double?` | Frecuencia cardíaca promedio (bpm) | `145.0` |
| `maxHeartRate` | `Double?` | Frecuencia cardíaca máxima (bpm) | `172.0` |
| `minHeartRate` | `Double?` | Frecuencia cardíaca mínima (bpm) | `98.0` |
| `source` | `String` | Origen del dato | `"healthkit"` |
| `healthKitID` | `String?` | UUID del workout en HealthKit (para dedup) | `"HKUUID..."` |
| `metadata` | `Data?` | JSON blob con datos extras | `{"weather": "sunny"}` |
| `createdAt` | `Date` | Fecha de creación en SyncSalud | |
| `updatedAt` | `Date` | Última modificación | |
| `syncStatus` | `String` | Estado de sync: `"synced"`, `"pending"`, `"failed"` | |

### 1.2 `WorkoutMetric`

Métricas detalladas asociadas a un workout (datos por intervalo, opcional).

| Atributo | Tipo | Descripción |
|---|---|---|
| `id` | `UUID` (PK) | Identificador único |
| `workout` | `WorkoutRecord` (FK) | Workout padre |
| `timestamp` | `Date` | Momento de la medición |
| `heartRate` | `Double?` | Frecuencia cardíaca en ese momento |
| `cadence` | `Double?` | Cadencia (spm — pasos por minuto) |
| `speed` | `Double?` | Velocidad (m/s) |
| `power` | `Double?` | Potencia (vatios) |
| `altitude` | `Double?` | Altitud (metros) |
| `locationLat` | `Double?` | Latitud (si hay GPS) |
| `locationLng` | `Double?` | Longitud (si hay GPS) |

> **Nota:** `WorkoutMetric` se almacena solo si se habilita en settings. Para la mayoría de los casos, los datos agregados en `WorkoutRecord` son suficientes. Se sincroniza via CloudKit igualmente.

### 1.3 `SyncLog`

Registro de sincronización para auditoría.

| Atributo | Tipo | Descripción |
|---|---|---|
| `id` | `UUID` (PK) | Identificador único |
| `timestamp` | `Date` | Cuándo ocurrió la sincronización |
| `type` | `String` | Tipo: `"healthkit_import"`, `"cloudkit_sync"`, `"manual_import"` |
| `workoutsCount` | `Int` | Workouts procesados |
| `success` | `Bool` | ¿Fue exitoso? |
| `errorDescription` | `String?` | Mensaje de error si falló |

---

## 2. Relaciones

```
WorkoutRecord 1 ──── * WorkoutMetric
WorkoutRecord 1 ──── * SyncLog (via type + timestamp)
```

---

## 3. Mapeo HealthKit → SyncSalud

| HKWorkout | WorkoutRecord |
|---|---|
| `uuid` | `healthKitID` |
| `workoutActivityType` → `displayString` | `workoutType` |
| `startDate` | `startDate` |
| `endDate` | `endDate` |
| `duration` | `duration` |
| `totalEnergyBurned?.doubleValue(for: .kilocalorie())` | `calories` |
| `totalDistance?.doubleValue(for: .meter())` | `distance` |

| HKSample (heart rate) | WorkoutMetric |
|---|---|
| `startDate` | `timestamp` |
| `quantity.doubleValue(for: .count().unitDivided(by: .minute()))` | `heartRate` |

> Los datos de frecuencia cardíaca se obtienen consultando `HKSampleQuery` con tipo `HKQuantityType.heartRate` dentro del rango del workout.

---

## 4. Estados de Sincronización

```
HealthKit ──▶ SwiftData ──▶ CloudKit ──▶ Otro dispositivo
                │
                ▼
           API Local (macOS)
                │
                ▼
           JSON Export
```

**Deduplicación:** Se usa `healthKitID` (UUID de HealthKit) para evitar duplicados. Si un registro con ese `healthKitID` ya existe en SQLite, se actualiza en vez de insertar.

---

## 5. Vistas Derivadas (para la API)

### `WorkoutSummary`

No es una tabla, es una vista calculada que la API devuelve:

```json
{
  "today": { "count": 1, "calories": 320, "duration": 2700, "distance": 5000 },
  "thisWeek": { "count": 5, "calories": 1540, "duration": 14400 },
  "thisMonth": { "count": 22, "calories": 6800, "duration": 59400 },
  "byType": {
    "running": { "count": 12, "totalDistance": 60000 },
    "cycling": { "count": 8, "totalDistance": 120000 },
    "swimming": { "count": 2, "totalDistance": 3000 }
  },
  "streak": { "current": 3, "longest": 14, "lastWorkoutDate": "..." }
}
```
