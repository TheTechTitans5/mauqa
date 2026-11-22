-- Mauqa — 0004: saved, interested, eligibility, applications, documents, notifications, reminders

create table public.saved_opportunities (
  user_id uuid not null references public.profiles (id) on delete cascade,
  opportunity_id uuid not null references public.opportunities (id) on delete cascade,
  folder text,
  reminders_enabled boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (user_id, opportunity_id)
);
create index saved_opportunities_opp on public.saved_opportunities (opportunity_id);

create table public.interested_opportunities (
  user_id uuid not null references public.profiles (id) on delete cascade,
  opportunity_id uuid not null references public.opportunities (id) on delete cascade,
  reminders_enabled boolean not null default true,
  reminder_offsets_days smallint[] not null default '{7,3,1,0}'
    check (reminder_offsets_days <@ '{0,1,2,3,4,5,6,7,10,14,21,30}'::smallint[]),
  note text,
  created_at timestamptz not null default now(),
  primary key (user_id, opportunity_id)
);
create index interested_opportunities_opp on public.interested_opportunities (opportunity_id);

create table public.eligibility_checks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  opportunity_id uuid not null references public.opportunities (id) on delete cascade,
  outcome public.eligibility_outcome not null,
  score numeric(5, 2), -- share of mandatory criteria met, for ranking only
  matched jsonb not null default '[]'::jsonb,
  failed jsonb not null default '[]'::jsonb,
  unconfirmed jsonb not null default '[]'::jsonb,
  missing_requirements jsonb not null default '[]'::jsonb,
  explanation text not null,
  profile_version integer not null,
  rules_version integer not null,
  is_stale boolean not null default false,
  checked_at timestamptz not null default now(),
  unique (user_id, opportunity_id)
);

create table public.applications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  opportunity_id uuid references public.opportunities (id) on delete set null,
  custom_title text,
  custom_organization text,
  custom_url text check (custom_url is null or custom_url ~* '^https?://'),
  status public.application_status not null default 'planning',
  applied_on date,
  deadline timestamptz,
  interview_at timestamptz,
  follow_up_at timestamptz,
  external_reference text,
  notes text,
  -- copy of the opportunity title so the user's history survives if the listing is removed
  title_snapshot text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (opportunity_id is not null or custom_title is not null or title_snapshot is not null)
);
create index applications_user on public.applications (user_id, updated_at desc);
create unique index applications_one_per_opp on public.applications (user_id, opportunity_id) where opportunity_id is not null;

create table public.application_status_history (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references public.applications (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  from_status public.application_status,
  to_status public.application_status not null,
  note text,
  changed_at timestamptz not null default now()
);
create index application_status_history_app on public.application_status_history (application_id, changed_at);

create table public.user_documents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  category public.document_category not null,
  title text not null check (char_length(title) between 1 and 120),
  storage_path text not null unique,
  mime_type text not null check (mime_type in ('application/pdf', 'image/jpeg', 'image/png', 'image/webp',
    'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document')),
  size_bytes integer not null check (size_bytes > 0 and size_bytes <= 10485760),
  expires_on date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- the object must live inside the owner's folder
  check (split_part(storage_path, '/', 1) = user_id::text)
);
create index user_documents_user on public.user_documents (user_id, category);

create table public.notification_preferences (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  push_enabled boolean not null default true,
  email_enabled boolean not null default true,
  sms_enabled boolean not null default false,
  whatsapp_enabled boolean not null default false,
  new_matches boolean not null default true,
  deadline_reminders boolean not null default true,
  closing_soon boolean not null default true,
  deadline_changes boolean not null default true,
  eligibility_updates boolean not null default true,
  application_reminders boolean not null default true,
  verification_updates boolean not null default true,
  announcements boolean not null default true,
  default_reminder_offsets smallint[] not null default '{7,3,1,0}',
  reminder_hour_local smallint not null default 9 check (reminder_hour_local between 0 and 23),
  quiet_hours_start smallint check (quiet_hours_start between 0 and 23),
  quiet_hours_end smallint check (quiet_hours_end between 0 and 23),
  updated_at timestamptz not null default now()
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  type text not null check (type in ('new_opportunity', 'matching_opportunity', 'interested_deadline',
    'saved_deadline', 'closing_soon', 'eligibility_update', 'application_reminder', 'interview_reminder',
    'verification_update', 'deadline_changed', 'opportunity_closed', 'announcement', 'document_expiry', 'system')),
  title text not null,
  body text not null,
  opportunity_id uuid references public.opportunities (id) on delete cascade,
  application_id uuid references public.applications (id) on delete cascade,
  data jsonb not null default '{}'::jsonb,
  dedupe_key text,
  is_read boolean not null default false,
  read_at timestamptz,
  push_status text not null default 'pending' check (push_status in ('pending', 'sent', 'skipped', 'failed')),
  email_status text not null default 'pending' check (email_status in ('pending', 'sent', 'skipped', 'failed')),
  delivery_attempts smallint not null default 0,
  created_at timestamptz not null default now()
);
create unique index notifications_dedupe on public.notifications (user_id, dedupe_key) where dedupe_key is not null;
create index notifications_user on public.notifications (user_id, created_at desc);
create index notifications_delivery on public.notifications (push_status, email_status) where push_status = 'pending' or email_status = 'pending';

create table public.reminders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  opportunity_id uuid references public.opportunities (id) on delete cascade,
  application_id uuid references public.applications (id) on delete cascade,
  document_id uuid references public.user_documents (id) on delete cascade,
  kind text not null check (kind in ('deadline_auto', 'custom', 'interview', 'follow_up', 'document_expiry')),
  origin text not null check (origin in ('interested', 'saved', 'application', 'document', 'manual')),
  offset_days smallint,
  deadline_snapshot timestamptz,
  remind_at timestamptz not null,
  title text not null,
  body text,
  status text not null default 'pending' check (status in ('pending', 'sent', 'cancelled')),
  sent_at timestamptz,
  created_at timestamptz not null default now()
);
create index reminders_due on public.reminders (remind_at) where status = 'pending';
create index reminders_user on public.reminders (user_id, remind_at);
-- Never schedule the same automatic reminder twice for the same deadline
create unique index reminders_auto_unique on public.reminders (user_id, opportunity_id, origin, offset_days, deadline_snapshot)
  where kind = 'deadline_auto' and status <> 'cancelled';
create unique index reminders_app_unique on public.reminders (application_id, kind, remind_at)
  where kind in ('interview', 'follow_up');

create table public.search_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  query text not null check (char_length(query) <= 200),
  filters jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index search_history_user on public.search_history (user_id, created_at desc);

create table public.opportunity_views (
  id bigint generated always as identity primary key,
  opportunity_id uuid not null references public.opportunities (id) on delete cascade,
  user_id uuid references public.profiles (id) on delete set null,
  viewed_at timestamptz not null default now()
);
create index opportunity_views_recent on public.opportunity_views (viewed_at desc, opportunity_id);

create table public.comparisons (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  name text not null default 'My comparison',
  opportunity_ids uuid[] not null check (cardinality(opportunity_ids) between 2 and 4),
  created_at timestamptz not null default now()
);

create table public.cv_documents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  title text not null default 'My CV',
  template text not null default 'modern' check (template in ('modern', 'classic', 'compact')),
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.cover_letters (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  opportunity_id uuid references public.opportunities (id) on delete set null,
  title text not null,
  template text not null default 'formal',
  body text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
