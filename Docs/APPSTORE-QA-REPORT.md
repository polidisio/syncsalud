# SyncSalud - Informe QA para App Store

**Fecha:** 2026-06-05
**Versión:** 1.0.0
**Estado:** Pendiente implementar

---

## RESUMEN EJECUTIVO

App SwiftUI/SwiftData bien estructurada para sync de HealthKit. **Sin monetización.** Faltan capabilities críticas para App Store. Técnicamente sólida pero necesita trabajo antes de lanzar.

---

## 1. HALLAZGOS CRÍTICOS

### ❌ 1.1 Monetización - NO EXISTE
```
Busqueda: StoreKit, RevenueCat, IAP, SKProduct, SKPayment → NADA
```
- Sin In-App Purchase
- Sin suscripciones
- Sin modelo de negocio
- App completamente gratis

**Impacto:** Sin revenue. App no monetizable en estado actual.

### ❌ 1.2 Sign in with Apple - NO CONFIGURADO
- Entitlements no incluyen `com.apple.developer.authentication-services.appleid`
- Sin autenticación de usuarios
- Datos atados a dispositivo + iCloud (no multiplataforma)
- Suscripción multi-dispositivo imposible sin esto

**Impacto:** No se puede ofrecer suscripción cross-device. Loss de revenue.

### ❌ 1.3 Push Notifications - NO CONFIGURADO
- `BGTaskScheduler` no reemplaza push notifications
- Sin mecanismo de re-engagement
- Sin alertas de sync completado

**Impacto:** Menor retention. Usuario no sabe cuando sync termina.

### ❌ 1.4 App Store Metadata - NO EXISTE
- Sin keywords, description, screenshots
- Sin Privacy Policy URL
- Sin Terms of Service

**Impacto:** No se puede subir a App Store.

---

## 2. CUMPLIMIENTO APP STORE

### ✅ Cumplen
| Requisito | Estado |
|-----------|--------|
| HealthKit solo lectura | ✅ |
| Descripción clara permisos | ✅ |
| Background modes apropiados | ✅ |
| iCloud container correcto | ✅ |
| Category Health & Fitness | ✅ |
| Age rating 4+ | ✅ |
| No contenido prohibido | ✅ |

### ⚠️ Con problemas
| Requisito | Problema |
|-----------|----------|
| Privacy Policy | Falta URL pública |
| Sign in with Apple | No capability |
| Push Notifications | No configurado |
| Monetización | No existe |

---

## 3. ISSUES TÉCNICOS

### 🔴 Seguridad
- `LocalAPIServer.swift:127` - CORS `*` (macOS only, peroaceita)
- Sin rate limiting en API local
- ✅ Sin credenciales hardcoded

### 🟡 Data Model
- `WorkoutRecord.healthKitID` sin unique constraint
- Deduplicación manual (código) en lugar de DB
- Riesgo duplicados si sync interrumpe

### 🟡 Error Handling
- `SyncLog.errorDescription` nunca se llena en muchos casos
- Background task failures no visibles al usuario
- Sin retry policy para fallos de red

### 🟡 UX/UI
- Sin onboarding flow
- Sin tutorial primera apertura
- UI español sin localization infrastructure
- Dashboard mejorable

---

## 4. RECOMENDACIONES MONETIZACIÓN

### Opción A: Freemium (Recomendada)
```
GRATIS:
- 30 workouts/sync
- Sincronización básica

PREMIUM ($4.99/mes ó $29.99/año):
- Workouts ilimitados
- Export avanzado (CSV, PDF)
- Múltiples dispositivos
- Prioridad sync
- Soporte prioritario
```

### Opción B: Suscripción pura
```
$4.99/mes
Trial 7 días gratis
Todo acceso
```

### Opción C: Compra única
```
$9.99 unlock permanente
Más simple, menos MRR
```

---

## 5. ROADMAP IMPLEMENTACIÓN

### Fase 1: App Store Ready
- [ ] Crear Privacy Policy (generador online)
- [ ] Configurar Sign in with Apple en capabilities
- [ ] Implementar StoreKit 2 (suscripciones)
- [ ] Añadir onboarding flow
- [ ] Metadata en App Store Connect

### Fase 2: Monetización
- [ ] Implementar paywall en Settings
- [ ] Límite 30 workouts para free
- [ ] Flow compra suscripción
- [ ] Restore purchases

### Fase 3: Engagement
- [ ] Push notifications (sync completado)
- [ ] Deep links para re-engagement
- [ ] Beta TestFlight externo

---

## 6. ARCHIVOS PRIORITARIOS

| Archivo | Qué revisar |
|---------|-------------|
| `SyncSalud/Health/HealthKitService.swift` | Auth state, permisos |
| `SyncSalud/Sync/HealthSyncManager.swift` | Deduplicación, sync logic |
| `SyncSalud/UI/SettingsView.swift` | Paywall integration |
| `SyncSalud/Export/VaultManager.swift` | Límites free tier |
| `SyncSalud/Models/WorkoutRecord.swift` | Unique constraint |

---

## 7. VERIFICACIÓN

```bash
# Construir iOS
xcodebuild -project SyncSalud.xcodeproj -scheme SyncSalud-iOS -configuration Release build

# TestFlight
xcodebuild -exportArchive -archive ... -exportOptionsPlist ...

# Checklist final
# □ Privacy Policy URL
# □ Sign in with Apple
# □ StoreKit 2 integrado
# □ Onboarding
# □ Metadata App Store Connect
# □ TestFlight beta
```

---

## 8. PROGRESO

| Tarea | Estado | Fecha |
|-------|--------|-------|
| Privacy Policy | ⬜ pending | - |
| Sign in with Apple | ⬜ pending | - |
| StoreKit 2 | ⬜ pending | - |
| Onboarding | ⬜ pending | - |
| App Store Connect | ⬜ pending | - |
| Paywall | ⬜ pending | - |
| Límite free tier | ⬜ pending | - |
| Push notifications | ⬜ pending | - |
| TestFlight | ⬜ pending | - |

---

**Conclusión:** App técnicamente sólida pero incompleta para App Store con monetización. Necesita ~4-6 semanas de desarrollo adicional antes de lanzar. Prioridad: Sign in with Apple + StoreKit 2 + Privacy Policy.