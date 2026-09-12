-- E-conomic v1.6 — hardening de seguridad y rendimiento
-- Optimiza RLS, agrega índices faltantes de claves foráneas y refuerza tablas internas.

-- Índices de FK para evitar scans innecesarios, especialmente al validar/eliminar usuarios relacionados.
create index if not exists idx_activity_logs_user_id on public.activity_logs(user_id);
create index if not exists idx_businesses_created_by on public.businesses(created_by);
create index if not exists idx_categories_created_by on public.categories(created_by);
create index if not exists idx_financial_goals_created_by on public.financial_goals(created_by);
create index if not exists idx_financial_goals_updated_by on public.financial_goals(updated_by);
create index if not exists idx_monthly_budgets_created_by on public.monthly_budgets(created_by);
create index if not exists idx_monthly_budgets_updated_by on public.monthly_budgets(updated_by);
create index if not exists idx_monthly_closures_closed_by on public.monthly_closures(closed_by) where closed_by is not null;
create index if not exists idx_monthly_closures_reopened_by on public.monthly_closures(reopened_by) where reopened_by is not null;
create index if not exists idx_obligation_payments_created_by on public.obligation_payments(created_by);
create index if not exists idx_obligation_payments_voided_by on public.obligation_payments(voided_by) where voided_by is not null;
create index if not exists idx_obligations_updated_by on public.obligations(updated_by);
create index if not exists idx_obligations_cancelled_by on public.obligations(cancelled_by) where cancelled_by is not null;
create index if not exists idx_transaction_attachments_uploaded_by on public.transaction_attachments(uploaded_by);
create index if not exists idx_transactions_created_by on public.transactions(created_by);
create index if not exists idx_transactions_updated_by on public.transactions(updated_by);

-- RLS: usar initplan de auth.uid() para que Postgres lo calcule una vez por consulta.
drop policy if exists transactions_insert on public.transactions;
create policy transactions_insert on public.transactions
for insert to authenticated
with check (
  public.is_business_member(business_id)
  and created_by = (select auth.uid())
  and updated_by = (select auth.uid())
);

drop policy if exists transactions_update on public.transactions;
create policy transactions_update on public.transactions
for update to authenticated
using (
  public.is_business_member(business_id)
  and (public.is_business_owner(business_id) or created_by = (select auth.uid()))
)
with check (
  public.is_business_member(business_id)
  and (public.is_business_owner(business_id) or created_by = (select auth.uid()))
  and updated_by = (select auth.uid())
);

drop policy if exists transactions_delete on public.transactions;
create policy transactions_delete on public.transactions
for delete to authenticated
using (
  public.is_business_member(business_id)
  and (public.is_business_owner(business_id) or created_by = (select auth.uid()))
);

drop policy if exists categories_insert on public.categories;
create policy categories_insert on public.categories
for insert to authenticated
with check (
  public.is_business_owner(business_id)
  and created_by = (select auth.uid())
);

drop policy if exists financial_goals_insert on public.financial_goals;
create policy financial_goals_insert on public.financial_goals
for insert to authenticated
with check (
  public.is_business_owner(business_id)
  and created_by = (select auth.uid())
  and updated_by = (select auth.uid())
);

drop policy if exists financial_goals_update on public.financial_goals;
create policy financial_goals_update on public.financial_goals
for update to authenticated
using (public.is_business_owner(business_id))
with check (
  public.is_business_owner(business_id)
  and updated_by = (select auth.uid())
);

drop policy if exists monthly_budgets_insert on public.monthly_budgets;
create policy monthly_budgets_insert on public.monthly_budgets
for insert to authenticated
with check (
  public.is_business_owner(business_id)
  and created_by = (select auth.uid())
  and updated_by = (select auth.uid())
);

drop policy if exists monthly_budgets_update on public.monthly_budgets;
create policy monthly_budgets_update on public.monthly_budgets
for update to authenticated
using (public.is_business_owner(business_id))
with check (
  public.is_business_owner(business_id)
  and updated_by = (select auth.uid())
);

drop policy if exists transaction_attachments_insert on public.transaction_attachments;
create policy transaction_attachments_insert on public.transaction_attachments
for insert to authenticated
with check (
  public.is_business_member(business_id)
  and uploaded_by = (select auth.uid())
  and exists (
    select 1 from public.transactions t
    where t.id = transaction_attachments.transaction_id
      and t.business_id = transaction_attachments.business_id
      and (public.is_business_owner(t.business_id) or t.created_by = (select auth.uid()))
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
      and (public.is_business_owner(t.business_id) or t.created_by = (select auth.uid()))
      and not exists (
        select 1 from public.monthly_closures c
        where c.business_id = t.business_id
          and c.period_start = date_trunc('month', t.occurred_on)::date
          and c.status = 'closed'
      )
  )
);

-- Tablas internas del pipeline Android: acceso solo de backend/service-role.
revoke all on public.android_release_payloads from anon, authenticated;
revoke all on public.android_signing_secrets from anon, authenticated;
