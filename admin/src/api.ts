// Minimal Supabase client for the admin dashboard (no third-party dependencies).
// Uses the PUBLIC anon key + the signed-in staff member's JWT. All permissions are enforced by RLS and
// role checks inside SQL functions — this dashboard has no special access of its own.

export interface AdminConfig { supabaseUrl: string; anonKey: string }
export interface Session { access_token: string; refresh_token: string; expires_at: number; user: { id: string; email?: string } }

export class ApiError extends Error {
  constructor(message: string, public status: number, public code?: string) { super(message); }
}

const SESSION_KEY = 'mauqa.admin.session';

export class Api {
  session: Session | null = null;
  constructor(public cfg: AdminConfig, private storage: Pick<Storage, 'getItem' | 'setItem' | 'removeItem'> | null = null,
    private f: typeof fetch = (i, init) => fetch(i, init)) {
    try {
      const raw = storage?.getItem(SESSION_KEY);
      if (raw) this.session = JSON.parse(raw) as Session;
    } catch { this.session = null; }
  }

  private headers(extra: Record<string, string> = {}): Record<string, string> {
    return { apikey: this.cfg.anonKey, Authorization: `Bearer ${this.session?.access_token ?? this.cfg.anonKey}`, 'Content-Type': 'application/json', ...extra };
  }

  private save(s: Session | null) {
    this.session = s;
    try { if (s) this.storage?.setItem(SESSION_KEY, JSON.stringify(s)); else this.storage?.removeItem(SESSION_KEY); } catch { /* private mode */ }
  }

  async signIn(email: string, password: string): Promise<void> {
    const r = await this.f(`${this.cfg.supabaseUrl}/auth/v1/token?grant_type=password`, {
      method: 'POST', headers: { apikey: this.cfg.anonKey, 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password }),
    });
    const j = await r.json().catch(() => ({}));
    if (!r.ok) throw new ApiError((j as { error_description?: string; msg?: string }).error_description ?? (j as { msg?: string }).msg ?? 'Sign-in failed', r.status);
    const s = j as { access_token: string; refresh_token: string; expires_in: number; user: Session['user'] };
    this.save({ access_token: s.access_token, refresh_token: s.refresh_token, expires_at: Date.now() + s.expires_in * 1000, user: s.user });
  }

  async refreshIfNeeded(): Promise<void> {
    if (!this.session || this.session.expires_at - Date.now() > 60_000) return;
    const r = await this.f(`${this.cfg.supabaseUrl}/auth/v1/token?grant_type=refresh_token`, {
      method: 'POST', headers: { apikey: this.cfg.anonKey, 'Content-Type': 'application/json' }, body: JSON.stringify({ refresh_token: this.session.refresh_token }),
    });
    if (!r.ok) { this.save(null); throw new ApiError('Session expired — please sign in again', 401); }
    const s = await r.json() as { access_token: string; refresh_token: string; expires_in: number; user: Session['user'] };
    this.save({ access_token: s.access_token, refresh_token: s.refresh_token, expires_at: Date.now() + s.expires_in * 1000, user: s.user });
  }

  signOut() { this.save(null); }

  private async req<T>(method: string, path: string, body?: unknown, extra: Record<string, string> = {}): Promise<T> {
    await this.refreshIfNeeded();
    const r = await this.f(`${this.cfg.supabaseUrl}${path}`, { method, headers: this.headers(extra), body: body === undefined ? undefined : JSON.stringify(body) });
    const text = await r.text();
    const data = text ? JSON.parse(text) : null;
    if (!r.ok) {
      const d = (data ?? {}) as { message?: string; code?: string; error?: { message?: string } };
      throw new ApiError(d.message ?? d.error?.message ?? r.statusText, r.status, d.code);
    }
    return data as T;
  }

  select<T>(table: string, query: string): Promise<T[]> { return this.req<T[]>('GET', `/rest/v1/${table}?${query}`); }
  insert<T>(table: string, row: unknown): Promise<T[]> { return this.req<T[]>('POST', `/rest/v1/${table}`, row, { Prefer: 'return=representation' }); }
  update<T>(table: string, query: string, patch: unknown): Promise<T[]> { return this.req<T[]>('PATCH', `/rest/v1/${table}?${query}`, patch, { Prefer: 'return=representation' }); }
  remove(table: string, query: string): Promise<null> { return this.req<null>('DELETE', `/rest/v1/${table}?${query}`); }
  rpc<T>(fn: string, args: Record<string, unknown> = {}): Promise<T> { return this.req<T>('POST', `/rest/v1/rpc/${fn}`, args); }
  fn<T>(name: string, body: unknown): Promise<T> { return this.req<T>('POST', `/functions/v1/${name}`, body); }
  async count(table: string, query: string): Promise<number> {
    await this.refreshIfNeeded();
    const r = await this.f(`${this.cfg.supabaseUrl}/rest/v1/${table}?${query}`, { method: 'HEAD', headers: this.headers({ Prefer: 'count=exact' }) });
    const range = r.headers.get('content-range') ?? '*/0';
    return Number(range.split('/')[1] ?? 0) || 0;
  }
}

export const enc = encodeURIComponent;
