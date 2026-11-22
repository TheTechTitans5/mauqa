# Mauqa — progress checklist

Legend: ✅ built and tested here · 🟦 built, **not compiled here** (Flutter) — run `flutter analyze && flutter test` ·
🔑 built, needs your credentials/authorisation to work · 🟨 partial (backend ready, UI or scope limited) · ⏭ deferred by design

| # | Area (brief section) | Status | Notes |
|---|---|---|---|
| 2 | No chatbot / no AI assistant | ✅ | None anywhere. Eligibility & recommendations are deterministic. |
| 3 | Stack: Flutter, Supabase, Postgres, Auth, Storage, Edge Functions, Cron, RLS | ✅/🟦 | Admin is a TypeScript web app (reason in ARCHITECTURE.md). |
| 4 | Premium 3D-inspired UI, light/dark, palette, 5-tab nav | 🟦 | Glass cards, tilt cards, animated gradients, painted 3D orbs, progress rings, skeletons, parallax hero. Reduce-motion/low-data respected. |
| 5 | Auth: email, phone OTP, verify, forgot/reset/change password, Google, sessions, deletion, consent, roles | 🟦 🔑 | SMS provider and Google OAuth must be configured in Supabase. Roles enforced in SQL (tested). |
| 6 | Profile & credentials, sections, completion %, recs refresh | 🟦 ✅ | Completion computed in SQL (tested). Sensitive fields opt-in. |
| 7 | Home dashboard (all listed widgets) | 🟦 | |
| 8 | 25 categories (EN/UR) | ✅ | Seeded. |
| 9 | Explore: backend search, filters, sorts, history, suggestions | ✅ 🟦 | `search_opportunities` tested (text, org, institution, category, province, gender, verified, pagination). |
| 10 | Detail screen + all actions | 🟦 | Apply flow asks before recording; link safety + fee warnings. |
| 11 | Interested + reminders (7/3/1/0, custom, change, close, no duplicates) | ✅ 🟦 | All behaviours covered by SQL tests. |
| 12 | Eligibility engine (3 outcomes, AND/OR, whitelists, thresholds, explanations, recalculation) | ✅ | 22 engine tests; staleness triggers tested; admin rule editor (browser-tested). |
| 13 | Recommendations with reasons, preferences, no closed items | ✅ 🟦 | |
| 14 | Saved (separate), search/filter, reminders, compare | ✅ 🟦 | |
| 15 | My Journey: 10 statuses, history, notes, interview/follow-up reminders | ✅ 🟦 | History & reminders tested. |
| 16 | Document vault: private, preview/download, replace, delete, expiry, checklists | ✅ 🟦 | Storage policies tested. |
| 17 | CV builder + PDF, cover letters, guides, interview prep, readiness | 🟦 | PDF builder has unit tests (run with `flutter test`). |
| 18 | Calendar month/week/day, reminders, PKT, .ics export | 🟦 | Two-way device-calendar sync is via .ics import (no OS calendar write access requested). |
| 18 | Push / email / SMS / WhatsApp | 🔑 | Channel code tested with fakes; unconfigured channels are skipped. |
| 19 | Data ingestion: API, RSS, web monitoring, PDF/OCR, manual, dedupe, change detection, logs, retries, human verification | ✅ 🔑 | Fully tested with fake sources. **No official source is connected** — none has a confirmed public API. |
| 20 | Official application redirection | 🟦 | Confirmation dialog, destination host, official-domain check. |
| 21 | Verification & scam protection, cautious labels | ✅ | Reporting threshold, payment-language and link checks tested. |
| 22 | Comparison (2–4, save, clear) | 🟦 | |
| 23 | Guides & resources (EN/UR) | 🟨 | 6 seeded guides (Urdu for 4) + interview questions; add more content via admin. |
| 24 | Notification centre, types, preferences, read/unread | ✅ 🟦 | New-match & eligibility-update notifications tested. |
| 25 | English/Urdu (RTL), text size, high contrast, simple mode, low-data, screen-reader labels, offline saved | 🟦 | Widget test checks RTL. Regional languages: add a map in `strings.dart`. Voice/TTS ⏭. |
| 26 | Community: stories (moderated), mentors, submit, report | 🟦 ✅ | Moderation in admin (browser-tested). |
| 27 | Institutions & organisations | 🟨 | Institution database, organisation profiles, submissions, verification requests table, ambassadors table exist. **No dedicated institution dashboard / ambassador application screen yet.** |
| 28 | Historical data & forecasting (labelled estimates) | 🟨 | `opportunity_cycles` + `opportunity_forecasts` view (tested) shown on detail page; no trend charts yet. |
| 29 | Settings (all items) | 🟦 | Data export + deletion via `account` function. |
| 30 | Admin dashboard (all sections + CSV export) | ✅ | tsc strict + headless Chromium smoke test. |
| 31 | Database design, constraints, indexes, RLS, migrations, seed | ✅ | 11 migrations, 5 SQL test suites. |
| 32 | Backend API endpoints | ✅ | `api` function + router tests. |
| 33 | Security & privacy | ✅ | See SECURITY.md. Backups: dashboard setting + documented procedure. |
| 34 | Offline & performance | 🟦 | Pagination, indexes, cached saved lists, skeletons, low-data mode. |
| 37 | Tests | ✅ / 🟦 | TS 47 · admin 5 + smoke · SQL 5 suites · Python 5 · Dart unit/widget tests written, not run here. |

## Must-do before release
1. Run `flutter analyze` and `flutter test` on a machine with Flutter, fix anything reported (the code was written to
   avoid version-sensitive APIs, but it has not been compiled).
2. Create the Supabase project, push migrations, set secrets, deploy functions, run `scheduled_jobs.sql`.
3. Configure SMS provider (phone auth), and optionally Google OAuth, FCM, Resend, WhatsApp.
4. Contact HEC / NITB / PASTIC / PDA for data-sharing permission; until then use manual entry by verifiers.
5. Replace demo data (`select purge_demo_data();`) with verified listings.
6. Legal review of Terms & Privacy text (`auth_screens.dart`).
