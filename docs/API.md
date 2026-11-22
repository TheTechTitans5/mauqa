# Mauqa API (our own API — not an external one)

The Flutter app talks to Supabase directly (PostgREST + RPC + Edge Functions) with the user's JWT, so Row Level
Security applies to every call. The same operations are also exposed as a REST facade in the `api` Edge Function for
other clients. Base URL: `https://<project>.supabase.co/functions/v1/api`. Header: `Authorization: Bearer <user JWT>`.

| Method & path | Purpose | Backed by |
|---|---|---|
| `GET /opportunities?q=&categories=a,b&provinces=&education_levels=&funding_types=&work_modes=&org_types=&statuses=&gender=&age=&max_experience_months=&min_amount_pkr=&verified_only=true&sort=relevance\|latest\|deadline\|popularity&limit=&offset=` | Search | `rpc/search_opportunities` |
| `GET /opportunities/{id}` | Details + rules + required documents (records a view) | `opportunity_feed`, rules, docs |
| `GET /opportunities/recommended?limit=` | Recommendations with reasons | `recommendations` service |
| `GET /opportunities/closing-soon` | Closing within 7 days | `opportunity_feed` |
| `POST /eligibility/check` `{opportunity_id \| opportunity_ids[], force?}` | Deterministic eligibility | `eligibility-check` service |
| `POST/DELETE /opportunities/{id}/save` `{folder?, reminders_enabled?}` | Saved list | `saved_opportunities` |
| `POST/DELETE /opportunities/{id}/interested` `{reminders_enabled?, reminder_offsets_days?}` | Interested + reminders | `interested_opportunities` (+ triggers) |
| `GET /applications` · `POST /applications` · `PATCH /applications/{id}` | Tracker | `applications` (+ history trigger) |
| `GET /documents` · `POST /documents/{id}/download` · `DELETE /documents/{id}` | Vault (signed URL, 120 s) | `user_documents` + Storage |
| `GET /notifications?unread=true` · `PATCH /notifications/{id}` `{is_read}` | Notification centre | `notifications` |
| `GET /sources/status` (staff) · `POST /sources/{id}/sync` (admin) | Ingestion | `data_sources`, `source-sync` |

Uploads go straight to Storage (`user-documents/<uid>/<file>`) with the user's JWT; storage policies only allow the
owner's folder.

Errors: `{"error": {"code": "validation|unauthenticated|forbidden|not_found|rate_limited|db_error|internal", "message": "…"}}`
with matching HTTP status. Rate limits: 120 req/min per token (api), 60/min (eligibility), 20/min (recommendations).

## Other Edge Functions

| Function | Auth | Purpose |
|---|---|---|
| `eligibility-check` | user JWT | `POST {opportunity_id(s), force?}` |
| `recommendations` | user JWT | `POST ?limit=20` |
| `account` | user JWT | `POST {action:"export"}` → JSON of all personal data; `{action:"delete", confirm:"DELETE"}` → deletes files + account |
| `source-sync` | admin JWT or `x-cron-secret` | manual or scheduled ingestion |
| `dispatch-notifications` | `x-cron-secret` | reminders → notifications → push/email/SMS/WhatsApp |

## Key SQL RPCs

`search_opportunities`, `trending_opportunities`, `home_summary`, `my_calendar_events`, `add_custom_reminder`,
`mark_all_notifications_read`, `record_opportunity_view`, `profile_completion`, `my_roles`;
staff: `admin_dashboard_stats`, `admin_analytics`, `admin_set_role`, `admin_set_suspended`, `review_opportunity`,
`create_opportunity_from_source_item`, `apply_source_item_changes`, `reject_source_item`, `accept_opportunity_submission`;
internal (not callable by users): `schedule_deadline_reminders`, `cancel_deadline_reminders`, `dispatch_due_reminders`,
`refresh_opportunity_statuses`.
