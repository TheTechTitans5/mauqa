// Loads a user's profile into the engine's UserFacts shape. Sensitive fields are dropped unless the user opted in.
import type { EducationFact, UserFacts } from './types.ts';
import type { Rest } from './rest.ts';

interface ProfileRow {
  id: string; profile_version: number; date_of_birth: string | null; gender: string | null; nationality: string | null;
  province: string | null; city: string | null; user_category: string | null; employment_status: string | null;
  household_income_monthly_pkr: number | null; household_income_range: string | null; has_disability: boolean | null;
  share_sensitive_for_eligibility: boolean; recommendation_prefs: Record<string, unknown>;
}
interface EduRow {
  level: EducationFact['level']; institution_id: string | null; institution_name: string | null; department: string | null;
  degree_program: string | null; field_of_study: string | null; current_semester: number | null;
  enrollment_status: EducationFact['enrollmentStatus']; graduation_year: number | null; score_type: EducationFact['scoreType'];
  score_value: number | string | null; score_max: number | string | null; is_current: boolean;
  institutions: { name: string; short_name: string | null } | null;
}

export function toFacts(p: ProfileRow, edu: EduRow[], skills: string[], interests: string[],
  exps: Array<{ kind: 'work' | 'internship' | 'volunteer'; start_date: string; end_date: string | null; is_current: boolean }>,
  docs: string[]): UserFacts {
  const sensitive = p.share_sensitive_for_eligibility === true;
  const num = (v: number | string | null) => (v === null || v === undefined ? null : Number(v));
  return {
    userId: p.id,
    profileVersion: p.profile_version,
    dateOfBirth: p.date_of_birth,
    gender: p.gender,
    nationality: p.nationality,
    province: p.province,
    city: p.city,
    userCategory: p.user_category,
    employmentStatus: p.employment_status,
    shareSensitive: sensitive,
    incomeMonthlyPkr: sensitive ? p.household_income_monthly_pkr : null,
    incomeRange: sensitive ? p.household_income_range : null,
    hasDisability: sensitive ? p.has_disability : null,
    education: edu.map((e) => ({
      level: e.level, institutionId: e.institution_id,
      institutionName: e.institutions?.name ?? e.institution_name, institutionShortName: e.institutions?.short_name ?? null,
      department: e.department, degreeProgram: e.degree_program, fieldOfStudy: e.field_of_study,
      currentSemester: e.current_semester, enrollmentStatus: e.enrollment_status, graduationYear: e.graduation_year,
      scoreType: e.score_type, scoreValue: num(e.score_value), scoreMax: num(e.score_max), isCurrent: e.is_current,
    })),
    skills, interests,
    experiences: exps.map((x) => ({ kind: x.kind, startDate: x.start_date, endDate: x.end_date, isCurrent: x.is_current })),
    documentCategories: [...new Set(docs)],
  };
}

/** Loads facts with the service role, strictly scoped to one user id that was authenticated beforehand. */
export async function loadFacts(db: Rest, userId: string): Promise<{ facts: UserFacts; prefs: Record<string, unknown> }> {
  const [profiles, edu, skills, interests, exps, docs] = await Promise.all([
    db.select<ProfileRow>('profiles', `select=id,profile_version,date_of_birth,gender,nationality,province,city,user_category,employment_status,household_income_monthly_pkr,household_income_range,has_disability,share_sensitive_for_eligibility,recommendation_prefs&id=eq.${userId}`),
    db.select<EduRow>('education_records', `select=level,institution_id,institution_name,department,degree_program,field_of_study,current_semester,enrollment_status,graduation_year,score_type,score_value,score_max,is_current,institutions(name,short_name)&user_id=eq.${userId}`),
    db.select<{ skill: string }>('user_skills', `select=skill&user_id=eq.${userId}`),
    db.select<{ interest: string }>('user_interests', `select=interest&user_id=eq.${userId}`),
    db.select<{ kind: 'work' | 'internship' | 'volunteer'; start_date: string; end_date: string | null; is_current: boolean }>(
      'user_experiences', `select=kind,start_date,end_date,is_current&user_id=eq.${userId}`),
    db.select<{ category: string }>('user_documents', `select=category&user_id=eq.${userId}`),
  ]);
  const p = profiles[0];
  if (!p) throw new Error('Profile not found');
  return {
    facts: toFacts(p, edu, skills.map((s) => s.skill), interests.map((i) => i.interest), exps, docs.map((d) => d.category)),
    prefs: p.recommendation_prefs ?? {},
  };
}
