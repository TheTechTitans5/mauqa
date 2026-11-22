-- Run ONCE in the Supabase SQL editor after deploying the Edge Functions.
-- Requires extensions pg_cron and pg_net (Database → Extensions) and two Vault secrets:
--   select vault.create_secret('https://<PROJECT-REF>.supabase.co', 'project_url');
--   select vault.create_secret('<same value as the CRON_SECRET function secret>', 'cron_secret');
-- The SQL-only jobs (reminder dispatch, status refresh, data retention) are created by migration 0008.

select cron.schedule('mauqa-dispatch-notifications', '*/10 * * * *', $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/dispatch-notifications',
    headers := jsonb_build_object('Content-Type', 'application/json',
                                  'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')),
    body := '{}'::jsonb,
    timeout_milliseconds := 55000);
$$);

select cron.schedule('mauqa-source-sync', '*/30 * * * *', $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/source-sync',
    headers := jsonb_build_object('Content-Type', 'application/json',
                                  'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')),
    body := '{}'::jsonb,
    timeout_milliseconds := 120000);
$$);

-- Inspect: select * from cron.job; select * from cron.job_run_details order by start_time desc limit 20;
