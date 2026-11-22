-- Mauqa — 0008: private storage buckets and scheduled jobs

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('user-documents', 'user-documents', false, 10485760,
   array['application/pdf', 'image/jpeg', 'image/png', 'image/webp', 'application/msword',
         'application/vnd.openxmlformats-officedocument.wordprocessingml.document']),
  ('avatars', 'avatars', false, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

-- Objects must be stored as "<auth.uid()>/<file>". Nobody else (including other users) can read them.
-- Downloads use short-lived signed URLs created by the owner.
create policy "owner can read own files" on storage.objects for select to authenticated
  using (bucket_id in ('user-documents', 'avatars') and (storage.foldername(name))[1] = auth.uid()::text);
create policy "owner can upload own files" on storage.objects for insert to authenticated
  with check (bucket_id in ('user-documents', 'avatars') and (storage.foldername(name))[1] = auth.uid()::text);
create policy "owner can update own files" on storage.objects for update to authenticated
  using (bucket_id in ('user-documents', 'avatars') and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id in ('user-documents', 'avatars') and (storage.foldername(name))[1] = auth.uid()::text);
create policy "owner can delete own files" on storage.objects for delete to authenticated
  using (bucket_id in ('user-documents', 'avatars') and (storage.foldername(name))[1] = auth.uid()::text);

-- Scheduled jobs. pg_cron is available on Supabase (enable it under Database → Extensions).
-- Edge-function jobs (source sync, push/email delivery) are scheduled with pg_net; see docs/SETUP.md.
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('mauqa-dispatch-reminders', '*/10 * * * *', $job$select public.dispatch_due_reminders(1000)$job$);
    perform cron.schedule('mauqa-refresh-statuses', '5 * * * *', $job$select public.refresh_opportunity_statuses()$job$);
    perform cron.schedule('mauqa-prune-search-history', '30 3 * * *',
      $job$delete from public.search_history where created_at < now() - interval '180 days'$job$);
    perform cron.schedule('mauqa-prune-views', '40 3 * * *',
      $job$delete from public.opportunity_views where viewed_at < now() - interval '400 days'$job$);
    perform cron.schedule('mauqa-prune-notifications', '50 3 * * *',
      $job$delete from public.notifications where is_read and created_at < now() - interval '365 days'$job$);
  else
    raise notice 'pg_cron not available: schedule dispatch_due_reminders() and refresh_opportunity_statuses() externally';
  end if;
end $$;
