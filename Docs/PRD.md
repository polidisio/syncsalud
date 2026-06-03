# PRD — SyncSalud

**Product Requirement Document**

---

## 1. Resumen Ejecutivo

SyncSalud es una aplicación nativa para iOS y macOS que extrae automáticamente datos de entrenamiento desde Apple Health / HealthKit, los almacena localmente en SQLite, los sincroniza entre dispositivos via CloudKit, y los expone a agentes de IA externos (que corren en el mismo Mac) mediante API REST local y exportación JSON.

**Stack:** Swift + SwiftUI, SwiftData (SQLite), CloudKit, Local HTTP Server (Vapor).

---

## 2. Objetivos

- Leer datos de entrenamiento desde HealthKit (workouts, métricas asociadas)
- Almacenar los datos en una base local SQLite (SwiftData) como fuente de verdad
- Sincronizar automáticamente entre iPhone y Mac mediante CloudKit
- Exponer una API REST local en macOS para que agentes de IA consulten los datos
- Permitir exportación manual a JSON
- Funcionar offline-first, sin dependencia de servidores externos
- Costo operativo: $0 (excepto Apple Developer Program, $99/año si se distribuye)

---

## 3. No-objetivos (fuera de scope v1)

- No es multi-usuario
- No requiere backend propio
- No incluye el agente de IA (lo provee el usuario)
- No requiere cuenta ni login
- No requiere Apple Watch (lee datos desde el iPhone, visibles en Mac)
- No tiene panel web (los datos se consultan desde la app o via API)

---

## 4. Usuarios

| Tipo | Descripción |
|---|---|
| **Usuario único** | El dueño del iPhone/Mac |
| **Agente externo** | Proceso/servicio del usuario que corre en el Mac y consume la API local |

---

## 5. Funcionalidades

| # | Funcionalidad | Prioridad | Dispositivo |
|---|---|---|---|
| F1 | Leer workouts de HealthKit (tipo, fecha, duración, calorías, distancia, ritmo cardíaco) | P0 | iOS |
| F2 | Almacenar en SQLite local | P0 | iOS + macOS |
| F3 | Sincronizar via CloudKit (iPhone ↔ Mac) | P0 | iOS + macOS |
| F4 | Sincronización al abrir la app | P0 | iOS + macOS |
| F5 | Botón manual "Sincronizar ahora" | P0 | iOS + macOS |
| F6 | Sincronización programada en background | P1 | iOS |
| F7 | API REST local en macOS | P0 | macOS |
| F8 | Exportación a JSON | P0 | iOS + macOS |
| F9 | Dashboard con resumen de actividad | P1 | iOS + macOS |
| F10 | Historial de workouts | P1 | iOS + macOS |
| F11 | Preferencias (frecuencia de sync, tipos de datos a incluir) | P2 | iOS + macOS |

---

## 6. Historias de Usuario

**HU1 — Lectura inicial**
> Como usuario, quiero que la app lea automáticamente todos mis workouts pasados de HealthKit la primera vez que la abro.

**HU2 — Sync automático**
> Como usuario, quiero que al abrir la app se sincronicen los workouts nuevos desde HealthKit sin que tenga que hacer nada.

**HU3 — Sync entre dispositivos**
> Como usuario, quiero que los workouts que leí en mi iPhone estén disponibles en mi Mac sin configuración extra.

**HU4 — API para agentes**
> Como usuario con agentes de IA, quiero que la app exponga una API local en mi Mac para que mis agentes consulten mis datos de entrenamiento.

**HU5 — Exportación**
> Como usuario, quiero exportar mis datos a JSON para respaldo o para procesarlos manualmente.

---

## 7. Métricas de éxito

- Workouts sincronizados correctamente del histórico de HealthKit: 100%
- Latencia de API local < 50ms para queries típicas
- Sin pérdida de datos entre dispositivos
- Sin crashes ni errores de permiso de HealthKit
