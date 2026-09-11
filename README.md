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
- Las actualizaciones OTA se validan mediante SHA-256 antes de activarse.

## 1. Preparar Supabase
1. Crea o abre un proyecto Supabase.
2. Ejecuta la migración financiera y `supabase/migrations/20260911_ota_frontend_releases.sql`.
3. Despliega `supabase/functions/rates/index.ts` como Edge Function llamada `rates`.
4. Mantén `verify_jwt = true` para `rates`.
5. Usa el **Project URL** y la **Publishable Key** en el cliente Android/web.

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
- BCV: `https://bcv.today/api/v1/rate.json`.
- Airtm: `https://rates.airtm.io/`, usando `ves/usd.addValue` para estimar cuántos VES cuesta adquirir 1 USD/USDC en Airtm.

La app consulta la función cada 60 segundos mientras está abierta.

## 4. Actualizaciones OTA del frontend
Desde Android 1.1.0, la aplicación consulta `public.app_releases` al arrancar.

Funcionamiento:
1. Busca la versión activa con mayor `version_code`.
2. Descarga el HTML desde Supabase.
3. Comprueba su SHA-256.
4. Guarda la versión válida en almacenamiento interno.
5. Si Supabase o Internet fallan, utiliza la última versión OTA verificada o el frontend incluido en el APK.

Por tanto, cambios de HTML, CSS y JavaScript se pueden distribuir sin reinstalar la APK. Solo los cambios nativos de Android (Java/Kotlin, permisos, SDK, icono nativo, etc.) requieren una nueva compilación.

La tabla `app_releases` permite lectura únicamente de versiones activas a `anon` y `authenticated`; no concede permisos de escritura al cliente.

## 5. Proyecto Android
El wrapper Android está en `android/`. Es una app WebView nativa con frontend local de emergencia y soporte OTA mediante Supabase.

Configuración actual:
- Application ID: `com.lineagrafica.finanzas`
- Android app: `1.1.0` (`versionCode 2`)
- minSdk: 24
- targetSdk / compileSdk: 36
- AGP: 9.4.0
- Gradle: 9.6.0
- Java: 17

## 6. Generar APK
### Android Studio
Abre la carpeta `android/`, deja que Android Studio instale SDK/Gradle y usa **Build > Build APK(s)**.

### GitHub Actions
El archivo `.github/workflows/build-apk.yml` compila automáticamente `app-debug.apk` y lo publica como artefacto del workflow.

## Nota de firma Android
Para actualizaciones nativas instalables encima de una APK anterior, ambas APK deben estar firmadas con la misma clave. Los builds `debug` generados en runners efímeros pueden no conservar la misma firma entre ejecuciones. Para una distribución nativa estable conviene configurar una clave de firma persistente mediante secretos de CI o una pista privada de Google Play.
