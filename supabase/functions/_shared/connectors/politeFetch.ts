// Polite HTTP: robots.txt enforcement, per-source rate limiting, bounded retries with backoff,
// and refusal to deal with login walls / CAPTCHAs (we never try to bypass access controls).
import { isAllowed, parseRobots, userAgent } from '../robots.ts';
import type { ConnectorContext } from './types.ts';
import { ConnectorBlockedError } from './types.ts';

export interface PoliteOptions { ratePerMinute: number; respectRobots: boolean; maxRetries?: number; headers?: Record<string, string> }

export class PoliteFetcher {
  private last = 0;
  private robots = new Map<string, ReturnType<typeof parseRobots> | null>();
  constructor(private ctx: ConnectorContext, private o: PoliteOptions) {}

  private async throttle(extraDelaySec = 0) {
    const gap = Math.max(60_000 / Math.max(1, this.o.ratePerMinute), extraDelaySec * 1000);
    const wait = this.last + gap - this.ctx.now().getTime();
    if (wait > 0) await this.ctx.sleep(wait);
    this.last = this.ctx.now().getTime();
  }

  async robotsCheck(url: string): Promise<number | undefined> {
    if (!this.o.respectRobots) return undefined;
    const origin = new URL(url).origin;
    if (!this.robots.has(origin)) {
      try {
        const r = await this.ctx.fetch(`${origin}/robots.txt`, { headers: { 'User-Agent': userAgent() } });
        this.robots.set(origin, r.ok ? parseRobots(await r.text()) : r.status >= 500 ? null : []);
      } catch { this.robots.set(origin, null); }
    }
    const groups = this.robots.get(origin);
    if (groups === null) throw new ConnectorBlockedError(`robots.txt for ${origin} could not be read; not fetching (fail-closed).`);
    const verdict = isAllowed(groups ?? [], url);
    if (!verdict.allowed) throw new ConnectorBlockedError(`robots.txt disallows ${url}`);
    return verdict.crawlDelay;
  }

  async get(url: string, accept = 'text/html,application/xhtml+xml,application/xml,application/json'): Promise<Response> {
    const crawlDelay = await this.robotsCheck(url);
    const max = this.o.maxRetries ?? 3;
    let lastErr: unknown;
    for (let attempt = 1; attempt <= max; attempt++) {
      await this.throttle(crawlDelay);
      try {
        const res = await this.ctx.fetch(url, { headers: { 'User-Agent': userAgent(), Accept: accept, ...(this.o.headers ?? {}) }, redirect: 'follow' });
        if (res.status === 401 || res.status === 403) {
          throw new ConnectorBlockedError(`Access denied (${res.status}) for ${url}. Authorisation is required; not retrying.`);
        }
        if (res.status === 429 || res.status >= 500) {
          const retryAfter = Number(res.headers.get('retry-after') ?? '0');
          lastErr = new Error(`HTTP ${res.status} for ${url}`);
          await this.ctx.sleep(Math.max(retryAfter * 1000, 2 ** attempt * 1000));
          continue;
        }
        if (!res.ok) throw new Error(`HTTP ${res.status} for ${url}`);
        return res;
      } catch (e) {
        if (e instanceof ConnectorBlockedError) throw e;
        lastErr = e;
        if (attempt < max) await this.ctx.sleep(2 ** attempt * 1000);
      }
    }
    throw lastErr instanceof Error ? lastErr : new Error(String(lastErr));
  }

  /** Detects pages that are clearly behind a login or CAPTCHA so we stop instead of bypassing. */
  static assertNotGated(html: string, url: string) {
    if (/g-recaptcha|hcaptcha|cf-challenge|captcha-container/i.test(html)) {
      throw new ConnectorBlockedError(`CAPTCHA detected at ${url}; automated access is not permitted.`);
    }
    if (/<input[^>]+type=["']password["']/i.test(html) && html.length < 20000) {
      throw new ConnectorBlockedError(`Login form detected at ${url}; content requires sign-in.`);
    }
  }
}
