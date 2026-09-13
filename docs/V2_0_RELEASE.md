# E-conomic v2.0.0

Release mayor orientado al negocio digital: clientes, proyectos y rentabilidad.

## Producción

- Frontend OTA: `2.0.0`, `version_code=10`.
- Backend aplicado mediante migraciones Supabase:
  - `v2_0_clients_projects_core`
  - `v2_0_clients_projects_rls`
  - `v2_0_transaction_dimensions`
  - `v2_0_profitability_views`
  - `v2_0_entity_audit`
  - `frontend_v2_0_clients_projects_profitability`
- No requiere un nuevo APK: el Android nativo permanece en `1.6.0` / versionCode 8 porque v2.0 no añade capacidades nativas.

## Funciones

- Fichas compartidas de clientes con empresa, contacto, correo, teléfono, notas y estado.
- Proyectos vinculados opcionalmente a un cliente, con estado, fechas y presupuesto USD.
- Movimientos vinculables a cliente y/o proyecto.
- Si se selecciona un proyecto que pertenece a un cliente, el backend completa/valida la relación para impedir cruces entre negocios o clientes inconsistentes.
- Rentabilidad por cliente y por proyecto: ingresos, egresos, resultado neto y cantidad de movimientos.
- Uso de presupuesto por proyecto en el frontend.
- Filtros de movimientos por cliente y proyecto.
- Realtime para clientes y proyectos.
- Auditoría para creación/actualización/eliminación de clientes y proyectos.
- RLS: ambos socios pueden consultar y crear; el Owner puede administrar todo y cada socio puede administrar las fichas que creó.

## Vistas

- `public.client_profitability`
- `public.project_profitability`

Ambas son `security_invoker` y respetan las políticas RLS de las tablas subyacentes.

## Pruebas realizadas

Se ejecutaron pruebas dentro de transacciones revertidas para verificar que un socio puede crear cliente/proyecto, vincular un movimiento al proyecto y que el trigger completa correctamente el cliente asociado. Se verificó posteriormente que no quedaron datos de prueba.
