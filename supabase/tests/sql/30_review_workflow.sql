-- Review workflow: ingested items never publish themselves; verifiers turn them into drafts, then verify.
\set ON_ERROR_STOP 1
\set ver '55555555-5555-5555-5555-555555555555'
\set alice '11111111-1111-1111-1111-111111111111'

update public.data_sources set integration_status = 'active', is_enabled = true where name = 'HEC scholarship announcements';
insert into public.source_items (source_id, external_id, item_url, extracted, content_hash)
select id, 'https://www.hec.gov.pk/x/1', 'https://www.hec.gov.pk/x/1',
       jsonb_build_object('title', 'Test ingested scholarship', 'source_url', 'https://www.hec.gov.pk/x/1',
                          'deadline', (now() + interval '30 days')::text),
       'hash-1'
  from public.data_sources where name = 'HEC scholarship announcements';

-- a normal user cannot see or act on the queue
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'alice', true);
do $$ begin
  assert (select count(*) from public.source_items) = 0, 'user sees review queue';
  begin
    perform public.create_opportunity_from_source_item((select gen_random_uuid()), 'scholarships');
    raise exception 'FAIL: user created listing from source item';
  exception when insufficient_privilege then null; end;
end $$;
commit;

begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'ver', true);
select public.create_opportunity_from_source_item((select id from public.source_items where external_id = 'https://www.hec.gov.pk/x/1'),
  'scholarships', 'https://www.hec.gov.pk/x/1/apply');
do $$ declare o record; begin
  select * into o from public.opportunities where title = 'Test ingested scholarship';
  assert o.verification_status = 'pending_verification' and not o.is_published, 'ingested item auto-published';
  assert o.official_application_url = 'https://www.hec.gov.pk/x/1/apply', 'apply url not set';
  assert (select review_status from public.source_items where external_id = 'https://www.hec.gov.pk/x/1') = 'approved', 'item not marked';
  begin
    perform public.create_opportunity_from_source_item((select id from public.source_items where external_id = 'https://www.hec.gov.pk/x/1'), 'scholarships');
    raise exception 'FAIL: double conversion';
  exception when sqlstate '22023' then null; end;
end $$;
-- verify + publish it, then a change arrives
select public.review_opportunity((select id from public.opportunities where title = 'Test ingested scholarship'), 'approved',
  '{"source_url_official":true,"application_url_official":true,"deadline_confirmed":true}', 'ok', true);
commit;

insert into public.interested_opportunities (user_id, opportunity_id)
select :'alice', id from public.opportunities where title = 'Test ingested scholarship';
insert into public.source_items (source_id, external_id, item_url, extracted, content_hash, opportunity_id, detected_changes)
select s.source_id, s.external_id, s.item_url, s.extracted || jsonb_build_object('deadline', (now() + interval '45 days')::text),
       'hash-2', s.opportunity_id, '{"deadline":{"from":"a","to":"b"}}'
  from public.source_items s where s.external_id = 'https://www.hec.gov.pk/x/1';
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'ver', true);
select public.apply_source_item_changes((select id from public.source_items where content_hash = 'hash-2'));
commit;
do $$ begin
  assert (select deadline > now() + interval '44 days' from public.opportunities where title = 'Test ingested scholarship'), 'change not applied';
  assert exists (select 1 from public.notifications n join public.opportunities o on o.id = n.opportunity_id
                  where o.title = 'Test ingested scholarship' and n.type = 'deadline_changed'), 'followers not notified of change';
  assert (select count(*) from public.reminders r join public.opportunities o on o.id = r.opportunity_id
           where o.title = 'Test ingested scholarship' and r.status = 'pending') = 4, 'reminders not rescheduled';
  assert exists (select 1 from public.verification_reviews v join public.source_items s on s.id = v.source_item_id
                  where s.content_hash = 'hash-2' and v.decision = 'approved'), 'change review not recorded';
end $$;

\echo '30_review_workflow: OK'

-- feedback: users file their own, cannot read others', cannot set staff fields
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'alice', true);
insert into public.feedback (user_id, kind, message) values (auth.uid(), 'technical_issue', 'The calendar does not load on my phone');
do $$ begin
  begin
    insert into public.feedback (user_id, kind, message, staff_notes) values (auth.uid(), 'feedback', 'hello there', 'x');
    raise exception 'FAIL: user wrote staff notes';
  exception when insufficient_privilege then null; end;
end $$;
commit;
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '66666666-6666-6666-6666-666666666666', true);
do $$ begin assert (select count(*) from public.feedback) = 0, 'other user sees feedback'; end $$;
commit;
\echo 'feedback: OK'
