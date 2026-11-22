# Security & privacy

## Access control
- **RLS on every table.** Owner-only tables (education, skills, saved, interested, applications, documents, CVs, …) allow
  `select/insert/update/delete` only where `user_id = auth.uid()`; inserts also require a non-suspended account.
- **Roles** live in `user_roles` and can only be changed through `admin_set_role()` (admins manage verifier/content
  manager; only super admins manage admin roles). Users cannot insert roles, set `is_suspended`, change their
  `profile_version`, forge eligibility results, insert automatic reminders, or edit notification text (column-level grant).
- **Verification integrity**: only verifiers can approve/verify; material edits by content managers drop a listing back to
  *pending verification*; a published listing must be approved; a verified listing must have a source URL; demo records
  can never be verified (CHECK constraint). Every change to opportunities, sources, rules, roles, reports and reviews is
  written to `audit_logs`, and opportunity edits create `opportunity_versions`.
- **Internal functions** (`schedule_deadline_reminders`, `dispatch_due_reminders`, …) have EXECUTE revoked from
  `anon`/`authenticated`. Staff RPCs check roles inside.
- All of the above is covered by `supabase/tests/sql/10_security_rls.sql` (privilege-escalation and cross-user tests).

## Secrets
- The app and admin dashboard contain only the Supabase URL + **anon** key (public by design).
- Service-role key, FCM/email/SMS/WhatsApp keys and connector credentials exist only as Edge Function secrets.
  Connector rows store a secret *name*; platform secret names are refused.
- Cron calls authenticate with `x-cron-secret` (constant-time comparison).

## Documents
- Private buckets; objects must live under `<uid>/`; storage policies restrict all operations to the owner.
- Downloads use signed URLs valid for 120 s. Type allow-list (PDF, images, Word) and 10 MB limit enforced in the app,
  the bucket configuration and a table CHECK.

## Personal data
- CNIC, income and disability are optional. Income/disability are only used when the user switches on
  `share_sensitive_for_eligibility`; otherwise income-limited programmes return *unconfirmed*.
- Data export (`account` function) and account deletion (files + auth user → cascades to all rows).
- Retention (pg_cron): search history 180 days, read notifications 365 days, view logs 400 days.

## Scam protection
- Link checks (non-https, shorteners, messaging links, raw IPs, punycode, look-alike or non-official domains) in both the
  backend validator and the app's *Apply officially* dialog; payment-language detection on ingested text; fee warnings.
- Labels are cautious: *Verified official source*, *Pending verification*, *Unverified*, *Reported for review* (after 3
  distinct reporters). The app never states that a listing is fraudulent.

## Web
- Admin dashboard uses `textContent` only (no `innerHTML`), a strict CSP (no inline scripts or styles), `no-referrer`, and
  CSV exports neutralise spreadsheet formula injection.

## Abuse limits
- Per-user in-memory rate limits in Edge Functions; one open report per user/listing/reason; view counting throttled
  to once per user per hour; search queries capped at 200 characters and 50 results per page.
