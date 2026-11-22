// Minimal, dependency-free client for Supabase REST (PostgREST), Auth and Storage.
// Two modes:
//   - user client: uses the caller's JWT → Row Level Security applies
//   - service client: uses the service-role key → server-side jobs only, never exposed to users
import { HttpError } from './http.ts';
import { requireEnv } from './env.ts';

export type FetchLike = (input: string, init?: RequestInit) => Promise<Response>;

export interface RestOptions { url: string; apiKey: string; token: string; fetch?: FetchLike }

export class Rest {
  private f: FetchLike;
  constructor(private o: RestOptions) { this.f = o.fetch ?? ((i, init) => fetch(i, init)); }

  static user(token: string, fetchImpl?: FetchLike): Rest {
    return new Rest({ url: requireEnv('SUPABASE_URL'), apiKey: requireEnv('SUPABASE_ANON_KEY'), token, fetch: fetchImpl });
  }
  static service(fetchImpl?: FetchLike): Rest {
    const key = requireEnv('SUPABASE_SERVICE_ROLE_KEY');
    return new Rest({ url: requireEnv('SUPABASE_URL'), apiKey: key, token: key, fetch: fetchImpl });
  }

  private headers(extra: Record<string, string> = {}): Record<string, string> {
    return { apikey: this.o.apiKey, Authorization: `Bearer ${this.o.token}`, 'Content-Type': 'application/json', ...extra };
  }

  private async send<T>(method: string, path: string, body?: unknown, extra: Record<string, string> = {}): Promise<T> {
    const res = await this.f(`${this.o.url}${path}`, {
      method, headers: this.headers(extra), body: body === undefined ? undefined : JSON.stringify(body),
    });
    const text = await res.text();
    const data = text ? safeParse(text) : null;
    if (!res.ok) {
      const msg = (data && typeof data === 'object' && 'message' in data) ? String((data as { message: unknown }).message) : res.statusText;
      const status = res.status === 401 ? 401 : res.status === 403 ? 403 : res.status === 404 ? 404 : res.status >= 500 ? 502 : 400;
      throw new HttpError(status, msg || 'Database request failed', 'db_error', data);
    }
    return data as T;
  }

  /** GET /rest/v1/{table}?{query}. `query` is a raw PostgREST query string, e.g. "select=*&id=eq.123". */
  select<T = Record<string, unknown>>(table: string, query: string): Promise<T[]> {
    return this.send<T[]>('GET', `/rest/v1/${table}?${query}`);
  }
  insert<T = Record<string, unknown>>(table: string, rows: unknown, opts: { upsert?: string; returning?: boolean } = {}): Promise<T[]> {
    const prefer = [opts.returning === false ? 'return=minimal' : 'return=representation'];
    if (opts.upsert) prefer.push('resolution=merge-duplicates');
    const q = opts.upsert ? `?on_conflict=${encodeURIComponent(opts.upsert)}` : '';
    return this.send<T[]>('POST', `/rest/v1/${table}${q}`, rows, { Prefer: prefer.join(',') }).then((r) => r ?? []);
  }
  update<T = Record<string, unknown>>(table: string, query: string, patch: unknown): Promise<T[]> {
    return this.send<T[]>('PATCH', `/rest/v1/${table}?${query}`, patch, { Prefer: 'return=representation' });
  }
  delete(table: string, query: string): Promise<unknown> {
    return this.send('DELETE', `/rest/v1/${table}?${query}`, undefined, { Prefer: 'return=minimal' });
  }
  rpc<T = unknown>(fn: string, args: Record<string, unknown> = {}): Promise<T> {
    return this.send<T>('POST', `/rest/v1/rpc/${fn}`, args);
  }

  /** Validates the bearer token with Supabase Auth and returns the user. */
  async authUser(): Promise<{ id: string; email?: string; phone?: string }> {
    const res = await this.f(`${this.o.url}/auth/v1/user`, { headers: this.headers() });
    if (!res.ok) throw new HttpError(401, 'Your session has expired. Please sign in again.', 'unauthenticated');
    return await res.json();
  }
  async adminDeleteUser(id: string): Promise<void> {
    const res = await this.f(`${this.o.url}/auth/v1/admin/users/${id}`, { method: 'DELETE', headers: this.headers() });
    if (!res.ok && res.status !== 404) throw new HttpError(502, 'Could not delete the account', 'auth_error');
  }
  async storageList(bucket: string, prefix: string): Promise<Array<{ name: string; id: string | null }>> {
    return this.sendStorage('POST', `/storage/v1/object/list/${bucket}`, { prefix, limit: 1000, offset: 0 });
  }
  async storageRemove(bucket: string, paths: string[]): Promise<void> {
    if (paths.length) await this.sendStorage('DELETE', `/storage/v1/object/${bucket}`, { prefixes: paths });
  }
  /** Short-lived signed download URL. Called with the USER client so storage RLS decides access. */
  async storageSign(bucket: string, path: string, expiresIn = 120): Promise<string> {
    const r = await this.sendStorage<{ signedURL: string }>('POST', `/storage/v1/object/sign/${bucket}/${path.split('/').map(encodeURIComponent).join('/')}`, { expiresIn });
    return `${this.o.url}/storage/v1${r.signedURL}`;
  }
  private async sendStorage<T>(method: string, path: string, body: unknown): Promise<T> {
    const res = await this.f(`${this.o.url}${path}`, { method, headers: this.headers(), body: JSON.stringify(body) });
    if (!res.ok) throw new HttpError(502, 'Storage request failed', 'storage_error', await res.text());
    return await res.json() as T;
  }
}

function safeParse(t: string): unknown { try { return JSON.parse(t); } catch { return t; } }

/** Encode a value for a PostgREST filter, e.g. eq(“a,b”) → "eq.%22a,b%22" */
export function inList(values: string[]): string {
  return `in.(${values.map((v) => `"${v.replace(/"/g, '')}"`).join(',')})`;
}
