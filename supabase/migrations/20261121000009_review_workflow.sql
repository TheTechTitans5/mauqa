-- Mauqa — 0009: human review workflow for ingested items

-- Turns a reviewed source item into a draft opportunity (still pending verification — never auto-verified).
create or replace function public.create_opportunity_from_source_item(p_item uuid, p_category_slug text, p_official_application_url text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare it record; v_org uuid; v_cat uuid; v_id uuid; x jsonb;
begin
  if not public.can_verify() then raise exception 'forbidden' using errcode = '42501'; end if;
  select si.*, ds.organization_id as org_id, ds.source_type as stype into it
    from source_items si join data_sources ds on ds.id = si.source_id where si.id = p_item for update of si;
  if not found then raise exception 'source item not found' using errcode = 'P0002'; end if;
  if it.review_status not in ('pending', 'duplicate') then raise exception 'item already reviewed' using errcode = '22023'; end if;
  if it.org_id is null then raise exception 'source has no organization' using errcode = '22023'; end if;
  select id into v_cat from opportunity_categories where slug = p_category_slug;
  if v_cat is null then raise exception 'unknown category %', p_category_slug using errcode = '22023'; end if;
  x := it.extracted;
  insert into opportunities (title, organization_id, category_id, summary, description, eligibility_summary, amount_text,
      amount_min_pkr, location_text, deadline, opening_date, source_id, source_type, source_url, official_application_url,
      last_checked_at, verification_status, approval_status, is_published, content_hash, has_application_fee)
  values (left(coalesce(nullif(x ->> 'title', ''), 'Untitled listing'), 250), it.org_id, v_cat, x ->> 'summary', x ->> 'description',
      x ->> 'eligibility_summary', x ->> 'amount_text', nullif(x ->> 'amount_min_pkr', '')::bigint, x ->> 'location_text',
      nullif(x ->> 'deadline', '')::timestamptz, nullif(x ->> 'opening_date', '')::timestamptz, it.source_id, it.stype,
      coalesce(x ->> 'source_url', it.item_url), coalesce(p_official_application_url, x ->> 'official_application_url'),
      now(), 'pending_verification', 'pending_review', false, it.content_hash, coalesce((x ->> 'has_application_fee')::boolean, false))
  returning id into v_id;
  update source_items set review_status = 'approved', opportunity_id = v_id where id = p_item;
  insert into verification_reviews (source_item_id, opportunity_id, reviewer_id, decision, notes)
  values (p_item, v_id, auth.uid(), 'needs_changes', 'Draft created from ingested item; awaiting full verification.');
  return v_id;
end $$;

-- Applies detected changes from a newer source item to the linked opportunity (deadline changes notify followers).
create or replace function public.apply_source_item_changes(p_item uuid, p_fields text[] default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare it record; x jsonb; f text;
  allowed text[] := array['title', 'summary', 'description', 'eligibility_summary', 'amount_text', 'deadline', 'opening_date',
                          'official_application_url', 'source_url', 'location_text'];
begin
  if not public.can_verify() then raise exception 'forbidden' using errcode = '42501'; end if;
  select * into it from source_items where id = p_item for update;
  if not found or it.opportunity_id is null then raise exception 'item is not linked to an opportunity' using errcode = '22023'; end if;
  if it.review_status <> 'pending' then raise exception 'item already reviewed' using errcode = '22023'; end if;
  x := it.extracted;
  foreach f in array coalesce(p_fields, array(select jsonb_object_keys(coalesce(it.detected_changes, '{}'::jsonb)))) loop
    if f = any(allowed) and x ? f then
      execute format('update opportunities set %I = $1::%s, last_checked_at = now() where id = $2', f,
                     case when f in ('deadline', 'opening_date') then 'timestamptz' else 'text' end)
        using x ->> f, it.opportunity_id;
    end if;
  end loop;
  update source_items set review_status = 'approved' where id = p_item;
  insert into verification_reviews (source_item_id, opportunity_id, reviewer_id, decision, checklist, notes)
  values (p_item, it.opportunity_id, auth.uid(), 'approved', jsonb_build_object('applied_fields', to_jsonb(p_fields)), 'Applied source changes');
  return it.opportunity_id;
end $$;

create or replace function public.reject_source_item(p_item uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.can_verify() then raise exception 'forbidden' using errcode = '42501'; end if;
  update source_items set review_status = 'rejected' where id = p_item and review_status in ('pending', 'duplicate');
  if not found then raise exception 'item not found or already reviewed' using errcode = '22023'; end if;
  insert into verification_reviews (source_item_id, reviewer_id, decision, notes) values (p_item, auth.uid(), 'rejected', p_reason);
end $$;

-- Converts an approved user/organisation submission into a draft listing for verification.
create or replace function public.accept_opportunity_submission(p_submission uuid, p_organization uuid, p_category_slug text)
returns uuid language plpgsql security definer set search_path = public as $$
declare s record; v_id uuid;
begin
  if not (public.can_verify() or public.can_manage_content()) then raise exception 'forbidden' using errcode = '42501'; end if;
  select * into s from opportunity_submissions where id = p_submission and status = 'pending' for update;
  if not found then raise exception 'submission not found or already handled' using errcode = '22023'; end if;
  insert into opportunities (title, organization_id, category_id, description, source_url, official_application_url, deadline,
                             verification_status, approval_status, is_published)
  values (s.title, p_organization, (select id from opportunity_categories where slug = p_category_slug),
          s.payload ->> 'description', s.source_url, s.payload ->> 'official_application_url',
          nullif(s.payload ->> 'deadline', '')::timestamptz, 'pending_verification', 'pending_review', false)
  returning id into v_id;
  update opportunity_submissions set status = 'approved', created_opportunity_id = v_id, reviewed_by = auth.uid() where id = p_submission;
  return v_id;
end $$;
