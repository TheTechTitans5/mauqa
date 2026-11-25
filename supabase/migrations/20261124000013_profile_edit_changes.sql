-- Mauqa — 0013: Edit Profile changes (grouped skills, required gender, completion %)
--
-- Additive only: no columns are dropped and no data is deleted.
--   * user_skills.category: which group a skill belongs to in Edit Profile
--     ('curricular', 'co_curricular', 'other'). NULL = not grouped yet; the app shows those under "Other".
--     Each skill is still one row in user_skills, so everything that reads skills (recommendations,
--     eligibility, CV builder, data export) keeps working unchanged. RLS policies and grants on
--     user_skills already cover the new column.
--   * profile_completion(): Interests moved from Edit Profile to the Home page and gender is now required,
--     so the 5 points for interests now go to gender. Same signature; a fully filled profile is still 100 %.
--     The address column was never counted. profiles.address and user_interests are kept unchanged.

alter table public.user_skills
  add column if not exists category text;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'user_skills_category_check') then
    alter table public.user_skills
      add constraint user_skills_category_check
      check (category is null or category in ('curricular', 'co_curricular', 'other'));
  end if;
end $$;

comment on column public.user_skills.category is
  'Edit Profile skill group: curricular | co_curricular | other. NULL = not grouped yet (shown under Other).';

create or replace function public.profile_completion(p_user uuid) returns integer
language sql stable security definer set search_path = public as $$
  select (
      (case when p.full_name is not null then 10 else 0 end)
    + (case when p.avatar_path is not null then 5 else 0 end)
    + (case when p.phone is not null or p.email is not null then 5 else 0 end)
    + (case when p.date_of_birth is not null then 10 else 0 end)
    + (case when p.gender in ('female', 'male', 'transgender') then 5 else 0 end)
    + (case when p.province is not null then 5 else 0 end)
    + (case when p.city is not null then 5 else 0 end)
    + (case when p.user_category is not null then 10 else 0 end)
    + (case when exists (select 1 from education_records e where e.user_id = p.id) then 15 else 0 end)
    + (case when exists (select 1 from education_records e where e.user_id = p.id and e.score_value is not null) then 10 else 0 end)
    + (case when (select count(*) from user_skills s where s.user_id = p.id) >= 3 then 10 else 0 end)
    + (case when exists (select 1 from user_experiences x where x.user_id = p.id) then 5 else 0 end)
    + (case when exists (select 1 from user_documents d where d.user_id = p.id and d.category = 'cv') then 5 else 0 end)
  )::int
  from profiles p
  where p.id = p_user and (p_user = auth.uid() or public.is_staff() or public.is_system());
$$;
