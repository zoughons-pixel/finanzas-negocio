-- E-conomic v1.3 foundation
-- Auditoria de movimientos entre socios

create table if not exists public.activity_logs (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  action text not null,
  description text not null default '',
  amount numeric(20,6),
  created_at timestamptz not null default now()
);

create index if not exists idx_activity_logs_business_date
on public.activity_logs(business_id, created_at desc);

alter table public.activity_logs enable row level security;

revoke all on public.activity_logs from anon;
grant select on public.activity_logs to authenticated;

drop policy if exists activity_logs_select on public.activity_logs;
create policy activity_logs_select on public.activity_logs
for select to authenticated
using (public.is_business_member(business_id));

-- Funcion auxiliar para registrar acciones desde funciones futuras
create or replace function public.log_activity(
  p_business_id uuid,
  p_action text,
  p_description text,
  p_amount numeric default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.activity_logs(business_id,user_id,action,description,amount)
  values(p_business_id, auth.uid(), p_action, p_description, p_amount);
end;
$$;

revoke all on function public.log_activity(uuid,text,text,numeric) from public;
grant execute on function public.log_activity(uuid,text,text,numeric) to authenticated;
