-- Mauqa — 0002: users, roles, profile and credentials

create table public.institutions (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  short_name text,
  city text,
  province text,
  institution_type text not null default 'university'
    check (institution_type in ('university', 'college', 'school', 'institute', 'other')),
  hec_recognized boolean,
  website text check (website is null or website ~* '^https?://'),
  is_demo boolean not null default false,
  created_at timestamptz not null default now(),
  unique (name)
);
create index institutions_name_trgm on public.institutions using gin (name gin_trgm_ops);

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text check (char_length(full_name) <= 120),
  avatar_path text,
  email text,
  phone text check (phone is null or phone ~ '^\+?[0-9]{10,15}$'),
  date_of_birth date check (date_of_birth is null or date_of_birth > date '1900-01-01'),
  gender text check (gender is null or gender in ('female', 'male', 'transgender', 'prefer_not_to_say')),
  -- CNIC is optional; stored only if the user chooses. Format 12345-1234567-1.
  cnic text check (cnic is null or cnic ~ '^[0-9]{5}-[0-9]{7}-[0-9]$'),
  nationality text default 'Pakistani',
  province text check (province is null or province in (
    'Punjab', 'Sindh', 'Khyber Pakhtunkhwa', 'Balochistan', 'Islamabad Capital Territory',
    'Gilgit-Baltistan', 'Azad Jammu and Kashmir')),
  city text,
  address text,
  user_category public.user_category,
  employment_status text check (employment_status is null or employment_status in (
    'student', 'unemployed', 'employed_full_time', 'employed_part_time', 'self_employed', 'freelancing')),
  languages text[] not null default '{}',
  -- Optional, sensitive. Only used when the user opts in for eligibility checks.
  household_income_monthly_pkr integer check (household_income_monthly_pkr is null or household_income_monthly_pkr >= 0),
  household_income_range text check (household_income_range is null or household_income_range in (
    'below_25k', '25k_50k', '50k_100k', '100k_200k', 'above_200k')),
  has_disability boolean,
  share_sensitive_for_eligibility boolean not null default false,
  preferred_language text not null default 'en' check (preferred_language in ('en', 'ur')),
  recommendation_prefs jsonb not null default '{}'::jsonb,
  privacy_settings jsonb not null default '{"show_in_mentor_directory": false}'::jsonb,
  terms_accepted_at timestamptz,
  privacy_accepted_at timestamptz,
  is_suspended boolean not null default false,
  profile_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.user_roles (
  user_id uuid not null references auth.users (id) on delete cascade,
  role public.app_role not null,
  granted_by uuid references auth.users (id) on delete set null,
  granted_at timestamptz not null default now(),
  primary key (user_id, role)
);

create table public.education_records (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  level public.education_level not null,
  institution_id uuid references public.institutions (id) on delete set null,
  institution_name text,
  department text,
  degree_program text,
  field_of_study text,
  current_semester smallint check (current_semester is null or current_semester between 1 and 16),
  enrollment_status text not null default 'completed'
    check (enrollment_status in ('enrolled', 'completed', 'awaiting_result', 'discontinued')),
  start_year smallint check (start_year is null or start_year between 1950 and 2100),
  graduation_year smallint check (graduation_year is null or graduation_year between 1950 and 2100),
  score_type text check (score_type is null or score_type in ('cgpa', 'percentage', 'grade')),
  score_value numeric(6, 2),
  score_max numeric(6, 2),
  is_current boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (score_value is null or score_max is null or score_value <= score_max),
  check (score_type <> 'cgpa' or score_value is null or score_value between 0 and 5)
);
create index education_records_user on public.education_records (user_id);

create table public.user_skills (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  skill text not null check (char_length(skill) between 1 and 60),
  proficiency text check (proficiency is null or proficiency in ('beginner', 'intermediate', 'advanced', 'expert')),
  created_at timestamptz not null default now()
);
create unique index user_skills_unique on public.user_skills (user_id, lower(skill));

create table public.user_interests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  interest text not null check (char_length(interest) between 1 and 60),
  created_at timestamptz not null default now()
);
create unique index user_interests_unique on public.user_interests (user_id, lower(interest));

create table public.user_experiences (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  kind text not null check (kind in ('work', 'internship', 'volunteer')),
  title text not null,
  organization text,
  start_date date not null,
  end_date date,
  is_current boolean not null default false,
  description text,
  created_at timestamptz not null default now(),
  check (end_date is null or end_date >= start_date)
);
create index user_experiences_user on public.user_experiences (user_id);

create table public.user_certifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  name text not null,
  issuer text,
  issued_on date,
  expires_on date,
  credential_url text check (credential_url is null or credential_url ~* '^https?://'),
  created_at timestamptz not null default now()
);
create index user_certifications_user on public.user_certifications (user_id);

create table public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  token text not null unique,
  platform text not null check (platform in ('android', 'ios', 'web')),
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);
