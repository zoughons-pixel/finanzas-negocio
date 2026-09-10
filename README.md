# Finanzas del Negocio — Android + Supabase

Esta versión reemplaza el almacenamiento local de movimientos por **Supabase PostgreSQL** y está diseñada para exactamente dos socios.

## Qué queda sincronizado
- Ingresos y egresos.
- Ediciones y eliminaciones.
- Categorías.
- Saldos USD (BCV), VES y USDC (Airtm).
- Realtime: cuando un socio cambia un movimiento, el otro teléfono recibe el evento y vuelve a cargar los datos.

Cada movimiento conserva `bcv_rate` y `airtm_rate`, por lo que el histórico no cambia cuando cambian las tasas futuras.

## Seguridad
- Login independiente por email/contraseña para cada socio.
- RLS activado en todas las tablas expuestas.
- El código SQL limita cada negocio a **máximo 2 usuarios**.
- La Publishable Key se puede usar en la app porque RLS limita los datos.
- **Nunca pongas una Secret Key / Service Role Key en el APK.**

## 1. Preparar Supabase
1. Crea o abre un proyecto Supabase.
2. En SQL Editor ejecuta `supabase/migrations/20260910_finance_shared.sql`.
3. Despliega `supabase/functions/rates/index.ts` como Edge Function llamada `rates`.
4. Mantén `verify_jwt = true` (incluido en `supabase/config.toml`).
5. Copia el **Project URL** y la **Publishable Key** desde Settings > API Keys.

## 2. Primer arranque en cada teléfono
La app pide Project URL + Publishable Key una sola vez y las guarda localmente en ese dispositivo.

Después:
- Socio 1: crea una cuenta, inicia sesión y pulsa **Crear negocio**.
- La app muestra un código de 8 caracteres.
- Socio 2: crea su propia cuenta, inicia sesión y pulsa **Unirme al negocio** con ese código.
- A partir de ahí ambos ven la misma contabilidad.

Si Supabase tiene activada la confirmación de email, cada usuario deberá confirmar su correo antes del primer inicio de sesión.

## 3. Tasas
La Edge Function consulta:
- BCV: `https://bcv.today/api/v1/rate.json` (replica datos publicados por bcv.org.ve).
- Airtm: conversor oficial `VES -> USD/USDC` y extrae su **Net rate**.

La app consulta la función cada 60 segundos mientras está abierta.

## 4. Proyecto Android
El wrapper Android está en `android/`. Es una app WebView nativa que carga el frontend empaquetado localmente y usa Internet únicamente para Supabase, Realtime, BCV/Airtm y la librería JS de Supabase.

Configuración actual:
- Application ID: `com.lineagrafica.finanzas`
- minSdk: 24
- targetSdk / compileSdk: 36
- AGP: 9.4.0
- Gradle: 9.6.0
- Java: 17

## 5. Generar APK
### Android Studio
Abre la carpeta `android/`, deja que Android Studio instale SDK/Gradle y usa **Build > Build APK(s)**.

### GitHub Actions
El archivo `.github/workflows/build-apk.yml` compila automáticamente `app-debug.apk`. Sube el proyecto a un repositorio, abre Actions > Build Android APK > Run workflow y descarga el artefacto.

## Nota sobre el APK incluido
Este paquete contiene el proyecto Android listo para compilar. Si no existe `FinanzasNegocio.apk` en la raíz, significa que el entorno donde se generó el proyecto no tenía Android SDK/Gradle disponibles para producir el binario; no afecta al código fuente.
