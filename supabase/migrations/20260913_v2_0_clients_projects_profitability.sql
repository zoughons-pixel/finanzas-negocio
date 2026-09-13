-- E-conomic v2.0 — clientes, proyectos y rentabilidad

create table if not exists public.clients (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null,
  company text not null default '',
  contact_name text not null default '',
  email text not null default '',
  phone text not null default '',
  notes text not null default '',
  status text not null default 'active' check (status in ('active','inactive','archived')),
  created_by uuid not null references auth.users(id),
  updated_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.projects (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  client_id uuid references public.clients(id) on delete set null,
  name text not null,
  description text not null default '',
  status text not null default 'active' check (status in ('active','paused','completed','archived')),
  start_date date,
  end_date date,
  budget_usd numeric,
  created_by uuid not null references auth.users(id),
  updated_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.transactions add column if not exists client_id uuid references public.clients(id) on delete set null;
alter table public.transactions add column if not exists project_id uuid references public.projects(id) on delete set null;

create index if not exists idx_clients_business_status on public.clients(business_id,status,name);
create index if not exists idx_clients_created_by on public.clients(created_by);
create index if not exists idx_clients_updated_by on public.clients(updated_by);
create index if not exists idx_projects_business_status on public.projects(business_id,status,name);
create index if not exists idx_projects_client_id on public.projects(client_id);
create index if not exists idx_projects_created_by on public.projects(created_by);
create index if not exists idx_projects_updated_by on public.projects(updated_by);
create index if not exists idx_transactions_client_id on public.transactions(client_id) where client_id is not null;
create index if not exists idx_transactions_project_id on public.transactions(project_id) where project_id is not null;

alter table public.clients enable row level security;
alter table public.projects enable row level security;
revoke all on public.clients, public.projects from anon;
grant select,insert,update,delete on public.clients,public.projects to authenticated;

drop policy if exists clients_select on public.clients;
create policy clients_select on public.clients for select to authenticated using (public.is_business_member(business_id));
drop policy if exists clients_insert on public.clients;
create policy clients_insert on public.clients for insert to authenticated with check (public.is_business_member(business_id) and created_by=(select auth.uid()) and updated_by=(select auth.uid()));
drop policy if exists clients_update on public.clients;
create policy clients_update on public.clients for update to authenticated using (public.is_business_member(business_id) and (public.is_business_owner(business_id) or created_by=(select auth.uid()))) with check (public.is_business_member(business_id) and (public.is_business_owner(business_id) or created_by=(select auth.uid())) and updated_by=(select auth.uid()));
drop policy if exists clients_delete on public.clients;
create policy clients_delete on public.clients for delete to authenticated using (public.is_business_member(business_id) and (public.is_business_owner(business_id) or created_by=(select auth.uid())));

drop policy if exists projects_select on public.projects;
create policy projects_select on public.projects for select to authenticated using (public.is_business_member(business_id));
drop policy if exists projects_insert on public.projects;
create policy projects_insert on public.projects for insert to authenticated with check (public.is_business_member(business_id) and created_by=(select auth.uid()) and updated_by=(select auth.uid()));
drop policy if exists projects_update on public.projects;
create policy projects_update on public.projects for update to authenticated using (public.is_business_member(business_id) and (public.is_business_owner(business_id) or created_by=(select auth.uid()))) with check (public.is_business_member(business_id) and (public.is_business_owner(business_id) or created_by=(select auth.uid())) and updated_by=(select auth.uid()));
drop policy if exists projects_delete on public.projects;
create policy projects_delete on public.projects for delete to authenticated using (public.is_business_member(business_id) and (public.is_business_owner(business_id) or created_by=(select auth.uid())));

create or replace function public.validate_transaction_dimensions()
returns trigger language plpgsql set search_path=public as $$
declare vpb uuid; vpc uuid; vcb uuid;
begin
  if new.project_id is not null then
    select business_id,client_id into vpb,vpc from public.projects where id=new.project_id;
    if vpb is null then raise exception 'Proyecto no válido'; end if;
    if vpb<>new.business_id then raise exception 'El proyecto pertenece a otro negocio'; end if;
    if new.client_id is null and vpc is not null then new.client_id:=vpc; end if;
    if new.client_id is not null and vpc is not null and new.client_id<>vpc then raise exception 'El cliente no coincide con el proyecto'; end if;
  end if;
  if new.client_id is not null then
    select business_id into vcb from public.clients where id=new.client_id;
    if vcb is null then raise exception 'Cliente no válido'; end if;
    if vcb<>new.business_id then raise exception 'El cliente pertenece a otro negocio'; end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_transactions_dimensions on public.transactions;
create trigger trg_transactions_dimensions before insert or update of business_id,client_id,project_id on public.transactions for each row execute function public.validate_transaction_dimensions();

drop trigger if exists trg_clients_updated_at on public.clients;
create trigger trg_clients_updated_at before update on public.clients for each row execute function public.touch_updated_at();
drop trigger if exists trg_projects_updated_at on public.projects;
create trigger trg_projects_updated_at before update on public.projects for each row execute function public.touch_updated_at();

create or replace function public.audit_v2_entity_changes()
returns trigger language plpgsql security definer set search_path=public as $$
declare vb uuid; vid uuid; vn text; va text;
begin
  if tg_op='DELETE' then vb:=old.business_id;vid:=old.id;vn:=old.name; else vb:=new.business_id;vid:=new.id;vn:=new.name; end if;
  va:=upper(tg_table_name)||'_'||case tg_op when 'INSERT' then 'CREATED' when 'UPDATE' then 'UPDATED' else 'DELETED' end;
  perform public.log_activity(vb,va,case tg_table_name when 'clients' then 'Cliente' else 'Proyecto' end||' '||lower(case tg_op when 'INSERT' then 'creado' when 'UPDATE' then 'actualizado' else 'eliminado' end),null,jsonb_build_object('entity_id',vid,'name',vn,'old',case when tg_op in ('UPDATE','DELETE') then to_jsonb(old)-'business_id' else null end,'new',case when tg_op in ('INSERT','UPDATE') then to_jsonb(new)-'business_id' else null end));
  return case when tg_op='DELETE' then old else new end;
end $$;
revoke execute on function public.audit_v2_entity_changes() from public,anon,authenticated;

drop trigger if exists trg_clients_activity on public.clients;
create trigger trg_clients_activity after insert or update or delete on public.clients for each row execute function public.audit_v2_entity_changes();
drop trigger if exists trg_projects_activity on public.projects;
create trigger trg_projects_activity after insert or update or delete on public.projects for each row execute function public.audit_v2_entity_changes();

create or replace view public.client_profitability with (security_invoker=true) as
select c.id,c.business_id,c.name,c.company,c.status,
coalesce(sum(case when t.type='income' then t.usd_bcv else 0 end),0)::numeric income_usd,
coalesce(sum(case when t.type='expense' then t.usd_bcv else 0 end),0)::numeric expense_usd,
coalesce(sum(case when t.type='income' then t.usd_bcv else -t.usd_bcv end),0)::numeric net_usd,
count(t.id)::bigint movement_count
from public.clients c left join public.transactions t on t.client_id=c.id and t.business_id=c.business_id
group by c.id,c.business_id,c.name,c.company,c.status;

create or replace view public.project_profitability with (security_invoker=true) as
select p.id,p.business_id,p.client_id,p.name,p.status,p.budget_usd,
coalesce(sum(case when t.type='income' then t.usd_bcv else 0 end),0)::numeric income_usd,
coalesce(sum(case when t.type='expense' then t.usd_bcv else 0 end),0)::numeric expense_usd,
coalesce(sum(case when t.type='income' then t.usd_bcv else -t.usd_bcv end),0)::numeric net_usd,
count(t.id)::bigint movement_count
from public.projects p left join public.transactions t on t.project_id=p.id and t.business_id=p.business_id
group by p.id,p.business_id,p.client_id,p.name,p.status,p.budget_usd;

grant select on public.client_profitability,public.project_profitability to authenticated;
revoke all on public.client_profitability,public.project_profitability from anon;

do $$ begin
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='clients') then alter publication supabase_realtime add table public.clients; end if;
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='projects') then alter publication supabase_realtime add table public.projects; end if;
end $$;
