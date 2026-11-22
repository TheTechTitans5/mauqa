-- Mauqa — 0003: organizations, data sources, opportunities, eligibility rules

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique check (slug ~ '^[a-z0-9-]+$'),
  org_type public.org_type not null default 'other',
  description text,
  website text check (website is null or website ~* '^https?://'),
  official_domains text[] not null default '{}', -- used by link-safety checks, e.g. {hec.gov.pk}
  logo_url text,
  contact_email text,
  contact_phone text,
  city text,
  province text,
  is_verified boolean not null default false,
  verified_at timestamptz,
  verified_by uuid references auth.users (id) on delete set null,
  is_demo boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.data_sources (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations (id) on delete set null,
  name text not null,
  source_type public.source_type not null,
  base_url text check (base_url is null or base_url ~* '^https://'),
  -- Non-secret connector configuration (endpoints, pagination, field mapping, CSS selectors, feed URL)
  config jsonb not null default '{}'::jsonb,
  auth_method text not null default 'none' check (auth_method in ('none', 'api_key_header', 'bearer_token', 'basic', 'oauth2_client_credentials')),
  -- Name of the backend environment variable / secret that holds the credential. NEVER the secret itself.
  secret_ref text check (secret_ref is null or secret_ref ~ '^[A-Z][A-Z0-9_]{2,63}$'),
  integration_status public.integration_status not null default 'awaiting_configuration',
  authorization_notes text, -- what permission/credential is required and from whom
  terms_reviewed_at timestamptz,
  robots_txt_checked_at timestamptz,
  sync_interval_minutes integer not null default 1440 check (sync_interval_minutes between 15 and 43200),
  rate_limit_per_minute integer not null default 10 check (rate_limit_per_minute between 1 and 600),
  is_enabled boolean not null default false,
  last_sync_at timestamptz,
  last_success_at timestamptz,
  next_sync_at timestamptz,
  consecutive_failures integer not null default 0,
  is_demo boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.organization_sources (
  organization_id uuid not null references public.organizations (id) on delete cascade,
  data_source_id uuid not null references public.data_sources (id) on delete cascade,
  primary key (organization_id, data_source_id)
);

create table public.opportunity_categories (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9_]+$'),
  name_en text not null,
  name_ur text not null,
  icon text not null default 'star',
  color_hex text not null default '#16B8A6' check (color_hex ~ '^#[0-9A-Fa-f]{6}$'),
  sort_order integer not null default 100
);

create table public.opportunities (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 3 and 250),
  title_ur text,
  organization_id uuid not null references public.organizations (id) on delete restrict,
  category_id uuid not null references public.opportunity_categories (id) on delete restrict,
  summary text,
  description text,
  benefits text,
  funding_type public.funding_type not null default 'not_applicable',
  amount_text text,
  amount_min_pkr bigint check (amount_min_pkr is null or amount_min_pkr >= 0),
  amount_max_pkr bigint check (amount_max_pkr is null or amount_max_pkr >= 0),
  work_mode public.work_mode not null default 'not_applicable',
  location_text text,
  is_nationwide boolean not null default true,
  provinces text[] not null default '{}',
  cities text[] not null default '{}',
  is_international boolean not null default false,
  eligibility_summary text,
  education_levels public.education_level[] not null default '{}',
  fields_of_study text[] not null default '{}',
  required_skills text[] not null default '{}',
  min_age smallint check (min_age is null or min_age between 0 and 120),
  max_age smallint check (max_age is null or max_age between 0 and 120),
  gender_eligibility text not null default 'any' check (gender_eligibility in ('any', 'female', 'male', 'transgender', 'female_transgender')),
  min_experience_months integer check (min_experience_months is null or min_experience_months >= 0),
  application_procedure text,
  selection_procedure text,
  important_instructions text,
  duration_text text,
  opening_date timestamptz,
  deadline timestamptz,
  status public.opportunity_status not null default 'open',
  tags text[] not null default '{}',
  has_application_fee boolean not null default false,
  application_fee_pkr integer check (application_fee_pkr is null or application_fee_pkr >= 0),
  -- Provenance and verification
  source_id uuid references public.data_sources (id) on delete set null,
  source_type public.source_type not null default 'manual',
  source_url text check (source_url is null or source_url ~* '^https?://'),
  official_application_url text check (official_application_url is null or official_application_url ~* '^https?://'),
  last_checked_at timestamptz,
  last_verified_at timestamptz,
  verified_by uuid references auth.users (id) on delete set null,
  verification_status public.verification_status not null default 'pending_verification',
  approval_status public.approval_status not null default 'draft',
  is_published boolean not null default false,
  is_featured boolean not null default false,
  is_reported boolean not null default false,
  is_demo boolean not null default false,
  data_version integer not null default 1,
  content_hash text,
  recurrence_key text, -- links yearly cycles of the same programme for history/forecasting
  view_count integer not null default 0,
  save_count integer not null default 0,
  interest_count integer not null default 0,
  search_tsv tsvector,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (max_age is null or min_age is null or max_age >= min_age),
  check (amount_max_pkr is null or amount_min_pkr is null or amount_max_pkr >= amount_min_pkr),
  check (deadline is null or opening_date is null or deadline >= opening_date),
  -- An opportunity can only be shown as verified if it links to its official source
  check (verification_status <> 'verified' or source_url is not null),
  -- Demo records can never be marked verified
  check (not (is_demo and verification_status = 'verified'))
);

create index opportunities_search on public.opportunities using gin (search_tsv);
create index opportunities_title_trgm on public.opportunities using gin (title gin_trgm_ops);
create index opportunities_deadline on public.opportunities (deadline) where is_published;
create index opportunities_category on public.opportunities (category_id);
create index opportunities_org on public.opportunities (organization_id);
create index opportunities_provinces on public.opportunities using gin (provinces);
create index opportunities_levels on public.opportunities using gin (education_levels);
create index opportunities_recurrence on public.opportunities (recurrence_key) where recurrence_key is not null;
create unique index opportunities_content_hash on public.opportunities (content_hash) where content_hash is not null;

-- Rule tree. Root nodes have parent_id null. Groups combine children with AND/OR.
create table public.opportunity_eligibility_rules (
  id uuid primary key default gen_random_uuid(),
  opportunity_id uuid not null references public.opportunities (id) on delete cascade,
  parent_id uuid references public.opportunity_eligibility_rules (id) on delete cascade,
  node_type text not null check (node_type in ('group', 'criterion')),
  group_operator text check (group_operator in ('and', 'or')),
  criterion_type text check (criterion_type in (
    'age_range', 'education_level_in', 'cgpa_min', 'percentage_min', 'semester_range',
    'enrollment_status_in', 'graduation_year_range', 'institution_whitelist', 'institution_blacklist',
    'department_whitelist', 'department_blacklist', 'field_of_study_in', 'gender_in', 'province_in',
    'city_in', 'nationality_in', 'income_max', 'experience_min_months', 'skills_required',
    'documents_required', 'user_category_in', 'disability_required', 'employment_status_in', 'custom')),
  params jsonb not null default '{}'::jsonb,
  label text,
  is_mandatory boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  check ((node_type = 'group' and group_operator is not null and criterion_type is null)
      or (node_type = 'criterion' and criterion_type is not null and group_operator is null))
);
create index eligibility_rules_opp on public.opportunity_eligibility_rules (opportunity_id);

create table public.opportunity_documents (
  id uuid primary key default gen_random_uuid(),
  opportunity_id uuid not null references public.opportunities (id) on delete cascade,
  category public.document_category not null,
  label text not null,
  is_mandatory boolean not null default true,
  notes text,
  unique (opportunity_id, category, label)
);

-- Ingestion staging: everything a connector extracts lands here first and waits for human review.
create table public.source_items (
  id uuid primary key default gen_random_uuid(),
  source_id uuid not null references public.data_sources (id) on delete cascade,
  external_id text not null,
  item_url text,
  raw jsonb not null default '{}'::jsonb,
  extracted jsonb not null default '{}'::jsonb,
  content_hash text not null,
  opportunity_id uuid references public.opportunities (id) on delete set null,
  review_status text not null default 'pending' check (review_status in ('pending', 'approved', 'rejected', 'duplicate', 'superseded')),
  duplicate_of uuid references public.opportunities (id) on delete set null,
  duplicate_score numeric(4, 3),
  detected_changes jsonb,
  validation_issues jsonb not null default '[]'::jsonb,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  unique (source_id, external_id, content_hash)
);
create index source_items_review on public.source_items (review_status, first_seen_at);

create table public.source_sync_logs (
  id uuid primary key default gen_random_uuid(),
  source_id uuid not null references public.data_sources (id) on delete cascade,
  triggered_by text not null default 'schedule' check (triggered_by in ('schedule', 'manual')),
  triggered_by_user uuid references auth.users (id) on delete set null,
  status public.sync_status not null default 'running',
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  items_found integer not null default 0,
  items_new integer not null default 0,
  items_changed integer not null default 0,
  items_unchanged integer not null default 0,
  items_duplicate integer not null default 0,
  items_invalid integer not null default 0,
  attempt integer not null default 1,
  error_message text,
  details jsonb not null default '{}'::jsonb
);
create index source_sync_logs_source on public.source_sync_logs (source_id, started_at desc);

create table public.opportunity_versions (
  id uuid primary key default gen_random_uuid(),
  opportunity_id uuid not null references public.opportunities (id) on delete cascade,
  version integer not null,
  snapshot jsonb not null,
  changed_fields text[] not null default '{}',
  changed_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  unique (opportunity_id, version)
);

create table public.verification_reviews (
  id uuid primary key default gen_random_uuid(),
  opportunity_id uuid references public.opportunities (id) on delete cascade,
  source_item_id uuid references public.source_items (id) on delete cascade,
  reviewer_id uuid not null references auth.users (id) on delete set null,
  decision text not null check (decision in ('approved', 'rejected', 'needs_changes')),
  checklist jsonb not null default '{}'::jsonb, -- e.g. {"source_url_official":true,"deadline_confirmed":true}
  notes text,
  created_at timestamptz not null default now(),
  check (opportunity_id is not null or source_item_id is not null)
);

-- Historical cycles for forecasting
create table public.opportunity_cycles (
  id uuid primary key default gen_random_uuid(),
  recurrence_key text not null,
  cycle_year smallint not null,
  opened_on date,
  deadline_on date,
  opportunity_id uuid references public.opportunities (id) on delete set null,
  funding_text text,
  eligibility_snapshot jsonb,
  notes text,
  unique (recurrence_key, cycle_year)
);
