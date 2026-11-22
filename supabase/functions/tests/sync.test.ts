import { test } from 'node:test';
import assert from 'node:assert/strict';
import { syncSource, CONNECTORS, type NewItemRow, type StoredItem, type SyncStore } from '../_shared/sync.ts';
import { apiConnector, getPath } from '../_shared/connectors/api.ts';
import { rssConnector, webMonitorConnector } from '../_shared/connectors/feeds.ts';
import { ConnectorConfigError, type Connector, type ConnectorContext, type DataSourceRow, type RawItem } from '../_shared/connectors/types.ts';

function memStore() {
  const items: Array<NewItemRow & { id: string; first_seen: number }> = [];
  const logs: Array<Record<string, unknown>> = [];
  const sourcePatches: Array<Record<string, unknown>> = [];
  const alerts: string[] = [];
  const touched: string[] = [];
  let seq = 0;
  const store: SyncStore = {
    async startLog(sourceId, triggeredBy, _u, attempt) { logs.push({ sourceId, triggeredBy, attempt, status: 'running' }); return String(logs.length - 1); },
    async finishLog(id, patch) { Object.assign(logs[Number(id)], patch); },
    async latestItem(sourceId, externalId) {
      const m = items.filter((i) => i.source_id === sourceId && i.external_id === externalId).sort((a, b) => b.first_seen - a.first_seen)[0];
      return m ? ({ id: m.id, content_hash: m.content_hash, extracted: m.extracted, opportunity_id: m.opportunity_id, review_status: m.review_status } as StoredItem) : null;
    },
    async touchItem() {},
    async insertItem(row) { items.push({ ...row, id: `i${++seq}`, first_seen: seq }); },
    async markSuperseded(id) { const it = items.find((i) => i.id === id); if (it) (it as { review_status: string }).review_status = 'superseded'; },
    async candidates() { return [{ id: 'opp-existing', title: 'Existing Merit Scholarship for Engineers', organization_id: 'org1', deadline: '2026-12-15T18:59:00Z' }]; },
    async touchOpportunity(id) { touched.push(id); },
    async updateSource(_id, patch) { sourcePatches.push(patch); },
    async officialDomains() { return ['example.gov.pk']; },
    async alertAdmins(title) { alerts.push(title); },
  };
  return { store, items, logs, sourcePatches, alerts, touched };
}

const ctx: ConnectorContext = { fetch: async () => new Response('nope', { status: 500 }), sleep: async () => {}, log: () => {}, now: () => new Date('2026-11-21T10:00:00Z') };

function source(over: Partial<DataSourceRow> = {}): DataSourceRow {
  return { id: 's1', organization_id: 'org1', name: 'Test source', source_type: 'api', base_url: 'https://api.example.gov.pk', config: {},
    auth_method: 'none', secret_ref: null, integration_status: 'active', rate_limit_per_minute: 600, sync_interval_minutes: 60,
    is_enabled: true, consecutive_failures: 0, terms_reviewed_at: '2026-11-01', robots_txt_checked_at: null, ...over };
}

function fakeConnector(batches: RawItem[][]): Connector & { calls: number } {
  const c = { calls: 0, validateConfig() {}, async fetchItems() { return batches[Math.min(c.calls++, batches.length - 1)]; } };
  return c;
}
const item = (id: string, title: string, deadline = '2027-01-10T18:59:00Z'): RawItem => ({ externalId: id, url: `https://www.example.gov.pk/${id}`, raw: {},
  draft: { title, source_url: `https://www.example.gov.pk/${id}`, official_application_url: `https://apply.example.gov.pk/${id}`, deadline } });

test('new → unchanged → changed lifecycle, with duplicate detection', async () => {
  const m = memStore();
  const conn = fakeConnector([
    [item('a', 'Women Leadership Fellowship'), item('b', 'Existing Merit Scholarship for Engineers', '2026-12-15T18:59:00Z'), item('a', 'Women Leadership Fellowship')],
    [item('a', 'Women Leadership Fellowship'), item('b', 'Existing Merit Scholarship for Engineers', '2026-12-15T18:59:00Z')],
    [item('a', 'Women Leadership Fellowship', '2027-01-20T18:59:00Z')],
  ]);
  const connectors = { ...CONNECTORS, api: conn };
  const r1 = await syncSource(source(), m.store, ctx, { triggeredBy: 'manual', connectors });
  assert.deepEqual([r1.status, r1.created, r1.duplicates, r1.found], ['success', 1, 1, 3]);
  assert.equal(m.items.find((i) => i.external_id === 'b')?.duplicate_of, 'opp-existing');
  const r2 = await syncSource(source(), m.store, ctx, { triggeredBy: 'schedule', connectors });
  assert.equal(r2.unchanged, 2);
  const r3 = await syncSource(source(), m.store, ctx, { triggeredBy: 'schedule', connectors });
  assert.equal(r3.changed, 1);
  const latest = m.items.filter((i) => i.external_id === 'a').at(-1)!;
  assert.deepEqual(Object.keys(latest.detected_changes ?? {}), ['deadline']);
  assert.equal(m.items.filter((i) => i.external_id === 'a')[0].review_status, 'superseded');
  assert.ok(m.items.every((i) => i.review_status !== ('approved' as string)), 'nothing is auto-approved');
  assert.equal(m.sourcePatches.at(-1)?.consecutive_failures, 0);
});

test('disabled / unauthorised sources are skipped without fetching', async () => {
  const m = memStore();
  const conn = fakeConnector([[item('a', 'x')]]);
  const r = await syncSource(source({ integration_status: 'awaiting_authorization' }), m.store, ctx, { triggeredBy: 'schedule', connectors: { ...CONNECTORS, api: conn } });
  assert.equal(r.status, 'skipped');
  assert.equal(conn.calls, 0);
  assert.match(String(m.logs[0].error_message), /awaiting authorization/);
});

test('configuration errors are not retried and alert admins', async () => {
  const m = memStore();
  let calls = 0;
  const conn: Connector = { validateConfig() {}, async fetchItems() { calls++; throw new ConnectorConfigError('Credential X not configured'); } };
  const r = await syncSource(source(), m.store, ctx, { triggeredBy: 'schedule', connectors: { ...CONNECTORS, api: conn } });
  assert.equal(r.status, 'failed');
  assert.equal(calls, 1);
  assert.equal(m.sourcePatches.at(-1)?.integration_status, 'error');
  assert.equal(m.alerts.length, 1);
});

test('transient errors are retried, then failure counted', async () => {
  const m = memStore();
  let calls = 0;
  const conn: Connector = { validateConfig() {}, async fetchItems() { calls++; if (calls < 3) throw new Error('timeout'); return [item('z', 'Recovered listing')]; } };
  const r = await syncSource(source(), m.store, ctx, { triggeredBy: 'schedule', connectors: { ...CONNECTORS, api: conn } });
  assert.equal(r.status, 'success');
  assert.equal(calls, 3);
  assert.equal(m.logs.filter((l) => l.status === 'failed').length, 2);
  const m2 = memStore();
  const always: Connector = { validateConfig() {}, async fetchItems() { throw new Error('down'); } };
  await syncSource(source({ consecutive_failures: 2 }), m2.store, ctx, { triggeredBy: 'schedule', connectors: { ...CONNECTORS, api: always } });
  assert.equal(m2.sourcePatches.at(-1)?.consecutive_failures, 3);
  assert.equal(m2.alerts.length, 1, 'third consecutive failure alerts admins');
});

test('API connector: pagination, mapping and credentials from env only', async () => {
  process.env.TEST_PORTAL_KEY = 'secret-123';
  const seen: string[] = [];
  const pages = [
    { data: { items: [{ id: 1, name: 'Data internship', closes: '2027-01-15', url: '/o/1', apply: 'https://apply.example.gov.pk/1' }] } },
    { data: { items: [] } },
  ];
  const fetchFake = async (url: string, init?: RequestInit) => {
    seen.push(url);
    assert.equal((init?.headers as Record<string, string>)['X-Portal-Key'], 'secret-123');
    return new Response(JSON.stringify(pages[seen.length - 1]), { status: 200 });
  };
  const s = source({ auth_method: 'api_key_header', secret_ref: 'TEST_PORTAL_KEY', config: {
    endpoint: '/v1/opps', items_path: 'data.items', api_key_header: 'X-Portal-Key',
    pagination: { type: 'page', param: 'page', size_param: 'per_page', size: 1, max_pages: 5 },
    mapping: { title: 'name', deadline: 'closes', source_url: 'url', official_application_url: 'apply' } } });
  const out = await apiConnector.fetchItems(s, { ...ctx, fetch: fetchFake });
  assert.equal(out.length, 1);
  assert.equal(out[0].draft.title, 'Data internship');
  assert.equal(out[0].draft.source_url, 'https://api.example.gov.pk/o/1');
  assert.equal(out[0].draft.deadline, '2027-01-15T18:59:00.000Z');
  assert.match(seen[0], /page=1&?/);
  assert.equal(seen.length, 2);
  assert.throws(() => apiConnector.validateConfig(source({ config: { endpoint: 'http://insecure.pk/x', mapping: { title: 't' } } })), /HTTPS/);
  await assert.rejects(apiConnector.fetchItems(source({ auth_method: 'bearer_token', secret_ref: 'MISSING_SECRET_X',
    config: { endpoint: '/x', mapping: { title: 't' } } }), ctx), /not configured/);
  assert.throws(() => apiConnector.validateConfig(source({ auth_method: 'bearer_token', secret_ref: null, config: { endpoint: '/x', mapping: { title: 't' } } })), /secret_ref/);
  assert.equal(getPath({ a: [{ b: 2 }] }, 'a.0.b'), 2);
});

test('RSS connector refuses when robots.txt disallows', async () => {
  const f = async (url: string) => url.endsWith('/robots.txt')
    ? new Response('User-agent: *\nDisallow: /feed', { status: 200 })
    : new Response('<rss></rss>', { status: 200 });
  await assert.rejects(rssConnector.fetchItems(source({ source_type: 'rss', config: { feed_url: 'https://news.example.gov.pk/feed' } }), { ...ctx, fetch: f }), /robots\.txt disallows/);
});

test('website monitor requires reviewed terms, BOT_CONTACT and link filters; stops at CAPTCHA', async () => {
  const base = { source_type: 'web_monitor' as const, config: { list_url: 'https://www.example.gov.pk/scholarships', link_include: ['/sch/'] } };
  assert.throws(() => webMonitorConnector.validateConfig(source({ ...base, terms_reviewed_at: null })), /terms of use/);
  delete process.env.BOT_CONTACT;
  assert.throws(() => webMonitorConnector.validateConfig(source(base)), /BOT_CONTACT/);
  process.env.BOT_CONTACT = 'ops@example.org';
  const f = async (url: string) => url.endsWith('/robots.txt') ? new Response('', { status: 404 })
    : new Response('<div class="g-recaptcha"></div>', { status: 200 });
  await assert.rejects(webMonitorConnector.fetchItems(source(base), { ...ctx, fetch: f }), /CAPTCHA/);
  const ok = async (url: string) => url.endsWith('/robots.txt') ? new Response('', { status: 404 })
    : new Response('<a href="/sch/1">Merit Scholarship – last date 10-01-2027</a><a href="/news/2">News</a><a href="https://evil.com/sch/3">Ext</a>', { status: 200 });
  const items = await webMonitorConnector.fetchItems(source(base), { ...ctx, fetch: ok });
  assert.deepEqual(items.map((i) => i.url), ['https://www.example.gov.pk/sch/1']);
  assert.equal(items[0].draft.deadline, '2027-01-10T18:59:00.000Z');
  assert.equal(items[0].draft.official_application_url, null, 'application link is never guessed');
});

test('403 from a site is treated as "authorisation required" and not retried', async () => {
  let n = 0;
  const f = async (url: string) => { if (url.endsWith('/robots.txt')) return new Response('', { status: 404 }); n++; return new Response('', { status: 403 }); };
  await assert.rejects(rssConnector.fetchItems(source({ source_type: 'rss', config: { feed_url: 'https://news.example.gov.pk/rss' } }), { ...ctx, fetch: f }), /Authorisation is required/);
  assert.equal(n, 1);
});
