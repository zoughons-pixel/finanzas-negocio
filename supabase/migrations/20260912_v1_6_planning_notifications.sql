-- E-conomic v1.6 — Presupuestos, metas, flujo de caja y base de alertas.
-- Negocio digital: no incluye inventario.

create table if not exists public.monthly_budgets (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  period_start date not null,
  category text not null default '*',
  limit_usd numeric(20,6) not null check (limit_usd > 0),
  alert_percent integer not null default 80 check (alert_percent between 50 and 100),
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint monthly_budgets_first_day check (period_start = date_trunc('month', period_start)::date),
  constraint monthly_budgets_category_not_blank check (btrim(category) <> ''),
  constraint monthly_budgets_business_period_category unique (business_id, period_start, category)
);

create index if not exists idx_monthly_budgets_business_period
  on public.monthly_budgets(business_id, period_start desc);

create table if not exists public.financial_goals (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null,
  goal_type text not null check (goal_type in ('income','net','balance')),
  target_usd numeric(20,6) not null check (target_usd > 0),
  start_date date not null,
  end_date date not null,
  status text not null default 'active' check (status in ('active','archived')),
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint financial_goals_name_not_blank check (btrim(name) <> ''),
  constraint financial_goals_date_order check (start_date <= end_date)
);

create index if not exists idx_financial_goals_business_dates
  on public.financial_goals(business_id, start_date, end_date);
create index if not exists idx_financial_goals_business_status
  on public.financial_goals(business_id, status);

alter table public.monthly_budgets enable row level security;
alter table public.financial_goals enable row level security;

revoke all on public.monthly_budgets from anon;
revoke all on public.financial_goals from anon;
revoke all on public.monthly_budgets from authenticated;
revoke all on public.financial_goals from authenticated;
grant select, insert, update, delete on public.monthly_budgets to authenticated;
grant select, insert, update, delete on public.financial_goals to authenticated;

drop policy if exists monthly_budgets_select on public.monthly_budgets;
create policy monthly_budgets_select on public.monthly_budgets
for select to authenticated
using (public.is_business_member(business_id));

drop policy if exists monthly_budgets_insert on public.monthly_budgets;
create policy monthly_budgets_insert on public.monthly_budgets
for insert to authenticated
with check (
  public.is_business_owner(business_id)
  and created_by = auth.uid()
  and updated_by = auth.uid()
);

drop policy if exists monthly_budgets_update on public.monthly_budgets;
create policy monthly_budgets_update on public.monthly_budgets
for update to authenticated
using (public.is_business_owner(business_id))
with check (
  public.is_business_owner(business_id)
  and updated_by = auth.uid()
);

drop policy if exists monthly_budgets_delete on public.monthly_budgets;
create policy monthly_budgets_delete on public.monthly_budgets
for delete to authenticated
using (public.is_business_owner(business_id));

drop policy if exists financial_goals_select on public.financial_goals;
create policy financial_goals_select on public.financial_goals
for select to authenticated
using (public.is_business_member(business_id));

drop policy if exists financial_goals_insert on public.financial_goals;
create policy financial_goals_insert on public.financial_goals
for insert to authenticated
with check (
  public.is_business_owner(business_id)
  and created_by = auth.uid()
  and updated_by = auth.uid()
);

drop policy if exists financial_goals_update on public.financial_goals;
create policy financial_goals_update on public.financial_goals
for update to authenticated
using (public.is_business_owner(business_id))
with check (
  public.is_business_owner(business_id)
  and updated_by = auth.uid()
);

drop policy if exists financial_goals_delete on public.financial_goals;
create policy financial_goals_delete on public.financial_goals
for delete to authenticated
using (public.is_business_owner(business_id));

create or replace function public.v16_touch_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
revoke all on function public.v16_touch_updated_at() from public;
revoke all on function public.v16_touch_updated_at() from anon;
revoke all on function public.v16_touch_updated_at() from authenticated;

drop trigger if exists trg_monthly_budgets_touch on public.monthly_budgets;
create trigger trg_monthly_budgets_touch
before update on public.monthly_budgets
for each row execute function public.v16_touch_updated_at();

drop trigger if exists trg_financial_goals_touch on public.financial_goals;
create trigger trg_financial_goals_touch
before update on public.financial_goals
for each row execute function public.v16_touch_updated_at();

-- Un presupuesto de un mes cerrado queda congelado hasta que el Owner reabra ese mes.
create or replace function public.v16_enforce_open_budget_month()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_business uuid;
  v_period date;
begin
  if tg_op = 'DELETE' then
    v_business := old.business_id;
    v_period := old.period_start;
  else
    v_business := new.business_id;
    v_period := new.period_start;
  end if;

  if tg_op = 'UPDATE' and (old.business_id <> new.business_id or old.period_start <> new.period_start) then
    if exists (
      select 1 from public.monthly_closures c
      where c.business_id = old.business_id
        and c.period_start = old.period_start
        and c.status = 'closed'
    ) then
      raise exception 'El presupuesto pertenece a un mes cerrado. Reábrelo antes de modificarlo.' using errcode='P0001';
    end if;
  end if;

  if exists (
    select 1 from public.monthly_closures c
    where c.business_id = v_business
      and c.period_start = v_period
      and c.status = 'closed'
  ) then
    raise exception 'El presupuesto pertenece a un mes cerrado. Reábrelo antes de modificarlo.' using errcode='P0001';
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
revoke all on function public.v16_enforce_open_budget_month() from public;
revoke all on function public.v16_enforce_open_budget_month() from anon;
revoke all on function public.v16_enforce_open_budget_month() from authenticated;

drop trigger if exists trg_monthly_budgets_open_month on public.monthly_budgets;
create trigger trg_monthly_budgets_open_month
before insert or update or delete on public.monthly_budgets
for each row execute function public.v16_enforce_open_budget_month();

-- Auditoría de presupuestos y metas en Actividad reciente.
create or replace function public.v16_log_planning_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row jsonb;
  v_old jsonb;
  v_business uuid;
  v_actor uuid;
  v_action text;
  v_description text;
  v_amount numeric;
begin
  if tg_op = 'DELETE' then
    v_row := to_jsonb(old);
    v_old := to_jsonb(old);
    v_business := old.business_id;
    v_actor := coalesce(auth.uid(), old.updated_by, old.created_by);
  else
    v_row := to_jsonb(new);
    v_old := case when tg_op='UPDATE' then to_jsonb(old) else null end;
    v_business := new.business_id;
    v_actor := coalesce(auth.uid(), new.updated_by, new.created_by);
  end if;

  if v_actor is null then
    if tg_op='DELETE' then return old; end if;
    return new;
  end if;

  if tg_table_name = 'monthly_budgets' then
    v_action := case tg_op when 'INSERT' then 'BUDGET_CREATED' when 'UPDATE' then 'BUDGET_UPDATED' else 'BUDGET_DELETED' end;
    v_description := case tg_op when 'INSERT' then 'Presupuesto creado' when 'UPDATE' then 'Presupuesto actualizado' else 'Presupuesto eliminado' end;
    v_amount := coalesce((v_row->>'limit_usd')::numeric,0);
  else
    v_action := case tg_op when 'INSERT' then 'GOAL_CREATED' when 'UPDATE' then 'GOAL_UPDATED' else 'GOAL_DELETED' end;
    v_description := case tg_op when 'INSERT' then 'Meta financiera creada' when 'UPDATE' then 'Meta financiera actualizada' else 'Meta financiera eliminada' end;
    v_amount := coalesce((v_row->>'target_usd')::numeric,0);
  end if;

  insert into public.activity_logs(business_id,user_id,action,description,amount,metadata)
  values(
    v_business,
    v_actor,
    v_action,
    v_description,
    v_amount,
    jsonb_build_object(
      'entity_id', v_row->>'id',
      'entity', tg_table_name,
      'old', v_old,
      'new', case when tg_op='DELETE' then null else v_row end
    )
  );

  if tg_op='DELETE' then return old; end if;
  return new;
end;
$$;
revoke all on function public.v16_log_planning_change() from public;
revoke all on function public.v16_log_planning_change() from anon;
revoke all on function public.v16_log_planning_change() from authenticated;

drop trigger if exists trg_monthly_budgets_activity on public.monthly_budgets;
create trigger trg_monthly_budgets_activity
after insert or update or delete on public.monthly_budgets
for each row execute function public.v16_log_planning_change();

drop trigger if exists trg_financial_goals_activity on public.financial_goals;
create trigger trg_financial_goals_activity
after insert or update or delete on public.financial_goals
for each row execute function public.v16_log_planning_change();

-- Realtime compartido para que ambos socios vean cambios al instante.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public' and tablename='monthly_budgets'
  ) then
    alter publication supabase_realtime add table public.monthly_budgets;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public' and tablename='financial_goals'
  ) then
    alter publication supabase_realtime add table public.financial_goals;
  end if;
end $$;
