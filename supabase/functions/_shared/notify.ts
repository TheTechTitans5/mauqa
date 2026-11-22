// Notification channels. Each channel reports whether it is configured; unconfigured channels are skipped
// (recorded as "skipped") instead of pretending to deliver.
import { env } from './env.ts';
import type { FetchLike } from './rest.ts';

export interface OutboundMessage { title: string; body: string; data?: Record<string, string> }
export interface ChannelResult { ok: boolean; skipped?: boolean; error?: string; invalidTokens?: string[] }

export interface Channel {
  name: 'push' | 'email' | 'sms' | 'whatsapp';
  configured(): boolean;
}

// ---------------------------------------------------------------- FCM HTTP v1
interface ServiceAccount { client_email: string; private_key: string; project_id: string }

function b64url(data: ArrayBuffer | Uint8Array | string): string {
  const bytes = typeof data === 'string' ? new TextEncoder().encode(data) : new Uint8Array(data);
  let s = '';
  bytes.forEach((b) => { s += String.fromCharCode(b); });
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const der = Uint8Array.from(atob(pem.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '')), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey('pkcs8', der, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
}

export async function signServiceAccountJwt(sa: ServiceAccount, scope: string, nowSec = Math.floor(Date.now() / 1000)): Promise<string> {
  const header = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claims = b64url(JSON.stringify({ iss: sa.client_email, scope, aud: 'https://oauth2.googleapis.com/token', iat: nowSec, exp: nowSec + 3600 }));
  const key = await importPrivateKey(sa.private_key);
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(`${header}.${claims}`));
  return `${header}.${claims}.${b64url(sig)}`;
}

export class FcmChannel implements Channel {
  name = 'push' as const;
  private token: { value: string; exp: number } | null = null;
  constructor(private f: FetchLike = (i, init) => fetch(i, init)) {}
  private sa(): ServiceAccount | null {
    const raw = env('FCM_SERVICE_ACCOUNT_JSON');
    if (!raw) return null;
    try { return JSON.parse(raw) as ServiceAccount; } catch { return null; }
  }
  configured() { return this.sa() !== null; }
  private async accessToken(sa: ServiceAccount): Promise<string> {
    if (this.token && this.token.exp > Date.now() + 60_000) return this.token.value;
    const assertion = await signServiceAccountJwt(sa, 'https://www.googleapis.com/auth/firebase.messaging');
    const res = await this.f('https://oauth2.googleapis.com/token', {
      method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }).toString(),
    });
    if (!res.ok) throw new Error(`FCM auth failed (${res.status})`);
    const j = await res.json() as { access_token: string; expires_in: number };
    this.token = { value: j.access_token, exp: Date.now() + j.expires_in * 1000 };
    return j.access_token;
  }
  async send(tokens: string[], msg: OutboundMessage): Promise<ChannelResult> {
    const sa = this.sa();
    if (!sa) return { ok: false, skipped: true, error: 'FCM not configured' };
    if (tokens.length === 0) return { ok: false, skipped: true, error: 'No registered devices' };
    const access = await this.accessToken(sa);
    const invalid: string[] = [];
    let delivered = 0;
    for (const token of tokens) {
      const res = await this.f(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
        method: 'POST', headers: { Authorization: `Bearer ${access}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ message: { token, notification: { title: msg.title, body: msg.body }, data: msg.data ?? {},
          android: { priority: 'high', notification: { channel_id: 'mauqa_deadlines' } } } }),
      });
      if (res.ok) delivered++;
      else if (res.status === 404 || res.status === 400) invalid.push(token);
    }
    return { ok: delivered > 0, invalidTokens: invalid, error: delivered ? undefined : 'No device accepted the message' };
  }
}

// ---------------------------------------------------------------- Email (Resend HTTP API; swap provider by implementing send)
export class EmailChannel implements Channel {
  name = 'email' as const;
  constructor(private f: FetchLike = (i, init) => fetch(i, init)) {}
  configured() { return Boolean(env('RESEND_API_KEY') && env('EMAIL_FROM')); }
  async send(to: string | null | undefined, msg: OutboundMessage): Promise<ChannelResult> {
    if (!this.configured()) return { ok: false, skipped: true, error: 'Email not configured' };
    if (!to) return { ok: false, skipped: true, error: 'User has no email' };
    const res = await this.f('https://api.resend.com/emails', {
      method: 'POST', headers: { Authorization: `Bearer ${env('RESEND_API_KEY')}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ from: env('EMAIL_FROM'), to: [to], subject: msg.title, text: `${msg.body}\n\n— Mauqa\nManage notifications in the app: Profile → Settings → Notifications.` }),
    });
    return res.ok ? { ok: true } : { ok: false, error: `Email provider returned ${res.status}` };
  }
}

// ---------------------------------------------------------------- SMS (generic HTTPS gateway — Pakistani providers differ)
export class SmsChannel implements Channel {
  name = 'sms' as const;
  constructor(private f: FetchLike = (i, init) => fetch(i, init)) {}
  configured() { return Boolean(env('SMS_GATEWAY_URL') && env('SMS_GATEWAY_TOKEN')); }
  async send(phone: string | null | undefined, msg: OutboundMessage): Promise<ChannelResult> {
    if (!this.configured()) return { ok: false, skipped: true, error: 'SMS gateway not configured' };
    if (!phone) return { ok: false, skipped: true, error: 'User has no phone' };
    const res = await this.f(env('SMS_GATEWAY_URL')!, {
      method: 'POST', headers: { Authorization: `Bearer ${env('SMS_GATEWAY_TOKEN')}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ to: phone, sender: env('SMS_SENDER_ID') ?? 'Mauqa', message: `${msg.title}: ${msg.body}`.slice(0, 300) }),
    });
    return res.ok ? { ok: true } : { ok: false, error: `SMS gateway returned ${res.status}` };
  }
}

// ---------------------------------------------------------------- WhatsApp Business (Meta Cloud API; needs an approved template)
export class WhatsAppChannel implements Channel {
  name = 'whatsapp' as const;
  constructor(private f: FetchLike = (i, init) => fetch(i, init)) {}
  configured() { return Boolean(env('WHATSAPP_TOKEN') && env('WHATSAPP_PHONE_NUMBER_ID') && env('WHATSAPP_TEMPLATE_NAME')); }
  async send(phone: string | null | undefined, msg: OutboundMessage): Promise<ChannelResult> {
    if (!this.configured()) return { ok: false, skipped: true, error: 'WhatsApp Business not configured' };
    if (!phone) return { ok: false, skipped: true, error: 'User has no phone' };
    const version = env('WHATSAPP_API_VERSION') ?? 'v21.0';
    const res = await this.f(`https://graph.facebook.com/${version}/${env('WHATSAPP_PHONE_NUMBER_ID')}/messages`, {
      method: 'POST', headers: { Authorization: `Bearer ${env('WHATSAPP_TOKEN')}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        messaging_product: 'whatsapp', to: phone.replace(/^\+/, ''), type: 'template',
        template: { name: env('WHATSAPP_TEMPLATE_NAME'), language: { code: env('WHATSAPP_TEMPLATE_LANG') ?? 'en' },
          components: [{ type: 'body', parameters: [{ type: 'text', text: msg.title }, { type: 'text', text: msg.body.slice(0, 900) }] }] },
      }),
    });
    return res.ok ? { ok: true } : { ok: false, error: `WhatsApp API returned ${res.status}` };
  }
}

// ---------------------------------------------------------------- Delivery policy (pure)
export interface Prefs {
  push_enabled: boolean; email_enabled: boolean; sms_enabled: boolean; whatsapp_enabled: boolean;
  quiet_hours_start: number | null; quiet_hours_end: number | null;
}

/** Hour-of-day in Pakistan (UTC+5, no DST). */
export function pktHour(d: Date): number { return (d.getUTCHours() + 5) % 24; }

export function inQuietHours(p: Prefs, now: Date): boolean {
  if (p.quiet_hours_start == null || p.quiet_hours_end == null || p.quiet_hours_start === p.quiet_hours_end) return false;
  const h = pktHour(now);
  return p.quiet_hours_start < p.quiet_hours_end
    ? h >= p.quiet_hours_start && h < p.quiet_hours_end
    : h >= p.quiet_hours_start || h < p.quiet_hours_end;
}

const EMAIL_TYPES = new Set(['deadline_changed', 'closing_soon', 'interview_reminder', 'opportunity_closed', 'interested_deadline', 'document_expiry']);
const SMS_TYPES = new Set(['closing_soon', 'interview_reminder']);

export function channelsFor(type: string, p: Prefs, now: Date): { push: boolean; email: boolean; sms: boolean; whatsapp: boolean; deferPush: boolean } {
  const quiet = inQuietHours(p, now);
  return {
    push: p.push_enabled && type !== 'system',
    deferPush: p.push_enabled && quiet && type !== 'interview_reminder',
    email: p.email_enabled && EMAIL_TYPES.has(type),
    sms: p.sms_enabled && SMS_TYPES.has(type),
    whatsapp: p.whatsapp_enabled && SMS_TYPES.has(type),
  };
}
