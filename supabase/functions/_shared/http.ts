// HTTP helpers for Edge Functions: CORS, JSON responses, typed errors, request validation, rate limiting.

export const corsHeaders: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-cron-secret',
  'Access-Control-Allow-Methods': 'GET, POST, PATCH, DELETE, OPTIONS',
};

export class HttpError extends Error {
  constructor(public status: number, message: string, public code = 'error', public details?: unknown) {
    super(message);
  }
}

export function json(body: unknown, status = 200, extra: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json; charset=utf-8', ...extra },
  });
}

export function errorResponse(e: unknown): Response {
  if (e instanceof HttpError) return json({ error: { code: e.code, message: e.message, details: e.details } }, e.status);
  console.error('Unhandled error', e);
  return json({ error: { code: 'internal', message: 'Something went wrong. Please try again.' } }, 500);
}

export async function readJson<T = Record<string, unknown>>(req: Request): Promise<T> {
  if (req.method === 'GET' || req.method === 'DELETE') return {} as T;
  const len = Number(req.headers.get('content-length') ?? '0');
  if (len > 256_000) throw new HttpError(413, 'Request body too large', 'payload_too_large');
  try {
    const text = await req.text();
    return (text ? JSON.parse(text) : {}) as T;
  } catch {
    throw new HttpError(400, 'Body must be valid JSON', 'bad_json');
  }
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function isUuid(v: unknown): v is string { return typeof v === 'string' && UUID_RE.test(v); }
export function requireUuid(v: unknown, field: string): string {
  if (!isUuid(v)) throw new HttpError(422, `${field} must be a UUID`, 'validation');
  return v;
}

export function bearer(req: Request): string {
  const h = req.headers.get('authorization') ?? '';
  const m = /^Bearer\s+(.+)$/i.exec(h);
  if (!m) throw new HttpError(401, 'Sign in required', 'unauthenticated');
  return m[1];
}

/** Constant-time comparison for shared secrets. */
export function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}

/** Simple in-memory token bucket per key (per isolate). Good enough to blunt abuse of a single instance. */
export class RateLimiter {
  private hits = new Map<string, number[]>();
  constructor(private limit: number, private windowMs: number) {}
  check(key: string, now = Date.now()): void {
    const arr = (this.hits.get(key) ?? []).filter((t) => now - t < this.windowMs);
    if (arr.length >= this.limit) throw new HttpError(429, 'Too many requests, slow down', 'rate_limited');
    arr.push(now);
    this.hits.set(key, arr);
  }
}

export function handle(fn: (req: Request) => Promise<Response>): (req: Request) => Promise<Response> {
  return async (req) => {
    if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
    try { return await fn(req); } catch (e) { return errorResponse(e); }
  };
}
