// Mauqa REST API (our own API — not an external one). Every handler uses the caller's JWT so RLS applies;
// the service role is used only where users must not write directly (eligibility results, source sync).
import { HttpError, isUuid, requireUuid } from './http.ts';
import { inList, Rest } from './rest.ts';
import { checkEligibility, recommendationsFor } from './services.ts';
import { restSyncStore, syncSource } from './sync.ts';
import type { ConnectorContext, DataSourceRow } from './connectors/types.ts';

export interface ApiRequest { method: string; path: string; query: URLSearchParams; body: Record<string, unknown>; token: string }
export interface ApiDeps { user: Rest; service: () => Rest; ctx: ConnectorContext }
type Handler = (req: ApiRequest, params: Record<string, string>, deps: ApiDeps & { userId: string }) => Promise<unknown>;

const STATUSES = ['interested', 'planning', 'preparing_documents', 'applied', 'under_review', 'shortlisted',
  'interview_scheduled', 'selected', 'rejected', 'withdrawn'];
const APP_FIELDS = ['status', 'custom_title', 'custom_organization', 'custom_url', 'applied_on', 'deadline', 'interview_at',
  'follow_up_at', 'external_reference', 'notes'];

function pick(body: Record<string, unknown>, allowed: string[]): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const k of allowed) if (k in body) out[k] = body[k];
  return out;
}

function validateApplication(b: Record<string, unknown>, creating: boolean) {
  if ('status' in b && !STATUSES.includes(String(b.status))) throw new HttpError(422, 'Invalid status', 'validation');
  if (creating && !b.opportunity_id && !b.custom_title) throw new HttpError(422, 'opportunity_id or custom_title is required', 'validation');
  if (b.opportunity_id !== undefined && b.opportunity_id !== null && !isUuid(b.opportunity_id)) throw new HttpError(422, 'opportunity_id must be a UUID', 'validation');
  for (const k of ['deadline', 'interview_at', 'follow_up_at']) {
    if (b[k] != null && !Number.isFinite(Date.parse(String(b[k])))) throw new HttpError(422, `${k} must be an ISO timestamp`, 'validation');
  }
  if (typeof b.notes === 'string' && b.notes.length > 5000) throw new HttpError(422, 'notes too long', 'validation');
}

const routes: Array<[string, RegExp, Handler]> = [
  ['GET', /^\/opportunities$/, async (r, _p, d) => {
    const filters: Record<string, unknown> = {};
    for (const key of ['categories', 'provinces', 'cities', 'education_levels', 'funding_types', 'work_modes', 'org_types', 'statuses', 'fields', 'skills']) {
      const v = r.query.get(key);
      if (v) filters[key] = v.split(',').map((s) => s.trim()).filter(Boolean);
    }
    for (const key of ['gender', 'deadline_before', 'deadline_after']) { const v = r.query.get(key); if (v) filters[key] = v; }
    for (const key of ['age', 'max_experience_months', 'min_amount_pkr']) { const v = r.query.get(key); if (v) filters[key] = Number(v); }
    if (r.query.get('verified_only') === 'true') filters.verified_only = true;
    return d.user.rpc('search_opportunities', {
      p_query: r.query.get('q'), p_filters: filters, p_sort: r.query.get('sort') ?? 'relevance',
      p_limit: Number(r.query.get('limit') ?? 20), p_offset: Number(r.query.get('offset') ?? 0),
    });
  }],
  ['GET', /^\/opportunities\/recommended$/, async (r, _p, d) =>
    ({ items: await recommendationsFor(d.user, d.service(), d.userId, Number(r.query.get('limit') ?? 20)) })],
  ['GET', /^\/opportunities\/closing-soon$/, async (r, _p, d) =>
    ({ items: await d.user.select('opportunity_feed', `select=*&effective_status=eq.closing_soon&order=deadline.asc&limit=${Math.min(Number(r.query.get('limit') ?? 20), 50)}`) })],
  ['GET', /^\/opportunities\/([0-9a-f-]{36})$/, async (_r, p, d) => {
    const [item] = await d.user.select('opportunity_feed', `select=*&id=eq.${p.id}`);
    if (!item) throw new HttpError(404, 'Opportunity not found', 'not_found');
    const [rules, documents] = await Promise.all([
      d.user.select('opportunity_eligibility_rules', `select=*&opportunity_id=eq.${p.id}&order=sort_order`),
      d.user.select('opportunity_documents', `select=*&opportunity_id=eq.${p.id}`),
    ]);
    await d.user.rpc('record_opportunity_view', { p_opportunity: p.id }).catch(() => undefined);
    return { ...item, eligibility_rules: rules, required_documents: documents };
  }],
  ['POST', /^\/eligibility\/check$/, async (r, _p, d) => {
    const ids = Array.isArray(r.body.opportunity_ids) ? r.body.opportunity_ids : [r.body.opportunity_id];
    if (!ids.every(isUuid)) throw new HttpError(422, 'opportunity_id(s) must be UUIDs', 'validation');
    return { results: await checkEligibility(d.user, d.service(), d.userId, ids as string[], { force: r.body.force === true }) };
  }],
  ['POST', /^\/opportunities\/([0-9a-f-]{36})\/save$/, async (r, p, d) =>
    (await d.user.insert('saved_opportunities', { user_id: d.userId, opportunity_id: p.id,
      folder: typeof r.body.folder === 'string' ? r.body.folder.slice(0, 40) : null, reminders_enabled: r.body.reminders_enabled === true },
      { upsert: 'user_id,opportunity_id' }))[0]],
  ['DELETE', /^\/opportunities\/([0-9a-f-]{36})\/save$/, async (_r, p, d) => {
    await d.user.delete('saved_opportunities', `user_id=eq.${d.userId}&opportunity_id=eq.${p.id}`); return { removed: true };
  }],
  ['POST', /^\/opportunities\/([0-9a-f-]{36})\/interested$/, async (r, p, d) => {
    const offsets = Array.isArray(r.body.reminder_offsets_days) ? r.body.reminder_offsets_days.map(Number) : [7, 3, 1, 0];
    return (await d.user.insert('interested_opportunities', { user_id: d.userId, opportunity_id: p.id,
      reminders_enabled: r.body.reminders_enabled !== false, reminder_offsets_days: offsets }, { upsert: 'user_id,opportunity_id' }))[0];
  }],
  ['DELETE', /^\/opportunities\/([0-9a-f-]{36})\/interested$/, async (_r, p, d) => {
    await d.user.delete('interested_opportunities', `user_id=eq.${d.userId}&opportunity_id=eq.${p.id}`); return { removed: true };
  }],
  ['GET', /^\/applications$/, async (_r, _p, d) =>
    ({ items: await d.user.select('applications', 'select=*,opportunities(title,deadline,official_application_url)&order=updated_at.desc') })],
  ['POST', /^\/applications$/, async (r, _p, d) => {
    validateApplication(r.body, true);
    return (await d.user.insert('applications', { ...pick(r.body, [...APP_FIELDS, 'opportunity_id']), user_id: d.userId }))[0];
  }],
  ['PATCH', /^\/applications\/([0-9a-f-]{36})$/, async (r, p, d) => {
    validateApplication(r.body, false);
    const [row] = await d.user.update('applications', `id=eq.${p.id}`, pick(r.body, APP_FIELDS));
    if (!row) throw new HttpError(404, 'Application not found', 'not_found');
    return row;
  }],
  ['GET', /^\/documents$/, async (_r, _p, d) => ({ items: await d.user.select('user_documents', 'select=*&order=created_at.desc') })],
  ['POST', /^\/documents\/([0-9a-f-]{36})\/download$/, async (_r, p, d) => {
    const [doc] = await d.user.select<{ storage_path: string }>('user_documents', `select=storage_path&id=eq.${p.id}`);
    if (!doc) throw new HttpError(404, 'Document not found', 'not_found');
    return { url: await d.user.storageSign('user-documents', doc.storage_path, 120), expires_in: 120 };
  }],
  ['DELETE', /^\/documents\/([0-9a-f-]{36})$/, async (_r, p, d) => {
    const [doc] = await d.user.select<{ storage_path: string }>('user_documents', `select=storage_path&id=eq.${p.id}`);
    if (!doc) throw new HttpError(404, 'Document not found', 'not_found');
    await d.user.storageRemove('user-documents', [doc.storage_path]);
    await d.user.delete('user_documents', `id=eq.${p.id}`);
    return { removed: true };
  }],
  ['GET', /^\/notifications$/, async (r, _p, d) => ({ items: await d.user.select('notifications',
    `select=id,type,title,body,opportunity_id,application_id,is_read,created_at&order=created_at.desc&limit=${Math.min(Number(r.query.get('limit') ?? 50), 100)}${r.query.get('unread') === 'true' ? '&is_read=eq.false' : ''}`) })],
  ['PATCH', /^\/notifications\/([0-9a-f-]{36})$/, async (r, p, d) => {
    if (typeof r.body.is_read !== 'boolean') throw new HttpError(422, 'is_read must be boolean', 'validation');
    const [row] = await d.user.update('notifications', `id=eq.${p.id}`, { is_read: r.body.is_read, read_at: r.body.is_read ? new Date().toISOString() : null });
    if (!row) throw new HttpError(404, 'Notification not found', 'not_found');
    return row;
  }],
  ['GET', /^\/sources\/status$/, async (_r, _p, d) => {
    const items = await d.user.select('data_sources',
      'select=id,name,source_type,integration_status,is_enabled,last_sync_at,last_success_at,next_sync_at,consecutive_failures,authorization_notes&order=name');
    if (!items.length) {
      const roles = await d.user.rpc<string[]>('my_roles');
      if (!roles.some((x) => x !== 'user')) throw new HttpError(403, 'Staff only', 'forbidden');
    }
    return { items };
  }],
  ['POST', /^\/sources\/([0-9a-f-]{36})\/sync$/, async (_r, p, d) => {
    const roles = await d.user.rpc<string[]>('my_roles');
    if (!roles.some((x) => x === 'admin' || x === 'super_admin')) throw new HttpError(403, 'Admins only', 'forbidden');
    const service = d.service();
    const [src] = await service.select<DataSourceRow>('data_sources', `select=*&id=eq.${requireUuid(p.id, 'id')}`);
    if (!src) throw new HttpError(404, 'Source not found', 'not_found');
    return syncSource(src, restSyncStore(service), d.ctx, { triggeredBy: 'manual', userId: d.userId });
  }],
];

export function matchRoute(method: string, path: string): { handler: Handler; params: Record<string, string> } | null {
  let pathMatched = false;
  for (const [m, re, h] of routes) {
    const x = re.exec(path);
    if (!x) continue;
    pathMatched = true;
    if (m === method) return { handler: h, params: x[1] ? { id: x[1].toLowerCase() } : {} };
  }
  if (pathMatched) throw new HttpError(405, 'Method not allowed', 'method_not_allowed');
  return null;
}

/** "/api/opportunities/x" or "/functions/v1/api/opportunities/x" → "/opportunities/x" */
export function apiPath(url: string): string {
  const p = new URL(url).pathname.replace(/\/+$/, '');
  const i = p.indexOf('/api');
  return i >= 0 ? (p.slice(i + 4) || '/') : p;
}

export async function dispatchApi(req: ApiRequest, deps: ApiDeps): Promise<unknown> {
  const m = matchRoute(req.method, req.path);
  if (!m) throw new HttpError(404, `No route for ${req.method} ${req.path}`, 'not_found');
  const me = await deps.user.authUser();
  return m.handler(req, m.params, { ...deps, userId: me.id });
}

export { inList };
