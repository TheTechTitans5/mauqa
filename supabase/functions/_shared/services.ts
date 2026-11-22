// Service layer shared by Edge Functions (eligibility, recommendations, account export/deletion).
import { evaluateEligibility } from './eligibility.ts';
import { loadFacts } from './facts.ts';
import { recommend, type RecommendationPrefs } from './recommend.ts';
import { HttpError } from './http.ts';
import { inList, type Rest } from './rest.ts';
import type { EligibilityResult, FeedRow, Outcome, RuleRow, UserFacts } from './types.ts';

export interface CheckedOpportunity { opportunity_id: string; result: EligibilityResult; cached: boolean }

/**
 * Runs eligibility for the authenticated user.
 * `userDb` (caller JWT) proves the listings are visible to this user; `serviceDb` writes the result,
 * because users must not be able to forge eligibility rows.
 */
export async function checkEligibility(userDb: Rest, serviceDb: Rest, userId: string, opportunityIds: string[],
  opts: { force?: boolean; facts?: UserFacts } = {}): Promise<CheckedOpportunity[]> {
  if (opportunityIds.length === 0) return [];
  if (opportunityIds.length > 100) throw new HttpError(422, 'Too many opportunities in one request (max 100)', 'validation');
  const visible = await userDb.select<{ id: string; deadline: string | null }>('opportunity_feed',
    `select=id,deadline&id=${inList(opportunityIds)}`);
  if (visible.length === 0) throw new HttpError(404, 'Opportunity not found', 'not_found');
  const ids = visible.map((v) => v.id);
  const [opps, rules, cached] = await Promise.all([
    serviceDb.select<{ id: string; rules_version: number }>('opportunities', `select=id,rules_version&id=${inList(ids)}`),
    serviceDb.select<RuleRow & { opportunity_id: string }>('opportunity_eligibility_rules',
      `select=id,opportunity_id,parent_id,node_type,group_operator,criterion_type,params,label,is_mandatory,sort_order&opportunity_id=${inList(ids)}`),
    serviceDb.select<{ opportunity_id: string; outcome: Outcome; matched: unknown; failed: unknown; unconfirmed: unknown;
      missing_requirements: string[]; explanation: string; score: number; is_stale: boolean; profile_version: number; rules_version: number }>(
      'eligibility_checks', `select=*&user_id=eq.${userId}&opportunity_id=${inList(ids)}`),
  ]);
  const facts = opts.facts ?? (await loadFacts(serviceDb, userId)).facts;
  const rulesVersion = new Map(opps.map((o) => [o.id, o.rules_version]));
  const cache = new Map(cached.map((c) => [c.opportunity_id, c]));
  const out: CheckedOpportunity[] = [];
  const writes: Record<string, unknown>[] = [];
  for (const v of visible) {
    const c = cache.get(v.id);
    const rv = rulesVersion.get(v.id) ?? 1;
    if (!opts.force && c && !c.is_stale && c.profile_version === facts.profileVersion && c.rules_version === rv) {
      out.push({ opportunity_id: v.id, cached: true, result: {
        outcome: c.outcome, score: Number(c.score ?? 0), matched: c.matched as EligibilityResult['matched'],
        failed: c.failed as EligibilityResult['failed'], unconfirmed: c.unconfirmed as EligibilityResult['unconfirmed'],
        missingRequirements: c.missing_requirements ?? [], explanation: c.explanation } });
      continue;
    }
    const result = evaluateEligibility(rules.filter((r) => r.opportunity_id === v.id), facts, { deadline: v.deadline });
    out.push({ opportunity_id: v.id, cached: false, result });
    writes.push({
      user_id: userId, opportunity_id: v.id, outcome: result.outcome, score: result.score, matched: result.matched,
      failed: result.failed, unconfirmed: result.unconfirmed, missing_requirements: result.missingRequirements,
      explanation: result.explanation, profile_version: facts.profileVersion, rules_version: rv, is_stale: false,
      checked_at: new Date().toISOString(),
    });
  }
  if (writes.length) await serviceDb.insert('eligibility_checks', writes, { upsert: 'user_id,opportunity_id', returning: false });
  return out;
}

export async function recommendationsFor(userDb: Rest, serviceDb: Rest, userId: string, limit = 20) {
  const { facts, prefs } = await loadFacts(serviceDb, userId);
  const feed = await userDb.select<FeedRow>('opportunity_feed',
    'select=id,title,organization_name,category_slug,tags,education_levels,fields_of_study,required_skills,provinces,cities,is_nationwide,work_mode,deadline,effective_status,verification_status,is_featured,is_demo,is_reported,gender_eligibility,created_at&effective_status=neq.closed&order=deadline.asc.nullslast&limit=300');
  const outcomes = new Map<string, Outcome>();
  // Evaluate in batches so every candidate has a real (cached or fresh) eligibility result.
  for (let i = 0; i < feed.length; i += 100) {
    const batch = feed.slice(i, i + 100).map((f) => f.id);
    if (!batch.length) break;
    const res = await checkEligibility(userDb, serviceDb, userId, batch, { facts });
    res.forEach((r) => outcomes.set(r.opportunity_id, r.result.outcome));
  }
  return recommend(feed, facts, outcomes, prefs as RecommendationPrefs, Math.min(Math.max(limit, 1), 50));
}

const EXPORT_TABLES: Array<[string, string]> = [
  ['profiles', 'id'], ['user_roles', 'user_id'], ['education_records', 'user_id'], ['user_skills', 'user_id'],
  ['user_interests', 'user_id'], ['user_experiences', 'user_id'], ['user_certifications', 'user_id'],
  ['saved_opportunities', 'user_id'], ['interested_opportunities', 'user_id'], ['eligibility_checks', 'user_id'],
  ['applications', 'user_id'], ['application_status_history', 'user_id'], ['user_documents', 'user_id'],
  ['notification_preferences', 'user_id'], ['notifications', 'user_id'], ['reminders', 'user_id'],
  ['search_history', 'user_id'], ['comparisons', 'user_id'], ['cv_documents', 'user_id'], ['cover_letters', 'user_id'],
  ['opportunity_reports', 'reporter_id'], ['user_corrections', 'user_id'], ['success_stories', 'author_id'],
  ['device_tokens', 'user_id'], ['feedback', 'user_id'], ['mentors', 'user_id'], ['university_ambassadors', 'user_id'],
];

export async function exportUserData(serviceDb: Rest, userId: string): Promise<Record<string, unknown>> {
  const out: Record<string, unknown> = { exported_at: new Date().toISOString(), user_id: userId,
    note: 'Document files are not embedded; download them from the Documents screen.' };
  for (const [table, col] of EXPORT_TABLES) {
    out[table] = await serviceDb.select(table, `select=*&${col}=eq.${userId}`);
  }
  // never export push tokens in full
  out.device_tokens = (out.device_tokens as Array<{ token: string }>).map((d) => ({ ...d, token: d.token.slice(0, 8) + '…' }));
  return out;
}

export async function deleteAccount(serviceDb: Rest, userId: string): Promise<{ files_removed: number }> {
  let removed = 0;
  for (const bucket of ['user-documents', 'avatars']) {
    const files = await serviceDb.storageList(bucket, userId);
    const paths = files.filter((f) => f.id !== null).map((f) => `${userId}/${f.name}`);
    await serviceDb.storageRemove(bucket, paths);
    removed += paths.length;
  }
  // Deleting the auth user cascades to profiles and every user-owned table (ON DELETE CASCADE).
  await serviceDb.adminDeleteUser(userId);
  return { files_removed: removed };
}
