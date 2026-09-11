-- E-conomic v1.1 - Auditoría y control de cambios
-- Registra quién crea, modifica y elimina información financiera.

create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete restrict,
  action text not null check (action in ('INSERT','UPDATE','DELETE')),
  entity text not null,
  entity_id uuid,
  old_data jsonb,
  new_data jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_audit_business_date
on public.audit_logs(business_id, created_at desc);

alter table public.audit_logs enable row level security;

revoke all on public.audit_logs from anon;
grant select on public.audit_logs to authenticated;

create policy audit_select_members
on public.audit_logs
for select
to authenticated
using (public.is_business_member(business_id));

create or replace function public.log_transaction_changes()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (TG_OP = 'INSERT') then
    insert into public.audit_logs(business_id,user_id,action,entity,entity_id,new_data)
    values(new.business_id,auth.uid(),'INSERT','transaction',new.id,to_jsonb(new));
    return new;
  elsif (TG_OP = 'UPDATE') then
    insert into public.audit_logs(business_id,user_id,action,entity,entity_id,old_data,new_data)
    values(new.business_id,auth.uid(),'UPDATE','transaction',new.id,to_jsonb(old),to_jsonb(new));
    return new;
  elsif (TG_OP = 'DELETE') then
    insert into public.audit_logs(business_id,user_id,action,entity,entity_id,old_data)
    values(old.business_id,auth.uid(),'DELETE','transaction',old.id,to_jsonb(old));
    return old;
  end if;
  return null;
end;
$$;

drop trigger if exists trg_transaction_audit on public.transactions;
create trigger trg_transaction_audit
after insert or update or delete on public.transactions
for each row execute function public.log_transaction_changes();
