-- Mauqa — 0001: extensions and enumerated types
-- All timestamps are stored as timestamptz (UTC). Display/scheduling uses Asia/Karachi.

create extension if not exists pgcrypto;
create extension if not exists pg_trgm;
create extension if not exists unaccent;

create type public.app_role as enum ('user', 'admin', 'super_admin', 'verifier', 'content_manager');

create type public.user_category as enum ('student', 'graduate', 'job_seeker', 'entrepreneur', 'farmer', 'freelancer', 'other');

create type public.education_level as enum (
  'primary', 'middle', 'matric', 'o_level', 'intermediate', 'a_level', 'diploma',
  'bachelor', 'master', 'mphil', 'phd', 'other'
);

create type public.verification_status as enum ('verified', 'pending_verification', 'unverified', 'rejected', 'expired');

create type public.approval_status as enum ('draft', 'pending_review', 'approved', 'rejected');

create type public.opportunity_status as enum ('upcoming', 'open', 'closed', 'cancelled');

create type public.application_status as enum (
  'interested', 'planning', 'preparing_documents', 'applied', 'under_review',
  'shortlisted', 'interview_scheduled', 'selected', 'rejected', 'withdrawn'
);

create type public.source_type as enum ('api', 'rss', 'web_monitor', 'pdf', 'manual');

create type public.integration_status as enum (
  'awaiting_authorization', 'awaiting_configuration', 'active', 'paused', 'error'
);

create type public.sync_status as enum ('running', 'success', 'partial', 'failed', 'skipped');

create type public.funding_type as enum ('fully_funded', 'partially_funded', 'paid', 'unpaid', 'not_applicable');

create type public.work_mode as enum ('remote', 'onsite', 'hybrid', 'not_applicable');

create type public.org_type as enum ('government', 'private', 'ngo', 'university', 'international', 'other');

create type public.eligibility_outcome as enum ('eligible', 'probably_eligible', 'not_eligible');

create type public.document_category as enum (
  'cnic', 'passport', 'cv', 'transcript', 'degree', 'domicile', 'photograph',
  'recommendation_letter', 'statement_of_purpose', 'personal_statement',
  'income_certificate', 'experience_certificate', 'skill_certificate', 'other'
);

create type public.moderation_status as enum ('pending', 'approved', 'rejected');
