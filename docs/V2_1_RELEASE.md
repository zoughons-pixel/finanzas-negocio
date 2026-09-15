# E-conomic 2.1 — offline, bloqueo del dispositivo y panel web

## Fuente y publicación

La interfaz activa 2.0 se recuperó de `app_releases` y se verificó su SHA-256 antes de modificarla. `web/` contiene ahora la fuente editable común; `python3 scripts/build_frontend.py` genera `dist/` para web, el HTML autónomo incluido en Android y el candidato OTA de `release/`. No necesita nuevas tablas ni migraciones. Las políticas RLS y los cierres existentes siguen siendo la autoridad al sincronizar.

- Android: 2.1.1, versionCode 10. Las notificaciones resuelven la actividad de inicio vigente para pasar por el bloqueo biométrico.
- Candidato frontend: 2.1.0, version_code 11.
- La publicación del APK usa el workflow existente y su firma persistente. Un PR compila sin firmar ni publicar. Solo main publica.
- El panel usa las cuentas Supabase existentes. Sites comienza con acceso privado del propietario; compartir el enlace con otro usuario requiere configurar su audiencia.

## Offline

Después del primer inicio de sesión conectado, IndexedDB conserva respuestas financieras consultadas, separadas por proyecto y usuario. El cliente de Supabase se incluye localmente: no depende de un CDN para abrir Android. El panel web instala un service worker que guarda únicamente recursos de la aplicación; no guarda autenticación ni comprobantes privados en Cache Storage.

Se pueden consultar datos guardados y crear ingresos/egresos con notas, referencia, etiquetas, cliente y proyecto existentes. Los nuevos movimientos se escriben en una cola durable antes de enviarse, incluso estando conectado. Cada uno tiene un UUID estable. Si el servidor confirma pero la respuesta se pierde, se comprueba el mismo UUID y contenido antes de retirar el pendiente, sin duplicar importes. Los pendientes se muestran aparte y no entran en saldos ni reportes confirmados.

Al recuperar Internet se valida la sesión y el servidor aplica permisos y cierres. Los rechazos permanecen visibles, con opción de reintentar o descartar. Las tasas usadas quedan guardadas en el movimiento; sin conexión se pide confirmar las últimas tasas disponibles.

Comprobantes, ediciones/eliminaciones de registros confirmados, cobros/pagos, categorías, clientes/proyectos y cierres necesitan conexión. Las operaciones RPC se bloquean mientras haya movimientos pendientes. Cerrar sesión exige primero sincronizar o descartar; después se borra la copia local y se recarga la aplicación para destruir los estados de las extensiones.

## Bloqueo Android

En Ajustes se activa la protección usando AndroidX BiometricPrompt: biometría del teléfono o credencial de pantalla (PIN/patrón/contraseña). Se exige autenticación para activar o desactivar la protección. El bloqueo cubre el WebView al salir y pide autenticación al volver desde segundo plano o reiniciar. No se guarda una huella ni un PIN propio. Se deshabilita backup de la app y se protege la ventana de capturas. Los enlaces externos salen del WebView para no exponer los puentes nativos a páginas ajenas.

Es una protección de acceso local, no un segundo factor de Supabase ni un cifrado adicional de la base IndexedDB. La sesión y el almacenamiento usan el aislamiento de Android. La biometría no se ofrece en el panel web.

## Verificación

`npm ci --prefix tests && node --test tests/*.test.cjs`

Las pruebas cubren aislamiento de caché, rechazo de permisos, rechazo por cierre, pérdida de respuesta después de confirmar, UUID en conflicto, sincronización concurrente, identidad distinta, limpieza y arranque del documento completo. La compilación de Android se comprueba en GitHub Actions. La huella/PIN y la vuelta desde cámara/selector necesitan una prueba final en dispositivo físico; una compilación no acredita esos flujos.

Documentación consultada: [Android biometría](https://developer.android.com/identity/sign-in/biometric-auth) y [Supabase renovación de sesión](https://supabase.com/docs/reference/javascript/auth-refreshsession).
