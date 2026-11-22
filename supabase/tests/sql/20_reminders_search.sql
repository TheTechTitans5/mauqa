-- Interested reminders, deadline changes, closures, dispatch dedupe, applications, search, staleness
\set ON_ERROR_STOP 1
\set alice '11111111-1111-1111-1111-111111111111'

create temp table t_ctx as
select (select id from public.opportunities where title like '[DEMO] Indus Need-cum-Merit Undergraduate%') as scholarship,
       (select id from public.opportunities where title like '[DEMO] Small Farmer%') as farmer,
       (select id from public.opportunities where title like '[DEMO] Junior Data Analyst%') as job;
grant select on t_ctx to authenticated;

-- ---------------------------------------------------------------- mark Interested → 4 reminders (7/3/1/0 days)
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'alice', true);
insert into public.interested_opportunities (user_id, opportunity_id) select auth.uid(), scholarship from t_ctx;
do $$ declare n int; begin
  select count(*) into n from public.reminders where opportunity_id = (select scholarship from t_ctx) and status = 'pending';
  assert n = 4, format('expected 4 reminders, got %s', n);
  -- reminders fire at 09:00 Pakistan time and never after the deadline
  assert not exists (select 1 from public.reminders r join public.opportunities o on o.id = r.opportunity_id
                      where r.status = 'pending' and (r.remind_at >= o.deadline or r.remind_at <= now())), 'reminder outside window';
  assert (select bool_and(extract(hour from remind_at at time zone 'Asia/Karachi') = 9 or offset_days = 0)
            from public.reminders where opportunity_id = (select scholarship from t_ctx)), 'not scheduled at 09:00 PKT';
  -- a second identical insert attempt must not duplicate reminders
  assert public.home_summary() ->> 'interested_count' = '1', 'home summary interested count';
end $$;
-- farmer scheme closes in 2 days → only the 1-day and 0-day reminders are still in the future
insert into public.interested_opportunities (user_id, opportunity_id) select auth.uid(), farmer from t_ctx;
do $$ declare n int; begin
  select count(*) into n from public.reminders where opportunity_id = (select farmer from t_ctx) and status = 'pending';
  assert n = 2, format('expected 2 reminders for near deadline, got %s', n);
end $$;
-- custom offsets
update public.interested_opportunities set reminder_offsets_days = '{14,1}' where opportunity_id = (select scholarship from t_ctx);
do $$ declare offs smallint[]; begin
  select array_agg(offset_days order by offset_days) into offs from public.reminders
   where opportunity_id = (select scholarship from t_ctx) and status = 'pending';
  assert offs = '{1,14}', format('custom offsets wrong: %s', offs);
  assert (select count(*) from public.reminders where opportunity_id = (select scholarship from t_ctx) and status = 'cancelled') = 4,
    'old reminders not cancelled';
end $$;
-- disable then re-enable → no duplicates
update public.interested_opportunities set reminders_enabled = false where opportunity_id = (select scholarship from t_ctx);
update public.interested_opportunities set reminders_enabled = true where opportunity_id = (select scholarship from t_ctx);
do $$ begin
  assert (select count(*) from public.reminders where opportunity_id = (select scholarship from t_ctx) and status = 'pending') = 2,
    'duplicate reminders after re-enable';
end $$;
-- invalid offset rejected
do $$ begin
  begin
    update public.interested_opportunities set reminder_offsets_days = '{99}' where opportunity_id = (select scholarship from t_ctx);
    raise exception 'FAIL: invalid offset accepted';
  exception when check_violation then null; end;
end $$;
-- also save the same listing with reminders on
insert into public.saved_opportunities (user_id, opportunity_id, reminders_enabled) select auth.uid(), scholarship, true from t_ctx
  on conflict (user_id, opportunity_id) do update set reminders_enabled = true;
-- custom reminder RPC
select public.add_custom_reminder('Ask teacher for reference', now() + interval '2 days', (select scholarship from t_ctx));
do $$ begin
  begin
    perform public.add_custom_reminder('past', now() - interval '1 hour');
    raise exception 'FAIL: past custom reminder accepted';
  exception when sqlstate '22023' then null; end;
  assert exists (select 1 from public.my_calendar_events(now(), now() + interval '60 days') where event_type = 'custom_reminder'), 'calendar missing custom';
  assert exists (select 1 from public.my_calendar_events(now(), now() + interval '60 days') where event_type = 'interested_deadline'), 'calendar missing deadline';
  -- interested + saved: deadline appears once
  assert (select count(*) from public.my_calendar_events(now(), now() + interval '60 days') where opportunity_id = (select scholarship from t_ctx)
            and event_type in ('interested_deadline', 'saved_deadline')) = 1, 'calendar duplicates deadline';
end $$;
commit;

-- ---------------------------------------------------------------- deadline change (by system/verifier)
update public.opportunities set deadline = deadline + interval '10 days' where id = (select scholarship from t_ctx);
do $$ declare new_deadline timestamptz; begin
  select deadline into new_deadline from public.opportunities where id = (select scholarship from t_ctx);
  assert not exists (select 1 from public.reminders where opportunity_id = (select scholarship from t_ctx) and status = 'pending'
                      and deadline_snapshot <> new_deadline), 'pending reminders still point at old deadline';
  assert (select count(*) from public.reminders where opportunity_id = (select scholarship from t_ctx) and status = 'pending' and origin = 'interested') = 2,
    'interested reminders not rescheduled';
  assert (select count(*) from public.notifications where type = 'deadline_changed' and opportunity_id = (select scholarship from t_ctx)) = 1,
    'deadline change notification missing or duplicated';
end $$;
-- same change replayed must not notify twice
update public.opportunities set deadline = deadline where id = (select scholarship from t_ctx);
do $$ begin
  assert (select count(*) from public.notifications where type = 'deadline_changed') = 1, 'duplicate deadline notification';
end $$;

-- ---------------------------------------------------------------- dispatch: due reminders → one notification each, idempotent
update public.reminders set remind_at = now() - interval '1 minute'
 where opportunity_id = (select scholarship from t_ctx) and status = 'pending' and offset_days = 1;  -- one interested + one saved
do $$ declare n int; begin
  n := public.dispatch_due_reminders(100);
  assert n = 1, format('expected 1 notification (saved+interested deduped), got %s', n);
  n := public.dispatch_due_reminders(100);
  assert n = 0, 'dispatch not idempotent';
  assert (select count(*) from public.notifications where type = 'closing_soon' and opportunity_id = (select scholarship from t_ctx)) = 1,
    'closing soon notification missing';
end $$;
-- preference off → deadline reminder not delivered
update public.notification_preferences set deadline_reminders = false, closing_soon = false where user_id = :'alice';
update public.reminders set remind_at = now() - interval '1 minute'
 where opportunity_id = (select scholarship from t_ctx) and status = 'pending' and offset_days = 14 and origin = 'interested';
do $$ begin
  assert public.dispatch_due_reminders(100) = 0, 'reminder delivered despite preference off';
end $$;
update public.notification_preferences set deadline_reminders = true, closing_soon = true where user_id = :'alice';

-- ---------------------------------------------------------------- closing → reminders stop, users told
update public.opportunities set status = 'closed' where id = (select farmer from t_ctx);
do $$ begin
  assert not exists (select 1 from public.reminders where opportunity_id = (select farmer from t_ctx) and status = 'pending'), 'reminders continue after close';
  assert exists (select 1 from public.notifications where type = 'opportunity_closed' and opportunity_id = (select farmer from t_ctx)), 'close notification missing';
end $$;
-- expiry job
update public.opportunities set deadline = now() - interval '1 minute', opening_date = now() - interval '2 days' where id = (select job from t_ctx);
do $$ begin
  assert (public.refresh_opportunity_statuses() ->> 'closed')::int >= 1, 'expiry job closed nothing';
  assert (select status = 'closed' and verification_status = 'expired' from public.opportunities where id = (select job from t_ctx)), 'not expired';
end $$;

-- ---------------------------------------------------------------- applications: history + interview reminders
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'alice', true);
insert into public.applications (user_id, opportunity_id, status) select auth.uid(), scholarship, 'planning' from t_ctx;
update public.applications set status = 'applied' where opportunity_id = (select scholarship from t_ctx);
update public.applications set status = 'interview_scheduled', interview_at = now() + interval '5 days' where opportunity_id = (select scholarship from t_ctx);
do $$ begin
  assert (select count(*) from public.application_status_history h join public.applications a on a.id = h.application_id
           where a.opportunity_id = (select scholarship from t_ctx)) = 3, 'status history incomplete';
  assert (select applied_on is not null from public.applications where opportunity_id = (select scholarship from t_ctx)), 'applied_on not set';
  assert (select count(*) from public.reminders r join public.applications a on a.id = r.application_id
           where a.opportunity_id = (select scholarship from t_ctx) and r.kind = 'interview' and r.status = 'pending') = 2, 'interview reminders missing';
  begin
    insert into public.applications (user_id, opportunity_id) select auth.uid(), scholarship from t_ctx;
    raise exception 'FAIL: duplicate application for same opportunity';
  exception when unique_violation then null; end;
end $$;
update public.applications set interview_at = now() + interval '8 days' where opportunity_id = (select scholarship from t_ctx);
do $$ begin
  assert (select count(*) from public.reminders r join public.applications a on a.id = r.application_id
           where a.opportunity_id = (select scholarship from t_ctx) and r.kind = 'interview' and r.status = 'pending') = 2, 'interview reschedule duplicated';
end $$;
commit;

-- ---------------------------------------------------------------- search
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'alice', true);
do $$ declare r jsonb; begin
  r := public.search_opportunities('scholarship', '{}', 'relevance', 10, 0);
  assert (r ->> 'total')::int >= 1, 'text search found nothing';
  assert not exists (select 1 from jsonb_array_elements(r -> 'items') i where i ->> 'effective_status' = 'closed'), 'closed listing returned by default';
  r := public.search_opportunities(null, '{"statuses":["closed"]}', 'latest', 10, 0);
  assert (r ->> 'total')::int >= 1, 'closed filter returns nothing';
  r := public.search_opportunities(null, '{"categories":["internships"]}', 'deadline', 10, 0);
  assert (select bool_and(i ->> 'category_slug' = 'internships') from jsonb_array_elements(r -> 'items') i), 'category filter leaks';
  r := public.search_opportunities(null, '{"provinces":["Sindh"]}', 'relevance', 50, 0);
  assert not exists (select 1 from jsonb_array_elements(r -> 'items') i where i ->> 'title' like '%Summer Software%'), 'province filter ignored';
  r := public.search_opportunities(null, '{"gender":"male"}', 'relevance', 50, 0);
  assert not exists (select 1 from jsonb_array_elements(r -> 'items') i where i ->> 'title' like '%Women in Tech%'), 'gender filter ignored';
  r := public.search_opportunities(null, '{"verified_only":true,"hide_demo":true}', 'relevance', 50, 0);
  assert not exists (select 1 from jsonb_array_elements(r -> 'items') i where (i ->> 'is_demo')::boolean), 'demo returned as verified';
  r := public.search_opportunities('NUST', '{}', 'relevance', 50, 0);
  assert exists (select 1 from jsonb_array_elements(r -> 'items') i where i ->> 'title' like '%Summer Software%'), 'institution search failed';
  r := public.search_opportunities(null, '{}', 'popularity', 2, 2);
  assert jsonb_array_length(r -> 'items') <= 2 and (r ->> 'offset')::int = 2, 'pagination broken';
  r := public.search_opportunities('ravi', '{}', 'relevance', 50, 0);
  assert (r ->> 'total')::int >= 2, 'organisation search failed';
  assert (select count(*) from public.trending_opportunities(5)) between 1 and 5, 'trending broken';
end $$;
select public.record_opportunity_view((select scholarship from t_ctx));
select public.record_opportunity_view((select scholarship from t_ctx));  -- within the hour: not double counted
commit;
do $$ begin
  assert (select view_count from public.opportunities where id = (select scholarship from t_ctx)) = 1, 'view counted twice';
end $$;

-- ---------------------------------------------------------------- eligibility staleness
insert into public.eligibility_checks (user_id, opportunity_id, outcome, explanation, profile_version, rules_version)
select :'alice', scholarship, 'probably_eligible', 'seeded', 1, 1 from t_ctx;
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'alice', true);
insert into public.education_records (user_id, level, enrollment_status, score_type, score_value, score_max, is_current)
values (auth.uid(), 'bachelor', 'enrolled', 'cgpa', 3.4, 4, true);
commit;
do $$ begin
  assert (select is_stale from public.eligibility_checks where user_id = '11111111-1111-1111-1111-111111111111'), 'profile change did not mark stale';
  assert (select profile_version from public.profiles where id = '11111111-1111-1111-1111-111111111111') > 1, 'profile version not bumped';
end $$;
update public.eligibility_checks set is_stale = false;
insert into public.opportunity_eligibility_rules (opportunity_id, node_type, criterion_type, params)
select scholarship, 'criterion', 'nationality_in', '{"nationalities":["Pakistani"]}' from t_ctx;
do $$ begin
  assert (select is_stale from public.eligibility_checks where user_id = '11111111-1111-1111-1111-111111111111'), 'rule change did not mark stale';
end $$;

-- ---------------------------------------------------------------- reports → "Reported for Review" at 3 distinct reporters
insert into auth.users (id, email) values ('66666666-6666-6666-6666-666666666666', 'r1@example.com'),
  ('77777777-7777-7777-7777-777777777777', 'r2@example.com'), ('88888888-8888-8888-8888-888888888888', 'r3@example.com');
insert into public.opportunity_reports (opportunity_id, reporter_id, reason)
select (select id from public.opportunities where title like '[DEMO] Early-stage%'), u, 'fee_requested'
  from unnest(array['66666666-6666-6666-6666-666666666666', '77777777-7777-7777-7777-777777777777']::uuid[]) u;
do $$ begin assert not (select is_reported from public.opportunities where title like '[DEMO] Early-stage%'), 'flagged too early'; end $$;
insert into public.opportunity_reports (opportunity_id, reporter_id, reason)
select id, '88888888-8888-8888-8888-888888888888', 'suspected_scam' from public.opportunities where title like '[DEMO] Early-stage%';
do $$ begin assert (select is_reported from public.opportunities where title like '[DEMO] Early-stage%'), 'not flagged after 3 reports'; end $$;
update public.opportunity_reports set status = 'dismissed';
do $$ begin assert not (select is_reported from public.opportunities where title like '[DEMO] Early-stage%'), 'flag not cleared'; end $$;

-- ---------------------------------------------------------------- forecasting & completion & account deletion cascade
do $$ begin
  assert exists (select 1 from public.opportunity_forecasts where recurrence_key = 'demo-indus-ug-scholarship' and is_estimate), 'forecast missing';
  assert public.profile_completion('11111111-1111-1111-1111-111111111111') between 1 and 100, 'completion out of range';
end $$;
delete from auth.users where id = '22222222-2222-2222-2222-222222222222';
do $$ begin
  assert not exists (select 1 from public.profiles where id = '22222222-2222-2222-2222-222222222222'), 'profile not deleted with account';
end $$;
-- deleting an opportunity with rules cascades cleanly
delete from public.opportunities where title = '[DEMO] Hidden draft';
select public.purge_demo_data();
do $$ begin
  assert not exists (select 1 from public.opportunities where is_demo), 'demo purge failed';
  assert exists (select 1 from public.opportunities where title = 'Real-looking test listing'), 'purge removed real data';
end $$;

\echo '20_reminders_search: OK'
