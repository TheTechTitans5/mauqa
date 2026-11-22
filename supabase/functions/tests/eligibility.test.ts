import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ageOn, evaluateEligibility, experienceMonths } from '../_shared/eligibility.ts';
import type { RuleRow, UserFacts } from '../_shared/types.ts';

const NOW = new Date('2026-11-21T10:00:00Z');

function user(over: Partial<UserFacts> = {}): UserFacts {
  return {
    userId: 'u1', profileVersion: 3, dateOfBirth: '2004-05-10', gender: 'female', nationality: 'Pakistani',
    province: 'Punjab', city: 'Lahore', userCategory: 'student', employmentStatus: 'student', shareSensitive: false,
    education: [{ level: 'bachelor', institutionId: 'nust-id', institutionName: 'National University of Sciences and Technology',
      institutionShortName: 'NUST', department: 'Computer Science', fieldOfStudy: 'Computer Science', currentSemester: 6,
      enrollmentStatus: 'enrolled', graduationYear: 2027, scoreType: 'cgpa', scoreValue: 3.4, scoreMax: 4, isCurrent: true },
    { level: 'intermediate', scoreType: 'percentage', scoreValue: 880, scoreMax: 1100 }],
    skills: ['Python', 'SQL'], interests: ['scholarships'], experiences: [], documentCategories: ['cv', 'transcript'],
    ...over,
  };
}

let n = 0;
const crit = (type: RuleRow['criterion_type'], params: Record<string, unknown>, over: Partial<RuleRow> = {}): RuleRow =>
  ({ id: `r${++n}`, parent_id: null, node_type: 'criterion', criterion_type: type, params, label: type ?? '', is_mandatory: true, sort_order: n, ...over });
const group = (id: string, op: 'and' | 'or', parent: string | null = null): RuleRow =>
  ({ id, parent_id: parent, node_type: 'group', group_operator: op, params: {}, is_mandatory: true, sort_order: 0 });

test('CGPA 3.4 satisfies a 3.0 minimum (example from the brief)', () => {
  const r = evaluateEligibility([crit('cgpa_min', { min: 3.0 })], user(), { deadline: null }, NOW);
  assert.equal(r.outcome, 'eligible');
  assert.match(r.matched[0].reason, /3\.4/);
});

test('CGPA below minimum → not eligible with reason', () => {
  const r = evaluateEligibility([crit('cgpa_min', { min: 3.5 })], user(), { deadline: null }, NOW);
  assert.equal(r.outcome, 'not_eligible');
  assert.equal(r.failed.length, 1);
  assert.match(r.explanation, /do not meet/);
});

test('CGPA on a 5.0 scale is normalised', () => {
  const u = user({ education: [{ level: 'master', scoreType: 'cgpa', scoreValue: 4.0, scoreMax: 5, isCurrent: true }] });
  assert.equal(evaluateEligibility([crit('cgpa_min', { min: 3.0, scale: 4 })], u, { deadline: null }, NOW).outcome, 'eligible');
  assert.equal(evaluateEligibility([crit('cgpa_min', { min: 3.3, scale: 4 })], u, { deadline: null }, NOW).outcome, 'not_eligible');
});

test('institution whitelist that is not published → unconfirmed, never a guess', () => {
  const r = evaluateEligibility([crit('institution_whitelist', { list_available: false })], user(), { deadline: null }, NOW);
  assert.equal(r.outcome, 'probably_eligible');
  assert.equal(r.unconfirmed.length, 1);
  assert.match(r.unconfirmed[0].reason, /official list is not available/);
});

test('institution whitelist matches by id or short name', () => {
  assert.equal(evaluateEligibility([crit('institution_whitelist', { institution_ids: ['nust-id'] })], user(), { deadline: null }, NOW).outcome, 'eligible');
  assert.equal(evaluateEligibility([crit('institution_whitelist', { names: ['NUST'] })],
    user({ education: [{ level: 'bachelor', institutionName: 'NUST Islamabad', isCurrent: true }] }), { deadline: null }, NOW).outcome, 'eligible');
  assert.equal(evaluateEligibility([crit('institution_whitelist', { names: ['LUMS'] })], user(), { deadline: null }, NOW).outcome, 'not_eligible');
});

test('missing important data → unconfirmed, not eligible', () => {
  const r = evaluateEligibility([crit('age_range', { max: 25 })], user({ dateOfBirth: null }), { deadline: null }, NOW);
  assert.equal(r.outcome, 'probably_eligible');
  assert.deepEqual(r.missingRequirements, ['Date of birth']);
});

test('age is computed at the deadline', () => {
  assert.equal(ageOn('2001-12-01', new Date('2026-11-30T00:00:00Z')), 24);
  assert.equal(ageOn('2001-12-01', new Date('2026-12-01T00:00:00Z')), 25);
  // turns 26 before the deadline → fails a max-25 rule even though they are 24 today
  const r = evaluateEligibility([crit('age_range', { max: 25 })], user({ dateOfBirth: '2001-12-01' }), { deadline: '2027-12-15T00:00:00Z' }, NOW);
  assert.equal(r.outcome, 'not_eligible');
});

test('AND with nested OR: either branch satisfies', () => {
  const rules = [group('g', 'and'), crit('gender_in', { genders: ['female'] }, { parent_id: 'g' }), group('o', 'or', 'g'),
    crit('field_of_study_in', { fields: ['Electrical Engineering'] }, { parent_id: 'o' }),
    crit('skills_required', { skills: ['Python', 'JavaScript'], mode: 'any' }, { parent_id: 'o' })];
  const r = evaluateEligibility(rules, user(), { deadline: null }, NOW);
  assert.equal(r.outcome, 'eligible');
  assert.equal(r.failed.length, 0, 'a failed OR alternative must not be reported as a failure');
  assert.equal(evaluateEligibility(rules, user({ gender: 'male' }), { deadline: null }, NOW).outcome, 'not_eligible');
  assert.equal(evaluateEligibility(rules, user({ skills: ['Go'], education: [] }), { deadline: null }, NOW).outcome, 'probably_eligible');
});

test('OR where all branches fail → not eligible', () => {
  const rules = [group('o', 'or'), crit('province_in', { provinces: ['Sindh'] }, { parent_id: 'o' }), crit('city_in', { cities: ['Quetta'] }, { parent_id: 'o' })];
  assert.equal(evaluateEligibility(rules, user(), { deadline: null }, NOW).outcome, 'not_eligible');
});

test('not_met dominates unknown in AND', () => {
  const rules = [crit('cgpa_min', { min: 3.9 }), crit('custom', { description: 'Hafiz-e-Quran' })];
  assert.equal(evaluateEligibility(rules, user(), { deadline: null }, NOW).outcome, 'not_eligible');
});

test('income is never used unless the user opted in', () => {
  const rule = [crit('income_max', { monthly_pkr: 100000 })];
  const hidden = user({ incomeMonthlyPkr: 50000, shareSensitive: false });
  assert.equal(evaluateEligibility(rule, hidden, { deadline: null }, NOW).outcome, 'probably_eligible');
  assert.equal(evaluateEligibility(rule, { ...hidden, shareSensitive: true }, { deadline: null }, NOW).outcome, 'eligible');
  assert.equal(evaluateEligibility(rule, user({ shareSensitive: true, incomeRange: '100k_200k' }), { deadline: null }, NOW).outcome, 'not_eligible');
  assert.equal(evaluateEligibility(rule, user({ shareSensitive: true, incomeRange: '50k_100k' }), { deadline: null }, NOW).outcome, 'eligible');
});

test('intermediate percentage computed from marks', () => {
  assert.equal(evaluateEligibility([crit('percentage_min', { level: 'intermediate', min: 80 })], user(), { deadline: null }, NOW).outcome, 'eligible');
  assert.equal(evaluateEligibility([crit('percentage_min', { level: 'intermediate', min: 85 })], user(), { deadline: null }, NOW).outcome, 'not_eligible');
  assert.equal(evaluateEligibility([crit('percentage_min', { level: 'matric', min: 60 })], user(), { deadline: null }, NOW).outcome, 'probably_eligible');
});

test('semester range and enrolment status', () => {
  assert.equal(evaluateEligibility([crit('semester_range', { min: 5, max: 8 })], user(), { deadline: null }, NOW).outcome, 'eligible');
  assert.equal(evaluateEligibility([crit('semester_range', { min: 7 })], user(), { deadline: null }, NOW).outcome, 'not_eligible');
  assert.equal(evaluateEligibility([crit('enrollment_status_in', { statuses: ['completed'] })], user(), { deadline: null }, NOW).outcome, 'not_eligible');
});

test('advisory documents never block eligibility but are listed', () => {
  const rules = [crit('cgpa_min', { min: 3 }), crit('documents_required', { categories: ['cnic', 'transcript'] }, { is_mandatory: false })];
  const r = evaluateEligibility(rules, user(), { deadline: null }, NOW);
  assert.equal(r.outcome, 'eligible');
  assert.ok(r.missingRequirements.includes('Document: cnic'));
});

test('no structured rules → unconfirmed with a clear message', () => {
  const r = evaluateEligibility([], user(), { deadline: null }, NOW);
  assert.equal(r.outcome, 'probably_eligible');
  assert.match(r.explanation, /no structured criteria/);
});

test('experience months merge overlapping periods', () => {
  const exps = [
    { kind: 'internship' as const, startDate: '2025-01-01', endDate: '2025-07-01' },
    { kind: 'work' as const, startDate: '2025-04-01', endDate: '2025-10-01' },
    { kind: 'volunteer' as const, startDate: '2024-01-01', endDate: '2024-12-31' },
  ];
  assert.equal(experienceMonths(exps, ['work', 'internship'], NOW), 8);
  const r = evaluateEligibility([crit('experience_min_months', { months: 6, kinds: ['work', 'internship'] })], user({ experiences: exps }), { deadline: null }, NOW);
  assert.equal(r.outcome, 'eligible');
});

test('skills: min mode and case-insensitivity', () => {
  const rule = [crit('skills_required', { skills: ['sql', 'excel', 'python'], mode: 'min', min_count: 2 })];
  assert.equal(evaluateEligibility(rule, user(), { deadline: null }, NOW).outcome, 'eligible');
  assert.equal(evaluateEligibility(rule, user({ skills: ['SQL'] }), { deadline: null }, NOW).outcome, 'not_eligible');
  assert.equal(evaluateEligibility(rule, user({ skills: [] }), { deadline: null }, NOW).outcome, 'probably_eligible');
});

test('gender "prefer not to say" is treated as unknown', () => {
  assert.equal(evaluateEligibility([crit('gender_in', { genders: ['female'] })], user({ gender: 'prefer_not_to_say' }), { deadline: null }, NOW).outcome, 'probably_eligible');
});

test('blacklists', () => {
  assert.equal(evaluateEligibility([crit('institution_blacklist', { names: ['NUST'] })], user(), { deadline: null }, NOW).outcome, 'not_eligible');
  assert.equal(evaluateEligibility([crit('department_blacklist', { departments: ['Medicine'] })], user(), { deadline: null }, NOW).outcome, 'eligible');
});

test('department matching uses whole words of the official entry', () => {
  assert.equal(evaluateEligibility([crit('department_whitelist', { departments: ['Computer Science'] })],
    user({ education: [{ level: 'bachelor', department: 'Science', isCurrent: true }] }), { deadline: null }, NOW).outcome, 'not_eligible');
  assert.equal(evaluateEligibility([crit('department_whitelist', { departments: ['Engineering'] })],
    user({ education: [{ level: 'bachelor', department: 'Software Engineering', isCurrent: true }] }), { deadline: null }, NOW).outcome, 'eligible');
});

test('unknown criterion type is reported, not crashed on', () => {
  const r = evaluateEligibility([crit('nope' as RuleRow['criterion_type'], {})], user(), { deadline: null }, NOW);
  assert.equal(r.outcome, 'probably_eligible');
});
