-- Mauqa — 0007: Row Level Security
-- Principle: users only ever see/modify their own private rows; staff access is role-scoped.

create or replace function public.is_active_user() returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and not coalesce((select is_suspended from public.profiles where id = auth.uid()), false);
$$;

do $$
declare t text;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

-- ---------------------------------------------------------------- owner-only tables
do $$
declare t text;
begin
  foreach t in array array['education_records', 'user_skills', 'user_interests', 'user_experiences', 'user_certifications',
                           'device_tokens', 'saved_opportunities', 'interested_opportunities', 'applications',
                           'user_documents', 'search_history', 'comparisons', 'cv_documents', 'cover_letters']
  loop
    execute format('create policy owner_select on public.%I for select to authenticated using (user_id = auth.uid())', t);
    execute format('create policy owner_insert on public.%I for insert to authenticated with check (user_id = auth.uid() and public.is_active_user())', t);
    execute format('create policy owner_update on public.%I for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid())', t);
    execute format('create policy owner_delete on public.%I for delete to authenticated using (user_id = auth.uid())', t);
  end loop;
end $$;

-- ---------------------------------------------------------------- profiles & roles
create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_staff());
create policy profiles_insert on public.profiles for insert to authenticated with check (id = auth.uid());
create policy profiles_update on public.profiles for update to authenticated
  using (id = auth.uid() or public.is_admin()) with check (id = auth.uid() or public.is_admin());

create policy roles_select on public.user_roles for select to authenticated
  using (user_id = auth.uid() or public.is_admin());
-- no insert/update/delete policies: roles change only through admin_set_role()

create policy prefs_select on public.notification_preferences for select to authenticated using (user_id = auth.uid());
create policy prefs_update on public.notification_preferences for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy prefs_insert on public.notification_preferences for insert to authenticated with check (user_id = auth.uid());

create policy history_select on public.application_status_history for select to authenticated using (user_id = auth.uid());

create policy eligibility_select on public.eligibility_checks for select to authenticated using (user_id = auth.uid());
create policy eligibility_delete on public.eligibility_checks for delete to authenticated using (user_id = auth.uid());
-- writes happen only in the eligibility-check Edge Function with the service role

create policy notifications_select on public.notifications for select to authenticated using (user_id = auth.uid());
create policy notifications_update on public.notifications for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy notifications_delete on public.notifications for delete to authenticated using (user_id = auth.uid());
revoke update on public.notifications from anon, authenticated;
grant update (is_read, read_at) on public.notifications to authenticated;

create policy reminders_select on public.reminders for select to authenticated using (user_id = auth.uid());
create policy reminders_insert on public.reminders for insert to authenticated
  with check (user_id = auth.uid() and kind = 'custom' and origin = 'manual' and status = 'pending');
create policy reminders_update on public.reminders for update to authenticated
  using (user_id = auth.uid() and kind = 'custom') with check (user_id = auth.uid() and kind = 'custom');
create policy reminders_delete on public.reminders for delete to authenticated using (user_id = auth.uid() and kind = 'custom');

-- ---------------------------------------------------------------- public reference data
create policy institutions_read on public.institutions for select to anon, authenticated using (true);
create policy institutions_write on public.institutions for all to authenticated
  using (public.can_manage_content() or public.can_verify()) with check (public.can_manage_content() or public.can_verify());

create policy categories_read on public.opportunity_categories for select to anon, authenticated using (true);
create policy categories_write on public.opportunity_categories for all to authenticated
  using (public.can_manage_content()) with check (public.can_manage_content());

create policy organizations_read on public.organizations for select to anon, authenticated using (true);
create policy organizations_insert on public.organizations for insert to authenticated
  with check (public.can_manage_content() or public.can_verify());
create policy organizations_update on public.organizations for update to authenticated
  using (public.can_manage_content() or public.can_verify()) with check (public.can_manage_content() or public.can_verify());
create policy organizations_delete on public.organizations for delete to authenticated using (public.is_admin());

create policy opportunities_read on public.opportunities for select to anon, authenticated
  using ((is_published and approval_status = 'approved') or public.is_staff());
create policy opportunities_insert on public.opportunities for insert to authenticated
  with check (public.can_manage_content() or public.can_verify());
create policy opportunities_update on public.opportunities for update to authenticated
  using (public.can_manage_content() or public.can_verify()) with check (public.can_manage_content() or public.can_verify());
create policy opportunities_delete on public.opportunities for delete to authenticated using (public.is_admin());

create policy rules_read on public.opportunity_eligibility_rules for select to anon, authenticated
  using (exists (select 1 from public.opportunities o where o.id = opportunity_id));
create policy rules_write on public.opportunity_eligibility_rules for all to authenticated
  using (public.can_manage_content() or public.can_verify()) with check (public.can_manage_content() or public.can_verify());

create policy opp_docs_read on public.opportunity_documents for select to anon, authenticated
  using (exists (select 1 from public.opportunities o where o.id = opportunity_id));
create policy opp_docs_write on public.opportunity_documents for all to authenticated
  using (public.can_manage_content() or public.can_verify()) with check (public.can_manage_content() or public.can_verify());

create policy cycles_read on public.opportunity_cycles for select to anon, authenticated using (true);
create policy cycles_write on public.opportunity_cycles for all to authenticated
  using (public.can_manage_content()) with check (public.can_manage_content());

-- ---------------------------------------------------------------- ingestion & verification (staff)
create policy sources_read on public.data_sources for select to authenticated using (public.is_staff());
create policy sources_write on public.data_sources for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy org_sources_read on public.organization_sources for select to authenticated using (public.is_staff());
create policy org_sources_write on public.organization_sources for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy sync_logs_read on public.source_sync_logs for select to authenticated using (public.is_staff());
create policy source_items_read on public.source_items for select to authenticated using (public.is_staff());
create policy source_items_review on public.source_items for update to authenticated
  using (public.can_verify()) with check (public.can_verify());
create policy versions_read on public.opportunity_versions for select to authenticated using (public.is_staff());
create policy reviews_read on public.verification_reviews for select to authenticated using (public.is_staff());
create policy reviews_insert on public.verification_reviews for insert to authenticated
  with check (public.can_verify() and reviewer_id = auth.uid());
create policy views_read on public.opportunity_views for select to authenticated using (public.is_staff());
create policy audit_read on public.audit_logs for select to authenticated using (public.is_admin());

-- ---------------------------------------------------------------- user reports & submissions
create policy reports_insert on public.opportunity_reports for insert to authenticated
  with check (reporter_id = auth.uid() and status = 'open' and public.is_active_user());
create policy reports_select on public.opportunity_reports for select to authenticated
  using (reporter_id = auth.uid() or public.is_staff());
create policy reports_update on public.opportunity_reports for update to authenticated
  using (public.can_verify()) with check (public.can_verify());

create policy corrections_insert on public.user_corrections for insert to authenticated
  with check (user_id = auth.uid() and status = 'pending' and public.is_active_user());
create policy corrections_select on public.user_corrections for select to authenticated
  using (user_id = auth.uid() or public.is_staff());
create policy corrections_update on public.user_corrections for update to authenticated
  using (public.can_verify()) with check (public.can_verify());

create policy submissions_insert on public.opportunity_submissions for insert to authenticated
  with check (submitted_by = auth.uid() and status = 'pending' and public.is_active_user());
create policy submissions_select on public.opportunity_submissions for select to authenticated
  using (submitted_by = auth.uid() or public.is_staff());
create policy submissions_update on public.opportunity_submissions for update to authenticated
  using (public.can_verify() or public.can_manage_content()) with check (public.can_verify() or public.can_manage_content());

create policy org_verif_insert on public.organization_verification_requests for insert to authenticated
  with check (requested_by = auth.uid() and status = 'pending' and public.is_active_user());
create policy org_verif_select on public.organization_verification_requests for select to authenticated
  using (requested_by = auth.uid() or public.is_staff());
create policy org_verif_update on public.organization_verification_requests for update to authenticated
  using (public.can_verify()) with check (public.can_verify());

-- ---------------------------------------------------------------- community & content
create policy stories_read on public.success_stories for select to anon, authenticated
  using (status = 'approved' or author_id = auth.uid() or public.can_manage_content());
create policy stories_insert on public.success_stories for insert to authenticated
  with check (author_id = auth.uid() and status = 'pending' and published_at is null and public.is_active_user());
create policy stories_update_own on public.success_stories for update to authenticated
  using (author_id = auth.uid() and status = 'pending') with check (author_id = auth.uid() and status = 'pending');
create policy stories_moderate on public.success_stories for update to authenticated
  using (public.can_manage_content()) with check (public.can_manage_content());
create policy stories_delete on public.success_stories for delete to authenticated
  using (author_id = auth.uid() or public.can_manage_content());

create policy content_reports_insert on public.content_reports for insert to authenticated
  with check (reporter_id = auth.uid() and status = 'open');
create policy content_reports_staff on public.content_reports for select to authenticated using (public.can_manage_content());
create policy content_reports_update on public.content_reports for update to authenticated
  using (public.can_manage_content()) with check (public.can_manage_content());

create policy guides_read on public.guides for select to anon, authenticated using (is_published or public.can_manage_content());
create policy guides_write on public.guides for all to authenticated using (public.can_manage_content()) with check (public.can_manage_content());
create policy questions_read on public.interview_questions for select to anon, authenticated using (is_published or public.can_manage_content());
create policy questions_write on public.interview_questions for all to authenticated
  using (public.can_manage_content()) with check (public.can_manage_content());
create policy announcements_read on public.announcements for select to anon, authenticated using (is_published or public.can_manage_content());
create policy announcements_write on public.announcements for all to authenticated
  using (public.can_manage_content()) with check (public.can_manage_content());

create policy mentors_read on public.mentors for select to authenticated
  using (status = 'approved' or user_id = auth.uid() or public.can_manage_content());
create policy mentors_insert on public.mentors for insert to authenticated
  with check (user_id = auth.uid() and status = 'pending');
create policy mentors_moderate on public.mentors for update to authenticated
  using (public.can_manage_content()) with check (public.can_manage_content());
create policy mentors_delete on public.mentors for delete to authenticated using (user_id = auth.uid() or public.can_manage_content());

create policy ambassadors_select on public.university_ambassadors for select to authenticated
  using (user_id = auth.uid() or public.is_staff());
create policy ambassadors_insert on public.university_ambassadors for insert to authenticated
  with check (user_id = auth.uid() and status = 'pending');
create policy ambassadors_moderate on public.university_ambassadors for update to authenticated
  using (public.is_admin()) with check (public.is_admin());
