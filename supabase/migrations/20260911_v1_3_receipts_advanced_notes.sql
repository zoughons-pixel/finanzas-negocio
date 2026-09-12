-- E-conomic v1.3 — comprobantes/fotos y notas avanzadas

alter table public.transactions
  add column if not exists reference text not null default '',
  add column if not exists notes text not null default '',
  add column if not exists tags text[] not null default '{}'::text[];

do $$
begin
  if not exists (select 1 from pg_constraint where conname='transactions_reference_length') then
    alter table public.transactions add constraint transactions_reference_length check (char_length(reference) <= 200);
  end if;
  if not exists (select 1 from pg_constraint where conname='transactions_notes_length') then
    alter table public.transactions add constraint transactions_notes_length check (char_length(notes) <= 5000);
  end if;
  if not exists (select 1 from pg_constraint where conname='transactions_tags_count') then
    alter table public.transactions add constraint transactions_tags_count check (coalesce(array_length(tags,1),0) <= 20);
  end if;
end $$;

create table if not exists public.transaction_attachments (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  transaction_id uuid not null references public.transactions(id) on delete cascade,
  storage_path text not null unique,
  file_name text not null,
  mime_type text not null check (mime_type in ('image/jpeg','image/png','image/webp','application/pdf')),
  size_bytes bigint not null check (size_bytes > 0 and size_bytes <= 10485760),
  uploaded_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);

create index if not exists idx_transaction_attachments_tx
  on public.transaction_attachments(transaction_id, created_at desc);
create index if not exists idx_transaction_attachments_business
  on public.transaction_attachments(business_id, created_at desc);

alter table public.transaction_attachments enable row level security;
revoke all on public.transaction_attachments from anon;
revoke all on public.transaction_attachments from authenticated;
grant select, insert, delete on public.transaction_attachments to authenticated;

drop policy if exists transaction_attachments_select on public.transaction_attachments;
create policy transaction_attachments_select
on public.transaction_attachments for select to authenticated
using (public.is_business_member(business_id));

drop policy if exists transaction_attachments_insert on public.transaction_attachments;
create policy transaction_attachments_insert
on public.transaction_attachments for insert to authenticated
with check (
  public.is_business_member(business_id)
  and uploaded_by = auth.uid()
  and exists (
    select 1 from public.transactions t
    where t.id = transaction_id
      and t.business_id = business_id
      and (public.is_business_owner(t.business_id) or t.created_by = auth.uid())
  )
);

drop policy if exists transaction_attachments_delete on public.transaction_attachments;
create policy transaction_attachments_delete
on public.transaction_attachments for delete to authenticated
using (
  public.is_business_member(business_id)
  and exists (
    select 1 from public.transactions t
    where t.id = transaction_id
      and t.business_id = business_id
      and (public.is_business_owner(t.business_id) or t.created_by = auth.uid())
  )
);

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('transaction-receipts','transaction-receipts',false,10485760,array['image/jpeg','image/png','image/webp','application/pdf']::text[])
on conflict (id) do update set
  public=false,
  file_size_limit=excluded.file_size_limit,
  allowed_mime_types=excluded.allowed_mime_types;

create or replace function public.try_uuid(p_text text)
returns uuid
language plpgsql
immutable
strict
set search_path = public
as $$
begin
  return p_text::uuid;
exception when others then
  return null;
end;
$$;
revoke all on function public.try_uuid(text) from public;
grant execute on function public.try_uuid(text) to authenticated;

drop policy if exists economic_receipts_select on storage.objects;
create policy economic_receipts_select
on storage.objects for select to authenticated
using (
  bucket_id='transaction-receipts'
  and public.is_business_member(public.try_uuid(split_part(name,'/',1)))
);

drop policy if exists economic_receipts_insert on storage.objects;
create policy economic_receipts_insert
on storage.objects for insert to authenticated
with check (
  bucket_id='transaction-receipts'
  and public.is_business_member(public.try_uuid(split_part(name,'/',1)))
  and exists (
    select 1 from public.transactions t
    where t.id = public.try_uuid(split_part(name,'/',2))
      and t.business_id = public.try_uuid(split_part(name,'/',1))
      and (public.is_business_owner(t.business_id) or t.created_by = auth.uid())
  )
);

drop policy if exists economic_receipts_delete on storage.objects;
create policy economic_receipts_delete
on storage.objects for delete to authenticated
using (
  bucket_id='transaction-receipts'
  and public.is_business_member(public.try_uuid(split_part(name,'/',1)))
  and exists (
    select 1 from public.transactions t
    where t.id = public.try_uuid(split_part(name,'/',2))
      and t.business_id = public.try_uuid(split_part(name,'/',1))
      and (public.is_business_owner(t.business_id) or t.created_by = auth.uid())
  )
);

create or replace function public.audit_attachment_changes()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op='INSERT' then
    insert into public.activity_logs(business_id,user_id,action,description,metadata)
    values(new.business_id,auth.uid(),'ATTACHMENT_ADDED','Comprobante agregado',jsonb_build_object('transaction_id',new.transaction_id,'attachment_id',new.id,'file_name',new.file_name,'mime_type',new.mime_type));
    return new;
  elsif tg_op='DELETE' then
    insert into public.activity_logs(business_id,user_id,action,description,metadata)
    values(old.business_id,auth.uid(),'ATTACHMENT_REMOVED','Comprobante eliminado',jsonb_build_object('transaction_id',old.transaction_id,'attachment_id',old.id,'file_name',old.file_name,'mime_type',old.mime_type));
    return old;
  end if;
  return null;
end;
$$;
revoke all on function public.audit_attachment_changes() from public;
revoke execute on function public.audit_attachment_changes() from anon, authenticated;

drop trigger if exists trg_transaction_attachments_activity on public.transaction_attachments;
create trigger trg_transaction_attachments_activity
after insert or delete on public.transaction_attachments
for each row execute function public.audit_attachment_changes();

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public' and tablename='transaction_attachments'
  ) then
    alter publication supabase_realtime add table public.transaction_attachments;
  end if;
end $$;
