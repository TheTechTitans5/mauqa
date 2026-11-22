# Mauqa — Pakistan Opportunity Discovery & Matching Platform

**Discover. Qualify. Track. Apply.** Mauqa brings scholarships, internships, jobs, government schemes, grants,
fellowships and training programmes into one app, checks eligibility with deterministic rules, reminds people
before deadlines, and always sends them to the **official** application page. No chatbot, no AI assistant.

| Part | Tech | Folder |
|---|---|---|
| Mobile app (Android-first, iOS-ready) | Flutter 3.24+, Dart 3.5+, Material 3, Riverpod, go_router | `app/` |
| Database, auth, storage, RLS | Supabase (PostgreSQL 15+), 11 migrations | `supabase/migrations/` |
| Backend services | Supabase Edge Functions (TypeScript/Deno) | `supabase/functions/` |
| Admin dashboard | TypeScript web app, no framework/dependencies | `admin/` |
| Optional ingestion worker (PDF/OCR, heavy HTML) | Python 3 (pdfminer, BeautifulSoup) | `workers/` |

## What is in the box

- **Auth**: email + password (verification), Pakistani phone + SMS OTP, forgot/reset/change password, optional Google sign-in, account deletion, consent recording. Roles: user, admin, super_admin, verifier, content_manager.
- **Profile**: personal, category, education (multiple records, institution autocomplete, CGPA/marks), skills, interests, experience, certifications, optional sensitive data (income, disability) used **only** with explicit opt-in; completion %.
- **Home**: greeting, completion ring, quick categories, stats, recommendations *with reasons*, closing soon, featured, trending, scholarships/internships/schemes, new, application progress, weekly activity, notifications preview, announcements.
- **Explore**: server-side full-text + fuzzy search, 20+ filters, 4 sorts, pagination, search history, suggestions.
- **Opportunity detail**: every field in the brief, verification badge, last checked/verified, demo/unverified/reported/fee warnings, official source & organisation profile, forecasts labelled as estimates, Interested / Save / Check eligibility / Compare / Share / Report / Suggest correction / **Apply officially** (confirmation dialog, link-safety check, and *asks* whether you applied — never assumes).
- **Eligibility engine**: AND/OR rule trees, 24 criterion types, three outcomes (Eligible / Probably eligible–unconfirmed / Not eligible) with matched, failed, unconfirmed and missing items. Unknown data ⇒ *unconfirmed*, never "eligible". Results are cached and marked stale when the profile or rules change.
- **Interested vs Saved**: separate lists; Interested schedules 7/3/1/0-day reminders (customisable + custom reminders) at 09:00 PKT; deadline changes reschedule and notify; closures stop reminders; duplicates are impossible at the database level.
- **My Journey**: 10 statuses, timeline/history, notes, interview & follow-up reminders, manual entries.
- **Documents**: private bucket, 2-minute signed URLs, replace/delete, expiry reminders, completeness, per-opportunity checklist.
- **Tools**: CV builder (3 templates, PDF export), cover letters, guides (EN/UR), interview practice, readiness score.
- **Calendar** (month/week/day), **Notification centre** (filters, read/unread, preferences, quiet hours), **Compare** (2–4, saved comparisons), **Community** (moderated stories, mentors, opportunity submissions), **Settings** (language, theme, text size, high contrast, simple mode, low-data, reduce motion, privacy, data export, account deletion, feedback).
- **Data ingestion**: connector framework for authorised APIs, RSS, website monitoring (robots.txt, rate limits, CAPTCHA/login detection), official PDFs (+OCR worker) and manual entry → validation → duplicate/change detection → **human review queue** → verification → publish. Audit log and version history on every change.
- **Admin dashboard**: stats, opportunity CRUD + rule editor + required documents, verification checklist, ingestion review, sources & sync logs, reports/moderation, users & roles, content, analytics + CSV export.

## Verification status (be precise about this)

| Component | How it was verified here |
|---|---|
| SQL migrations, RLS, triggers, reminders, search, review workflow | Applied to a real PostgreSQL 16 server with a Supabase auth/storage stub; **all 4 SQL test files pass** (RLS/roles, reminders/search, review workflow + feedback, notifications) (`supabase/tests/`) |
| Edge Function logic (eligibility, recommendations, dedupe, link safety, connectors, sync, notifications, API router) | `tsc --strict` clean; **47 tests pass** |
| Admin dashboard | `tsc --strict` clean; 5 unit tests + **headless Chromium smoke test passes** |
| Python worker | 5 tests pass |
| **Flutter app** | **Not compiled here** — no Flutter SDK was available. Structural check (brackets, strings, imports, routes) passes for all 52 Dart files. Run `flutter analyze && flutter test` first; see `docs/PROGRESS.md`. |
| Real Supabase project, FCM, email, SMS, WhatsApp, official sources | **Not connected** — require your credentials/authorisation (see `docs/SETUP.md`, `docs/DATA_SOURCES.md`) |

## Quick start

```bash
# 1. Backend (Supabase CLI ≥ 1.200, Docker running)
supabase start                      # local stack; applies migrations + seed
supabase functions serve --env-file supabase/.env   # copy .env.example → supabase/.env first

# 2. Mobile app
cd app
python3 tool/setup_platforms.py     # runs `flutter create` for android/ios + patches deep links/permissions
cp env/dev.example.json env/dev.json  # put your Supabase URL + anon key
flutter pub get
flutter run --dart-define-from-file=env/dev.json

# 3. Admin dashboard
cd admin && cp config.example.js config.js   # same URL + anon key
npx tsc -p tsconfig.json && npx serve .      # or any static server
# make yourself an admin (SQL editor):  insert into user_roles (user_id, role) values ('<your auth uid>', 'super_admin');
```

Full instructions: **[docs/SETUP.md](docs/SETUP.md)** · Android APK: **[docs/ANDROID_BUILD.md](docs/ANDROID_BUILD.md)** ·
Official sources: **[docs/DATA_SOURCES.md](docs/DATA_SOURCES.md)** · API: **[docs/API.md](docs/API.md)** ·
Security & privacy: **[docs/SECURITY.md](docs/SECURITY.md)** · Progress checklist: **[docs/PROGRESS.md](docs/PROGRESS.md)** ·
Architecture: **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)**

## Tests

```bash
npm install                 # dev tooling (typescript, tsx, playwright)
bash scripts/test_all.sh    # everything; SQL tests need a local Postgres (PGHOST/PGPORT/PGUSER)
cd app && flutter analyze && flutter test
```

## Demo data

`supabase/seed.sql` contains clearly marked demo records: fictional organisations named `[DEMO] …`, links on the reserved
`example.org` domain, `is_demo = true`, and a database constraint that makes it impossible to mark them verified.
Remove them with `select public.purge_demo_data();` (super admin or SQL editor). The seed also registers the real
HEC, National Jobs Portal (NITB), PASTIC and Pakistan Digital Authority **as sources awaiting authorisation** — nothing is
fetched from them until an admin configures and activates them.
