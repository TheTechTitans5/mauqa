// Source synchronisation pipeline:
// connector → extraction → validation → duplicate/change detection → source_items (review queue) → human verification.
// Nothing fetched here is ever published directly.
import { contentHash, diffDrafts, findDuplicate, type DraftOpportunity } from './dedupe.ts';
import { hasBlockingIssue, validateDraft, type ValidationIssue } from './validate.ts';
import type { Connector, ConnectorContext, DataSourceRow, RawItem } from './connectors/types.ts';
import { ConnectorBlockedError, ConnectorConfigError } from './connectors/types.ts';
import { apiConnector } from './connectors/api.ts';
import { manualConnector, pdfConnector, rssConnector, webMonitorConnector } from './connectors/feeds.ts';
import type { Rest } from './rest.ts';

export const CONNECTORS: Record<DataSourceRow['source_type'], Connector> = {
  api: apiConnector, rss: rssConnector, web_monitor: webMonitorConnector, pdf: pdfConnector, manual: manualConnector,
};

export interface StoredItem { id: string; content_hash: string; extracted: DraftOpportunity; opportunity_id: string | null; review_status: string }

export interface NewItemRow {
  source_id: string; external_id: string; item_url: string | null; raw: Record<string, unknown>; extracted: DraftOpportunity;
  content_hash: string; opportunity_id: string | null; review_status: 'pending' | 'duplicate'; duplicate_of: string | null;
  duplicate_score: number | null; detected_changes: Record<string, unknown> | null; validation_issues: ValidationIssue[];
}

export interface SyncStore {
  startLog(sourceId: string, triggeredBy: 'schedule' | 'manual', userId: string | null, attempt: number): Promise<string>;
  finishLog(logId: string, patch: Record<string, unknown>): Promise<void>;
  latestItem(sourceId: string, externalId: string): Promise<StoredItem | null>;
  touchItem(id: string): Promise<void>;
  insertItem(row: NewItemRow): Promise<void>;
  markSuperseded(id: string): Promise<void>;
  candidates(organizationId: string | null): Promise<Array<DraftOpportunity & { id: string }>>;
  touchOpportunity(id: string): Promise<void>;
  updateSource(id: string, patch: Record<string, unknown>): Promise<void>;
  officialDomains(organizationId: string | null): Promise<string[]>;
  alertAdmins(title: string, body: string, dedupeKey: string): Promise<void>;
}

export interface SyncSummary {
  status: 'success' | 'partial' | 'failed' | 'skipped';
  found: number; created: number; changed: number; unchanged: number; duplicates: number; invalid: number;
  message?: string;
}

export async function syncSource(
  source: DataSourceRow, store: SyncStore, ctx: ConnectorContext,
  opts: { triggeredBy: 'schedule' | 'manual'; userId?: string | null; maxAttempts?: number; connectors?: typeof CONNECTORS } = { triggeredBy: 'schedule' },
): Promise<SyncSummary> {
  const empty = { found: 0, created: 0, changed: 0, unchanged: 0, duplicates: 0, invalid: 0 };
  const connectors = opts.connectors ?? CONNECTORS;

  if (source.source_type === 'manual') {
    const logId = await store.startLog(source.id, opts.triggeredBy, opts.userId ?? null, 1);
    await store.finishLog(logId, { status: 'skipped', error_message: 'Manual source: opportunities are entered by admins.' });
    return { status: 'skipped', ...empty, message: 'manual source' };
  }
  if (!source.is_enabled || source.integration_status !== 'active') {
    const logId = await store.startLog(source.id, opts.triggeredBy, opts.userId ?? null, 1);
    const msg = `Source is ${source.is_enabled ? source.integration_status.replace(/_/g, ' ') : 'disabled'}; no data was fetched.`;
    await store.finishLog(logId, { status: 'skipped', error_message: msg });
    return { status: 'skipped', ...empty, message: msg };
  }

  const maxAttempts = opts.maxAttempts ?? 3;
  let lastError: unknown;
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    const logId = await store.startLog(source.id, opts.triggeredBy, opts.userId ?? null, attempt);
    try {
      const connector = connectors[source.source_type];
      const raw = await connector.fetchItems(source, ctx);
      const counts = await processItems(source, raw, store, ctx);
      const status: SyncSummary['status'] = counts.errors > 0 ? 'partial' : 'success';
      await store.finishLog(logId, {
        status, finished_at: ctx.now().toISOString(), items_found: raw.length, items_new: counts.created,
        items_changed: counts.changed, items_unchanged: counts.unchanged, items_duplicate: counts.duplicates,
        items_invalid: counts.invalid, details: { item_errors: counts.errorMessages.slice(0, 20) },
      });
      const now = ctx.now();
      await store.updateSource(source.id, {
        last_sync_at: now.toISOString(), last_success_at: now.toISOString(), consecutive_failures: 0,
        next_sync_at: new Date(now.getTime() + source.sync_interval_minutes * 60_000).toISOString(),
      });
      return { status, found: raw.length, created: counts.created, changed: counts.changed, unchanged: counts.unchanged,
        duplicates: counts.duplicates, invalid: counts.invalid };
    } catch (e) {
      lastError = e;
      const msg = e instanceof Error ? e.message : String(e);
      await store.finishLog(logId, { status: 'failed', finished_at: ctx.now().toISOString(), error_message: msg.slice(0, 2000) });
      ctx.log(`sync attempt ${attempt} failed for ${source.name}: ${msg}`);
      if (e instanceof ConnectorConfigError || e instanceof ConnectorBlockedError) break; // retrying will not help
      if (attempt < maxAttempts) await ctx.sleep(2 ** attempt * 1000);
    }
  }

  const failures = source.consecutive_failures + 1;
  const now = ctx.now();
  const msg = lastError instanceof Error ? lastError.message : String(lastError);
  const blocked = lastError instanceof ConnectorConfigError || lastError instanceof ConnectorBlockedError;
  await store.updateSource(source.id, {
    last_sync_at: now.toISOString(), consecutive_failures: failures,
    integration_status: blocked ? 'error' : source.integration_status,
    next_sync_at: new Date(now.getTime() + Math.min(source.sync_interval_minutes, 60 * 2 ** Math.min(failures, 5)) * 60_000).toISOString(),
  });
  if (blocked || failures >= 3) {
    await store.alertAdmins(`Data source needs attention: ${source.name}`, msg.slice(0, 300),
      `sync-failure:${source.id}:${now.toISOString().slice(0, 10)}`);
  }
  return { status: 'failed', ...empty, message: msg };
}

async function processItems(source: DataSourceRow, items: RawItem[], store: SyncStore, ctx: ConnectorContext) {
  const domains = await store.officialDomains(source.organization_id);
  const candidates = await store.candidates(source.organization_id);
  const c = { created: 0, changed: 0, unchanged: 0, duplicates: 0, invalid: 0, errors: 0, errorMessages: [] as string[] };
  const seen = new Set<string>();
  for (const item of items) {
    if (seen.has(item.externalId)) continue;
    seen.add(item.externalId);
    try {
      const draft: DraftOpportunity = { ...item.draft, organization_id: source.organization_id };
      const hash = await contentHash(draft);
      const issues = validateDraft(draft, domains, ctx.now());
      if (hasBlockingIssue(issues)) c.invalid++;
      const prev = await store.latestItem(source.id, item.externalId);
      if (prev && prev.content_hash === hash) {
        await store.touchItem(prev.id);
        if (prev.opportunity_id) await store.touchOpportunity(prev.opportunity_id);
        c.unchanged++;
        continue;
      }
      if (prev) {
        await store.insertItem({
          source_id: source.id, external_id: item.externalId, item_url: item.url, raw: item.raw, extracted: draft,
          content_hash: hash, opportunity_id: prev.opportunity_id, review_status: 'pending', duplicate_of: null,
          duplicate_score: null, detected_changes: diffDrafts(prev.extracted, draft), validation_issues: issues,
        });
        if (prev.review_status === 'pending') await store.markSuperseded(prev.id);
        c.changed++;
        continue;
      }
      const dup = findDuplicate(draft, candidates);
      await store.insertItem({
        source_id: source.id, external_id: item.externalId, item_url: item.url, raw: item.raw, extracted: draft,
        content_hash: hash, opportunity_id: null, review_status: dup ? 'duplicate' : 'pending',
        duplicate_of: dup?.match.id ?? null, duplicate_score: dup?.score ?? null, detected_changes: null, validation_issues: issues,
      });
      if (dup) c.duplicates++; else c.created++;
    } catch (e) {
      c.errors++;
      c.errorMessages.push(`${item.externalId}: ${e instanceof Error ? e.message : String(e)}`);
    }
  }
  return c;
}

/** Production SyncStore backed by Supabase REST with the service role. */
export function restSyncStore(db: Rest): SyncStore {
  const enc = encodeURIComponent;
  return {
    async startLog(sourceId, triggeredBy, userId, attempt) {
      const [row] = await db.insert<{ id: string }>('source_sync_logs', {
        source_id: sourceId, triggered_by: triggeredBy, triggered_by_user: userId, attempt, status: 'running',
      });
      return row.id;
    },
    async finishLog(id, patch) { await db.update('source_sync_logs', `id=eq.${id}`, { finished_at: new Date().toISOString(), ...patch }); },
    async latestItem(sourceId, externalId) {
      const rows = await db.select<StoredItem>('source_items',
        `select=id,content_hash,extracted,opportunity_id,review_status&source_id=eq.${sourceId}&external_id=eq.${enc(externalId)}&order=first_seen_at.desc&limit=1`);
      return rows[0] ?? null;
    },
    async touchItem(id) { await db.update('source_items', `id=eq.${id}`, { last_seen_at: new Date().toISOString() }); },
    async insertItem(row) { await db.insert('source_items', row, { returning: false }); },
    async markSuperseded(id) { await db.update('source_items', `id=eq.${id}`, { review_status: 'superseded' }); },
    async candidates(orgId) {
      const filter = orgId ? `&organization_id=eq.${orgId}` : '';
      return db.select<DraftOpportunity & { id: string }>('opportunities',
        `select=id,title,organization_id,source_url,official_application_url,deadline&status=neq.cancelled${filter}&order=created_at.desc&limit=500`);
    },
    async touchOpportunity(id) { await db.update('opportunities', `id=eq.${id}`, { last_checked_at: new Date().toISOString() }); },
    async updateSource(id, patch) { await db.update('data_sources', `id=eq.${id}`, patch); },
    async officialDomains(orgId) {
      if (!orgId) return [];
      const rows = await db.select<{ official_domains: string[] }>('organizations', `select=official_domains&id=eq.${orgId}`);
      return rows[0]?.official_domains ?? [];
    },
    async alertAdmins(title, body, dedupeKey) {
      const admins = await db.select<{ user_id: string }>('user_roles', 'select=user_id&role=in.(admin,super_admin)');
      if (!admins.length) return;
      // one insert per admin: an existing dedupe key (already alerted today) must not block the others
      for (const a of admins) {
        await db.insert('notifications', { user_id: a.user_id, type: 'system', title, body, dedupe_key: dedupeKey }, { returning: false })
          .catch(() => undefined);
      }
    },
  };
}
