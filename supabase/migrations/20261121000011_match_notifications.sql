-- Mauqa — 0011: "new matching opportunity" and "eligibility update" notifications

-- When a (non-demo) listing is first published, notify users whose interests include its category or tags.
create or replace function public.tg_notify_new_match() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_slug text;
begin
  if not (new.is_published and new.approval_status = 'approved') or new.is_demo then return new; end if;
  if tg_op = 'UPDATE' and old.is_published and old.approval_status = 'approved' then return new; end if;
  select slug into v_slug from opportunity_categories where id = new.category_id;
  insert into notifications (user_id, type, title, body, opportunity_id, dedupe_key)
  select distinct i.user_id, 'matching_opportunity', 'New opportunity for you', new.title, new.id, 'match:' || new.id
    from user_interests i
    join notification_preferences p on p.user_id = i.user_id and p.new_matches
   where lower(i.interest) = v_slug or lower(i.interest) = any (select lower(t) from unnest(new.tags) t)
  on conflict do nothing;
  return new;
end $$;
create trigger notify_new_match after insert or update of is_published, approval_status on public.opportunities
  for each row execute function public.tg_notify_new_match();

-- When eligibility rules change, tell people following the listing to re-check (at most once per day per listing).
create or replace function public.tg_notify_rules_changed() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_opp uuid := coalesce(new.opportunity_id, old.opportunity_id); v_title text;
begin
  select title into v_title from opportunities where id = v_opp and is_published;
  if v_title is null then return null; end if;
  insert into notifications (user_id, type, title, body, opportunity_id, dedupe_key)
  select i.user_id, 'eligibility_update', 'Eligibility criteria updated',
         'The requirements for ' || v_title || ' changed. Check your eligibility again.', v_opp,
         'rules:' || v_opp || ':' || to_char(now() at time zone 'Asia/Karachi', 'YYYYMMDD')
    from interested_opportunities i
    join notification_preferences p on p.user_id = i.user_id and p.eligibility_updates
   where i.opportunity_id = v_opp
  on conflict do nothing;
  return null;
end $$;
create trigger notify_rules_changed after insert or update or delete on public.opportunity_eligibility_rules
  for each row execute function public.tg_notify_rules_changed();
