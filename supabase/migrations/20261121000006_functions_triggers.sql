-- Mauqa — 0006: helper functions, triggers, reminder scheduling, RPCs

alter table public.opportunities add column rules_version integer not null default 1;

-- ---------------------------------------------------------------------------
-- Role helpers (security definer so they can read user_roles under RLS)
-- ---------------------------------------------------------------------------
create or replace function public.has_any_role(p_roles public.app_role[])
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.user_roles where user_id = auth.uid() and role = any (p_roles));
$$;

create or replace function public.is_staff() returns boolean language sql stable as $$
  select public.has_any_role('{admin,super_admin,verifier,content_manager}'::public.app_role[]);
$$;
create or replace function public.is_admin() returns boolean language sql stable as $$
  select public.has_any_role('{admin,super_admin}'::public.app_role[]);
$$;
create or replace function public.is_super_admin() returns boolean language sql stable as $$
  select public.has_any_role('{super_admin}'::public.app_role[]);
$$;
create or replace function public.can_verify() returns boolean language sql stable as $$
  select public.has_any_role('{admin,super_admin,verifier}'::public.app_role[]);
$$;
create or replace function public.can_manage_content() returns boolean language sql stable as $$
  select public.has_any_role('{admin,super_admin,content_manager}'::public.app_role[]);
$$;
-- True when running as the database itself (cron, migrations, service role) rather than an end user.
create or replace function public.is_system() returns boolean language sql stable as $$
  select auth.uid() is null;
$$;

create or replace function public.my_roles() returns public.app_role[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(role order by role), '{}') from public.user_roles where user_id = auth.uid();
$$;

-- ---------------------------------------------------------------------------
-- Generic triggers
-- ---------------------------------------------------------------------------
create or replace function public.tg_set_updated_at() returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['profiles', 'education_records', 'organizations', 'data_sources', 'opportunities',
                           'applications', 'user_documents', 'notification_preferences', 'cv_documents', 'cover_letters']
  loop
    execute format('create trigger set_updated_at before update on public.%I for each row execute function public.tg_set_updated_at()', t);
  end loop;
end $$;

create or replace function public.tg_audit() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_id text;
begin
  v_id := coalesce(to_jsonb(new) ->> 'id', to_jsonb(old) ->> 'id', to_jsonb(new) ->> 'user_id', to_jsonb(old) ->> 'user_id');
  insert into public.audit_logs (actor_id, action, table_name, record_id, old_data, new_data)
  values (auth.uid(), lower(tg_op), tg_table_name, v_id,
          case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end,
          case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end);
  return coalesce(new, old);
end $$;

do $$
declare t text;
begin
  foreach t in array array['opportunities', 'organizations', 'data_sources', 'user_roles', 'opportunity_eligibility_rules',
                           'verification_reviews', 'opportunity_reports', 'guides', 'success_stories', 'source_items']
  loop
    execute format('create trigger audit after insert or update or delete on public.%I for each row execute function public.tg_audit()', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- New user bootstrap
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, phone, full_name, preferred_language, terms_accepted_at, privacy_accepted_at)
  values (new.id, new.email, new.phone,
          nullif(new.raw_user_meta_data ->> 'full_name', ''),
          coalesce(nullif(new.raw_user_meta_data ->> 'preferred_language', ''), 'en'),
          case when (new.raw_user_meta_data ->> 'accepted_terms') = 'true' then now() end,
          case when (new.raw_user_meta_data ->> 'accepted_terms') = 'true' then now() end)
  on conflict (id) do nothing;
  insert into public.notification_preferences (user_id) values (new.id) on conflict do nothing;
  insert into public.user_roles (user_id, role) values (new.id, 'user') on conflict do nothing;
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Profile protection + eligibility staleness
-- ---------------------------------------------------------------------------
create or replace function public.tg_profiles_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_system() and not public.is_admin() then
    new.is_suspended := old.is_suspended;
  end if;
  new.id := old.id;
  if (new.date_of_birth, new.gender, new.nationality, new.province, new.city, new.user_category,
      new.employment_status, new.household_income_monthly_pkr, new.household_income_range,
      new.has_disability, new.share_sensitive_for_eligibility, new.languages)
     is distinct from
     (old.date_of_birth, old.gender, old.nationality, old.province, old.city, old.user_category,
      old.employment_status, old.household_income_monthly_pkr, old.household_income_range,
      old.has_disability, old.share_sensitive_for_eligibility, old.languages) then
    new.profile_version := old.profile_version + 1;
    update public.eligibility_checks set is_stale = true where user_id = new.id;
  else
    -- users cannot set the version themselves
    if not public.is_system() and new.profile_version is distinct from old.profile_version
       and current_setting('mauqa.bump_version', true) is distinct from 'on' then
      new.profile_version := old.profile_version;
    end if;
  end if;
  return new;
end $$;
create trigger guard before update on public.profiles for each row execute function public.tg_profiles_guard();

create or replace function public.bump_profile_version(p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform set_config('mauqa.bump_version', 'on', true);
  update public.profiles set profile_version = profile_version + 1 where id = p_user;
  perform set_config('mauqa.bump_version', 'off', true);
  update public.eligibility_checks set is_stale = true where user_id = p_user;
end $$;

create or replace function public.tg_profile_child_changed() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.bump_profile_version(coalesce(new.user_id, old.user_id));
  return coalesce(new, old);
end $$;

do $$
declare t text;
begin
  foreach t in array array['education_records', 'user_skills', 'user_interests', 'user_experiences', 'user_certifications', 'user_documents']
  loop
    execute format('create trigger profile_changed after insert or update or delete on public.%I for each row execute function public.tg_profile_child_changed()', t);
  end loop;
end $$;

create or replace function public.tg_rules_changed() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_opp uuid := coalesce(new.opportunity_id, old.opportunity_id);
begin
  update public.opportunities set rules_version = rules_version + 1 where id = v_opp;
  update public.eligibility_checks set is_stale = true where opportunity_id = v_opp;
  return coalesce(new, old);
end $$;
create trigger rules_changed after insert or update or delete on public.opportunity_eligibility_rules
  for each row execute function public.tg_rules_changed();

create or replace function public.profile_completion(p_user uuid) returns integer
language sql stable security definer set search_path = public as $$
  select (
      (case when p.full_name is not null then 10 else 0 end)
    + (case when p.avatar_path is not null then 5 else 0 end)
    + (case when p.phone is not null or p.email is not null then 5 else 0 end)
    + (case when p.date_of_birth is not null then 10 else 0 end)
    + (case when p.province is not null then 5 else 0 end)
    + (case when p.city is not null then 5 else 0 end)
    + (case when p.user_category is not null then 10 else 0 end)
    + (case when exists (select 1 from education_records e where e.user_id = p.id) then 15 else 0 end)
    + (case when exists (select 1 from education_records e where e.user_id = p.id and e.score_value is not null) then 10 else 0 end)
    + (case when (select count(*) from user_skills s where s.user_id = p.id) >= 3 then 10 else 0 end)
    + (case when exists (select 1 from user_interests i where i.user_id = p.id) then 5 else 0 end)
    + (case when exists (select 1 from user_experiences x where x.user_id = p.id) then 5 else 0 end)
    + (case when exists (select 1 from user_documents d where d.user_id = p.id and d.category = 'cv') then 5 else 0 end)
  )::int
  from profiles p
  where p.id = p_user and (p_user = auth.uid() or public.is_staff() or public.is_system());
$$;

-- ---------------------------------------------------------------------------
-- Opportunities: search vector, versioning, verification guard
-- ---------------------------------------------------------------------------
create or replace function public.tg_opportunities_before() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_org text; v_cat text; v_material boolean := false;
begin
  select name into v_org from organizations where id = new.organization_id;
  select name_en into v_cat from opportunity_categories where id = new.category_id;
  new.search_tsv :=
       setweight(to_tsvector('simple', unaccent(coalesce(new.title, ''))), 'A')
    || setweight(to_tsvector('simple', unaccent(coalesce(v_org, '') || ' ' || coalesce(v_cat, ''))), 'B')
    || setweight(to_tsvector('simple', unaccent(array_to_string(new.tags || new.fields_of_study || new.required_skills, ' ')
                                          || ' ' || coalesce(new.location_text, '') || ' ' || array_to_string(new.cities || new.provinces, ' '))), 'B')
    || setweight(to_tsvector('simple', unaccent(coalesce(new.summary, '') || ' ' || coalesce(new.eligibility_summary, ''))), 'C')
    || setweight(to_tsvector('simple', unaccent(coalesce(new.description, ''))), 'D');

  if new.has_application_fee is false and coalesce(new.application_fee_pkr, 0) > 0 then
    new.has_application_fee := true;
  end if;

  if tg_op = 'UPDATE' then
    v_material := (new.title, new.description, new.benefits, new.eligibility_summary, new.deadline, new.opening_date,
                   new.official_application_url, new.source_url, new.amount_text, new.amount_min_pkr, new.amount_max_pkr,
                   new.education_levels, new.fields_of_study, new.min_age, new.max_age, new.gender_eligibility,
                   new.provinces, new.cities, new.application_procedure, new.has_application_fee, new.application_fee_pkr,
                   new.organization_id)
              is distinct from
                  (old.title, old.description, old.benefits, old.eligibility_summary, old.deadline, old.opening_date,
                   old.official_application_url, old.source_url, old.amount_text, old.amount_min_pkr, old.amount_max_pkr,
                   old.education_levels, old.fields_of_study, old.min_age, old.max_age, old.gender_eligibility,
                   old.provinces, old.cities, old.application_procedure, old.has_application_fee, old.application_fee_pkr,
                   old.organization_id);
    if v_material then
      new.data_version := old.data_version + 1;
      -- Material edits by non-verifiers lose verified status until re-reviewed.
      if not public.is_system() and not public.can_verify() and old.verification_status = 'verified' then
        new.verification_status := 'pending_verification';
      end if;
    end if;
    -- Only verifiers (or the system) may set verified / publish approvals.
    if not public.is_system() and not public.can_verify() then
      if new.verification_status = 'verified' and old.verification_status <> 'verified' then
        raise exception 'Only verifiers can mark an opportunity as verified' using errcode = '42501';
      end if;
      if new.approval_status = 'approved' and old.approval_status <> 'approved' then
        raise exception 'Only verifiers can approve an opportunity' using errcode = '42501';
      end if;
    end if;
    if new.verification_status = 'verified' and old.verification_status is distinct from 'verified' then
      new.last_verified_at := now();
      new.verified_by := coalesce(auth.uid(), new.verified_by);
    end if;
  else
    if not public.is_system() and not public.can_verify() then
      new.verification_status := case when new.verification_status = 'verified' then 'pending_verification' else new.verification_status end;
      new.approval_status := case when new.approval_status = 'approved' then 'pending_review' else new.approval_status end;
    end if;
    if new.verification_status = 'verified' then
      new.last_verified_at := coalesce(new.last_verified_at, now());
    end if;
    new.created_by := coalesce(new.created_by, auth.uid());
  end if;

  -- published listings must be approved
  if new.is_published and new.approval_status <> 'approved' then
    raise exception 'Opportunity must be approved before publishing' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger before_write before insert or update on public.opportunities
  for each row execute function public.tg_opportunities_before();

-- ---------------------------------------------------------------------------
-- Reminder scheduling
-- ---------------------------------------------------------------------------
create or replace function public.schedule_deadline_reminders(p_user uuid, p_opp uuid, p_origin text, p_offsets smallint[])
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_deadline timestamptz; v_title text; v_status public.opportunity_status; v_hour int;
  v_off smallint; v_at timestamptz; v_n int := 0; v_rc int;
begin
  select deadline, title, status into v_deadline, v_title, v_status from opportunities where id = p_opp;
  if v_deadline is null or v_status in ('closed', 'cancelled') or v_deadline <= now() then
    return 0;
  end if;
  select reminder_hour_local into v_hour from notification_preferences where user_id = p_user;
  v_hour := coalesce(v_hour, 9);
  foreach v_off in array coalesce(p_offsets, '{}'::smallint[]) loop
    -- local Pakistan date of the deadline, minus offset, at the user's preferred hour (PKT)
    v_at := ((((v_deadline at time zone 'Asia/Karachi')::date - v_off) + make_time(v_hour, 0, 0)) at time zone 'Asia/Karachi');
    if v_at >= v_deadline then
      v_at := v_deadline - interval '3 hours';
    end if;
    if v_at > now() then
      insert into reminders (user_id, opportunity_id, kind, origin, offset_days, deadline_snapshot, remind_at, title, body)
      values (p_user, p_opp, 'deadline_auto', p_origin, v_off, v_deadline, v_at,
              case when v_off = 0 then 'Deadline today: ' || v_title
                   when v_off = 1 then 'Closes tomorrow: ' || v_title
                   else 'Deadline in ' || v_off || ' days: ' || v_title end,
              'Closes ' || to_char(v_deadline at time zone 'Asia/Karachi', 'DD Mon YYYY, HH12:MI AM') || ' (PKT)')
      on conflict do nothing;
      get diagnostics v_rc = row_count;
      v_n := v_n + v_rc;
    end if;
  end loop;
  return v_n;
end $$;

create or replace function public.cancel_deadline_reminders(p_user uuid, p_opp uuid, p_origin text)
returns integer language plpgsql security definer set search_path = public as $$
declare v_rc int;
begin
  update reminders set status = 'cancelled'
   where opportunity_id = p_opp and kind = 'deadline_auto' and status = 'pending'
     and (p_user is null or user_id = p_user) and (p_origin is null or origin = p_origin);
  get diagnostics v_rc = row_count;
  return v_rc;
end $$;

create or replace function public.tg_interested_changed() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    update opportunities set interest_count = interest_count + 1 where id = new.opportunity_id;
    if new.reminders_enabled then
      perform public.schedule_deadline_reminders(new.user_id, new.opportunity_id, 'interested', new.reminder_offsets_days);
    end if;
  elsif tg_op = 'UPDATE' then
    if (new.reminders_enabled, new.reminder_offsets_days) is distinct from (old.reminders_enabled, old.reminder_offsets_days) then
      perform public.cancel_deadline_reminders(new.user_id, new.opportunity_id, 'interested');
      if new.reminders_enabled then
        perform public.schedule_deadline_reminders(new.user_id, new.opportunity_id, 'interested', new.reminder_offsets_days);
      end if;
    end if;
  else
    update opportunities set interest_count = greatest(interest_count - 1, 0) where id = old.opportunity_id;
    perform public.cancel_deadline_reminders(old.user_id, old.opportunity_id, 'interested');
  end if;
  return coalesce(new, old);
end $$;
create trigger interested_changed after insert or update or delete on public.interested_opportunities
  for each row execute function public.tg_interested_changed();

create or replace function public.tg_saved_changed() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_offsets smallint[];
begin
  if tg_op = 'INSERT' then
    update opportunities set save_count = save_count + 1 where id = new.opportunity_id;
  elsif tg_op = 'DELETE' then
    update opportunities set save_count = greatest(save_count - 1, 0) where id = old.opportunity_id;
    perform public.cancel_deadline_reminders(old.user_id, old.opportunity_id, 'saved');
    return old;
  end if;
  if tg_op = 'INSERT' or new.reminders_enabled is distinct from old.reminders_enabled then
    perform public.cancel_deadline_reminders(new.user_id, new.opportunity_id, 'saved');
    if new.reminders_enabled then
      select default_reminder_offsets into v_offsets from notification_preferences where user_id = new.user_id;
      perform public.schedule_deadline_reminders(new.user_id, new.opportunity_id, 'saved', coalesce(v_offsets, '{7,3,1,0}'));
    end if;
  end if;
  return new;
end $$;
create trigger saved_changed after insert or update or delete on public.saved_opportunities
  for each row execute function public.tg_saved_changed();

-- Deadline changes / closures propagate to everyone following the opportunity.
create or replace function public.tg_opportunities_after() returns trigger
language plpgsql security definer set search_path = public as $$
declare r record; v_offsets smallint[];
begin
  if new.data_version is distinct from old.data_version then
    insert into opportunity_versions (opportunity_id, version, snapshot, changed_fields, changed_by)
    select new.id, new.data_version, to_jsonb(new) - 'search_tsv',
           coalesce(array_agg(n.key) filter (where n.value is distinct from o.value), '{}'), auth.uid()
      from jsonb_each(to_jsonb(new) - 'search_tsv') n
      join jsonb_each(to_jsonb(old) - 'search_tsv') o using (key)
     where n.key not in ('updated_at', 'data_version', 'view_count', 'save_count', 'interest_count')
    on conflict (opportunity_id, version) do nothing;
  end if;

  if new.status in ('closed', 'cancelled') and old.status not in ('closed', 'cancelled') then
    perform public.cancel_deadline_reminders(null, new.id, null);
    insert into notifications (user_id, type, title, body, opportunity_id, dedupe_key)
    select i.user_id, 'opportunity_closed', 'Opportunity closed', new.title || ' is no longer accepting applications.',
           new.id, 'closed:' || new.id
      from interested_opportunities i
    on conflict do nothing;
    return new;
  end if;

  if new.deadline is distinct from old.deadline and new.status not in ('closed', 'cancelled') then
    for r in select user_id, reminders_enabled, reminder_offsets_days from interested_opportunities where opportunity_id = new.id loop
      perform public.cancel_deadline_reminders(r.user_id, new.id, 'interested');
      if r.reminders_enabled then
        perform public.schedule_deadline_reminders(r.user_id, new.id, 'interested', r.reminder_offsets_days);
      end if;
    end loop;
    for r in select s.user_id from saved_opportunities s where s.opportunity_id = new.id and s.reminders_enabled loop
      perform public.cancel_deadline_reminders(r.user_id, new.id, 'saved');
      select default_reminder_offsets into v_offsets from notification_preferences where user_id = r.user_id;
      perform public.schedule_deadline_reminders(r.user_id, new.id, 'saved', coalesce(v_offsets, '{7,3,1,0}'));
    end loop;
    if new.is_published and new.deadline is not null then
      insert into notifications (user_id, type, title, body, opportunity_id, data, dedupe_key)
      select u.user_id, 'deadline_changed', 'Deadline changed',
             new.title || ' now closes ' || to_char(new.deadline at time zone 'Asia/Karachi', 'DD Mon YYYY, HH12:MI AM') || ' (PKT).',
             new.id, jsonb_build_object('old_deadline', old.deadline, 'new_deadline', new.deadline),
             'deadline_changed:' || new.id || ':' || extract(epoch from new.deadline)::bigint
        from (select user_id from interested_opportunities where opportunity_id = new.id
              union select user_id from saved_opportunities where opportunity_id = new.id) u
      on conflict do nothing;
    end if;
  end if;
  return new;
end $$;
create trigger after_update after update on public.opportunities
  for each row execute function public.tg_opportunities_after();

create or replace function public.tg_applications_before() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.opportunity_id is not null and (tg_op = 'INSERT' or new.opportunity_id is distinct from old.opportunity_id) then
    select title into new.title_snapshot from opportunities where id = new.opportunity_id;
  end if;
  if new.status = 'applied' and new.applied_on is null then
    new.applied_on := (now() at time zone 'Asia/Karachi')::date;
  end if;
  return new;
end $$;
create trigger applications_before before insert or update on public.applications
  for each row execute function public.tg_applications_before();

-- Applications: status history and interview / follow-up reminders
create or replace function public.tg_applications_changed() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_title text;
begin
  if tg_op = 'INSERT' or new.status is distinct from old.status then
    insert into application_status_history (application_id, user_id, from_status, to_status)
    values (new.id, new.user_id, case when tg_op = 'UPDATE' then old.status end, new.status);
  end if;

  v_title := coalesce(new.custom_title, new.title_snapshot, 'Your application');

  if tg_op = 'INSERT' or new.interview_at is distinct from old.interview_at then
    update reminders set status = 'cancelled' where application_id = new.id and kind = 'interview' and status = 'pending';
    if new.interview_at is not null then
      insert into reminders (user_id, application_id, opportunity_id, kind, origin, remind_at, title, body)
      select new.user_id, new.id, new.opportunity_id, 'interview', 'application', t, 'Interview: ' || v_title,
             'Scheduled ' || to_char(new.interview_at at time zone 'Asia/Karachi', 'DD Mon YYYY, HH12:MI AM') || ' (PKT)'
        from unnest(array[new.interview_at - interval '1 day', new.interview_at - interval '2 hours']) t
       where t > now()
      on conflict do nothing;
    end if;
  end if;
  if tg_op = 'INSERT' or new.follow_up_at is distinct from old.follow_up_at then
    update reminders set status = 'cancelled' where application_id = new.id and kind = 'follow_up' and status = 'pending';
    if new.follow_up_at is not null and new.follow_up_at > now() then
      insert into reminders (user_id, application_id, opportunity_id, kind, origin, remind_at, title, body)
      values (new.user_id, new.id, new.opportunity_id, 'follow_up', 'application', new.follow_up_at,
              'Follow up: ' || v_title, 'You planned to follow up on this application today.')
      on conflict do nothing;
    end if;
  end if;
  return new;
end $$;
create trigger applications_changed after insert or update on public.applications
  for each row execute function public.tg_applications_changed();

create or replace function public.tg_document_expiry() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and new.expires_on is not distinct from old.expires_on then
    return new;
  end if;
  update reminders set status = 'cancelled' where document_id = new.id and status = 'pending';
  if new.expires_on is not null then
    insert into reminders (user_id, document_id, kind, origin, remind_at, title, body)
    select new.user_id, new.id, 'document_expiry', 'document', t,
           'Document expiring: ' || new.title, 'Expires on ' || to_char(new.expires_on, 'DD Mon YYYY')
      from unnest(array[((new.expires_on - 30) + time '09:00') at time zone 'Asia/Karachi',
                        ((new.expires_on - 7) + time '09:00') at time zone 'Asia/Karachi']) t
     where t > now();
  end if;
  return new;
end $$;
create trigger document_expiry after insert or update on public.user_documents
  for each row execute function public.tg_document_expiry();

-- Reports: label listings "Reported for Review" once several distinct users report them.
create or replace function public.tg_reports_changed() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_opp uuid := coalesce(new.opportunity_id, old.opportunity_id); v_open int;
begin
  if v_opp is null then return coalesce(new, old); end if;
  select count(distinct reporter_id) into v_open from opportunity_reports
   where opportunity_id = v_opp and status in ('open', 'investigating');
  update opportunities set is_reported = (v_open >= 3) where id = v_opp and is_reported is distinct from (v_open >= 3);
  return coalesce(new, old);
end $$;
create trigger reports_changed after insert or update on public.opportunity_reports
  for each row execute function public.tg_reports_changed();

-- ---------------------------------------------------------------------------
-- Scheduled jobs (called by pg_cron / scheduler; not exposed to users)
-- ---------------------------------------------------------------------------
create or replace function public.dispatch_due_reminders(p_limit int default 500)
returns integer language plpgsql security definer set search_path = public as $$
declare r record; v_n int := 0; v_type text; v_key text; v_allowed boolean; v_rc int;
begin
  for r in
    select rem.*, o.status as opp_status, o.deadline as opp_deadline
      from reminders rem left join opportunities o on o.id = rem.opportunity_id
     where rem.status = 'pending' and rem.remind_at <= now()
     order by rem.remind_at
     limit p_limit
     for update of rem skip locked
  loop
    if r.kind = 'deadline_auto' and (r.opp_status in ('closed', 'cancelled') or r.opp_deadline is distinct from r.deadline_snapshot
                                     or r.opp_deadline <= now()) then
      update reminders set status = 'cancelled' where id = r.id;
      continue;
    end if;
    v_type := case
      when r.kind = 'deadline_auto' and r.origin = 'interested' and r.offset_days <= 1 then 'closing_soon'
      when r.kind = 'deadline_auto' and r.origin = 'interested' then 'interested_deadline'
      when r.kind = 'deadline_auto' then 'saved_deadline'
      when r.kind = 'interview' then 'interview_reminder'
      when r.kind = 'follow_up' then 'application_reminder'
      when r.kind = 'document_expiry' then 'document_expiry'
      else 'application_reminder' end;
    select case
      when v_type in ('interested_deadline', 'saved_deadline') then coalesce(p.deadline_reminders, true)
      when v_type = 'closing_soon' then coalesce(p.closing_soon, true) or coalesce(p.deadline_reminders, true)
      when v_type in ('interview_reminder', 'application_reminder') then coalesce(p.application_reminders, true)
      else true end
      into v_allowed
      from (select 1) x left join notification_preferences p on p.user_id = r.user_id;
    if r.kind = 'custom' then v_allowed := true; end if;  -- explicit user-created reminders always fire
    if v_allowed then
      -- One notification per opportunity/offset/deadline even if saved AND interested both scheduled one.
      v_key := case when r.kind = 'deadline_auto'
                    then 'deadline:' || r.opportunity_id || ':' || r.offset_days || ':' || extract(epoch from r.deadline_snapshot)::bigint
                    else 'reminder:' || r.id end;
      insert into notifications (user_id, type, title, body, opportunity_id, application_id, data, dedupe_key)
      values (r.user_id, v_type, r.title, coalesce(r.body, ''), r.opportunity_id, r.application_id,
              jsonb_build_object('reminder_id', r.id, 'kind', r.kind), v_key)
      on conflict do nothing;
      get diagnostics v_rc = row_count;
      v_n := v_n + v_rc;
      update reminders set status = 'sent', sent_at = now() where id = r.id;
    else
      update reminders set status = 'cancelled' where id = r.id;
    end if;
  end loop;
  return v_n;
end $$;

create or replace function public.refresh_opportunity_statuses()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_closed int; v_opened int;
begin
  update opportunities set status = 'open'
   where status = 'upcoming' and opening_date is not null and opening_date <= now()
     and (deadline is null or deadline > now());
  get diagnostics v_opened = row_count;
  update opportunities
     set status = 'closed',
         verification_status = case when verification_status in ('rejected') then verification_status else 'expired' end
   where status in ('open', 'upcoming') and deadline is not null and deadline <= now();
  get diagnostics v_closed = row_count;
  return jsonb_build_object('opened', v_opened, 'closed', v_closed);
end $$;

-- ---------------------------------------------------------------------------
-- Read models & RPCs for the app
-- ---------------------------------------------------------------------------
create or replace view public.opportunity_feed with (security_invoker = true) as
select o.id, o.title, o.title_ur, o.summary, o.organization_id, org.name as organization_name, org.slug as organization_slug,
       org.org_type, org.is_verified as organization_verified, org.logo_url as organization_logo_url, org.website as organization_website,
       c.slug as category_slug, c.name_en as category_name_en, c.name_ur as category_name_ur, c.icon as category_icon,
       c.color_hex as category_color, o.funding_type, o.amount_text, o.amount_min_pkr, o.amount_max_pkr, o.work_mode,
       o.location_text, o.is_nationwide, o.provinces, o.cities, o.is_international, o.education_levels, o.fields_of_study,
       o.required_skills, o.min_age, o.max_age, o.gender_eligibility, o.min_experience_months, o.opening_date, o.deadline,
       o.status, o.tags, o.has_application_fee, o.application_fee_pkr, o.verification_status, o.is_featured, o.is_reported, o.is_demo,
       o.last_checked_at, o.last_verified_at, o.source_url, o.official_application_url, o.view_count, o.save_count,
       o.interest_count, o.created_at, o.updated_at, o.recurrence_key, o.duration_text,
       case when o.status in ('closed', 'cancelled') or (o.deadline is not null and o.deadline <= now()) then 'closed'
            when o.opening_date is not null and o.opening_date > now() then 'upcoming'
            when o.deadline is not null and o.deadline < now() + interval '7 days' then 'closing_soon'
            else 'open' end as effective_status,
       case when o.deadline is null then null
            else greatest(0, ceil(extract(epoch from (o.deadline - now())) / 86400))::int end as days_left
  from public.opportunities o
  join public.organizations org on org.id = o.organization_id
  join public.opportunity_categories c on c.id = o.category_id
 where o.is_published and o.approval_status = 'approved';

create or replace function public.search_opportunities(
  p_query text default null,
  p_filters jsonb default '{}'::jsonb,
  p_sort text default 'relevance',
  p_limit int default 20,
  p_offset int default 0)
returns jsonb language plpgsql stable security invoker set search_path = public as $$
declare
  v_q text := nullif(btrim(coalesce(p_query, '')), '');
  v_tsq tsquery;
  v_f jsonb := coalesce(p_filters, '{}'::jsonb);
  v_result jsonb;
begin
  p_limit := least(greatest(coalesce(p_limit, 20), 1), 50);
  p_offset := greatest(coalesce(p_offset, 0), 0);
  if p_sort not in ('relevance', 'latest', 'deadline', 'popularity') then p_sort := 'relevance'; end if;
  if v_q is not null then
    if char_length(v_q) > 200 then raise exception 'query too long' using errcode = '22001'; end if;
    v_tsq := websearch_to_tsquery('simple', unaccent(v_q));
  end if;

  with base as (
    select f.*,
           case when v_q is null then 0
                else ts_rank(o.search_tsv, v_tsq) + similarity(f.title, v_q) end as rank
      from opportunity_feed f
      join opportunities o on o.id = f.id
     where (v_q is null or o.search_tsv @@ v_tsq or f.title % v_q
            or f.organization_name ilike '%' || v_q || '%'
            or exists (select 1 from opportunity_eligibility_rules r
                        where r.opportunity_id = f.id and r.criterion_type = 'institution_whitelist'
                          and r.params::text ilike '%' || v_q || '%'))
       and (not v_f ? 'categories' or f.category_slug in (select jsonb_array_elements_text(v_f -> 'categories')))
       and (not v_f ? 'provinces' or f.is_nationwide
            or f.provinces && array(select jsonb_array_elements_text(v_f -> 'provinces')))
       and (not v_f ? 'cities' or f.is_nationwide or f.cities && array(select jsonb_array_elements_text(v_f -> 'cities')))
       and (not v_f ? 'education_levels' or cardinality(f.education_levels) = 0
            or f.education_levels && array(select jsonb_array_elements_text(v_f -> 'education_levels'))::education_level[])
       and (not v_f ? 'fields' or cardinality(f.fields_of_study) = 0
            or exists (select 1 from unnest(f.fields_of_study) fs, jsonb_array_elements_text(v_f -> 'fields') q
                        where fs ilike '%' || q || '%'))
       and (not v_f ? 'skills' or exists (select 1 from unnest(f.required_skills) s, jsonb_array_elements_text(v_f -> 'skills') q
                                           where lower(s) = lower(q)))
       and (not v_f ? 'funding_types' or f.funding_type::text in (select jsonb_array_elements_text(v_f -> 'funding_types')))
       and (not v_f ? 'work_modes' or f.work_mode::text in (select jsonb_array_elements_text(v_f -> 'work_modes')))
       and (not v_f ? 'org_types' or f.org_type::text in (select jsonb_array_elements_text(v_f -> 'org_types')))
       and (case when v_f ? 'statuses' then f.effective_status in (select jsonb_array_elements_text(v_f -> 'statuses'))
                 else f.effective_status <> 'closed' end)
       and (not v_f ? 'gender' or f.gender_eligibility = 'any'
            or (v_f ->> 'gender' = 'female' and f.gender_eligibility in ('female', 'female_transgender'))
            or (v_f ->> 'gender' = 'transgender' and f.gender_eligibility in ('transgender', 'female_transgender'))
            or (v_f ->> 'gender' = 'male' and f.gender_eligibility = 'male'))
       and (not v_f ? 'age' or ((f.min_age is null or f.min_age <= (v_f ->> 'age')::int)
                                and (f.max_age is null or f.max_age >= (v_f ->> 'age')::int)))
       and (not v_f ? 'max_experience_months' or f.min_experience_months is null
            or f.min_experience_months <= (v_f ->> 'max_experience_months')::int)
       and (not v_f ? 'min_amount_pkr' or coalesce(f.amount_max_pkr, f.amount_min_pkr) >= (v_f ->> 'min_amount_pkr')::bigint)
       and (not v_f ? 'deadline_before' or f.deadline <= (v_f ->> 'deadline_before')::timestamptz)
       and (not v_f ? 'deadline_after' or f.deadline >= (v_f ->> 'deadline_after')::timestamptz)
       and (not coalesce((v_f ->> 'verified_only')::boolean, false) or f.verification_status = 'verified')
       and (not v_f ? 'income_based' or not (v_f ->> 'income_based')::boolean
            or exists (select 1 from opportunity_eligibility_rules r where r.opportunity_id = f.id and r.criterion_type = 'income_max'))
       and (not coalesce((v_f ->> 'hide_demo')::boolean, false) or not f.is_demo)
  ), paged as (
    select b.*, row_number() over (
             order by
               case when p_sort = 'deadline' then b.deadline end asc nulls last,
               case when p_sort = 'latest' then b.created_at end desc,
               case when p_sort = 'popularity' then b.save_count + b.interest_count + b.view_count / 10 end desc,
               case when p_sort = 'relevance' then b.rank end desc,
               b.is_featured desc, b.deadline asc nulls last, b.id) as rn
      from base b
     order by rn
     limit p_limit offset p_offset
  )
  select jsonb_build_object(
           'total', (select count(*) from base),
           'limit', p_limit,
           'offset', p_offset,
           'items', coalesce((select jsonb_agg(to_jsonb(p) - 'rank' - 'rn' order by p.rn) from paged p), '[]'::jsonb))
    into v_result;
  return v_result;
end $$;

create or replace function public.record_opportunity_view(p_opportunity uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from opportunity_feed where id = p_opportunity) then return; end if;
  if auth.uid() is not null and exists (
       select 1 from opportunity_views where opportunity_id = p_opportunity and user_id = auth.uid()
          and viewed_at > now() - interval '1 hour') then
    return;
  end if;
  insert into opportunity_views (opportunity_id, user_id) values (p_opportunity, auth.uid());
  update opportunities set view_count = view_count + 1 where id = p_opportunity;
end $$;

create or replace function public.trending_opportunities(p_limit int default 10)
returns setof public.opportunity_feed language sql stable security invoker set search_path = public as $$
  select f.* from opportunity_feed f
    left join (select opportunity_id, count(*) as c from opportunity_views
                where viewed_at > now() - interval '7 days' group by opportunity_id) v on v.opportunity_id = f.id
   where f.effective_status <> 'closed'
   order by coalesce(v.c, 0) + f.save_count * 3 + f.interest_count * 3 desc, f.deadline asc nulls last
   limit least(greatest(p_limit, 1), 50);
$$;

create or replace function public.home_summary() returns jsonb
language sql stable security invoker set search_path = public as $$
  select jsonb_build_object(
    'profile_completion', coalesce(public.profile_completion(auth.uid()), 0),
    'saved_count', (select count(*) from saved_opportunities where user_id = auth.uid()),
    'interested_count', (select count(*) from interested_opportunities where user_id = auth.uid()),
    'unread_notifications', (select count(*) from notifications where user_id = auth.uid() and not is_read),
    'applications_by_status', coalesce((select jsonb_object_agg(status, n) from
        (select status, count(*) n from applications where user_id = auth.uid() group by status) s), '{}'::jsonb),
    'upcoming_deadlines', (select count(*) from opportunity_feed f
        where f.id in (select opportunity_id from interested_opportunities where user_id = auth.uid()
                       union select opportunity_id from saved_opportunities where user_id = auth.uid())
          and f.deadline between now() and now() + interval '14 days'),
    'new_this_week', (select count(*) from opportunity_feed where created_at > now() - interval '7 days' and effective_status <> 'closed'),
    'week_activity', jsonb_build_object(
        'viewed', (select count(*) from opportunity_views where user_id = auth.uid() and viewed_at > now() - interval '7 days'),
        'saved', (select count(*) from saved_opportunities where user_id = auth.uid() and created_at > now() - interval '7 days'),
        'interested', (select count(*) from interested_opportunities where user_id = auth.uid() and created_at > now() - interval '7 days'),
        'applied', (select count(*) from application_status_history where user_id = auth.uid() and to_status = 'applied'
                     and changed_at > now() - interval '7 days'))
  );
$$;

create or replace function public.my_calendar_events(p_from timestamptz, p_to timestamptz)
returns table (event_date timestamptz, event_type text, title text, opportunity_id uuid, application_id uuid, reminder_id uuid)
language sql stable security invoker set search_path = public as $$
  select f.deadline, 'interested_deadline', f.title, f.id, null::uuid, null::uuid
    from interested_opportunities i join opportunity_feed f on f.id = i.opportunity_id
   where i.user_id = auth.uid() and f.deadline between p_from and p_to
  union all
  select f.deadline, 'saved_deadline', f.title, f.id, null, null
    from saved_opportunities s join opportunity_feed f on f.id = s.opportunity_id
   where s.user_id = auth.uid() and f.deadline between p_from and p_to
     and not exists (select 1 from interested_opportunities i where i.user_id = s.user_id and i.opportunity_id = s.opportunity_id)
  union all
  select coalesce(a.deadline, o.deadline), 'application_deadline', coalesce(a.custom_title, o.title), a.opportunity_id, a.id, null
    from applications a left join opportunities o on o.id = a.opportunity_id
   where a.user_id = auth.uid() and coalesce(a.deadline, o.deadline) between p_from and p_to
     and a.status not in ('applied', 'under_review', 'shortlisted', 'interview_scheduled', 'selected', 'rejected', 'withdrawn')
  union all
  select a.interview_at, 'interview', coalesce(a.custom_title, o.title), a.opportunity_id, a.id, null
    from applications a left join opportunities o on o.id = a.opportunity_id
   where a.user_id = auth.uid() and a.interview_at between p_from and p_to
  union all
  select a.follow_up_at, 'follow_up', coalesce(a.custom_title, o.title), a.opportunity_id, a.id, null
    from applications a left join opportunities o on o.id = a.opportunity_id
   where a.user_id = auth.uid() and a.follow_up_at between p_from and p_to
  union all
  select r.remind_at, 'custom_reminder', r.title, r.opportunity_id, r.application_id, r.id
    from reminders r
   where r.user_id = auth.uid() and r.kind = 'custom' and r.status <> 'cancelled' and r.remind_at between p_from and p_to
  order by 1;
$$;

create or replace function public.add_custom_reminder(p_title text, p_remind_at timestamptz,
  p_opportunity uuid default null, p_application uuid default null, p_body text default null)
returns uuid language plpgsql security invoker set search_path = public as $$
declare v_id uuid;
begin
  if p_remind_at <= now() then raise exception 'Reminder time must be in the future' using errcode = '22023'; end if;
  insert into reminders (user_id, opportunity_id, application_id, kind, origin, remind_at, title, body)
  values (auth.uid(), p_opportunity, p_application, 'custom', 'manual', p_remind_at, left(p_title, 140), p_body)
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.mark_all_notifications_read() returns integer
language sql security invoker set search_path = public as $$
  with u as (update notifications set is_read = true, read_at = now() where user_id = auth.uid() and not is_read returning 1)
  select count(*)::int from u;
$$;

-- Historical forecasting: clearly an estimate based on prior cycles
create or replace view public.opportunity_forecasts with (security_invoker = true) as
select c.recurrence_key,
       count(*) as cycles_observed,
       max(c.cycle_year) as last_cycle_year,
       round(avg(extract(doy from c.opened_on))) as avg_open_day_of_year,
       round(avg(extract(doy from c.deadline_on))) as avg_deadline_day_of_year,
       (make_date(max(c.cycle_year) + 1, 1, 1) + (round(avg(extract(doy from c.opened_on)))::int - 1)) as estimated_next_opening,
       (make_date(max(c.cycle_year) + 1, 1, 1) + (round(avg(extract(doy from c.deadline_on)))::int - 1)) as estimated_next_deadline,
       true as is_estimate
  from public.opportunity_cycles c
 where c.opened_on is not null and c.deadline_on is not null
 group by c.recurrence_key
having count(*) >= 2;

-- ---------------------------------------------------------------------------
-- Admin RPCs (role-checked inside)
-- ---------------------------------------------------------------------------
create or replace function public.admin_dashboard_stats() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_staff() then raise exception 'forbidden' using errcode = '42501'; end if;
  return jsonb_build_object(
    'total_users', (select count(*) from profiles),
    'active_users_30d', (select count(distinct user_id) from opportunity_views where viewed_at > now() - interval '30 days'),
    'total_opportunities', (select count(*) from opportunities),
    'published', (select count(*) from opportunities where is_published),
    'verified', (select count(*) from opportunities where verification_status = 'verified'),
    'pending', (select count(*) from opportunities where verification_status = 'pending_verification'),
    'expired', (select count(*) from opportunities where verification_status = 'expired' or status = 'closed'),
    'reported', (select count(*) from opportunity_reports where status in ('open', 'investigating')),
    'pending_source_items', (select count(*) from source_items where review_status = 'pending'),
    'pending_submissions', (select count(*) from opportunity_submissions where status = 'pending'),
    'pending_stories', (select count(*) from success_stories where status = 'pending'),
    'pending_corrections', (select count(*) from user_corrections where status = 'pending'),
    'sources', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name, 'status', integration_status,
                 'enabled', is_enabled, 'last_success_at', last_success_at, 'failures', consecutive_failures) order by name), '[]')
                from data_sources),
    'recent_activity', (select coalesce(jsonb_agg(a order by a.created_at desc), '[]') from
                (select action, table_name, record_id, created_at, actor_id from audit_logs order by created_at desc limit 20) a)
  );
end $$;

create or replace function public.admin_analytics() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_staff() then raise exception 'forbidden' using errcode = '42501'; end if;
  return jsonb_build_object(
    'users_by_category', (select coalesce(jsonb_object_agg(coalesce(user_category::text, 'unspecified'), n), '{}') from
        (select user_category, count(*) n from profiles group by 1) x),
    'users_by_province', (select coalesce(jsonb_object_agg(coalesce(province, 'unspecified'), n), '{}') from
        (select province, count(*) n from profiles group by 1) x),
    'signups_by_week', (select coalesce(jsonb_agg(jsonb_build_object('week', w, 'count', n) order by w), '[]') from
        (select date_trunc('week', created_at)::date w, count(*) n from profiles
          where created_at > now() - interval '12 weeks' group by 1) x),
    'opportunities_by_category', (select coalesce(jsonb_object_agg(c.slug, n), '{}') from
        (select category_id, count(*) n from opportunities group by 1) x join opportunity_categories c on c.id = x.category_id),
    'popular_categories', (select coalesce(jsonb_agg(jsonb_build_object('category', c.slug, 'views', n) order by n desc), '[]') from
        (select o.category_id, count(*) n from opportunity_views v join opportunities o on o.id = v.opportunity_id
          where v.viewed_at > now() - interval '30 days' group by 1) x join opportunity_categories c on c.id = x.category_id),
    'popular_locations', (select coalesce(jsonb_agg(jsonb_build_object('province', p, 'count', n) order by n desc), '[]') from
        (select unnest(provinces) p, count(*) n from opportunities where is_published group by 1) x),
    'most_viewed', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'title', title, 'count', view_count) order by view_count desc), '[]')
        from (select id, title, view_count from opportunities order by view_count desc limit 10) x),
    'most_saved', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'title', title, 'count', save_count) order by save_count desc), '[]')
        from (select id, title, save_count from opportunities order by save_count desc limit 10) x),
    'most_interested', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'title', title, 'count', interest_count) order by interest_count desc), '[]')
        from (select id, title, interest_count from opportunities order by interest_count desc limit 10) x),
    'applications_by_status', (select coalesce(jsonb_object_agg(status, n), '{}') from
        (select status, count(*) n from applications group by 1) x),
    'source_reliability', (select coalesce(jsonb_agg(jsonb_build_object('source', s.name, 'runs', x.runs,
          'success_rate', round(x.ok::numeric / nullif(x.runs, 0), 3)) order by s.name), '[]')
        from data_sources s join (select source_id, count(*) runs, count(*) filter (where status = 'success') ok
          from source_sync_logs where started_at > now() - interval '30 days' group by 1) x on x.source_id = s.id),
    'verification', (select coalesce(jsonb_object_agg(verification_status, n), '{}') from
        (select verification_status, count(*) n from opportunities group by 1) x),
    'reviews_last_30d', (select count(*) from verification_reviews where created_at > now() - interval '30 days')
  );
end $$;

create or replace function public.admin_set_role(p_user uuid, p_role public.app_role, p_grant boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_role in ('admin', 'super_admin') and not public.is_super_admin() then
    raise exception 'Only a super admin can manage admin roles' using errcode = '42501';
  end if;
  if not public.is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if p_role = 'user' then raise exception 'The base user role cannot be changed' using errcode = '22023'; end if;
  if p_user = auth.uid() and not p_grant and p_role = 'super_admin' then
    raise exception 'You cannot remove your own super admin role' using errcode = '22023';
  end if;
  if p_grant then
    insert into user_roles (user_id, role, granted_by) values (p_user, p_role, auth.uid()) on conflict do nothing;
  else
    delete from user_roles where user_id = p_user and role = p_role;
  end if;
end $$;

create or replace function public.admin_set_suspended(p_user uuid, p_suspended boolean, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if p_reason is null or char_length(btrim(p_reason)) < 5 then
    raise exception 'A justification is required' using errcode = '22023';
  end if;
  update profiles set is_suspended = p_suspended where id = p_user;
  insert into audit_logs (actor_id, action, table_name, record_id, new_data)
  values (auth.uid(), case when p_suspended then 'suspend' else 'unsuspend' end, 'profiles', p_user::text,
          jsonb_build_object('reason', p_reason));
end $$;

-- Verifier decision on an opportunity: writes review record + updates status atomically.
create or replace function public.review_opportunity(p_opportunity uuid, p_decision text, p_checklist jsonb, p_notes text, p_publish boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.can_verify() then raise exception 'forbidden' using errcode = '42501'; end if;
  if p_decision not in ('approved', 'rejected', 'needs_changes') then raise exception 'invalid decision'; end if;
  if p_decision = 'approved' and not (coalesce((p_checklist ->> 'source_url_official')::boolean, false)
                                       and coalesce((p_checklist ->> 'application_url_official')::boolean, false)
                                       and coalesce((p_checklist ->> 'deadline_confirmed')::boolean, false)) then
    raise exception 'Approval requires confirming the source URL, application URL and deadline' using errcode = '22023';
  end if;
  insert into verification_reviews (opportunity_id, reviewer_id, decision, checklist, notes)
  values (p_opportunity, auth.uid(), p_decision, coalesce(p_checklist, '{}'), p_notes);
  update opportunities set
    approval_status = case p_decision when 'approved' then 'approved'::approval_status
                                       when 'rejected' then 'rejected'::approval_status else 'pending_review'::approval_status end,
    verification_status = case p_decision when 'approved' then (case when is_demo then 'unverified' else 'verified' end)::verification_status
                                          when 'rejected' then 'rejected'::verification_status else 'pending_verification'::verification_status end,
    is_published = case when p_decision = 'approved' then coalesce(p_publish, true) else false end
  where id = p_opportunity;
  insert into notifications (user_id, type, title, body, opportunity_id, dedupe_key)
  select i.user_id, 'verification_update', 'Listing verified', o.title || ' has been verified against its official source.',
         o.id, 'verified:' || o.id || ':' || o.data_version
    from interested_opportunities i join opportunities o on o.id = i.opportunity_id
   where i.opportunity_id = p_opportunity and p_decision = 'approved' and not o.is_demo
  on conflict do nothing;
end $$;

-- ---------------------------------------------------------------------------
-- Execute permissions: internal jobs are never callable by app users.
-- ---------------------------------------------------------------------------
revoke execute on function public.schedule_deadline_reminders(uuid, uuid, text, smallint[]) from public, anon, authenticated;
revoke execute on function public.cancel_deadline_reminders(uuid, uuid, text) from public, anon, authenticated;
revoke execute on function public.dispatch_due_reminders(int) from public, anon, authenticated;
revoke execute on function public.refresh_opportunity_statuses() from public, anon, authenticated;
revoke execute on function public.bump_profile_version(uuid) from public, anon, authenticated;
revoke execute on function public.handle_new_user() from public, anon, authenticated;
grant execute on function public.dispatch_due_reminders(int) to service_role;
grant execute on function public.refresh_opportunity_statuses() to service_role;
