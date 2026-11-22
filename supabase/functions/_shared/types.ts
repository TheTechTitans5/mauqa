// Shared domain types for Mauqa backend functions. Pure TypeScript: runs in Deno (Edge Functions) and Node (tests).

export type Tri = 'met' | 'not_met' | 'unknown';
export type Outcome = 'eligible' | 'probably_eligible' | 'not_eligible';

export type EducationLevel =
  | 'primary' | 'middle' | 'matric' | 'o_level' | 'intermediate' | 'a_level' | 'diploma'
  | 'bachelor' | 'master' | 'mphil' | 'phd' | 'other';

export interface EducationFact {
  level: EducationLevel;
  institutionId?: string | null;
  institutionName?: string | null;
  institutionShortName?: string | null;
  department?: string | null;
  degreeProgram?: string | null;
  fieldOfStudy?: string | null;
  currentSemester?: number | null;
  enrollmentStatus?: 'enrolled' | 'completed' | 'awaiting_result' | 'discontinued' | null;
  graduationYear?: number | null;
  scoreType?: 'cgpa' | 'percentage' | 'grade' | null;
  scoreValue?: number | null;
  scoreMax?: number | null;
  isCurrent?: boolean;
}

export interface ExperienceFact {
  kind: 'work' | 'internship' | 'volunteer';
  startDate: string; // ISO date
  endDate?: string | null;
  isCurrent?: boolean;
}

export interface UserFacts {
  userId: string;
  profileVersion: number;
  dateOfBirth?: string | null;
  gender?: string | null;
  nationality?: string | null;
  province?: string | null;
  city?: string | null;
  userCategory?: string | null;
  employmentStatus?: string | null;
  /** Sensitive fields are only populated when the user opted in (share_sensitive_for_eligibility). */
  shareSensitive: boolean;
  incomeMonthlyPkr?: number | null;
  incomeRange?: string | null;
  hasDisability?: boolean | null;
  education: EducationFact[];
  skills: string[];
  interests: string[];
  experiences: ExperienceFact[];
  documentCategories: string[];
}

export type CriterionType =
  | 'age_range' | 'education_level_in' | 'cgpa_min' | 'percentage_min' | 'semester_range'
  | 'enrollment_status_in' | 'graduation_year_range' | 'institution_whitelist' | 'institution_blacklist'
  | 'department_whitelist' | 'department_blacklist' | 'field_of_study_in' | 'gender_in' | 'province_in'
  | 'city_in' | 'nationality_in' | 'income_max' | 'experience_min_months' | 'skills_required'
  | 'documents_required' | 'user_category_in' | 'disability_required' | 'employment_status_in' | 'custom';

export interface RuleRow {
  id: string;
  parent_id: string | null;
  node_type: 'group' | 'criterion';
  group_operator?: 'and' | 'or' | null;
  criterion_type?: CriterionType | null;
  params: Record<string, unknown>;
  label?: string | null;
  is_mandatory: boolean;
  sort_order: number;
}

export interface CriterionResult {
  ruleId: string;
  type: CriterionType;
  label: string;
  status: Tri;
  reason: string;
  mandatory: boolean;
}

export interface EligibilityResult {
  outcome: Outcome;
  score: number; // 0..1 share of mandatory criteria met
  matched: CriterionResult[];
  failed: CriterionResult[];
  unconfirmed: CriterionResult[];
  missingRequirements: string[];
  explanation: string;
}

export interface OpportunityContext {
  id: string;
  deadline?: string | null;
  rulesVersion: number;
}

/** Row shape of the public.opportunity_feed view (subset used by the backend). */
export interface FeedRow {
  id: string;
  title: string;
  organization_name: string;
  category_slug: string;
  tags: string[];
  education_levels: EducationLevel[];
  fields_of_study: string[];
  required_skills: string[];
  provinces: string[];
  cities: string[];
  is_nationwide: boolean;
  work_mode: string;
  deadline: string | null;
  effective_status: 'open' | 'closing_soon' | 'upcoming' | 'closed';
  verification_status: string;
  is_featured: boolean;
  is_demo: boolean;
  is_reported: boolean;
  gender_eligibility: string;
  created_at: string;
}
