// Duplicate and change detection for ingested listings.

export interface DraftOpportunity {
  title: string;
  organization_id?: string | null;
  organization_name?: string | null;
  source_url?: string | null;
  official_application_url?: string | null;
  deadline?: string | null;
  opening_date?: string | null;
  summary?: string | null;
  description?: string | null;
  eligibility_summary?: string | null;
  amount_text?: string | null;
  amount_min_pkr?: number | null;
  location_text?: string | null;
  category_slug?: string | null;
  has_application_fee?: boolean;
}

const STOPWORDS = new Set(['the', 'a', 'an', 'of', 'for', 'and', 'in', 'to', 'at', 'on', 'program', 'programme', 'scheme', '2024', '2025', '2026', '2027', '2028', 'call', 'applications', 'invited']);

export function titleTokens(title: string): Set<string> {
  return new Set(title.toLowerCase().replace(/[^a-z0-9؀-ۿ ]+/g, ' ').split(/\s+/)
    .filter((t) => t.length > 1 && !STOPWORDS.has(t)));
}

export function jaccard(a: Set<string>, b: Set<string>): number {
  if (a.size === 0 && b.size === 0) return 1;
  let inter = 0;
  for (const x of a) if (b.has(x)) inter++;
  return inter / (a.size + b.size - inter);
}

function normUrl(u?: string | null): string | null {
  if (!u) return null;
  try {
    const x = new URL(u);
    x.hash = '';
    ['utm_source', 'utm_medium', 'utm_campaign', 'utm_term', 'utm_content', 'fbclid'].forEach((p) => x.searchParams.delete(p));
    return (x.hostname.replace(/^www\./, '') + x.pathname.replace(/\/+$/, '') + x.search).toLowerCase();
  } catch { return null; }
}

/** 0..1 likelihood that two listings describe the same opportunity. */
export function duplicateScore(a: DraftOpportunity, b: DraftOpportunity): number {
  const ua = normUrl(a.official_application_url) ?? normUrl(a.source_url);
  const ub = normUrl(b.official_application_url) ?? normUrl(b.source_url);
  if (ua && ub && ua === ub) return 1;
  let score = jaccard(titleTokens(a.title), titleTokens(b.title)) * 0.7;
  if (a.organization_id && a.organization_id === b.organization_id) score += 0.2;
  else if (a.organization_name && b.organization_name &&
    jaccard(titleTokens(a.organization_name), titleTokens(b.organization_name)) > 0.6) score += 0.15;
  if (a.deadline && b.deadline) {
    const days = Math.abs(new Date(a.deadline).getTime() - new Date(b.deadline).getTime()) / 86_400_000;
    score += days <= 1 ? 0.1 : days <= 7 ? 0.05 : -0.1;
  }
  return Math.max(0, Math.min(1, Math.round(score * 1000) / 1000));
}

export function findDuplicate<T extends DraftOpportunity & { id: string }>(
  draft: DraftOpportunity, candidates: T[], threshold = 0.8,
): { match: T; score: number } | null {
  let best: { match: T; score: number } | null = null;
  for (const c of candidates) {
    const s = duplicateScore(draft, c);
    if (s >= threshold && (!best || s > best.score)) best = { match: c, score: s };
  }
  return best;
}

const TRACKED: Array<keyof DraftOpportunity> = ['title', 'deadline', 'opening_date', 'official_application_url', 'source_url',
  'eligibility_summary', 'amount_text', 'amount_min_pkr', 'summary', 'description', 'location_text', 'has_application_fee'];

export function canonicalJson(d: DraftOpportunity): string {
  const o: Record<string, unknown> = {};
  for (const k of TRACKED) {
    const v = d[k];
    o[k] = typeof v === 'string' ? v.replace(/\s+/g, ' ').trim() : v ?? null;
  }
  return JSON.stringify(o);
}

export async function contentHash(d: DraftOpportunity): Promise<string> {
  const bytes = new TextEncoder().encode(canonicalJson(d));
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

export function diffDrafts(before: DraftOpportunity, after: DraftOpportunity): Record<string, { from: unknown; to: unknown }> {
  const out: Record<string, { from: unknown; to: unknown }> = {};
  for (const k of TRACKED) {
    const a = before[k] ?? null, b = after[k] ?? null;
    if (JSON.stringify(a) !== JSON.stringify(b)) out[k] = { from: a, to: b };
  }
  return out;
}
