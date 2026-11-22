-- Mauqa — 0010: feedback, support requests and technical issue reports

create table public.feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles (id) on delete set null,
  kind text not null check (kind in ('feedback', 'technical_issue', 'support')),
  message text not null check (char_length(message) between 5 and 4000),
  app_version text,
  platform text,
  status text not null default 'open' check (status in ('open', 'in_progress', 'closed')),
  staff_notes text,
  created_at timestamptz not null default now()
);
create index feedback_status on public.feedback (status, created_at desc);

alter table public.feedback enable row level security;
create policy feedback_insert on public.feedback for insert to authenticated
  with check (user_id = auth.uid() and status = 'open' and staff_notes is null);
create policy feedback_select on public.feedback for select to authenticated using (user_id = auth.uid() or public.is_staff());
create policy feedback_update on public.feedback for update to authenticated using (public.is_staff()) with check (public.is_staff());
