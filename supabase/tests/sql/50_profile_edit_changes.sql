-- Migration 0013: grouped skills (user_skills.category) and profile completion with required gender
\set ON_ERROR_STOP 1
\set carol 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'

insert into auth.users (id, email, raw_user_meta_data) values (:'carol', 'carol@example.com', '{"full_name":"Carol Test"}');

-- ---------------------------------------------------------------- skills: groups, RLS, flat list unchanged
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'carol', true);
insert into public.user_skills (user_id, skill, category) values
  (auth.uid(), 'Python', 'curricular'),
  (auth.uid(), 'Debating', 'co_curricular'),
  (auth.uid(), 'Communication', 'other');
-- a skill saved before 0013 has no group (NULL) and is still valid
insert into public.user_skills (user_id, skill) values (auth.uid(), 'Teaching');
do $$ begin
  assert (select count(*) from public.user_skills where user_id = auth.uid()) = 4, 'own skills not visible';
  assert (select count(*) from public.user_skills where user_id = auth.uid() and category is null) = 1, 'ungrouped skill missing';
end $$;
-- moving a skill to another group is an update of its own row
update public.user_skills set category = 'curricular' where user_id = auth.uid() and skill = 'Teaching';
do $$ begin
  assert (select category from public.user_skills where user_id = auth.uid() and skill = 'Teaching') = 'curricular', 'move failed';
end $$;
-- the same skill cannot be added twice, whatever the group or letter case (flat list stays de-duplicated)
do $$ begin
  begin
    insert into public.user_skills (user_id, skill, category) values (auth.uid(), 'python', 'other');
    assert false, 'duplicate skill accepted';
  exception when unique_violation then null;
  end;
end $$;
-- unknown group names are rejected
do $$ begin
  begin
    insert into public.user_skills (user_id, skill, category) values (auth.uid(), 'Chess', 'hobbies');
    assert false, 'invalid category accepted';
  exception when check_violation then null;
  end;
end $$;
commit;

-- another user cannot see or regroup Carol's skills
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
update public.user_skills set category = 'other' where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
do $$ begin
  assert not exists (select 1 from public.user_skills where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), 'other user sees skills';
end $$;
commit;
do $$ begin
  assert (select category from public.user_skills where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and skill = 'Python') = 'curricular',
    'other user changed a skill group';
end $$;

-- ---------------------------------------------------------------- profile completion
-- fill every field the Edit Profile screen offers (plus photo and a CV document)
update public.profiles set avatar_path = :'carol' || '/avatar.jpg', date_of_birth = '2003-05-01', province = 'Punjab',
       city = 'Lahore', user_category = 'student', gender = 'female', address = null
 where id = :'carol';
insert into public.education_records (user_id, level, institution_name, score_type, score_value, score_max, is_current)
values (:'carol', 'bachelor', 'Test University', 'cgpa', 3.5, 4, true);
insert into public.user_experiences (user_id, kind, title, start_date) values (:'carol', 'internship', 'Intern', '2025-06-01');
insert into public.user_documents (user_id, category, title, storage_path, mime_type, size_bytes)
values (:'carol', 'cv', 'CV', :'carol' || '/cv.pdf', 'application/pdf', 1000);

begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'carol', true);
do $$ begin
  -- no interests and no address: a fully filled Edit Profile still reaches 100 %
  assert not exists (select 1 from public.user_interests where user_id = auth.uid()), 'test expects no interests';
  assert public.profile_completion(auth.uid()) = 100,
    format('full profile should be 100%%, got %s', public.profile_completion(auth.uid()));
end $$;
rollback;

-- gender counts 5 points; "prefer not to say" (old value) and empty do not
update public.profiles set gender = 'prefer_not_to_say' where id = :'carol';
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'carol', true);
do $$ begin
  assert public.profile_completion(auth.uid()) = 95, format('prefer_not_to_say should give 95, got %s', public.profile_completion(auth.uid()));
end $$;
rollback;
update public.profiles set gender = null where id = :'carol';
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'carol', true);
do $$ begin
  assert public.profile_completion(auth.uid()) = 95, format('missing gender should give 95, got %s', public.profile_completion(auth.uid()));
end $$;
rollback;

-- interests (now chosen on Home) no longer change the percentage
update public.profiles set gender = 'male' where id = :'carol';
insert into public.user_interests (user_id, interest) values (:'carol', 'scholarships');
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'carol', true);
do $$ begin
  assert public.profile_completion(auth.uid()) = 100, format('interests must not push past 100, got %s', public.profile_completion(auth.uid()));
end $$;
rollback;

-- other users still cannot read Carol's completion
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
do $$ begin
  assert public.profile_completion('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa') is null, 'completion leaked to another user';
end $$;
rollback;

select 'profile_edit_changes: OK';
