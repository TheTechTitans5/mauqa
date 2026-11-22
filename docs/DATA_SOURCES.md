# Connecting official data sources

**Rule: never assume an API exists, never bypass access controls, never publish without human verification.**

```
Official source ─► connector (api | rss | web_monitor | pdf | manual)
               ─► extraction (title, dates, links, amounts)
               ─► validation (official domain? https? deadline sane? fee language?)
               ─► duplicate / change detection (content hash, title similarity, URL match)
               ─► source_items review queue  ─► verifier: create draft / apply changes / reject
               ─► opportunities (pending_verification) ─► verifier checklist ─► verified + published
```

## Seeded sources (all `awaiting_authorization`, disabled)

| Organisation | Official site | Public API confirmed? | Recommended path |
|---|---|---|---|
| Higher Education Commission | https://www.hec.gov.pk | No | Manual entry from official announcements/PDFs; ask HEC for a data feed; web monitoring only after reviewing terms and robots.txt |
| National Jobs Portal (operated by NITB) | https://www.njp.gov.pk | No | Request data access from NITB (`info@njp.gov.pk`). Do **not** automate account sign-in. |
| PASTIC | https://www.pastic.gov.pk | No | Trainings portal; monitor public listing pages after terms review; registration stays on PASTIC |
| Pakistan Digital Authority | *not confirmed* | No | Confirm the official domain first, then manual entry |

Universities, companies and NGOs: add each as an organisation (with `official_domains`) and a source.

## Adding a source (admin dashboard → Data sources → Add source)

1. **Organisation** — set its `official_domains` (Content → Organisations). Links outside these domains are flagged.
2. **Type and config** (JSON):
   - `api`: `{"endpoint": "/v1/opps", "items_path": "data", "id_path": "id", "pagination": {"type": "page", "param": "page", "size_param": "per_page", "size": 50, "max_pages": 10}, "mapping": {"title": "title", "deadline": "closing_date", "source_url": "url", "official_application_url": "apply_url", "summary": "summary"}}`
   - `rss`: `{"feed_url": "https://…/feed.xml"}`
   - `web_monitor`: `{"list_url": "https://…/scholarships", "link_include": ["/scholarship"], "fetch_details": true, "max_items": 25}`
   - `pdf`: `{"pdf_urls": ["https://…/advertisement.pdf"], "ocr": true}`
3. **Credentials** — choose the auth method and enter only the **secret name** (e.g. `NJP_API_TOKEN`). Store the value with
   `supabase secrets set NJP_API_TOKEN=…`. Names starting with `SUPABASE_`, `SERVICE_ROLE` or `CRON_SECRET` are refused.
4. **Authorisation notes** — record who granted access, when, and any conditions.
5. Tick **Terms of use & robots.txt reviewed** (required before a web monitor can be activated).
6. Set **interval** and **rate limit**, then set status to **active** and **enabled**. Use *Sync now* and check *Logs*.

### What connectors do automatically

- Respect `robots.txt` (fail closed if it cannot be read), crawl-delay and the per-source rate limit.
- Stop on HTTP 401/403, login forms or CAPTCHAs and mark the source **error** with an admin alert.
- Retry transient failures with exponential backoff (3 attempts); 3 consecutive failures alert admins.
- Never guess an official application URL — reviewers add it.
- Record every run in `source_sync_logs` and every item (raw + extracted + issues) in `source_items`.

## Reviewing (dashboard → Verification)

- **Ingested items** → *Create draft* (choose category, add the official application link) or *Apply changes* for an
  already-linked listing (e.g. the deadline moved — followers are notified and reminders rescheduled), or *Reject*.
- **Listings awaiting verification** → open the official source and confirm the checklist. Approval requires source URL,
  application URL and deadline to be confirmed; demo listings can never become "verified".
- **Submissions** from users/organisations and **corrections** are handled in the same queue.

## Adding a new connector type

Implement `Connector` in `supabase/functions/_shared/connectors/` (`validateConfig` + `fetchItems` returning `RawItem[]`),
register it in `CONNECTORS` in `sync.ts`, add the value to the `source_type` enum in a migration, and write a test with a
fake `fetch` like `tests/sync.test.ts`.
