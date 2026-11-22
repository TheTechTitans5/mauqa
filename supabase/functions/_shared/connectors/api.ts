// Configurable connector for an AUTHORISED official API.
// Nothing here assumes any real organisation's API exists: every endpoint, mapping and credential comes from
// data_sources.config / secret_ref, filled in by an admin once access has been granted.
import { readSecretRef } from '../env.ts';
import { findDeadline, parseLooseDate } from '../textExtract.ts';
import { PoliteFetcher } from './politeFetch.ts';
import type { Connector, ConnectorContext, DataSourceRow, RawItem } from './types.ts';
import { ConnectorConfigError } from './types.ts';

export interface ApiConfig {
  endpoint: string;
  items_path?: string;
  id_path?: string;
  query?: Record<string, string>;
  api_key_header?: string;
  token_url?: string;
  since_param?: string;
  pagination?: {
    type: 'none' | 'page' | 'offset' | 'cursor';
    param?: string; size_param?: string; size?: number; max_pages?: number; start?: number;
    cursor_param?: string; next_cursor_path?: string;
  };
  mapping: Record<string, string>;
}

export function getPath(obj: unknown, path: string | undefined): unknown {
  if (!path) return obj;
  return path.split('.').reduce<unknown>((acc, key) => {
    if (acc === null || acc === undefined) return undefined;
    if (Array.isArray(acc) && /^\d+$/.test(key)) return acc[Number(key)];
    return typeof acc === 'object' ? (acc as Record<string, unknown>)[key] : undefined;
  }, obj);
}

function str(v: unknown): string | null {
  if (v === null || v === undefined) return null;
  const s = String(v).trim();
  return s ? s : null;
}

function toIso(v: unknown): string | null {
  const s = str(v);
  if (!s) return null;
  if (/^\d{4}-\d{2}-\d{2}T/.test(s)) { const d = new Date(s); return Number.isFinite(d.getTime()) ? d.toISOString() : null; }
  return parseLooseDate(s) ?? findDeadline(`deadline: ${s}`);
}

export function mapRecord(rec: unknown, mapping: Record<string, string>, base: string | null): RawItem['draft'] {
  const g = (k: string) => (mapping[k] ? getPath(rec, mapping[k]) : undefined);
  const abs = (u: unknown) => { const s = str(u); if (!s) return null; try { return new URL(s, base ?? undefined).toString(); } catch { return null; } };
  const amount = g('amount_min_pkr');
  return {
    title: str(g('title')) ?? '',
    summary: str(g('summary')),
    description: str(g('description')),
    eligibility_summary: str(g('eligibility_summary')),
    deadline: toIso(g('deadline')),
    opening_date: toIso(g('opening_date')),
    source_url: abs(g('source_url')),
    official_application_url: abs(g('official_application_url')),
    amount_text: str(g('amount_text')),
    amount_min_pkr: amount === undefined || amount === null || amount === '' ? null : Number(amount) || null,
    location_text: str(g('location_text')),
    organization_name: str(g('organization_name')),
    category_slug: str(g('category_slug')),
  };
}

async function authHeaders(source: DataSourceRow, cfg: ApiConfig, ctx: ConnectorContext): Promise<Record<string, string>> {
  if (source.auth_method === 'none') return {};
  const secret = readSecretRef(source.secret_ref);
  if (!secret) throw new ConnectorConfigError(`Credential ${source.secret_ref ?? '(secret_ref not set)'} is not configured in the backend environment.`);
  switch (source.auth_method) {
    case 'api_key_header': return { [cfg.api_key_header ?? 'X-API-Key']: secret };
    case 'bearer_token': return { Authorization: `Bearer ${secret}` };
    case 'basic': return { Authorization: `Basic ${btoa(secret)}` };
    case 'oauth2_client_credentials': {
      if (!cfg.token_url) throw new ConnectorConfigError('token_url is required for OAuth2 client credentials.');
      const [id, sec] = secret.split(':');
      const res = await ctx.fetch(cfg.token_url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({ grant_type: 'client_credentials', client_id: id ?? '', client_secret: sec ?? '' }).toString(),
      });
      if (!res.ok) throw new ConnectorConfigError(`OAuth token request failed (${res.status}).`);
      const tok = await res.json() as { access_token?: string };
      if (!tok.access_token) throw new ConnectorConfigError('OAuth token response had no access_token.');
      return { Authorization: `Bearer ${tok.access_token}` };
    }
  }
}

export const apiConnector: Connector = {
  validateConfig(source) {
    const c = source.config as Partial<ApiConfig>;
    if (!c.endpoint) throw new ConnectorConfigError('config.endpoint is required');
    if (!c.mapping || !c.mapping.title) throw new ConnectorConfigError('config.mapping.title is required');
    const url = new URL(c.endpoint, source.base_url ?? undefined);
    if (url.protocol !== 'https:') throw new ConnectorConfigError('API endpoint must use HTTPS');
    if (source.auth_method !== 'none' && !source.secret_ref) throw new ConnectorConfigError('secret_ref is required for authenticated APIs');
  },

  async fetchItems(source, ctx) {
    this.validateConfig(source);
    const cfg = source.config as unknown as ApiConfig;
    const headers = { ...(await authHeaders(source, cfg, ctx)), Accept: 'application/json' };
    const http = new PoliteFetcher(ctx, { ratePerMinute: source.rate_limit_per_minute, respectRobots: false, headers });
    const p = cfg.pagination ?? { type: 'none' };
    const maxPages = Math.min(p.max_pages ?? 10, 100);
    const items: RawItem[] = [];
    let cursor: string | null = null;

    for (let page = 0; page < maxPages; page++) {
      const url = new URL(cfg.endpoint, source.base_url ?? undefined);
      Object.entries(cfg.query ?? {}).forEach(([k, v]) => url.searchParams.set(k, v));
      if (p.size_param && p.size) url.searchParams.set(p.size_param, String(p.size));
      if (p.type === 'page') url.searchParams.set(p.param ?? 'page', String((p.start ?? 1) + page));
      if (p.type === 'offset') url.searchParams.set(p.param ?? 'offset', String(page * (p.size ?? 50)));
      if (p.type === 'cursor' && cursor) url.searchParams.set(p.cursor_param ?? 'cursor', cursor);

      const res = await http.get(url.toString(), 'application/json');
      const body = await res.json();
      const list = getPath(body, cfg.items_path);
      if (!Array.isArray(list)) throw new ConnectorConfigError(`items_path "${cfg.items_path ?? ''}" did not resolve to an array`);
      for (const rec of list) {
        const draft = mapRecord(rec, cfg.mapping, source.base_url);
        const id = str(getPath(rec, cfg.id_path ?? 'id')) ?? draft.official_application_url ?? draft.source_url ?? draft.title;
        items.push({ externalId: id, url: draft.source_url ?? null, raw: rec as Record<string, unknown>, draft });
      }
      if (p.type === 'none' || list.length === 0) break;
      if (p.type === 'cursor') {
        cursor = str(getPath(body, p.next_cursor_path ?? 'next'));
        if (!cursor) break;
      } else if (p.size && list.length < p.size) break;
    }
    ctx.log(`api: ${items.length} items from ${source.name}`);
    return items;
  },
};
