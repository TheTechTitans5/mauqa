// POST /functions/v1/source-sync
//   { "source_id": uuid }   → manual sync by an admin (Authorization: user JWT with admin role)
//   {} + x-cron-secret       → scheduled run of all due sources
import { bearer, handle, HttpError, json, readJson, requireUuid, safeEqual } from '../_shared/http.ts';
import { env } from '../_shared/env.ts';
import { Rest } from '../_shared/rest.ts';
import { restSyncStore, syncSource } from '../_shared/sync.ts';
import type { ConnectorContext, DataSourceRow } from '../_shared/connectors/types.ts';

const ctx: ConnectorContext = {
  fetch: (i, init) => fetch(i, init),
  sleep: (ms) => new Promise((r) => setTimeout(r, ms)),
  log: (m, d) => console.log(m, d ?? ''),
  now: () => new Date(),
};

Deno.serve(handle(async (req) => {
  if (req.method !== 'POST') throw new HttpError(405, 'Use POST', 'method_not_allowed');
  const service = Rest.service();
  const store = restSyncStore(service);
  const cronSecret = env('CRON_SECRET');
  const provided = req.headers.get('x-cron-secret');

  if (provided) {
    if (!cronSecret || !safeEqual(provided, cronSecret)) throw new HttpError(401, 'Invalid cron secret', 'unauthenticated');
    const due = await service.select<DataSourceRow>('data_sources',
      `select=*&is_enabled=eq.true&integration_status=eq.active&or=(next_sync_at.is.null,next_sync_at.lte.${new Date().toISOString()})&limit=10`);
    const results = [];
    for (const s of due) results.push({ source_id: s.id, ...(await syncSource(s, store, ctx, { triggeredBy: 'schedule' })) });
    return json({ ran: results.length, results });
  }

  const userDb = Rest.user(bearer(req));
  const user = await userDb.authUser();
  const roles = await userDb.rpc<string[]>('my_roles');
  if (!roles.some((r) => r === 'admin' || r === 'super_admin')) throw new HttpError(403, 'Admins only', 'forbidden');
  const body = await readJson<{ source_id?: unknown }>(req);
  const id = requireUuid(body.source_id, 'source_id');
  const [source] = await service.select<DataSourceRow>('data_sources', `select=*&id=eq.${id}`);
  if (!source) throw new HttpError(404, 'Source not found', 'not_found');
  const summary = await syncSource(source, store, ctx, { triggeredBy: 'manual', userId: user.id });
  return json(summary);
}));
