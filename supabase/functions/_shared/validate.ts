// Validation of extracted drafts before they enter the review queue.
import type { DraftOpportunity } from './dedupe.ts';
import { analyzeLink, analyzeText, hostOf } from './linkSafety.ts';

export interface ValidationIssue { code: string; severity: 'info' | 'warning' | 'error'; message: string }

export function validateDraft(d: DraftOpportunity, officialDomains: string[], now = new Date()): ValidationIssue[] {
  const issues: ValidationIssue[] = [];
  if (!d.title || d.title.trim().length < 5) issues.push({ code: 'title_missing', severity: 'error', message: 'Title is missing or too short.' });
  if (!d.source_url) issues.push({ code: 'source_missing', severity: 'error', message: 'Source URL is missing.' });
  else if (officialDomains.length) {
    const host = hostOf(d.source_url);
    if (!host || !officialDomains.some((x) => host === x || host.endsWith('.' + x))) {
      issues.push({ code: 'source_not_official', severity: 'error', message: `Source ${host ?? d.source_url} is not on an official domain.` });
    }
  }
  if (!d.official_application_url) {
    issues.push({ code: 'apply_link_missing', severity: 'warning', message: 'No official application link was found — add it during review.' });
  } else {
    const r = analyzeLink(d.official_application_url, officialDomains);
    r.flags.forEach((f) => issues.push({ code: 'apply_link_flag', severity: r.level === 'warning' ? 'error' : 'warning', message: f }));
  }
  if (!d.deadline) issues.push({ code: 'deadline_missing', severity: 'warning', message: 'No deadline could be extracted.' });
  else {
    const t = new Date(d.deadline).getTime();
    if (!Number.isFinite(t)) issues.push({ code: 'deadline_invalid', severity: 'error', message: 'Deadline is not a valid date.' });
    else if (t < now.getTime()) issues.push({ code: 'deadline_past', severity: 'warning', message: 'Deadline is in the past (listing may be expired).' });
    else if (t > now.getTime() + 2 * 365 * 86_400_000) issues.push({ code: 'deadline_far', severity: 'warning', message: 'Deadline is more than two years away — check the year.' });
  }
  if (d.opening_date && d.deadline && new Date(d.opening_date) > new Date(d.deadline)) {
    issues.push({ code: 'dates_inverted', severity: 'error', message: 'Opening date is after the deadline.' });
  }
  if (!d.eligibility_summary) issues.push({ code: 'eligibility_missing', severity: 'info', message: 'Eligibility criteria need to be structured by a reviewer.' });
  const t = analyzeText([d.title, d.summary, d.description, d.eligibility_summary].filter(Boolean).join('\n'));
  t.flags.forEach((f) => issues.push({ code: 'payment_language', severity: 'warning', message: f }));
  return issues;
}

export function hasBlockingIssue(issues: ValidationIssue[]): boolean {
  return issues.some((i) => i.severity === 'error');
}
