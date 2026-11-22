-- Mauqa — 0012: table privileges for the API roles
--
-- Why: migrations 0001–0011 relied on Supabase's old default of automatically granting new public tables to the
-- anon / authenticated / service_role roles. Newer Supabase projects no longer do this, so every request from the
-- app failed with 42501 ("permission denied") before Row Level Security was even evaluated.
--
-- Access is still decided by the RLS policies from 0007/0010: these grants only let a role *reach* a table, and the
-- policies then decide which rows it may see or change. As a safety check, this migration refuses to run if any
-- public table does not have RLS enabled.

do $$
declare missing text;
begin
  select string_agg(c.relname, ', ') into missing
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('r', 'p') and not c.relrowsecurity;
  if missing is not null then
    raise exception 'Refusing to grant access: RLS is not enabled on: %', missing;
  end if;
end $$;

grant usage on schema public to anon, authenticated, service_role;

-- Visitors (not signed in): read only; the policies limit this to published public content.
grant select on all tables in schema public to anon;

-- Signed-in users: normal row operations; every row is filtered by the RLS policies.
grant select, insert, update, delete on all tables in schema public to authenticated;

-- Backend (Edge Functions with the service role key, never shipped in the app).
grant all on all tables in schema public to service_role;

grant usage, select on all sequences in schema public to authenticated, service_role;

-- Re-apply the column restriction from 0007: users may only mark notifications as read.
revoke update on public.notifications from anon, authenticated;
grant update (is_read, read_at) on public.notifications to authenticated;

-- Tables created by future migrations get the same privileges automatically.
alter default privileges in schema public grant select on tables to anon;
alter default privileges in schema public grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema public grant all on tables to service_role;
alter default privileges in schema public grant usage, select on sequences to authenticated, service_role;
