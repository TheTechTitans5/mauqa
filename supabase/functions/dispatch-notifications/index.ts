// POST /functions/v1/dispatch-notifications   (x-cron-secret required; schedule every 10 minutes)
// 1. Turns due reminders into in-app notifications (SQL: dispatch_due_reminders, idempotent + deduplicated)
// 2. Delivers pending notifications over push / email / SMS / WhatsApp according to user preferences.
//    Unconfigured channels are marked "skipped", never "sent".
import { handle, HttpError, json, safeEqual } from '../_shared/http.ts';
import { env } from '../_shared/env.ts';
import { inList, Rest } from '../_shared/rest.ts';
import { channelsFor, EmailChannel, FcmChannel, SmsChannel, WhatsAppChannel, type Prefs } from '../_shared/notify.ts';

interface Pending {
  id: string; user_id: string; type: string; title: string; body: string; opportunity_id: string | null;
  delivery_attempts: number; push_status: string; email_status: string;
}

const fcm = new FcmChannel();
const email = new EmailChannel();
const sms = new SmsChannel();
const wa = new WhatsAppChannel();

Deno.serve(handle(async (req) => {
  const secret = env('CRON_SECRET');
  const provided = req.headers.get('x-cron-secret') ?? '';
  if (!secret || !safeEqual(provided, secret)) throw new HttpError(401, 'Invalid cron secret', 'unauthenticated');
  const db = Rest.service();

  const created = await db.rpc<number>('dispatch_due_reminders', { p_limit: 1000 });
  const pending = await db.select<Pending>('notifications',
    'select=id,user_id,type,title,body,opportunity_id,delivery_attempts,push_status,email_status&or=(push_status.eq.pending,email_status.eq.pending)&delivery_attempts=lt.5&order=created_at.asc&limit=200');
  if (pending.length === 0) return json({ reminders_converted: created, delivered: 0 });

  const userIds = [...new Set(pending.map((p) => p.user_id))];
  const [prefs, tokens, profiles] = await Promise.all([
    db.select<Prefs & { user_id: string }>('notification_preferences', `select=*&user_id=${inList(userIds)}`),
    db.select<{ user_id: string; token: string }>('device_tokens', `select=user_id,token&user_id=${inList(userIds)}`),
    db.select<{ id: string; email: string | null; phone: string | null }>('profiles', `select=id,email,phone&id=${inList(userIds)}`),
  ]);
  const prefMap = new Map(prefs.map((p) => [p.user_id, p]));
  const profMap = new Map(profiles.map((p) => [p.id, p]));
  const now = new Date();
  const stats = { push_sent: 0, email_sent: 0, sms_sent: 0, whatsapp_sent: 0, skipped: 0, failed: 0, deferred: 0 };
  const invalidTokens: string[] = [];

  for (const n of pending) {
    const p = prefMap.get(n.user_id);
    if (!p) { await db.update('notifications', `id=eq.${n.id}`, { push_status: 'skipped', email_status: 'skipped' }); continue; }
    const ch = channelsFor(n.type, p, now);
    const msg = { title: n.title, body: n.body, data: { notification_id: n.id, type: n.type, opportunity_id: n.opportunity_id ?? '' } };
    const patch: Record<string, unknown> = { delivery_attempts: n.delivery_attempts + 1 };
    const prof = profMap.get(n.user_id);

    if (n.push_status === 'pending') {
      if (!ch.push) { patch.push_status = 'skipped'; stats.skipped++; }
      else if (ch.deferPush) { stats.deferred++; delete patch.delivery_attempts; }
      else {
        const r = await fcm.send(tokens.filter((t) => t.user_id === n.user_id).map((t) => t.token), msg);
        invalidTokens.push(...(r.invalidTokens ?? []));
        patch.push_status = r.ok ? 'sent' : r.skipped ? 'skipped' : n.delivery_attempts >= 4 ? 'failed' : 'pending';
        if (r.ok) stats.push_sent++; else if (r.skipped) stats.skipped++; else stats.failed++;
      }
    }
    if (n.email_status === 'pending') {
      if (!ch.email) patch.email_status = 'skipped';
      else {
        const r = await email.send(prof?.email, msg);
        patch.email_status = r.ok ? 'sent' : r.skipped ? 'skipped' : n.delivery_attempts >= 4 ? 'failed' : 'pending';
        if (r.ok) stats.email_sent++;
      }
    }
    // SMS / WhatsApp are best-effort extras for the most time-critical alerts only.
    if (ch.sms && (await sms.send(prof?.phone, msg)).ok) stats.sms_sent++;
    if (ch.whatsapp && (await wa.send(prof?.phone, msg)).ok) stats.whatsapp_sent++;
    await db.update('notifications', `id=eq.${n.id}`, patch);
  }
  if (invalidTokens.length) await db.delete('device_tokens', `token=${inList(invalidTokens)}`);
  return json({ reminders_converted: created, processed: pending.length, ...stats,
    channels: { push: fcm.configured(), email: email.configured(), sms: sms.configured(), whatsapp: wa.configured() } });
}));
