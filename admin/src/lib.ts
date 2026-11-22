// Pure helpers for the admin dashboard (unit-tested).

export function toCsv(rows: Array<Record<string, unknown>>): string {
  if (rows.length === 0) return '';
  const cols = [...new Set(rows.flatMap((r) => Object.keys(r)))];
  const cell = (v: unknown) => {
    const s = v === null || v === undefined ? '' : typeof v === 'object' ? JSON.stringify(v) : String(v);
    // neutralise spreadsheet formula injection
    const safe = /^[=+\-@\t\r]/.test(s) ? `'${s}` : s;
    return /[",\n]/.test(safe) ? `"${safe.replace(/"/g, '""')}"` : safe;
  };
  return [cols.join(','), ...rows.map((r) => cols.map((c) => cell(r[c])).join(','))].join('\n');
}

export interface RuleRow {
  id?: string; opportunity_id: string; parent_id: string | null; node_type: 'group' | 'criterion';
  group_operator?: 'and' | 'or' | null; criterion_type?: string | null; params: Record<string, unknown>;
  label?: string | null; is_mandatory: boolean; sort_order: number;
}

/** Editable nested representation used by the rule editor. */
export interface RuleNode {
  kind: 'group' | 'criterion';
  op?: 'and' | 'or';
  type?: string;
  params?: Record<string, unknown>;
  label?: string;
  mandatory: boolean;
  children?: RuleNode[];
}

export function rowsToTree(rows: RuleRow[]): RuleNode {
  const byParent = new Map<string | null, RuleRow[]>();
  rows.forEach((r) => byParent.set(r.parent_id, [...(byParent.get(r.parent_id) ?? []), r]));
  const build = (r: RuleRow): RuleNode => r.node_type === 'group'
    ? { kind: 'group', op: r.group_operator ?? 'and', label: r.label ?? undefined, mandatory: r.is_mandatory,
        children: (byParent.get(r.id ?? '') ?? []).sort((a, b) => a.sort_order - b.sort_order).map(build) }
    : { kind: 'criterion', type: r.criterion_type ?? 'custom', params: r.params, label: r.label ?? undefined, mandatory: r.is_mandatory };
  const roots = (byParent.get(null) ?? []).sort((a, b) => a.sort_order - b.sort_order);
  if (roots.length === 1 && roots[0].node_type === 'group') return build(roots[0]);
  return { kind: 'group', op: 'and', mandatory: true, children: roots.map(build) };
}

/** Flattens a tree into insert rows with client-generated ids so parents can be referenced. */
export function treeToRows(tree: RuleNode, opportunityId: string, newId: () => string): RuleRow[] {
  const out: RuleRow[] = [];
  const walk = (n: RuleNode, parent: string | null, order: number) => {
    const id = newId();
    out.push({
      id, opportunity_id: opportunityId, parent_id: parent, node_type: n.kind,
      group_operator: n.kind === 'group' ? (n.op ?? 'and') : null,
      criterion_type: n.kind === 'criterion' ? (n.type ?? 'custom') : null,
      params: n.kind === 'criterion' ? (n.params ?? {}) : {},
      label: n.label ?? null, is_mandatory: n.mandatory, sort_order: order,
    });
    n.children?.forEach((c, i) => walk(c, id, i));
  };
  walk(tree, null, 0);
  return out;
}

export const CRITERIA: Record<string, { label: string; params: string; example: Record<string, unknown> }> = {
  age_range: { label: 'Age range', params: 'min, max', example: { min: 18, max: 25 } },
  education_level_in: { label: 'Education level', params: 'levels[]', example: { levels: ['bachelor'] } },
  cgpa_min: { label: 'Minimum CGPA', params: 'min, scale', example: { min: 3.0, scale: 4.0 } },
  percentage_min: { label: 'Minimum marks %', params: 'level (matric|intermediate), min', example: { level: 'intermediate', min: 60 } },
  semester_range: { label: 'Semester range', params: 'min, max', example: { min: 5, max: 8 } },
  enrollment_status_in: { label: 'Enrolment status', params: 'statuses[]', example: { statuses: ['enrolled'] } },
  graduation_year_range: { label: 'Graduation year', params: 'min, max', example: { min: 2024, max: 2027 } },
  institution_whitelist: { label: 'Institution whitelist', params: 'list_available, institution_ids[], names[]', example: { list_available: true, names: ['NUST'] } },
  institution_blacklist: { label: 'Institution blacklist', params: 'institution_ids[], names[]', example: { names: [] } },
  department_whitelist: { label: 'Department whitelist', params: 'departments[]', example: { departments: ['Computer Science'] } },
  department_blacklist: { label: 'Department blacklist', params: 'departments[]', example: { departments: [] } },
  field_of_study_in: { label: 'Field of study', params: 'fields[]', example: { fields: ['Computer Science'] } },
  gender_in: { label: 'Gender', params: 'genders[]', example: { genders: ['female'] } },
  province_in: { label: 'Province', params: 'provinces[]', example: { provinces: ['Punjab'] } },
  city_in: { label: 'City', params: 'cities[]', example: { cities: ['Lahore'] } },
  nationality_in: { label: 'Nationality', params: 'nationalities[]', example: { nationalities: ['Pakistani'] } },
  income_max: { label: 'Max household income', params: 'monthly_pkr', example: { monthly_pkr: 100000 } },
  experience_min_months: { label: 'Minimum experience', params: 'months, kinds[]', example: { months: 6, kinds: ['work', 'internship'] } },
  skills_required: { label: 'Skills', params: 'skills[], mode (all|any|min), min_count', example: { skills: ['Python'], mode: 'any' } },
  documents_required: { label: 'Documents (advisory)', params: 'categories[]', example: { categories: ['cnic', 'transcript'] } },
  user_category_in: { label: 'User category', params: 'categories[]', example: { categories: ['student'] } },
  disability_required: { label: 'Persons with disabilities', params: '—', example: {} },
  employment_status_in: { label: 'Employment status', params: 'statuses[]', example: { statuses: ['unemployed'] } },
  custom: { label: 'Custom (manual check)', params: 'description', example: { description: 'Must be Hafiz-e-Quran' } },
};

export function validateTree(n: RuleNode, path = 'root'): string[] {
  const errs: string[] = [];
  if (n.kind === 'group') {
    if (!n.children?.length) errs.push(`${path}: group has no conditions`);
    n.children?.forEach((c, i) => errs.push(...validateTree(c, `${path}.${i + 1}`)));
  } else {
    if (!n.type || !CRITERIA[n.type]) errs.push(`${path}: unknown criterion "${n.type}"`);
    if (n.type === 'cgpa_min' && typeof n.params?.min !== 'number') errs.push(`${path}: cgpa_min needs numeric "min"`);
    if (n.type === 'age_range' && n.params?.min === undefined && n.params?.max === undefined) errs.push(`${path}: age_range needs min or max`);
    if (n.type === 'institution_whitelist' && n.params?.list_available !== false
        && !(Array.isArray(n.params?.names) && n.params.names.length) && !(Array.isArray(n.params?.institution_ids) && n.params.institution_ids.length)) {
      errs.push(`${path}: whitelist is empty — set list_available:false if the official list is not published`);
    }
  }
  return errs;
}

export function isHttpsUrl(s: string | null | undefined): boolean {
  if (!s) return false;
  try { return new URL(s).protocol === 'https:'; } catch { return false; }
}

/** Converts a datetime-local value entered as Pakistan time to an ISO UTC string. */
export function pktLocalToIso(v: string): string | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/.exec(v);
  if (!m) return null;
  return new Date(Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4] - 5, +m[5])).toISOString();
}

export function isoToPktLocal(iso: string | null | undefined): string {
  if (!iso) return '';
  const d = new Date(new Date(iso).getTime() + 5 * 3600_000);
  return d.toISOString().slice(0, 16);
}

export function slugify(s: string): string {
  return s.toLowerCase().normalize('NFKD').replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 60);
}
