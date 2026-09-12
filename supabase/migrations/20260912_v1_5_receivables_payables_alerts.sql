-- E-conomic v1.5 — cuentas por cobrar/pagar y alertas
-- Obligaciones compartidas, abonos parciales, vínculo con movimientos y control por roles.

create table if not exists public.obligations (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  kind text not null check (kind in ('receivable','payable')),
  counterparty text not null,
  contact text not null default '',
  description text not null default '',
  reference text not null default '',
  notes text not null default '',
  category text not null default 'Otros',
  amount_original numeric(20,6) not null check (amount_original > 0),
  original_currency text not null check (original_currency in ('VES','USD','USDC')),
  bcv_rate numeric(20,8) not null check (bcv_rate > 0),
  airtm_rate numeric(20,8) not null check (airtm_rate > 0),
  usd_bcv numeric(20,6) not null check (usd_bcv >= 0),
  ves numeric(20,6) not null check (ves >= 0),
  usdc_airtm numeric(20,6) not null check (usdc_airtm >= 0),
  issue_date date not null default current_date,
  due_date date not null,
  alert_days integer not null default 7 check (alert_days between 0 and 90),
  status text not null default 'open' check (status in ('open','partial','paid','cancelled')),
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid not null references auth.users(id) on delete restrict,
  paid_at timestamptz,
  cancelled_at timestamptz,
  cancelled_by uuid references auth.users(id) on delete set null,
  cancellation_reason text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint obligations_due_after_issue check (due_date >= issue_date),
  constraint obligations_counterparty_nonempty check (length(btrim(counterparty)) > 0)
);

create table if not exists public.obligation_payments (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  obligation_id uuid not null references public.obligations(id) on delete cascade,
  amount_original numeric(20,6) not null check (amount_original > 0),
  original_currency text not null check (original_currency in ('VES','USD','USDC')),
  applied_original numeric(20,6) not null check (applied_original > 0),
  bcv_rate numeric(20,8) not null check (bcv_rate > 0),
  airtm_rate numeric(20,8) not null check (airtm_rate > 0),
  usd_bcv numeric(20,6) not null check (usd_bcv >= 0),
  ves numeric(20,6) not null check (ves >= 0),
  usdc_airtm numeric(20,6) not null check (usdc_airtm >= 0),
  paid_on date not null default current_date,
  note text not null default '',
  transaction_id uuid references public.transactions(id) on delete set null,
  status text not null default 'posted' check (status in ('posted','voided')),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  voided_at timestamptz,
  voided_by uuid references auth.users(id) on delete set null,
  void_reason text not null default ''
);

create index if not exists idx_obligations_business_due on public.obligations(business_id,due_date);
create index if not exists idx_obligations_business_status on public.obligations(business_id,status,kind);
create index if not exists idx_obligations_created_by on public.obligations(created_by);
create index if not exists idx_obligation_payments_obligation on public.obligation_payments(obligation_id,status,paid_on);
create index if not exists idx_obligation_payments_business on public.obligation_payments(business_id,paid_on desc);
create unique index if not exists idx_obligation_payments_transaction on public.obligation_payments(transaction_id) where transaction_id is not null;

alter table public.obligations enable row level security;
alter table public.obligation_payments enable row level security;
revoke all on public.obligations from anon, authenticated;
revoke all on public.obligation_payments from anon, authenticated;
grant select on public.obligations to authenticated;
grant select on public.obligation_payments to authenticated;

drop policy if exists obligations_select on public.obligations;
create policy obligations_select on public.obligations for select to authenticated using (public.is_business_member(business_id));
drop policy if exists obligation_payments_select on public.obligation_payments;
create policy obligation_payments_select on public.obligation_payments for select to authenticated using (public.is_business_member(business_id));

create or replace function public.touch_obligation_updated_at() returns trigger language plpgsql security definer set search_path=public as $$
begin new.updated_at:=now();return new;end;$$;
revoke all on function public.touch_obligation_updated_at() from public,anon,authenticated;
drop trigger if exists trg_obligations_updated_at on public.obligations;
create trigger trg_obligations_updated_at before update on public.obligations for each row execute function public.touch_obligation_updated_at();

create or replace function public.create_obligation(
  p_business_id uuid,p_kind text,p_counterparty text,p_contact text,p_description text,p_reference text,p_notes text,p_category text,
  p_amount_original numeric,p_original_currency text,p_bcv_rate numeric,p_airtm_rate numeric,p_issue_date date,p_due_date date,p_alert_days integer default 7
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_user uuid:=auth.uid();v_id uuid;v_usd numeric;v_ves numeric;v_usdc numeric;
begin
  if v_user is null then raise exception 'Debes iniciar sesión.' using errcode='P0001';end if;
  if not public.is_business_member(p_business_id) then raise exception 'No perteneces a este negocio.' using errcode='P0001';end if;
  if p_kind not in ('receivable','payable') then raise exception 'Tipo de cuenta no válido.' using errcode='P0001';end if;
  if length(btrim(coalesce(p_counterparty,'')))=0 then raise exception 'Indica cliente o proveedor.' using errcode='P0001';end if;
  if coalesce(p_amount_original,0)<=0 then raise exception 'El monto debe ser mayor que cero.' using errcode='P0001';end if;
  if p_original_currency not in ('VES','USD','USDC') then raise exception 'Moneda no válida.' using errcode='P0001';end if;
  if coalesce(p_bcv_rate,0)<=0 or coalesce(p_airtm_rate,0)<=0 then raise exception 'No hay tasas válidas.' using errcode='P0001';end if;
  if p_due_date is null or p_issue_date is null or p_due_date<p_issue_date then raise exception 'La fecha de vencimiento no puede ser anterior a la fecha de emisión.' using errcode='P0001';end if;
  if p_original_currency='VES' then v_ves:=p_amount_original;v_usd:=v_ves/p_bcv_rate;v_usdc:=v_ves/p_airtm_rate;
  elsif p_original_currency='USD' then v_usd:=p_amount_original;v_ves:=v_usd*p_bcv_rate;v_usdc:=v_ves/p_airtm_rate;
  else v_usdc:=p_amount_original;v_ves:=v_usdc*p_airtm_rate;v_usd:=v_ves/p_bcv_rate;end if;
  insert into public.obligations(business_id,kind,counterparty,contact,description,reference,notes,category,amount_original,original_currency,bcv_rate,airtm_rate,usd_bcv,ves,usdc_airtm,issue_date,due_date,alert_days,created_by,updated_by)
  values(p_business_id,p_kind,btrim(p_counterparty),btrim(coalesce(p_contact,'')),btrim(coalesce(p_description,'')),btrim(coalesce(p_reference,'')),coalesce(p_notes,''),coalesce(nullif(btrim(p_category),''),'Otros'),p_amount_original,p_original_currency,p_bcv_rate,p_airtm_rate,v_usd,v_ves,v_usdc,p_issue_date,p_due_date,least(90,greatest(0,coalesce(p_alert_days,7))),v_user,v_user) returning id into v_id;
  perform public.log_activity(p_business_id,case when p_kind='receivable' then 'RECEIVABLE_CREATED' else 'PAYABLE_CREATED' end,case when p_kind='receivable' then 'Cuenta por cobrar creada' else 'Cuenta por pagar creada' end,v_usd,jsonb_build_object('obligation_id',v_id,'counterparty',btrim(p_counterparty),'due_date',p_due_date,'amount_original',p_amount_original,'currency',p_original_currency));
  return(select to_jsonb(o) from public.obligations o where o.id=v_id);
end;$$;

create or replace function public.update_obligation(
  p_id uuid,p_counterparty text,p_contact text,p_description text,p_reference text,p_notes text,p_category text,p_amount_original numeric,p_original_currency text,p_bcv_rate numeric,p_airtm_rate numeric,p_issue_date date,p_due_date date,p_alert_days integer default 7
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_user uuid:=auth.uid();v_old public.obligations%rowtype;v_payments integer;v_usd numeric;v_ves numeric;v_usdc numeric;
begin
  select * into v_old from public.obligations where id=p_id for update;if v_old.id is null then raise exception 'Cuenta no encontrada.' using errcode='P0001';end if;
  if v_user is null or not public.is_business_member(v_old.business_id) then raise exception 'Sin acceso.' using errcode='P0001';end if;
  if not(public.is_business_owner(v_old.business_id) or v_old.created_by=v_user) then raise exception 'No tienes permiso para editar esta cuenta.' using errcode='P0001';end if;
  if v_old.status='cancelled' then raise exception 'La cuenta está anulada.' using errcode='P0001';end if;
  if length(btrim(coalesce(p_counterparty,'')))=0 then raise exception 'Indica cliente o proveedor.' using errcode='P0001';end if;
  if coalesce(p_amount_original,0)<=0 or p_original_currency not in ('VES','USD','USDC') or coalesce(p_bcv_rate,0)<=0 or coalesce(p_airtm_rate,0)<=0 then raise exception 'Revisa monto, moneda y tasas.' using errcode='P0001';end if;
  if p_due_date is null or p_issue_date is null or p_due_date<p_issue_date then raise exception 'La fecha de vencimiento no puede ser anterior a la fecha de emisión.' using errcode='P0001';end if;
  select count(*)::integer into v_payments from public.obligation_payments where obligation_id=p_id and status='posted';
  if v_payments>0 and(p_amount_original is distinct from v_old.amount_original or p_original_currency is distinct from v_old.original_currency) then raise exception 'No puedes cambiar monto o moneda después de registrar abonos. Anula los abonos primero.' using errcode='P0001';end if;
  if p_original_currency='VES' then v_ves:=p_amount_original;v_usd:=v_ves/p_bcv_rate;v_usdc:=v_ves/p_airtm_rate;elsif p_original_currency='USD' then v_usd:=p_amount_original;v_ves:=v_usd*p_bcv_rate;v_usdc:=v_ves/p_airtm_rate;else v_usdc:=p_amount_original;v_ves:=v_usdc*p_airtm_rate;v_usd:=v_ves/p_bcv_rate;end if;
  update public.obligations set counterparty=btrim(p_counterparty),contact=btrim(coalesce(p_contact,'')),description=btrim(coalesce(p_description,'')),reference=btrim(coalesce(p_reference,'')),notes=coalesce(p_notes,''),category=coalesce(nullif(btrim(p_category),''),'Otros'),amount_original=p_amount_original,original_currency=p_original_currency,bcv_rate=p_bcv_rate,airtm_rate=p_airtm_rate,usd_bcv=v_usd,ves=v_ves,usdc_airtm=v_usdc,issue_date=p_issue_date,due_date=p_due_date,alert_days=least(90,greatest(0,coalesce(p_alert_days,7))),updated_by=v_user where id=p_id;
  perform public.log_activity(v_old.business_id,'OBLIGATION_UPDATED','Cuenta actualizada',v_usd,jsonb_build_object('obligation_id',p_id,'kind',v_old.kind,'counterparty',btrim(p_counterparty),'due_date',p_due_date));
  return(select to_jsonb(o) from public.obligations o where o.id=p_id);
end;$$;

create or replace function public.cancel_obligation(p_id uuid,p_reason text default '') returns jsonb language plpgsql security definer set search_path=public as $$
declare v_user uuid:=auth.uid();v_o public.obligations%rowtype;
begin
  select * into v_o from public.obligations where id=p_id for update;if v_o.id is null then raise exception 'Cuenta no encontrada.' using errcode='P0001';end if;
  if v_user is null or not public.is_business_member(v_o.business_id) then raise exception 'Sin acceso.' using errcode='P0001';end if;
  if not(public.is_business_owner(v_o.business_id) or v_o.created_by=v_user) then raise exception 'No tienes permiso para anular esta cuenta.' using errcode='P0001';end if;
  if v_o.status='paid' then raise exception 'Una cuenta pagada/cobrada no se puede anular. Anula primero sus abonos.' using errcode='P0001';end if;
  if v_o.status='cancelled' then return to_jsonb(v_o);end if;
  update public.obligations set status='cancelled',cancelled_at=now(),cancelled_by=v_user,cancellation_reason=btrim(coalesce(p_reason,'')),updated_by=v_user where id=p_id;
  perform public.log_activity(v_o.business_id,'OBLIGATION_CANCELLED','Cuenta anulada',v_o.usd_bcv,jsonb_build_object('obligation_id',p_id,'kind',v_o.kind,'counterparty',v_o.counterparty,'reason',btrim(coalesce(p_reason,''))));
  return(select to_jsonb(o) from public.obligations o where o.id=p_id);
end;$$;

create or replace function public.delete_obligation(p_id uuid) returns boolean language plpgsql security definer set search_path=public as $$
declare v_user uuid:=auth.uid();v_o public.obligations%rowtype;v_count integer;
begin
  select * into v_o from public.obligations where id=p_id for update;if v_o.id is null then return false;end if;
  if v_user is null or not public.is_business_member(v_o.business_id) then raise exception 'Sin acceso.' using errcode='P0001';end if;
  if not(public.is_business_owner(v_o.business_id) or v_o.created_by=v_user) then raise exception 'No tienes permiso para eliminar esta cuenta.' using errcode='P0001';end if;
  select count(*)::integer into v_count from public.obligation_payments where obligation_id=p_id;if v_count>0 then raise exception 'Esta cuenta tiene historial de abonos. Anúlala en lugar de eliminarla.' using errcode='P0001';end if;
  perform public.log_activity(v_o.business_id,'OBLIGATION_DELETED','Cuenta eliminada',v_o.usd_bcv,jsonb_build_object('obligation_id',p_id,'kind',v_o.kind,'counterparty',v_o.counterparty));delete from public.obligations where id=p_id;return true;
end;$$;

create or replace function public.record_obligation_payment(
  p_obligation_id uuid,p_amount_original numeric,p_original_currency text,p_bcv_rate numeric,p_airtm_rate numeric,p_paid_on date,p_note text default ''
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_user uuid:=auth.uid();v_o public.obligations%rowtype;v_payment_id uuid;v_tx_id uuid;v_usd numeric;v_ves numeric;v_usdc numeric;v_applied numeric;v_paid_before numeric:=0;v_paid_after numeric:=0;v_remaining numeric:=0;v_new_status text;v_desc text;
begin
  select * into v_o from public.obligations where id=p_obligation_id for update;if v_o.id is null then raise exception 'Cuenta no encontrada.' using errcode='P0001';end if;
  if v_user is null or not public.is_business_member(v_o.business_id) then raise exception 'Sin acceso.' using errcode='P0001';end if;
  if v_o.status in('paid','cancelled') then raise exception 'Esta cuenta ya está cerrada.' using errcode='P0001';end if;
  if coalesce(p_amount_original,0)<=0 or p_original_currency not in('VES','USD','USDC') or coalesce(p_bcv_rate,0)<=0 or coalesce(p_airtm_rate,0)<=0 then raise exception 'Revisa monto, moneda y tasas.' using errcode='P0001';end if;
  if p_paid_on is null then raise exception 'Indica la fecha del cobro/pago.' using errcode='P0001';end if;
  if p_original_currency='VES' then v_ves:=p_amount_original;v_usd:=v_ves/p_bcv_rate;v_usdc:=v_ves/p_airtm_rate;elsif p_original_currency='USD' then v_usd:=p_amount_original;v_ves:=v_usd*p_bcv_rate;v_usdc:=v_ves/p_airtm_rate;else v_usdc:=p_amount_original;v_ves:=v_usdc*p_airtm_rate;v_usd:=v_ves/p_bcv_rate;end if;
  if v_o.original_currency='VES' then v_applied:=v_ves;elsif v_o.original_currency='USD' then v_applied:=v_ves/p_bcv_rate;else v_applied:=v_ves/p_airtm_rate;end if;
  select coalesce(sum(applied_original),0) into v_paid_before from public.obligation_payments where obligation_id=v_o.id and status='posted';v_remaining:=greatest(v_o.amount_original-v_paid_before,0);
  if v_applied>v_remaining+0.01 then raise exception 'El abono supera el saldo pendiente (% %).',round(v_remaining,2),v_o.original_currency using errcode='P0001';end if;if v_applied>v_remaining then v_applied:=v_remaining;end if;
  v_desc:=case when v_o.kind='receivable' then 'Cobro de ' else 'Pago a ' end||v_o.counterparty||case when btrim(v_o.description)<>'' then ' · '||v_o.description else '' end;
  insert into public.transactions(business_id,type,amount_original,original_currency,category,description,occurred_on,bcv_rate,airtm_rate,usd_bcv,ves,usdc_airtm,created_by,updated_by,reference,notes,tags)
  values(v_o.business_id,case when v_o.kind='receivable' then 'income' else 'expense' end,p_amount_original,p_original_currency,coalesce(nullif(v_o.category,''),'Otros'),v_desc,p_paid_on,p_bcv_rate,p_airtm_rate,v_usd,v_ves,v_usdc,v_user,v_user,v_o.reference,btrim(coalesce(p_note,'')),array[case when v_o.kind='receivable' then 'cuenta-por-cobrar' else 'cuenta-por-pagar' end]) returning id into v_tx_id;
  insert into public.obligation_payments(business_id,obligation_id,amount_original,original_currency,applied_original,bcv_rate,airtm_rate,usd_bcv,ves,usdc_airtm,paid_on,note,transaction_id,created_by)
  values(v_o.business_id,v_o.id,p_amount_original,p_original_currency,v_applied,p_bcv_rate,p_airtm_rate,v_usd,v_ves,v_usdc,p_paid_on,btrim(coalesce(p_note,'')),v_tx_id,v_user) returning id into v_payment_id;
  select coalesce(sum(applied_original),0) into v_paid_after from public.obligation_payments where obligation_id=v_o.id and status='posted';if v_paid_after>=v_o.amount_original-0.01 then v_new_status:='paid';else v_new_status:='partial';end if;
  update public.obligations set status=v_new_status,paid_at=case when v_new_status='paid' then now() else null end,updated_by=v_user where id=v_o.id;
  perform public.log_activity(v_o.business_id,case when v_o.kind='receivable' then 'RECEIVABLE_PAYMENT' else 'PAYABLE_PAYMENT' end,case when v_o.kind='receivable' then 'Cobro registrado' else 'Pago registrado' end,v_usd,jsonb_build_object('obligation_id',v_o.id,'payment_id',v_payment_id,'transaction_id',v_tx_id,'counterparty',v_o.counterparty,'applied_original',v_applied,'obligation_currency',v_o.original_currency,'paid_on',p_paid_on));
  return jsonb_build_object('payment_id',v_payment_id,'transaction_id',v_tx_id,'status',v_new_status,'paid_original',v_paid_after,'remaining_original',greatest(v_o.amount_original-v_paid_after,0));
end;$$;

create or replace function public.void_obligation_payment(p_payment_id uuid,p_reason text default '') returns jsonb language plpgsql security definer set search_path=public as $$
declare v_user uuid:=auth.uid();v_p public.obligation_payments%rowtype;v_o public.obligations%rowtype;v_paid numeric:=0;v_status text;
begin
  select * into v_p from public.obligation_payments where id=p_payment_id for update;if v_p.id is null then raise exception 'Abono no encontrado.' using errcode='P0001';end if;select * into v_o from public.obligations where id=v_p.obligation_id for update;
  if v_user is null or not public.is_business_member(v_p.business_id) then raise exception 'Sin acceso.' using errcode='P0001';end if;if not(public.is_business_owner(v_p.business_id) or v_p.created_by=v_user) then raise exception 'No tienes permiso para anular este abono.' using errcode='P0001';end if;if v_p.status='voided' then return jsonb_build_object('payment_id',v_p.id,'status','voided');end if;
  if v_p.transaction_id is not null then delete from public.transactions where id=v_p.transaction_id;end if;update public.obligation_payments set status='voided',voided_at=now(),voided_by=v_user,void_reason=btrim(coalesce(p_reason,'')) where id=v_p.id;
  select coalesce(sum(applied_original),0) into v_paid from public.obligation_payments where obligation_id=v_o.id and status='posted';if v_o.status<>'cancelled' then if v_paid<=.000001 then v_status:='open';elsif v_paid>=v_o.amount_original-0.01 then v_status:='paid';else v_status:='partial';end if;update public.obligations set status=v_status,paid_at=case when v_status='paid' then paid_at else null end,updated_by=v_user where id=v_o.id;else v_status:='cancelled';end if;
  perform public.log_activity(v_p.business_id,'OBLIGATION_PAYMENT_VOIDED','Abono anulado',v_p.usd_bcv,jsonb_build_object('obligation_id',v_o.id,'payment_id',v_p.id,'counterparty',v_o.counterparty,'reason',btrim(coalesce(p_reason,''))));return jsonb_build_object('payment_id',v_p.id,'status','voided','obligation_status',v_status,'paid_original',v_paid,'remaining_original',greatest(v_o.amount_original-v_paid,0));
end;$$;

revoke all on function public.create_obligation(uuid,text,text,text,text,text,text,text,numeric,text,numeric,numeric,date,date,integer) from public,anon;
revoke all on function public.update_obligation(uuid,text,text,text,text,text,text,numeric,text,numeric,numeric,date,date,integer) from public,anon;
revoke all on function public.cancel_obligation(uuid,text) from public,anon;
revoke all on function public.delete_obligation(uuid) from public,anon;
revoke all on function public.record_obligation_payment(uuid,numeric,text,numeric,numeric,date,text) from public,anon;
revoke all on function public.void_obligation_payment(uuid,text) from public,anon;
grant execute on function public.create_obligation(uuid,text,text,text,text,text,text,text,numeric,text,numeric,numeric,date,date,integer) to authenticated;
grant execute on function public.update_obligation(uuid,text,text,text,text,text,text,numeric,text,numeric,numeric,date,date,integer) to authenticated;
grant execute on function public.cancel_obligation(uuid,text) to authenticated;
grant execute on function public.delete_obligation(uuid) to authenticated;
grant execute on function public.record_obligation_payment(uuid,numeric,text,numeric,numeric,date,text) to authenticated;
grant execute on function public.void_obligation_payment(uuid,text) to authenticated;

do $$begin
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='obligations') then alter publication supabase_realtime add table public.obligations;end if;
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='obligation_payments') then alter publication supabase_realtime add table public.obligation_payments;end if;
end$$;
