-- Supabase automatic-RLS helper is an internal SECURITY DEFINER function.
-- It is not part of the application API and should not be callable by clients.
revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
