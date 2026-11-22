-- Mauqa — 0005: reports, corrections, community content, guides, audit

create table public.opportunity_reports (
  id uuid primary key default gen_random_uuid(),
  opportunity_id uuid references public.opportunities (id) on delete cascade,
  organization_id uuid references public.organizations (id) on delete cascade,
  reporter_id uuid references public.profiles (id) on delete set null,
  reason text not null check (reason in ('suspected_scam', 'fee_requested', 'payment_request', 'broken_link',
    'incorrect_information', 'expired', 'duplicate', 'fake_organization', 'other')),
  details text check (char_length(details) <= 2000),
  evidence_url text check (evidence_url is null or evidence_url ~* '^https?://'),
  status text not null default 'open' check (status in ('open', 'investigating', 'resolved', 'dismissed')),
  resolution text,
  handled_by uuid references auth.users (id) on delete set null,
  handled_at timestamptz,
  created_at timestamptz not null default now(),
  check (opportunity_id is not null or organization_id is not null)
);
create index opportunity_reports_status on public.opportunity_reports (status, created_at);
create unique index opportunity_reports_one_open on public.opportunity_reports (opportunity_id, reporter_id, reason)
  where status in ('open', 'investigating');

create table public.user_corrections (
  id uuid primary key default gen_random_uuid(),
  opportunity_id uuid not null references public.opportunities (id) on delete cascade,
  user_id uuid references public.profiles (id) on delete set null,
  field text not null check (field in ('title', 'deadline', 'eligibility', 'official_application_url', 'source_url',
    'amount', 'documents', 'description', 'other')),
  suggested_value text not null check (char_length(suggested_value) <= 2000),
  evidence_url text check (evidence_url is null or evidence_url ~* '^https?://'),
  status public.moderation_status not null default 'pending',
  reviewed_by uuid references auth.users (id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.opportunity_submissions (
  id uuid primary key default gen_random_uuid(),
  submitted_by uuid references public.profiles (id) on delete set null,
  organization_name text not null,
  title text not null,
  payload jsonb not null default '{}'::jsonb,
  source_url text not null check (source_url ~* '^https?://'),
  status public.moderation_status not null default 'pending',
  created_opportunity_id uuid references public.opportunities (id) on delete set null,
  reviewed_by uuid references auth.users (id) on delete set null,
  review_notes text,
  created_at timestamptz not null default now()
);

create table public.organization_verification_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations (id) on delete cascade,
  requested_by uuid references public.profiles (id) on delete set null,
  organization_name text not null,
  website text not null check (website ~* '^https?://'),
  official_email text not null,
  evidence text,
  status public.moderation_status not null default 'pending',
  reviewed_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.success_stories (
  id uuid primary key default gen_random_uuid(),
  author_id uuid references public.profiles (id) on delete set null,
  author_display_name text not null,
  title text not null check (char_length(title) between 5 and 150),
  body text not null check (char_length(body) between 50 and 8000),
  story_type text not null default 'scholarship' check (story_type in ('scholarship', 'internship', 'job', 'fellowship', 'alumni', 'tip', 'other')),
  institution_name text,
  opportunity_id uuid references public.opportunities (id) on delete set null,
  status public.moderation_status not null default 'pending',
  moderated_by uuid references auth.users (id) on delete set null,
  published_at timestamptz,
  is_demo boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.content_reports (
  id uuid primary key default gen_random_uuid(),
  story_id uuid not null references public.success_stories (id) on delete cascade,
  reporter_id uuid references public.profiles (id) on delete set null,
  reason text not null check (reason in ('inappropriate', 'spam', 'misleading', 'personal_information', 'other')),
  details text,
  status text not null default 'open' check (status in ('open', 'resolved', 'dismissed')),
  created_at timestamptz not null default now()
);

create table public.guides (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9-]+$'),
  category text not null check (category in ('scholarship', 'internship', 'job', 'government_scheme', 'cv', 'interview',
    'aptitude_test', 'entry_test', 'english', 'digital_skills', 'free_courses', 'certification', 'tips', 'faq',
    'personal_statement', 'statement_of_purpose')),
  title_en text not null,
  title_ur text,
  body_en text not null,
  body_ur text,
  external_links jsonb not null default '[]'::jsonb,
  is_published boolean not null default false,
  sort_order integer not null default 100,
  updated_by uuid references auth.users (id) on delete set null,
  updated_at timestamptz not null default now()
);

create table public.interview_questions (
  id uuid primary key default gen_random_uuid(),
  category text not null check (category in ('general', 'scholarship', 'internship', 'technical', 'behavioural')),
  question_en text not null,
  question_ur text,
  guidance_en text,
  guidance_ur text,
  is_published boolean not null default true
);

create table public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  institution_id uuid references public.institutions (id) on delete cascade,
  audience text not null default 'all' check (audience in ('all', 'students', 'institution')),
  is_published boolean not null default false,
  published_at timestamptz,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.mentors (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles (id) on delete cascade,
  display_name text not null,
  expertise text[] not null default '{}',
  institution_name text,
  bio text,
  contact_url text check (contact_url is null or contact_url ~* '^https://'),
  status public.moderation_status not null default 'pending',
  created_at timestamptz not null default now()
);

create table public.university_ambassadors (
  user_id uuid not null references public.profiles (id) on delete cascade,
  institution_id uuid not null references public.institutions (id) on delete cascade,
  status public.moderation_status not null default 'pending',
  motivation text,
  created_at timestamptz not null default now(),
  primary key (user_id, institution_id)
);

create table public.audit_logs (
  id bigint generated always as identity primary key,
  actor_id uuid,
  action text not null,
  table_name text not null,
  record_id text,
  old_data jsonb,
  new_data jsonb,
  created_at timestamptz not null default now()
);
create index audit_logs_table on public.audit_logs (table_name, created_at desc);
create index audit_logs_actor on public.audit_logs (actor_id, created_at desc);
