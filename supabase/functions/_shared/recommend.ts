// Transparent, rule-based recommendation scoring. Every point awarded comes with a human-readable reason.
import type { FeedRow, Outcome, UserFacts } from './types.ts';
import { currentEducation, normalize } from './eligibility.ts';

export interface RecommendationPrefs {
  excluded_categories?: string[];
  preferred_categories?: string[];
  verified_only?: boolean;
  include_demo?: boolean;
  remote_only?: boolean;
  include_not_eligible?: boolean;
}

export interface Recommendation {
  opportunityId: string;
  score: number;
  reasons: string[];
  eligibility?: Outcome;
}

const DAY = 86_400_000;

export function scoreOpportunity(
  o: FeedRow, u: UserFacts, eligibility: Outcome | undefined, prefs: RecommendationPrefs, now = new Date(),
): Recommendation | null {
  if (o.effective_status === 'closed') return null; // never recommend closed listings as active
  if (o.deadline && new Date(o.deadline).getTime() <= now.getTime()) return null;
  if (prefs.excluded_categories?.includes(o.category_slug)) return null;
  if (prefs.verified_only && o.verification_status !== 'verified') return null;
  if (o.is_demo && prefs.include_demo === false) return null;
  if (prefs.remote_only && o.work_mode !== 'remote') return null;
  if (eligibility === 'not_eligible' && !prefs.include_not_eligible) return null;
  if (u.gender === 'male' && ['female', 'female_transgender'].includes(o.gender_eligibility)) return null;
  if (u.gender === 'female' && o.gender_eligibility === 'male') return null;

  let score = 0;
  const reasons: Array<[number, string]> = [];
  const add = (pts: number, reason?: string) => { score += pts; if (reason) reasons.push([pts, reason]); };

  if (eligibility === 'eligible') add(40, 'You meet the main eligibility requirements');
  else if (eligibility === 'probably_eligible') add(15, 'You may be eligible — some criteria need confirming');
  else if (eligibility === 'not_eligible') add(-40);

  const edu = currentEducation(u.education);
  if (o.education_levels.length && u.education.some((e) => o.education_levels.includes(e.level))) add(15, 'Matches your education');

  const myFields = u.education.flatMap((e) => [e.fieldOfStudy, e.department, e.degreeProgram]).filter(Boolean).map((s) => normalize(s));
  if (o.fields_of_study.length && o.fields_of_study.some((f) => myFields.some((m) => m.includes(normalize(f)) || normalize(f).includes(m)))) {
    add(15, 'Matches your field of study');
  }

  if (edu?.institutionShortName && normalize(o.title).includes(normalize(edu.institutionShortName))) add(10, 'Matches your university');

  const mySkills = new Set(u.skills.map(normalize));
  const skillHits = o.required_skills.filter((s) => mySkills.has(normalize(s))).length;
  if (skillHits > 0) add(Math.min(15, skillHits * 5), 'Matches your skills');

  const interests = u.interests.map(normalize);
  const tagPool = [o.category_slug, ...o.tags].map(normalize);
  if (interests.some((i) => tagPool.some((t) => t === i || t.includes(i) || i.includes(t)))) add(10, 'Matches your interests');
  if (prefs.preferred_categories?.includes(o.category_slug)) add(8, 'In a category you follow');

  if (!o.is_nationwide && o.provinces.length) {
    if (u.province && o.provinces.includes(u.province)) add(6, 'Available in your province');
    else if (u.province) add(-25);
  }
  if (o.work_mode === 'remote') add(2);

  if (o.deadline) {
    const days = (new Date(o.deadline).getTime() - now.getTime()) / DAY;
    if (days <= 7) add(8, 'Deadline approaching');
    else if (days <= 21) add(3);
  }
  if (o.effective_status === 'upcoming') add(-5, 'Opens soon');
  if (o.verification_status === 'verified') add(6, 'Verified official source');
  if (o.is_featured) add(3);
  if (o.is_reported) add(-30);
  if ((now.getTime() - new Date(o.created_at).getTime()) / DAY <= 7) add(2, 'New this week');

  if (score <= 0) return null;
  const top = reasons.filter(([p]) => p > 0).sort((a, b) => b[0] - a[0]).slice(0, 3).map(([, r]) => r);
  return { opportunityId: o.id, score, reasons: top, eligibility };
}

export function recommend(
  feed: FeedRow[], user: UserFacts, eligibility: Map<string, Outcome>, prefs: RecommendationPrefs, limit = 20, now = new Date(),
): Recommendation[] {
  return feed
    .map((o) => scoreOpportunity(o, user, eligibility.get(o.id), prefs, now))
    .filter((r): r is Recommendation => r !== null)
    .sort((a, b) => b.score - a.score || a.opportunityId.localeCompare(b.opportunityId))
    .slice(0, limit);
}
