-- Row Level Security and role-based access tests
\set ON_ERROR_STOP 1
\set alice '11111111-1111-1111-1111-111111111111'
\set bob   '22222222-2222-2222-2222-222222222222'
\set admin '33333333-3333-3333-3333-333333333333'
\set cm    '44444444-4444-4444-4444-444444444444'
\set ver   '55555555-5555-5555-5555-555555555555'

insert into auth.users (id, email, raw_user_meta_data) values
  (:'alice', 'alice@example.com', '{"full_name":"Alice Test","accepted_terms":"true"}'),
  (:'bob', 'bob@example.com', '{"full_name":"Bob Test"}'),
  (:'admin', 'admin@example.com', '{}'),
  (:'cm', 'cm@example.com', '{}'),
  (:'ver', 'ver@example.com', '{}');
insert into public.user_roles (user_id, role) values (:'admin', 'super_admin'), (:'cm', 'content_manager'), (:'ver', 'verifier');

-- bootstrap trigger
do $$ begin
  assert (select count(*) from public.profiles where id in ('11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222')) = 2, 'profiles not created';
  assert (select full_name from public.profiles where id = '11111111-1111-1111-1111-111111111111') = 'Alice Test', 'full_name not copied';
  assert (select terms_accepted_at is not null from public.profiles where id = '11111111-1111-1111-1111-111111111111'), 'consent not recorded';
  assert exists (select 1 from public.notification_preferences where user_id = '11111111-1111-1111-1111-111111111111'), 'prefs missing';
  assert exists (select 1 from public.user_roles where user_id = '11111111-1111-1111-1111-111111111111' and role = 'user'), 'base role missing';
end $$;

-- ---------------------------------------------------------------- anon: only published opportunities
begin;
set local role anon;
do $$ begin
  assert (select count(*) from public.opportunities) = (select count(*) from public.opportunity_feed), 'anon sees non-feed rows';
  assert (select count(*) from public.opportunity_feed) >= 9, 'anon cannot browse demo feed';
  assert (select count(*) from public.profiles) = 0, 'anon can read profiles';
  assert (select count(*) from public.data_sources) = 0, 'anon can read data sources';
end $$;
rollback;

-- unpublished listing must be hidden from users
insert into public.opportunities (title, organization_id, category_id, approval_status, is_published, is_demo)
select '[DEMO] Hidden draft', (select id from organizations where slug='demo-ravi-tech'), (select id from opportunity_categories where slug='jobs'),
       'draft', false, true;

-- ---------------------------------------------------------------- alice writes private data
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'alice', true);
insert into public.saved_opportunities (user_id, opportunity_id)
  select auth.uid(), id from public.opportunity_feed where title like '%Junior Data Analyst%';
insert into public.applications (user_id, custom_title, status) values (auth.uid(), 'Alice private app', 'planning');
insert into public.user_documents (user_id, category, title, storage_path, mime_type, size_bytes)
  values (auth.uid(), 'cv', 'My CV', auth.uid() || '/cv.pdf', 'application/pdf', 1000);
insert into storage.objects (bucket_id, name) values ('user-documents', auth.uid() || '/cv.pdf');
update public.profiles set city = 'Lahore', province = 'Punjab' where id = auth.uid();
do $$ begin
  assert (select count(*) from public.opportunities where title = '[DEMO] Hidden draft') = 0, 'user sees draft';
  assert (select count(*) from public.profiles) = 1, 'user sees other profiles';
end $$;
-- cannot write rows for someone else
do $$ begin
  begin
    insert into public.saved_opportunities (user_id, opportunity_id)
      select '22222222-2222-2222-2222-222222222222', id from public.opportunity_feed limit 1;
    raise exception 'FAIL: inserted row for another user';
  exception when insufficient_privilege then null; end;
  begin
    insert into storage.objects (bucket_id, name) values ('user-documents', '22222222-2222-2222-2222-222222222222/x.pdf');
    raise exception 'FAIL: wrote into another user''s storage folder';
  exception when insufficient_privilege then null; end;
  begin
    insert into public.user_documents (user_id, category, title, storage_path, mime_type, size_bytes)
      values (auth.uid(), 'cv', 'bad', '22222222-2222-2222-2222-222222222222/x.pdf', 'application/pdf', 10);
    raise exception 'FAIL: document path outside own folder accepted';
  exception when check_violation then null; end;
end $$;
commit;

-- ---------------------------------------------------------------- bob cannot see alice's data
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'bob', true);
do $$ begin
  assert (select count(*) from public.saved_opportunities) = 0, 'bob sees alice saved';
  assert (select count(*) from public.applications) = 0, 'bob sees alice applications';
  assert (select count(*) from public.user_documents) = 0, 'bob sees alice documents';
  assert (select count(*) from storage.objects) = 0, 'bob sees alice files';
  assert (select count(*) from public.profiles where id = '11111111-1111-1111-1111-111111111111') = 0, 'bob sees alice profile';
  assert (select count(*) from public.notifications) = 0, 'bob sees notifications';
end $$;
update public.applications set notes = 'hacked';     -- must silently affect 0 rows
delete from public.user_documents;                   -- must affect 0 rows
commit;
do $$ begin
  assert (select notes from public.applications where custom_title = 'Alice private app') is null, 'bob modified alice application';
  assert (select count(*) from public.user_documents) = 1, 'bob deleted alice document';
end $$;

-- ---------------------------------------------------------------- privilege escalation attempts by a normal user
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'alice', true);
do $$ begin
  begin
    insert into public.user_roles (user_id, role) values (auth.uid(), 'admin');
    raise exception 'FAIL: self-granted admin';
  exception when insufficient_privilege then null; end;
  begin
    perform public.admin_dashboard_stats();
    raise exception 'FAIL: user read admin stats';
  exception when insufficient_privilege then null; end;
  begin
    perform public.admin_set_role(auth.uid(), 'admin', true);
    raise exception 'FAIL: user called admin_set_role';
  exception when insufficient_privilege then null; end;
  begin
    perform public.dispatch_due_reminders(10);
    raise exception 'FAIL: user called internal job';
  exception when insufficient_privilege then null; end;
  begin
    perform public.schedule_deadline_reminders(auth.uid(), gen_random_uuid(), 'interested', '{1}');
    raise exception 'FAIL: user called internal scheduler';
  exception when insufficient_privilege then null; end;
  begin
    insert into public.eligibility_checks (user_id, opportunity_id, outcome, explanation, profile_version, rules_version)
      select auth.uid(), id, 'eligible', 'forged', 1, 1 from public.opportunity_feed limit 1;
    raise exception 'FAIL: user forged an eligibility result';
  exception when insufficient_privilege then null; end;
  begin
    update public.notifications set title = 'x';
    raise exception 'FAIL: user updated notification title';
  exception when insufficient_privilege then null; end;
  begin
    insert into public.reminders (user_id, kind, origin, remind_at, title) values (auth.uid(), 'deadline_auto', 'interested', now() + interval '1 day', 'x');
    raise exception 'FAIL: user inserted an automatic reminder';
  exception when insufficient_privilege then null; end;
end $$;
update public.profiles set is_suspended = true where id = auth.uid();   -- guard trigger must ignore this
update public.opportunities set title = 'pwned';                         -- RLS: 0 rows
commit;
do $$ begin
  assert not (select is_suspended from public.profiles where id = '11111111-1111-1111-1111-111111111111'), 'user suspended self (guard failed)';
  assert not exists (select 1 from public.opportunities where title = 'pwned'), 'user edited opportunity';
  assert not exists (select 1 from public.user_roles where user_id = '11111111-1111-1111-1111-111111111111' and role <> 'user'), 'role escalation';
end $$;

-- ---------------------------------------------------------------- content manager vs verifier
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'cm', true);
do $$ begin
  assert (select count(*) from public.opportunities where title = '[DEMO] Hidden draft') = 1, 'staff cannot see drafts';
  begin
    update public.opportunities set approval_status = 'approved' where title = '[DEMO] Hidden draft';
    raise exception 'FAIL: content manager approved listing';
  exception when insufficient_privilege then null; end;
  begin
    perform public.admin_set_role('11111111-1111-1111-1111-111111111111', 'verifier', true);
    raise exception 'FAIL: content manager granted role';
  exception when insufficient_privilege then null; end;
  assert (select count(*) from public.data_sources) > 0, 'staff cannot read sources';
end $$;
-- content manager edits a verified listing's deadline → loses verified status (set up below by verifier)
commit;

begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'ver', true);
do $$ declare v uuid; begin
  select id into v from public.opportunities where title = '[DEMO] Hidden draft';
  begin
    perform public.review_opportunity(v, 'approved', '{"source_url_official":true}', 'incomplete', true);
    raise exception 'FAIL: approval without checklist';
  exception when sqlstate '22023' then null; end;
end $$;
commit;

-- non-demo listing: verifier approves → verified; content manager material edit → pending_verification
insert into public.opportunities (title, organization_id, category_id, source_url, official_application_url, deadline, approval_status)
select 'Real-looking test listing', (select id from organizations where slug='hec'), (select id from opportunity_categories where slug='scholarships'),
       'https://www.hec.gov.pk/test', 'https://www.hec.gov.pk/test/apply', now() + interval '30 days', 'pending_review';
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'ver', true);
select public.review_opportunity((select id from public.opportunities where title = 'Real-looking test listing'), 'approved',
  '{"source_url_official":true,"application_url_official":true,"deadline_confirmed":true}', 'checked', true);
commit;
do $$ begin
  assert (select verification_status from public.opportunities where title = 'Real-looking test listing') = 'verified', 'verifier approval failed';
  assert (select last_verified_at is not null and is_published from public.opportunities where title = 'Real-looking test listing'), 'not published/verified_at';
  assert exists (select 1 from public.verification_reviews r join public.opportunities o on o.id = r.opportunity_id where o.title = 'Real-looking test listing'), 'no review record';
end $$;
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'cm', true);
update public.opportunities set deadline = deadline + interval '3 days' where title = 'Real-looking test listing';
commit;
do $$ begin
  assert (select verification_status from public.opportunities where title = 'Real-looking test listing') = 'pending_verification',
    'material edit by content manager kept verified status';
  assert (select max(version) from public.opportunity_versions v join public.opportunities o on o.id = v.opportunity_id
           where o.title = 'Real-looking test listing') >= 2, 'version history not recorded';
  assert exists (select 1 from public.audit_logs where table_name = 'opportunities' and action = 'update'), 'audit log missing';
end $$;

-- demo listings can never become verified
do $$ begin
  begin
    update public.opportunities set verification_status = 'verified' where is_demo and title like '%Junior Data Analyst%';
    raise exception 'FAIL: demo marked verified';
  exception when check_violation then null; end;
end $$;

-- super admin can manage roles
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'admin', true);
select public.admin_set_role(:'bob', 'verifier', true);
select public.admin_set_role(:'bob', 'verifier', false);
do $$ begin
  assert (public.admin_dashboard_stats() ->> 'total_users')::int >= 5, 'admin stats broken';
  assert (public.admin_analytics() ? 'source_reliability'), 'analytics broken';
end $$;
commit;

\echo '10_security_rls: OK'
