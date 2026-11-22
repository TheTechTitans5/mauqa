-- New-match and eligibility-update notifications
\set ON_ERROR_STOP 1
insert into auth.users (id, email) values ('99999999-9999-9999-9999-999999999999', 'm@example.com');
insert into public.user_interests (user_id, interest) values ('99999999-9999-9999-9999-999999999999', 'scholarships');

insert into public.opportunities (title, organization_id, category_id, source_url, deadline, approval_status, is_published)
select 'Match test scholarship', (select id from organizations where slug = 'hec'), (select id from opportunity_categories where slug = 'scholarships'),
       'https://www.hec.gov.pk/m', now() + interval '20 days', 'approved', true;
do $$ begin
  assert (select count(*) from public.notifications where user_id = '99999999-9999-9999-9999-999999999999' and type = 'matching_opportunity') = 1,
    'interested user not notified of new match';
end $$;
update public.opportunities set is_published = false where title = 'Match test scholarship';
update public.opportunities set is_published = true where title = 'Match test scholarship';
do $$ begin
  assert (select count(*) from public.notifications where type = 'matching_opportunity' and user_id = '99999999-9999-9999-9999-999999999999') = 1,
    'republishing notified twice';
end $$;
update public.notification_preferences set new_matches = false where user_id = '99999999-9999-9999-9999-999999999999';
insert into public.opportunities (title, organization_id, category_id, source_url, approval_status, is_published)
select 'Second match', (select id from organizations where slug = 'hec'), (select id from opportunity_categories where slug = 'scholarships'),
       'https://www.hec.gov.pk/m2', 'approved', true;
do $$ begin
  assert (select count(*) from public.notifications where type = 'matching_opportunity' and user_id = '99999999-9999-9999-9999-999999999999') = 1,
    'preference new_matches=false ignored';
end $$;

insert into public.interested_opportunities (user_id, opportunity_id)
select '99999999-9999-9999-9999-999999999999', id from public.opportunities where title = 'Match test scholarship';
insert into public.opportunity_eligibility_rules (opportunity_id, node_type, criterion_type, params)
select id, 'criterion', 'cgpa_min', '{"min":3}' from public.opportunities where title = 'Match test scholarship';
insert into public.opportunity_eligibility_rules (opportunity_id, node_type, criterion_type, params)
select id, 'criterion', 'age_range', '{"max":30}' from public.opportunities where title = 'Match test scholarship';
do $$ begin
  assert (select count(*) from public.notifications where type = 'eligibility_update' and user_id = '99999999-9999-9999-9999-999999999999') = 1,
    'eligibility update missing or not deduplicated';
end $$;
\echo '40_match_notifications: OK'
