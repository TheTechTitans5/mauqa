# Setup guide

## 1. Create the Supabase project

1. Create a project at supabase.com (region close to Pakistan, e.g. Mumbai or Singapore). Note:
   - **Project URL** and **anon key** (Settings → API) — public, used by the app and admin dashboard.
   - **service_role key** — secret, used only inside Edge Functions (automatically available there).
2. Install the CLI and link: `supabase login && supabase link --project-ref <ref>`.
3. Push the schema and seed:
   ```bash
   supabase db push                       # applies supabase/migrations/*
   psql "$DATABASE_URL" -f supabase/seed.sql   # or paste seed.sql into the SQL editor
   ```
4. Enable extensions (Database → Extensions): `pg_cron`, `pg_net` (pgcrypto, pg_trgm, unaccent are created by migrations).
   If pg_cron was not enabled when migration 0008 ran, re-run the `do $$ … $$` block at the end of
   `20261121000008_storage_cron.sql` to create the SQL jobs.

## 2. Auth configuration (Authentication → Providers / URL configuration)

| Setting | Value |
|---|---|
| Site URL / redirect URLs | `io.mauqa.app://login-callback` (mobile deep link). Add your admin URL too. |
| Email | Enable, **confirm email ON** |
| Phone | Enable and configure an SMS provider (Twilio, MessageBird, Vonage or Textlocal). Without it, phone sign-up and OTP will fail with a clear error; email still works. |
| Google (optional) | Create an OAuth client (Google Cloud Console → Credentials), paste client id/secret, then build the app with `GOOGLE_SIGN_IN_ENABLED=true`. |
| Password | minimum length 8 |

## 3. Deploy Edge Functions and secrets

```bash
cp .env.example supabase/.env      # fill in what you have; leave unused channels empty
supabase secrets set --env-file supabase/.env
supabase functions deploy eligibility-check recommendations account api
supabase functions deploy source-sync dispatch-notifications --no-verify-jwt   # these check x-cron-secret
```

Then schedule the function jobs: create the two Vault secrets described at the top of
`supabase/scheduled_jobs.sql` and run that file in the SQL editor.

### What each optional secret enables

| Feature | Secrets | Where to get them |
|---|---|---|
| Push notifications | `FCM_SERVICE_ACCOUNT_JSON` (backend) + `FIREBASE_*` dart-defines (app) | Firebase console → Project settings → Service accounts → *Generate new private key*; and General → your Android app's config values |
| Email reminders | `RESEND_API_KEY`, `EMAIL_FROM` | resend.com → API keys; verify your sending domain |
| SMS | `SMS_GATEWAY_URL`, `SMS_GATEWAY_TOKEN`, `SMS_SENDER_ID` | Your PTA-registered SMS aggregator (masking/sender ID approval required). Adjust `SmsChannel` in `notify.ts` to the provider's exact request format. |
| WhatsApp | `WHATSAPP_TOKEN`, `WHATSAPP_PHONE_NUMBER_ID`, `WHATSAPP_TEMPLATE_NAME` | Meta Business → WhatsApp → API setup; create and get approval for a template with two body variables |
| Website monitoring | `BOT_CONTACT` | An email/URL you control, shown in the bot's User-Agent |
| PDF/OCR | `PDF_EXTRACT_URL`, `PDF_EXTRACT_TOKEN` | Deploy `workers/ingest_worker.py` (any Python host). OCR needs `tesseract-ocr` + `tesseract-ocr-urd` + `poppler` |

Channels without credentials are recorded as **skipped**, never as sent. In-app notifications always work.

## 4. First admin

Sign up in the app (or Authentication → Users → Add user), then in the SQL editor:
```sql
insert into public.user_roles (user_id, role) values ('<auth user id>', 'super_admin');
```
Further roles are managed from the admin dashboard (Users page).

## 5. Run the app

```bash
cd app
python3 tool/setup_platforms.py          # one time: generates android/ and ios/ and patches them
cp env/dev.example.json env/dev.json     # fill SUPABASE_URL + SUPABASE_ANON_KEY (+ FIREBASE_* if using push)
flutter pub get
flutter analyze && flutter test
flutter run --dart-define-from-file=env/dev.json
```

For push on Android you can skip `google-services.json`: the app initialises Firebase from the dart-defines.

## 6. Admin dashboard

```bash
cd admin
cp config.example.js config.js           # same public URL + anon key
npx tsc -p tsconfig.json                 # outputs dist/
npx serve .                              # or deploy the folder (index.html, styles.css, config.js, dist/) to any static host
```
Add the dashboard's URL to Supabase Auth redirect URLs and, if you host it on a custom domain, add that domain to
the `connect-src` of the CSP in `index.html` (it already allows `https://*.supabase.co`).

## 7. Local development without the cloud

`supabase start` runs Postgres/Auth/Storage/Functions in Docker and applies migrations + seed automatically. Use the
printed local URL/anon key in `env/dev.json` (Android emulator: replace `localhost` with `10.0.2.2`).

## 8. Backups and recovery

- Enable **Point-in-Time Recovery** (Pro plan) or at minimum daily backups (Database → Backups).
- Weekly logical dump to off-site storage: `supabase db dump --data-only -f backup.sql` (cron on a trusted machine).
- Storage objects: periodically sync the `user-documents` bucket with `rclone` using a service key stored only on that machine.
- Recovery drill: restore the latest backup into a new project, re-run `scheduled_jobs.sql`, point a staging build at it.
