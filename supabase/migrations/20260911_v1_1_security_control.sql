-- E-conomic v1.1 — Seguridad y control
-- Consolida auditoría detallada, permisos por rol y actividad de solo lectura.

create or replace function public.is_business_owner(p_business_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.business_members bm
    where bm.business_id = p_business_id
      and bm.user_id = auth.uid()
      and bm.role = 'owner'
  );
$$;

revoke all on function public.is_business_owner(uuid) from public;
grant execute on function public.is_business_owner(uuid) to authenticated;

create or replace function public.audit_transaction_changes()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    perform public.log_activity(
      new.business_id,
      'CREATE_TRANSACTION',
      'Nuevo movimiento creado',
      new.amount_original,
      jsonb_build_object(
        'transaction_id', new.id,
        'new', to_jsonb(new) - 'business_id'
      )
    );
    return new;
  elsif tg_op = 'UPDATE' then
    perform public.log_activity(
      new.business_id,
      'UPDATE_TRANSACTION',
      'Movimiento actualizado',
      new.amount_original,
      jsonb_build_object(
        'transaction_id', new.id,
        'old', to_jsonb(old) - 'business_id',
        'new', to_jsonb(new) - 'business_id'
      )
    );
    return new;
  elsif tg_op = 'DELETE' then
    perform public.log_activity(
      old.business_id,
      'DELETE_TRANSACTION',
      'Movimiento eliminado',
      old.amount_original,
      jsonb_build_object(
        'transaction_id', old.id,
        'old', to_jsonb(old) - 'business_id'
      )
    );
    return old;
  end if;
  return null;
end;
$$;

-- Owner: puede editar/eliminar cualquier movimiento.
-- Partner: solo movimientos creados por él.
drop policy if exists transactions_update on public.transactions;
create policy transactions_update on public.transactions
for update to authenticated
using (
  public.is_business_member(business_id)
  and (public.is_business_owner(business_id) or created_by = auth.uid())
)
with check (
  public.is_business_member(business_id)
  and (public.is_business_owner(business_id) or created_by = auth.uid())
  and updated_by = auth.uid()
);

drop policy if exists transactions_delete on public.transactions;
create policy transactions_delete on public.transactions
for delete to authenticated
using (
  public.is_business_member(business_id)
  and (public.is_business_owner(business_id) or created_by = auth.uid())
);

-- La configuración de categorías queda en manos del propietario.
drop policy if exists categories_insert on public.categories;
create policy categories_insert on public.categories
for insert to authenticated
with check (
  public.is_business_owner(business_id)
  and created_by = auth.uid()
);

drop policy if exists categories_update on public.categories;
create policy categories_update on public.categories
for update to authenticated
using (public.is_business_owner(business_id))
with check (public.is_business_owner(business_id));

drop policy if exists categories_delete on public.categories;
create policy categories_delete on public.categories
for delete to authenticated
using (public.is_business_owner(business_id));

-- El registro de auditoría es visible para miembros, pero no modificable desde el cliente.
revoke all on public.activity_logs from authenticated;
grant select on public.activity_logs to authenticated;
revoke all on public.activity_logs from anon;
drop policy if exists activity_logs_insert on public.activity_logs;
revoke execute on function public.log_activity(uuid,text,text,numeric,jsonb) from authenticated;
revoke execute on function public.log_activity(uuid,text,text,numeric,jsonb) from public;

-- Actividad en tiempo real.
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'activity_logs'
  ) then
    alter publication supabase_realtime add table public.activity_logs;
  end if;
end $$;
