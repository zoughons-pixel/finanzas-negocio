-- E-conomic v1.4 — Reportes y cierres mensuales
-- Cierres auditables, bloqueo de meses cerrados y snapshots para PDF/Excel.

create table if not exists public.monthly_closures (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  period_start date not null,
  status text not null default 'closed' check (status in ('closed','reopened')),
  transaction_count integer not null default 0,
  income_usd numeric(20,6) not null default 0,
  expense_usd numeric(20,6) not null default 0,
  net_usd numeric(20,6) not null default 0,
  income_ves numeric(20,6) not null default 0,
  expense_ves numeric(20,6) not null default 0,
  net_ves numeric(20,6) not null default 0,
  income_usdc numeric(20,6) not null default 0,
  expense_usdc numeric(20,6) not null default 0,
  net_usdc numeric(20,6) not null default 0,
  opening_usd numeric(20,6) not null default 0,
  closing_usd numeric(20,6) not null default 0,
  opening_ves numeric(20,6) not null default 0,
  closing_ves numeric(20,6) not null default 0,
  opening_usdc numeric(20,6) not null default 0,
  closing_usdc numeric(20,6) not null default 0,
  warnings jsonb not null default '{}'::jsonb,
  snapshot jsonb not null default '{}'::jsonb,
  closed_at timestamptz not null default now(),
  closed_by uuid references auth.users(id) on delete set null,
  reopened_at timestamptz,
  reopened_by uuid references auth.users(id) on delete set null,
  reopen_reason text not null default '',
  reopen_count integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint monthly_closures_first_day check (period_start = date_trunc('month', period_start)::date),
  constraint monthly_closures_business_period unique (business_id, period_start)
);

create index if not exists idx_monthly_closures_business_period
  on public.monthly_closures(business_id, period_start desc);

alter table public.monthly_closures enable row level security;
revoke all on public.monthly_closures from anon;
revoke all on public.monthly_closures from authenticated;
grant select on public.monthly_closures to authenticated;

drop policy if exists monthly_closures_select on public.monthly_closures;
create policy monthly_closures_select on public.monthly_closures
for select to authenticated
using (public.is_business_member(business_id));

-- Bloqueo transaccional compartido por cierre y modificaciones del mismo mes.
create or replace function public.enforce_open_transaction_month()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_business_id uuid;
  v_date date;
  v_period date;
begin
  if tg_op = 'INSERT' then
    v_business_id := new.business_id;
    v_date := new.occurred_on;
  elsif tg_op = 'UPDATE' then
    perform pg_advisory_xact_lock(hashtextextended(old.business_id::text || ':' || date_trunc('month', old.occurred_on)::date::text, 0));
    if exists (
      select 1 from public.monthly_closures c
      where c.business_id = old.business_id
        and c.period_start = date_trunc('month', old.occurred_on)::date
        and c.status = 'closed'
    ) then
      raise exception 'El mes % está cerrado. El propietario debe reabrirlo antes de modificar movimientos.', to_char(old.occurred_on, 'YYYY-MM') using errcode = 'P0001';
    end if;
    v_business_id := new.business_id;
    v_date := new.occurred_on;
  else
    v_business_id := old.business_id;
    v_date := old.occurred_on;
  end if;

  v_period := date_trunc('month', v_date)::date;
  perform pg_advisory_xact_lock(hashtextextended(v_business_id::text || ':' || v_period::text, 0));

  if exists (
    select 1 from public.monthly_closures c
    where c.business_id = v_business_id
      and c.period_start = v_period
      and c.status = 'closed'
  ) then
    raise exception 'El mes % está cerrado. El propietario debe reabrirlo antes de modificar movimientos.', to_char(v_period, 'YYYY-MM') using errcode = 'P0001';
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

revoke all on function public.enforce_open_transaction_month() from public;
revoke all on function public.enforce_open_transaction_month() from anon;
revoke all on function public.enforce_open_transaction_month() from authenticated;

drop trigger if exists trg_transactions_open_month on public.transactions;
create trigger trg_transactions_open_month
before insert or update or delete on public.transactions
for each row execute function public.enforce_open_transaction_month();

create or replace function public.enforce_open_attachment_month()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tx_id uuid := case when tg_op = 'DELETE' then old.transaction_id else new.transaction_id end;
  v_business_id uuid;
  v_date date;
  v_period date;
begin
  select t.business_id, t.occurred_on into v_business_id, v_date
  from public.transactions t where t.id = v_tx_id;

  if v_business_id is null then
    raise exception 'Movimiento no encontrado para el comprobante.' using errcode = 'P0001';
  end if;

  v_period := date_trunc('month', v_date)::date;
  perform pg_advisory_xact_lock(hashtextextended(v_business_id::text || ':' || v_period::text, 0));

  if exists (
    select 1 from public.monthly_closures c
    where c.business_id = v_business_id
      and c.period_start = v_period
      and c.status = 'closed'
  ) then
    raise exception 'El mes % está cerrado. Reábrelo antes de cambiar comprobantes.', to_char(v_period, 'YYYY-MM') using errcode = 'P0001';
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

revoke all on function public.enforce_open_attachment_month() from public;
revoke all on function public.enforce_open_attachment_month() from anon;
revoke all on function public.enforce_open_attachment_month() from authenticated;

drop trigger if exists trg_attachments_open_month on public.transaction_attachments;
create trigger trg_attachments_open_month
before insert or delete on public.transaction_attachments
for each row execute function public.enforce_open_attachment_month();

-- Corrige la relación del comprobante con su negocio y respeta el cierre mensual.
drop policy if exists transaction_attachments_insert on public.transaction_attachments;
create policy transaction_attachments_insert on public.transaction_attachments
for insert to authenticated
with check (
  public.is_business_member(business_id)
  and uploaded_by = auth.uid()
  and exists (
    select 1 from public.transactions t
    where t.id = transaction_attachments.transaction_id
      and t.business_id = transaction_attachments.business_id
      and (public.is_business_owner(t.business_id) or t.created_by = auth.uid())
      and not exists (
        select 1 from public.monthly_closures c
        where c.business_id = t.business_id
          and c.period_start = date_trunc('month', t.occurred_on)::date
          and c.status = 'closed'
      )
  )
);

drop policy if exists transaction_attachments_delete on public.transaction_attachments;
create policy transaction_attachments_delete on public.transaction_attachments
for delete to authenticated
using (
  public.is_business_member(business_id)
  and exists (
    select 1 from public.transactions t
    where t.id = transaction_attachments.transaction_id
      and t.business_id = transaction_attachments.business_id
      and (public.is_business_owner(t.business_id) or t.created_by = auth.uid())
      and not exists (
        select 1 from public.monthly_closures c
        where c.business_id = t.business_id
          and c.period_start = date_trunc('month', t.occurred_on)::date
          and c.status = 'closed'
      )
  )
);

-- Storage: tampoco se agregan/eliminan archivos de movimientos de un mes cerrado.
drop policy if exists economic_receipts_insert on storage.objects;
create policy economic_receipts_insert on storage.objects
for insert to authenticated
with check (
  bucket_id = 'transaction-receipts'
  and public.is_business_member(public.try_uuid(split_part(name, '/', 1)))
  and exists (
    select 1 from public.transactions t
    where t.id = public.try_uuid(split_part(storage.objects.name, '/', 2))
      and t.business_id = public.try_uuid(split_part(storage.objects.name, '/', 1))
      and (public.is_business_owner(t.business_id) or t.created_by = auth.uid())
      and not exists (
        select 1 from public.monthly_closures c
        where c.business_id = t.business_id
          and c.period_start = date_trunc('month', t.occurred_on)::date
          and c.status = 'closed'
      )
  )
);

drop policy if exists economic_receipts_delete on storage.objects;
create policy economic_receipts_delete on storage.objects
for delete to authenticated
using (
  bucket_id = 'transaction-receipts'
  and public.is_business_member(public.try_uuid(split_part(name, '/', 1)))
  and exists (
    select 1 from public.transactions t
    where t.id = public.try_uuid(split_part(storage.objects.name, '/', 2))
      and t.business_id = public.try_uuid(split_part(storage.objects.name, '/', 1))
      and (public.is_business_owner(t.business_id) or t.created_by = auth.uid())
      and not exists (
        select 1 from public.monthly_closures c
        where c.business_id = t.business_id
          and c.period_start = date_trunc('month', t.occurred_on)::date
          and c.status = 'closed'
      )
  )
);

create or replace function public.close_month(p_business_id uuid, p_period_start date)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_period date;
  v_next date;
  v_id uuid;
  v_count integer := 0;
  v_income_usd numeric := 0;
  v_expense_usd numeric := 0;
  v_income_ves numeric := 0;
  v_expense_ves numeric := 0;
  v_income_usdc numeric := 0;
  v_expense_usdc numeric := 0;
  v_open_usd numeric := 0;
  v_open_ves numeric := 0;
  v_open_usdc numeric := 0;
  v_missing_description integer := 0;
  v_other_category integer := 0;
  v_expense_without_receipt integer := 0;
  v_transactions jsonb := '[]'::jsonb;
  v_categories jsonb := '[]'::jsonb;
  v_warnings jsonb;
  v_summary jsonb;
  v_snapshot jsonb;
begin
  if v_user is null then raise exception 'Debes iniciar sesión.' using errcode = 'P0001'; end if;
  if p_period_start is null then raise exception 'Selecciona un mes.' using errcode = 'P0001'; end if;
  if not public.is_business_owner(p_business_id) then
    raise exception 'Solo el propietario puede cerrar el mes.' using errcode = 'P0001';
  end if;

  v_period := date_trunc('month', p_period_start)::date;
  v_next := (v_period + interval '1 month')::date;
  perform pg_advisory_xact_lock(hashtextextended(p_business_id::text || ':' || v_period::text, 0));

  if exists (
    select 1 from public.monthly_closures c
    where c.business_id = p_business_id and c.period_start = v_period and c.status = 'closed'
  ) then
    raise exception 'Ese mes ya está cerrado.' using errcode = 'P0001';
  end if;

  select
    count(*)::integer,
    coalesce(sum(case when t.type='income' then t.usd_bcv else 0 end),0),
    coalesce(sum(case when t.type='expense' then t.usd_bcv else 0 end),0),
    coalesce(sum(case when t.type='income' then t.ves else 0 end),0),
    coalesce(sum(case when t.type='expense' then t.ves else 0 end),0),
    coalesce(sum(case when t.type='income' then t.usdc_airtm else 0 end),0),
    coalesce(sum(case when t.type='expense' then t.usdc_airtm else 0 end),0),
    count(*) filter (where btrim(coalesce(t.description,''))='')::integer,
    count(*) filter (where btrim(coalesce(t.category,''))='' or lower(btrim(t.category))='otros')::integer,
    count(*) filter (
      where t.type='expense' and not exists (
        select 1 from public.transaction_attachments a where a.transaction_id=t.id
      )
    )::integer,
    coalesce(jsonb_agg(to_jsonb(t) order by t.occurred_on, t.created_at), '[]'::jsonb)
  into v_count,v_income_usd,v_expense_usd,v_income_ves,v_expense_ves,v_income_usdc,v_expense_usdc,
       v_missing_description,v_other_category,v_expense_without_receipt,v_transactions
  from public.transactions t
  where t.business_id=p_business_id and t.occurred_on>=v_period and t.occurred_on<v_next;

  select
    coalesce(sum(case when t.type='income' then t.usd_bcv else -t.usd_bcv end),0),
    coalesce(sum(case when t.type='income' then t.ves else -t.ves end),0),
    coalesce(sum(case when t.type='income' then t.usdc_airtm else -t.usdc_airtm end),0)
  into v_open_usd,v_open_ves,v_open_usdc
  from public.transactions t
  where t.business_id=p_business_id and t.occurred_on<v_period;

  select coalesce(jsonb_agg(x order by (x->>'total_usd')::numeric desc), '[]'::jsonb)
  into v_categories
  from (
    select jsonb_build_object(
      'category', t.category,
      'income_usd', coalesce(sum(case when t.type='income' then t.usd_bcv else 0 end),0),
      'expense_usd', coalesce(sum(case when t.type='expense' then t.usd_bcv else 0 end),0),
      'total_usd', coalesce(sum(t.usd_bcv),0),
      'count', count(*)
    ) x
    from public.transactions t
    where t.business_id=p_business_id and t.occurred_on>=v_period and t.occurred_on<v_next
    group by t.category
  ) q;

  v_warnings := jsonb_build_object(
    'missing_description', v_missing_description,
    'other_category', v_other_category,
    'expense_without_receipt', v_expense_without_receipt
  );
  v_summary := jsonb_build_object(
    'transaction_count',v_count,
    'income_usd',v_income_usd,'expense_usd',v_expense_usd,'net_usd',v_income_usd-v_expense_usd,
    'income_ves',v_income_ves,'expense_ves',v_expense_ves,'net_ves',v_income_ves-v_expense_ves,
    'income_usdc',v_income_usdc,'expense_usdc',v_expense_usdc,'net_usdc',v_income_usdc-v_expense_usdc,
    'opening_usd',v_open_usd,'closing_usd',v_open_usd+v_income_usd-v_expense_usd,
    'opening_ves',v_open_ves,'closing_ves',v_open_ves+v_income_ves-v_expense_ves,
    'opening_usdc',v_open_usdc,'closing_usdc',v_open_usdc+v_income_usdc-v_expense_usdc
  );
  v_snapshot := jsonb_build_object(
    'period_start',v_period,
    'period_end',(v_next-1),
    'summary',v_summary,
    'warnings',v_warnings,
    'categories',v_categories,
    'transactions',v_transactions,
    'captured_at',now()
  );

  insert into public.monthly_closures(
    business_id,period_start,status,transaction_count,
    income_usd,expense_usd,net_usd,income_ves,expense_ves,net_ves,income_usdc,expense_usdc,net_usdc,
    opening_usd,closing_usd,opening_ves,closing_ves,opening_usdc,closing_usdc,
    warnings,snapshot,closed_at,closed_by,updated_at
  ) values (
    p_business_id,v_period,'closed',v_count,
    v_income_usd,v_expense_usd,v_income_usd-v_expense_usd,
    v_income_ves,v_expense_ves,v_income_ves-v_expense_ves,
    v_income_usdc,v_expense_usdc,v_income_usdc-v_expense_usdc,
    v_open_usd,v_open_usd+v_income_usd-v_expense_usd,
    v_open_ves,v_open_ves+v_income_ves-v_expense_ves,
    v_open_usdc,v_open_usdc+v_income_usdc-v_expense_usdc,
    v_warnings,v_snapshot,now(),v_user,now()
  )
  on conflict (business_id,period_start) do update set
    status='closed',
    transaction_count=excluded.transaction_count,
    income_usd=excluded.income_usd, expense_usd=excluded.expense_usd, net_usd=excluded.net_usd,
    income_ves=excluded.income_ves, expense_ves=excluded.expense_ves, net_ves=excluded.net_ves,
    income_usdc=excluded.income_usdc, expense_usdc=excluded.expense_usdc, net_usdc=excluded.net_usdc,
    opening_usd=excluded.opening_usd, closing_usd=excluded.closing_usd,
    opening_ves=excluded.opening_ves, closing_ves=excluded.closing_ves,
    opening_usdc=excluded.opening_usdc, closing_usdc=excluded.closing_usdc,
    warnings=excluded.warnings, snapshot=excluded.snapshot,
    closed_at=excluded.closed_at, closed_by=excluded.closed_by, updated_at=now()
  returning id into v_id;

  insert into public.activity_logs(business_id,user_id,action,description,amount,metadata)
  values(
    p_business_id,v_user,'MONTH_CLOSED','Cierre mensual realizado',v_income_usd-v_expense_usd,
    jsonb_build_object('closure_id',v_id,'period_start',v_period,'summary',v_summary,'warnings',v_warnings)
  );

  return jsonb_build_object('id',v_id,'status','closed','period_start',v_period,'summary',v_summary,'warnings',v_warnings);
end;
$$;

revoke all on function public.close_month(uuid,date) from public;
revoke all on function public.close_month(uuid,date) from anon;
grant execute on function public.close_month(uuid,date) to authenticated;

create or replace function public.reopen_month(p_business_id uuid, p_period_start date, p_reason text default '')
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_period date;
  v_id uuid;
  v_reason text := btrim(coalesce(p_reason,''));
begin
  if v_user is null then raise exception 'Debes iniciar sesión.' using errcode = 'P0001'; end if;
  if p_period_start is null then raise exception 'Selecciona un mes.' using errcode = 'P0001'; end if;
  if not public.is_business_owner(p_business_id) then
    raise exception 'Solo el propietario puede reabrir el mes.' using errcode = 'P0001';
  end if;
  if v_reason = '' then raise exception 'Indica el motivo de la reapertura.' using errcode = 'P0001'; end if;

  v_period := date_trunc('month', p_period_start)::date;
  perform pg_advisory_xact_lock(hashtextextended(p_business_id::text || ':' || v_period::text, 0));

  update public.monthly_closures
  set status='reopened', reopened_at=now(), reopened_by=v_user,
      reopen_reason=v_reason, reopen_count=reopen_count+1, updated_at=now()
  where business_id=p_business_id and period_start=v_period and status='closed'
  returning id into v_id;

  if v_id is null then
    raise exception 'Ese mes no está cerrado.' using errcode = 'P0001';
  end if;

  insert into public.activity_logs(business_id,user_id,action,description,metadata)
  values(
    p_business_id,v_user,'MONTH_REOPENED','Cierre mensual reabierto',
    jsonb_build_object('closure_id',v_id,'period_start',v_period,'reason',v_reason)
  );

  return jsonb_build_object('id',v_id,'status','reopened','period_start',v_period,'reason',v_reason);
end;
$$;

revoke all on function public.reopen_month(uuid,date,text) from public;
revoke all on function public.reopen_month(uuid,date,text) from anon;
grant execute on function public.reopen_month(uuid,date,text) to authenticated;

-- Realtime para que ambos socios vean el estado del cierre al instante.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public' and tablename='monthly_closures'
  ) then
    alter publication supabase_realtime add table public.monthly_closures;
  end if;
end $$;
