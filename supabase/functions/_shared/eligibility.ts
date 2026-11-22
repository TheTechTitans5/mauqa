// Deterministic eligibility engine. No AI, no guessing:
//  - every criterion evaluates to met / not_met / unknown
//  - AND: any not_met → not_met; else any unknown → unknown; else met
//  - OR:  any met → met; else any unknown → unknown; else not_met
//  - outcome: met → ELIGIBLE, unknown → PROBABLY ELIGIBLE / UNCONFIRMED, not_met → NOT ELIGIBLE
//  - non-mandatory (advisory) criteria are reported but never change the outcome.

import type {
  CriterionResult, CriterionType, EducationFact, EducationLevel, EligibilityResult, OpportunityContext,
  RuleRow, Tri, UserFacts,
} from './types.ts';

const LEVEL_RANK: Record<EducationLevel, number> = {
  primary: 1, middle: 2, matric: 3, o_level: 3, intermediate: 4, a_level: 4, diploma: 4,
  bachelor: 5, master: 6, mphil: 7, phd: 8, other: 0,
};
const SECONDARY_EQUIV: Record<string, EducationLevel[]> = {
  matric: ['matric', 'o_level'],
  intermediate: ['intermediate', 'a_level'],
};
const INCOME_RANGES: Record<string, [number, number | null]> = {
  below_25k: [0, 25000], '25k_50k': [25000, 50000], '50k_100k': [50000, 100000],
  '100k_200k': [100000, 200000], above_200k: [200000, null],
};

export function normalize(s: string | null | undefined): string {
  return (s ?? '').toLowerCase().normalize('NFKD').replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9؀-ۿ]+/g, ' ').trim();
}

/**
 * True when every word of the configured `entry` appears as a whole word in the user's `value`.
 * "Engineering" matches "Software Engineering"; "Computer Science" does NOT match "Science".
 */
function textMatches(entry: string | null | undefined, value: string | null | undefined): boolean {
  const x = normalize(entry), y = normalize(value);
  if (!x || !y) return false;
  if (x === y) return true;
  const words = new Set(y.split(' '));
  return x.split(' ').every((w) => words.has(w));
}

function asStrings(v: unknown): string[] {
  return Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string' && x.trim() !== '') : [];
}
function asNumber(v: unknown): number | null {
  if (typeof v === 'number' && Number.isFinite(v)) return v;
  if (typeof v === 'string' && v.trim() !== '' && Number.isFinite(Number(v))) return Number(v);
  return null;
}

/** The record describing what the user is doing now (or most recently). */
export function currentEducation(edu: EducationFact[]): EducationFact | null {
  if (edu.length === 0) return null;
  const current = edu.filter((e) => e.isCurrent);
  const pool = current.length ? current : edu;
  return [...pool].sort((a, b) => (LEVEL_RANK[b.level] - LEVEL_RANK[a.level])
    || ((b.graduationYear ?? 0) - (a.graduationYear ?? 0)))[0];
}

export function ageOn(dob: string, on: Date): number {
  const d = new Date(dob + (dob.length === 10 ? 'T00:00:00Z' : ''));
  let age = on.getUTCFullYear() - d.getUTCFullYear();
  const m = on.getUTCMonth() - d.getUTCMonth();
  if (m < 0 || (m === 0 && on.getUTCDate() < d.getUTCDate())) age--;
  return age;
}

/** Total months of experience, merging overlapping periods. */
export function experienceMonths(exps: UserFacts['experiences'], kinds: string[] | null, now: Date): number {
  const ranges = exps
    .filter((e) => !kinds || kinds.length === 0 || kinds.includes(e.kind))
    .map((e) => {
      const s = new Date(e.startDate).getTime();
      const end = e.isCurrent || !e.endDate ? now.getTime() : new Date(e.endDate).getTime();
      return [s, Math.max(s, end)] as [number, number];
    })
    .filter(([s]) => Number.isFinite(s))
    .sort((a, b) => a[0] - b[0]);
  let total = 0;
  let cur: [number, number] | null = null;
  for (const r of ranges) {
    if (!cur) { cur = [...r] as [number, number]; continue; }
    if (r[0] <= cur[1]) cur[1] = Math.max(cur[1], r[1]);
    else { total += cur[1] - cur[0]; cur = [...r] as [number, number]; }
  }
  if (cur) total += cur[1] - cur[0];
  return Math.floor(total / (1000 * 60 * 60 * 24 * 30.44));
}

interface Eval { status: Tri; reason: string; missing?: string[] }
const met = (reason: string): Eval => ({ status: 'met', reason });
const notMet = (reason: string): Eval => ({ status: 'not_met', reason });
const unknown = (reason: string, missing?: string[]): Eval => ({ status: 'unknown', reason, missing });

type Evaluator = (p: Record<string, unknown>, u: UserFacts, ctx: { asOf: Date; now: Date }) => Eval;

const listCheck = (value: string | null | undefined, allowed: string[], what: string, prompt: string): Eval => {
  if (allowed.length === 0) return unknown(`The ${what} requirement has no values configured.`);
  if (!value || value === 'prefer_not_to_say') return unknown(`Add your ${what} to your profile to confirm this.`, [prompt]);
  // Exact (normalised) match for enumerated values: substring matching would let "male" pass a "female" rule.
  return allowed.some((a) => normalize(a) === normalize(value))
    ? met(`Your ${what} (${value}) is accepted.`)
    : notMet(`Open to ${allowed.join(', ')} only; your ${what} is ${value}.`);
};

const EVALUATORS: Record<CriterionType, Evaluator> = {
  age_range(p, u, { asOf }) {
    const min = asNumber(p.min), max = asNumber(p.max);
    if (!u.dateOfBirth) return unknown('Add your date of birth to confirm the age limit.', ['Date of birth']);
    const age = ageOn(u.dateOfBirth, asOf);
    if (min !== null && age < min) return notMet(`Minimum age is ${min}; you will be ${age}.`);
    if (max !== null && age > max) return notMet(`Maximum age is ${max}; you will be ${age}.`);
    return met(`Your age (${age}) is within the limit.`);
  },
  education_level_in(p, u) {
    const levels = asStrings(p.levels) as EducationLevel[];
    if (u.education.length === 0) return unknown('Add your education to confirm this.', ['Education record']);
    const hit = u.education.find((e) => levels.includes(e.level));
    return hit ? met(`Your ${hit.level.replace('_', ' ')} record matches.`)
      : notMet(`Requires ${levels.join(' / ')}; your records do not include this level.`);
  },
  cgpa_min(p, u) {
    const min = asNumber(p.min) ?? 0;
    const scale = asNumber(p.scale) ?? 4;
    const pool = u.education.filter((e) => e.scoreType === 'cgpa' && e.scoreValue != null && LEVEL_RANK[e.level] >= 5);
    const rec = currentEducation(pool);
    if (!rec || rec.scoreValue == null) {
      const hasPct = u.education.some((e) => e.scoreType === 'percentage' && LEVEL_RANK[e.level] >= 5);
      return unknown(hasPct ? 'Your university result is recorded as a percentage; the CGPA requirement cannot be converted reliably.'
        : 'Add your university CGPA to confirm this.', ['University CGPA']);
    }
    const value = rec.scoreMax && rec.scoreMax !== scale ? (rec.scoreValue / rec.scoreMax) * scale : rec.scoreValue;
    const shown = Math.round(value * 100) / 100;
    return value + 1e-9 >= min ? met(`Your CGPA ${shown} meets the minimum of ${min}.`)
      : notMet(`Minimum CGPA is ${min}; yours is ${shown}.`);
  },
  percentage_min(p, u) {
    const level = String(p.level ?? '');
    const min = asNumber(p.min) ?? 0;
    const levels = SECONDARY_EQUIV[level] ?? [level as EducationLevel];
    const rec = u.education.find((e) => levels.includes(e.level) && e.scoreValue != null);
    const label = level === 'intermediate' ? 'Intermediate' : level === 'matric' ? 'Matric' : level;
    if (!rec || rec.scoreValue == null) return unknown(`Add your ${label} marks to confirm this.`, [`${label} marks`]);
    let pct: number | null = null;
    if (rec.scoreType === 'percentage') pct = rec.scoreMax && rec.scoreMax !== 100 ? (rec.scoreValue / rec.scoreMax) * 100 : rec.scoreValue;
    else if (rec.scoreMax && rec.scoreType !== 'grade' && rec.scoreType !== 'cgpa') pct = (rec.scoreValue / rec.scoreMax) * 100;
    if (pct === null) return unknown(`${label} result is not recorded as marks/percentage.`, [`${label} marks`]);
    const shown = Math.round(pct * 10) / 10;
    return pct + 1e-9 >= min ? met(`${label} ${shown}% meets the minimum ${min}%.`) : notMet(`Minimum ${label} is ${min}%; yours is ${shown}%.`);
  },
  semester_range(p, u) {
    const min = asNumber(p.min), max = asNumber(p.max);
    const rec = currentEducation(u.education.filter((e) => e.enrollmentStatus === 'enrolled'));
    if (!rec || rec.currentSemester == null) return unknown('Add your current semester to confirm this.', ['Current semester']);
    const s = rec.currentSemester;
    if ((min !== null && s < min) || (max !== null && s > max)) {
      return notMet(`Open to semesters ${min ?? 1}–${max ?? 'any'}; you are in semester ${s}.`);
    }
    return met(`Semester ${s} is within the allowed range.`);
  },
  enrollment_status_in(p, u) {
    const allowed = asStrings(p.statuses);
    const rec = currentEducation(u.education);
    if (!rec || !rec.enrollmentStatus) return unknown('Add your enrolment status to confirm this.', ['Enrolment status']);
    const pretty = rec.enrollmentStatus.replace('_', ' ');
    return allowed.includes(rec.enrollmentStatus) ? met(`Enrolment status (${pretty}) is accepted.`)
      : notMet(`Requires ${allowed.map((s) => s.replace('_', ' ')).join(' / ')}; you are ${pretty}.`);
  },
  graduation_year_range(p, u) {
    const min = asNumber(p.min), max = asNumber(p.max);
    const rec = currentEducation(u.education);
    if (!rec || rec.graduationYear == null) return unknown('Add your (expected) graduation year to confirm this.', ['Graduation year']);
    const y = rec.graduationYear;
    if ((min !== null && y < min) || (max !== null && y > max)) return notMet(`Graduation year must be ${min ?? '…'}–${max ?? '…'}; yours is ${y}.`);
    return met(`Graduation year ${y} is within range.`);
  },
  institution_whitelist(p, u) {
    const ids = asStrings(p.institution_ids), names = asStrings(p.names);
    if (p.list_available === false || (ids.length === 0 && names.length === 0)) {
      return unknown('This opportunity is limited to specific institutions, but the official list is not available. Check the official announcement.');
    }
    const rec = currentEducation(u.education);
    if (!rec || (!rec.institutionId && !rec.institutionName)) return unknown('Add your institution to confirm this.', ['Institution']);
    const ok = (rec.institutionId && ids.includes(rec.institutionId))
      || names.some((n) => textMatches(n, rec.institutionName) || textMatches(n, rec.institutionShortName));
    return ok ? met(`${rec.institutionShortName ?? rec.institutionName} is on the eligible institutions list.`)
      : notMet(`Only students of ${names.length ? names.join(', ') : 'listed institutions'} can apply.`);
  },
  institution_blacklist(p, u) {
    const ids = asStrings(p.institution_ids), names = asStrings(p.names);
    if (ids.length === 0 && names.length === 0) return met('No institutions are excluded.');
    const rec = currentEducation(u.education);
    if (!rec || (!rec.institutionId && !rec.institutionName)) return unknown('Add your institution to confirm this.', ['Institution']);
    const excluded = (rec.institutionId && ids.includes(rec.institutionId))
      || names.some((n) => textMatches(n, rec.institutionName) || textMatches(n, rec.institutionShortName));
    return excluded ? notMet(`Students of ${rec.institutionShortName ?? rec.institutionName} are excluded.`) : met('Your institution is not excluded.');
  },
  department_whitelist(p, u) {
    const deps = asStrings(p.departments);
    if (deps.length === 0) return unknown('The department list is not available.');
    const rec = currentEducation(u.education);
    const mine = rec?.department ?? rec?.fieldOfStudy ?? rec?.degreeProgram;
    if (!mine) return unknown('Add your department to confirm this.', ['Department']);
    return deps.some((d) => textMatches(d, mine)) ? met(`${mine} is an eligible department.`)
      : notMet(`Open to ${deps.join(', ')} departments only.`);
  },
  department_blacklist(p, u) {
    const deps = asStrings(p.departments);
    if (deps.length === 0) return met('No departments are excluded.');
    const rec = currentEducation(u.education);
    const mine = rec?.department ?? rec?.fieldOfStudy;
    if (!mine) return unknown('Add your department to confirm this.', ['Department']);
    return deps.some((d) => textMatches(d, mine)) ? notMet(`The ${mine} department is excluded.`) : met('Your department is not excluded.');
  },
  field_of_study_in(p, u) {
    const fields = asStrings(p.fields);
    if (fields.length === 0) return unknown('No fields of study are configured.');
    const candidates = u.education.flatMap((e) => [e.fieldOfStudy, e.department, e.degreeProgram]).filter(Boolean) as string[];
    if (candidates.length === 0) return unknown('Add your field of study to confirm this.', ['Field of study']);
    const hit = candidates.find((c) => fields.some((f) => textMatches(f, c)));
    return hit ? met(`Your field (${hit}) matches.`) : notMet(`Open to ${fields.join(', ')}.`);
  },
  gender_in: (p, u) => listCheck(u.gender, asStrings(p.genders), 'gender', 'Gender (optional)'),
  province_in: (p, u) => listCheck(u.province, asStrings(p.provinces), 'province', 'Province'),
  city_in: (p, u) => listCheck(u.city, asStrings(p.cities), 'city', 'City'),
  nationality_in: (p, u) => listCheck(u.nationality, asStrings(p.nationalities), 'nationality', 'Nationality'),
  user_category_in: (p, u) => listCheck(u.userCategory, asStrings(p.categories), 'category', 'User category'),
  employment_status_in: (p, u) => listCheck(u.employmentStatus, asStrings(p.statuses), 'employment status', 'Employment status'),
  income_max(p, u) {
    const max = asNumber(p.monthly_pkr);
    if (max === null) return unknown('Income limit not configured.');
    if (!u.shareSensitive) {
      return unknown('This has an income limit. Allow Mauqa to use your income range for eligibility (Privacy settings) to check it.', ['Household income (optional)']);
    }
    if (u.incomeMonthlyPkr != null) {
      return u.incomeMonthlyPkr <= max ? met(`Household income is within the PKR ${max.toLocaleString('en-US')} limit.`)
        : notMet(`Household income must be PKR ${max.toLocaleString('en-US')}/month or less.`);
    }
    const range = u.incomeRange ? INCOME_RANGES[u.incomeRange] : undefined;
    if (!range) return unknown('Add your household income range to check the income limit.', ['Household income (optional)']);
    const [lo, hi] = range;
    if (hi !== null && hi <= max) return met(`Your income range is within the PKR ${max.toLocaleString('en-US')} limit.`);
    if (lo >= max) return notMet(`Household income must be PKR ${max.toLocaleString('en-US')}/month or less.`);
    return unknown('Your income range overlaps the limit; enter an exact monthly figure to confirm.', ['Exact household income']);
  },
  experience_min_months(p, u, { now }) {
    const months = asNumber(p.months) ?? 0;
    const kinds = asStrings(p.kinds);
    if (u.experiences.length === 0) return unknown(`Requires ${months} months of experience. Add your experience to confirm.`, ['Work/internship experience']);
    const have = experienceMonths(u.experiences, kinds, now);
    return have >= months ? met(`You have about ${have} months of relevant experience (needs ${months}).`)
      : notMet(`Requires ${months} months of ${kinds.length ? kinds.join('/') : ''} experience; you have about ${have}.`);
  },
  skills_required(p, u) {
    const skills = asStrings(p.skills);
    const mode = String(p.mode ?? 'all');
    if (skills.length === 0) return met('No specific skills required.');
    if (u.skills.length === 0) return unknown(`Add your skills to confirm (${skills.join(', ')}).`, ['Skills']);
    const mine = new Set(u.skills.map(normalize));
    const have = skills.filter((s) => mine.has(normalize(s)));
    const lacking = skills.filter((s) => !mine.has(normalize(s)));
    const need = mode === 'any' ? 1 : mode === 'min' ? Math.max(1, asNumber(p.min_count) ?? 1) : skills.length;
    return have.length >= need ? met(`You have ${have.join(', ')}.`)
      : notMet(`Missing skills: ${lacking.join(', ')}${mode !== 'all' ? ` (needs ${need} of ${skills.length})` : ''}.`);
  },
  documents_required(p, u) {
    const cats = asStrings(p.categories);
    const missing = cats.filter((c) => !u.documentCategories.includes(c));
    const pretty = (c: string) => c.replace(/_/g, ' ');
    // Uploading is optional: missing uploads never make someone ineligible, they are listed as to-dos.
    return missing.length === 0 ? met('All required documents are in your vault.')
      : unknown(`Not yet in your document vault: ${missing.map(pretty).join(', ')}.`, missing.map((m) => `Document: ${pretty(m)}`));
  },
  disability_required(_p, u) {
    if (!u.shareSensitive || u.hasDisability == null) {
      return unknown('This programme is for persons with disabilities. Share disability status (optional, Privacy settings) to confirm.', ['Disability status (optional)']);
    }
    return u.hasDisability ? met('Matches the disability support requirement.') : notMet('This programme is for persons with disabilities.');
  },
  custom(p) {
    const d = typeof p.description === 'string' && p.description ? p.description : 'an additional condition';
    return unknown(`Cannot be checked automatically: ${d}. Confirm with the official announcement.`);
  },
};

interface Node { row: RuleRow; children: Node[] }

function buildForest(rows: RuleRow[]): Node[] {
  const byId = new Map<string, Node>();
  rows.forEach((r) => byId.set(r.id, { row: r, children: [] }));
  const roots: Node[] = [];
  for (const n of byId.values()) {
    const parent = n.row.parent_id ? byId.get(n.row.parent_id) : undefined;
    if (parent) parent.children.push(n); else roots.push(n);
  }
  const sort = (ns: Node[]) => { ns.sort((a, b) => a.row.sort_order - b.row.sort_order); ns.forEach((n) => sort(n.children)); };
  sort(roots);
  return roots;
}

function combine(op: 'and' | 'or', statuses: Tri[]): Tri {
  if (statuses.length === 0) return 'met';
  if (op === 'and') return statuses.includes('not_met') ? 'not_met' : statuses.includes('unknown') ? 'unknown' : 'met';
  return statuses.includes('met') ? 'met' : statuses.includes('unknown') ? 'unknown' : 'not_met';
}

interface NodeEval { status: Tri; leaves: CriterionResult[]; missing: string[] }

function evalNode(n: Node, u: UserFacts, ctx: { asOf: Date; now: Date }, inheritedMandatory: boolean): NodeEval {
  const mandatory = inheritedMandatory && n.row.is_mandatory;
  if (n.row.node_type === 'criterion') {
    const type = n.row.criterion_type as CriterionType;
    const fn = EVALUATORS[type];
    const e: Eval = fn ? fn(n.row.params ?? {}, u, ctx) : unknown(`Unsupported criterion "${type}".`);
    const leaf: CriterionResult = {
      ruleId: n.row.id, type, label: n.row.label ?? type.replace(/_/g, ' '), status: e.status, reason: e.reason, mandatory,
    };
    return { status: e.status, leaves: [leaf], missing: e.missing ?? [] };
  }
  const op = n.row.group_operator === 'or' ? 'or' : 'and';
  const kids = n.children.map((c) => ({ c, r: evalNode(c, u, ctx, mandatory) }));
  const decisive = kids.filter((k) => k.c.row.is_mandatory);
  const status = combine(op, decisive.map((k) => k.r.status));
  // For a satisfied OR, only report the branches that satisfied it (failed alternatives are irrelevant).
  const reported = op === 'or' && status === 'met'
    ? kids.filter((k) => !k.c.row.is_mandatory || k.r.status === 'met')
    : kids;
  return {
    status,
    leaves: reported.flatMap((k) => k.r.leaves),
    missing: reported.flatMap((k) => k.r.missing),
  };
}

export function evaluateEligibility(
  rules: RuleRow[], user: UserFacts, opp: Pick<OpportunityContext, 'deadline'>, now: Date = new Date(),
): EligibilityResult {
  if (rules.length === 0) {
    const leaf: CriterionResult = {
      ruleId: 'none', type: 'custom', label: 'Eligibility criteria', status: 'unknown', mandatory: true,
      reason: 'Eligibility criteria for this listing have not been structured yet. Read the official announcement before applying.',
    };
    return {
      outcome: 'probably_eligible', score: 0, matched: [], failed: [], unconfirmed: [leaf], missingRequirements: [],
      explanation: 'We could not confirm your eligibility because this listing has no structured criteria yet.',
    };
  }
  const deadline = opp.deadline ? new Date(opp.deadline) : null;
  const asOf = deadline && deadline > now ? deadline : now;
  const roots = buildForest(rules);
  const top: Node = roots.length === 1 ? roots[0] : {
    row: { id: 'root', parent_id: null, node_type: 'group', group_operator: 'and', params: {}, is_mandatory: true, sort_order: 0 },
    children: roots,
  };
  const r = evalNode(top, user, { asOf, now }, true);

  const matched = r.leaves.filter((l) => l.status === 'met');
  const failed = r.leaves.filter((l) => l.status === 'not_met' && l.mandatory);
  const advisoryFailed = r.leaves.filter((l) => l.status === 'not_met' && !l.mandatory);
  const unconfirmed = r.leaves.filter((l) => l.status === 'unknown');
  const missingRequirements = [...new Set([...r.missing, ...advisoryFailed.map((l) => l.label)])];
  const mandatoryLeaves = r.leaves.filter((l) => l.mandatory);
  const score = mandatoryLeaves.length ? mandatoryLeaves.filter((l) => l.status === 'met').length / mandatoryLeaves.length : 0;

  const outcome = r.status === 'met' ? 'eligible' : r.status === 'unknown' ? 'probably_eligible' : 'not_eligible';
  let explanation: string;
  if (outcome === 'eligible') {
    explanation = `You meet all ${mandatoryLeaves.filter((l) => l.status === 'met').length} required criteria we could check.`
      + (missingRequirements.length ? ` Still to prepare: ${missingRequirements.join('; ')}.` : '');
  } else if (outcome === 'not_eligible') {
    explanation = `You do not meet: ${failed.map((f) => f.label).join('; ')}.`;
  } else {
    const unconfirmedMandatory = unconfirmed.filter((l) => l.mandatory);
    explanation = `You may be eligible, but ${unconfirmedMandatory.length || unconfirmed.length} requirement(s) could not be confirmed: `
      + `${(unconfirmedMandatory.length ? unconfirmedMandatory : unconfirmed).map((l) => l.label).join('; ')}.`;
  }
  return { outcome, score: Math.round(score * 100) / 100, matched, failed, unconfirmed, missingRequirements, explanation };
}
